# Архитектура, безопасность и воспроизведение

> Часть постоянного handoff из [README.md](README.md).

## 4. Архитектура

### QML

- `BarWidget.qml` — entry point виджета бара.
- `BarPlayer.qml` — визуальный мини-плеер в баре.
- `WidgetLogic.qml` — bootstrap, процессы CLI, polling status, загрузка панели.
- `Panel.qml` — попап: «Сейчас», «Медиатека», «Поиск», настройки, OAuth и ошибки.
- `manifest.json` — metadata Omarchy и версия.

`WidgetLogic.qml` запускает `bootstrap.sh`, затем опрашивает CLI:
- каждые 1 с, если попап открыт или идёт воспроизведение;
- каждые 3 с в остальных случаях.

Команды UI выполняются через один `actionProcess`; после завершения запускается короткий settle refresh.

### Backend

- Источник: `backend/backend.py`.
- Установленная копия: `~/.local/share/omarchy-yandex-music/backend.py`.
- Python venv: `~/.local/share/omarchy-yandex-music/venv/`.
- systemd user service: `omarchy-yandex-music.service`.
- CLI: `bin/omarchy-yandex-music`, установлен в `~/.local/bin/omarchy-yandex-music`.
- IPC: newline-delimited JSON через Unix socket `$XDG_RUNTIME_DIR/omarchy-yandex-music.sock`.
- `mpv` управляется через `$XDG_RUNTIME_DIR/omarchy-yandex-music-mpv.sock`.
- MPRIS реализован внутри backend через `dbus-next`.

Основные команды IPC/CLI:
- `status`, `details`, `network`, `lyrics`, `lyrics_refresh`, `track_info`, `track_info_refresh`;
- `auth`, `logout`;
- `likes`, `playlist <kind>`, `load_more_library`, `close_library`;
- `wave`, `track_radio`;
- `search <query>`, `play_search <index>`;
- `artist <id>`, `play_artist_track <index>`, `close_artist`;
- `play_queue <index>`, `play_library_track <index>`;
- `pause`, `next`, `previous`, `seek`, `volume`, `mute`, `mode`, `like`, `dislike`, `stop`;
- `setting <key> <value>`.

`status` отдаёт компактное состояние. `details` дополнительно формирует queue/library/artist lists. Тексты и credits не входят ни в один из этих ответов: `lyrics` и `track_info` возвращают отдельные snapshots текущего трека и при необходимости запускают фоновую загрузку, а команды с суффиксом `_refresh` сбрасывают соответствующую кэшированную запись для ручного повтора. Не переносить тяжёлые списки в частый bar polling.

## 8. OAuth, файлы и безопасность

- Device OAuth открывает браузер только для авторизации.
- Токен автоматически обновляется.
- Файлы создаются atomic write и с правами `600`:
  - `~/.config/omarchy-yandex-music/token.json`;
  - `~/.config/omarchy-yandex-music/state.json`;
  - `~/.config/omarchy-yandex-music/preferences.json`.
- Runtime-кэш обложек уведомлений: `$XDG_RUNTIME_DIR/omarchy-yandex-music-covers/`, максимум 30 файлов.
- MPRIS публикует метаданные и обложку, но никогда временный URL аудиопотока.
- systemd unit использует `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict`, `ProtectHome=read-only` и точечные `ReadWritePaths`.

## 9. Воспроизведение

- Используется отдельный headless `mpv`; браузер после OAuth не нужен.
- Сохраняются очередь, индекс, источник коллекции (`queueCollectionKey`), позиция, пауза, громкость и preferences.
- Восстановление регулируется `autoResume`, `restoreQueue`, `restorePosition`, `restoreVolume`.
- Режимы: порядок, shuffle, repeat queue, repeat track; синхронизированы с MPRIS.
- Play/Pause проверяет `idle-active`: после Stop текущий трек загружается заново с начала, а для активного файла переключается pause.
- Stop предназначен для MPRIS и внутренних сценариев: выгружает поток, сбрасывает позицию, сохраняет текущий трек/очередь и выставляет `stopped`, чтобы MPRIS отличал Stop от Pause.
- «Моя волна» и `track:<id>` radio-chain лениво расширяются через общий `_extend_radio()`; настройки mood/diversity/language применяются только к пользовательской Волне.
- Playback reporting хранит одну активную сессию с `play_id`, считает фактически проигранное время без пауз и отправляет `play_audio` в начале и конце.
- Runtime state хранит дробную `position` mpv и wall-clock `positionObservedAt`; Panel интерполирует её локальным 100 ms UI-таймером максимум на 3 секунды от последнего измерения. Это не увеличивает частоту IPC/API и убирает задержку LRC между секундными monitor/status polling.
- Для Волны и радио по треку отправляются `radioStarted`, `trackStarted`, `trackFinished` и `skip`; `batch_id` хранится по треку, а продолжение sequence ждёт feedback предыдущего трека.
- Телеметрия проходит через отдельную упорядоченную очередь и общий `api_lock`, но без повторов 429 и без пользовательской ошибки: сбой аналитики не останавливает звук.
- `settings2` принимает JSON body напрямую; form encoding ранее приводил к HTTP 415 `unsupported-media-type`.
- При снятии лайка с текущего трека очереди likes `detached_track` позволяет убрать строку, не прерывая уже запущенное аудио, и сохранить корректную навигацию.
- При обрыве/неоткрытии потока есть повторные попытки. Не публиковать direct link в state, logs или MPRIS.

## 9.1. Тексты песен

- Текст загружается только после открытия блока «ТЕКСТ», отдельным worker без блокировки воспроизведения.
- Сначала запрашивается `tracks_lyrics(track_id, format_="LRC")`, затем сам файл текста; если временных меток нет или LRC недоступен, выполняется fallback на `TEXT`.
- Оба API/download-вызова проходят через общую `_api_call()` и `api_lock`, включая правила HTTP 429.
- Стандартные LRC timestamps, несколько timestamp у строки, `offset` и enhanced word timestamps преобразуются в упорядоченные seekable-строки.
- Одновременно хранится не более восьми LRU-записей только в памяти. Кэш очищается при logout и рестарте; stale worker предыдущей сессии не может вернуть данные в новый кэш.
- Отсутствие текста и ошибка загрузки возвращаются только в lyrics snapshot и не меняют общий `state.error` плеера.

## 9.2. Сведения и credits текущего трека

- Карточка загружается только после открытия иконки `information_outline`; очередь заменяется областью той же фиксированной высоты.
- Worker последовательно вызывает через `_api_call()` методы `tracks_full_info(track_id)` и `tracks_credits(track_id)`.
- Backend нормализует альбом, дату/год релиза, жанр, лейблы, позицию на диске, длительность, версию, explicit, aliases, описание и пары role/value из `Credits`.
- Частичный сбой одного endpoint сохраняет доступную часть ответа и локальное предупреждение с повтором; общий `state.error` не меняется.
- Отдельный LRU-кэш максимум на восемь треков хранится только в памяти, очищается при logout/restart и защищён generation/client check от stale worker.

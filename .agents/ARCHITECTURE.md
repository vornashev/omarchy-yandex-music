# Архитектура, безопасность и воспроизведение

> Часть постоянного handoff из [README.md](README.md).

## 4. Архитектура

### QML

- `BarWidget.qml` — entry point виджета бара.
- `BarPlayer.qml` — визуальный мини-плеер в баре.
- `WidgetLogic.qml` — bootstrap, процессы CLI, polling status, загрузка панели.
- `Panel.qml` — попап: «Сейчас», «Медиатека», «Поиск», настройки, OAuth и ошибки.
- `CatalogController.qml`, `LibraryController.qml`, `CollectionController.qml` — testable state/navigation для каталога, персонализации и mutation UX без зависимостей Quickshell.
- `manifest.json` — metadata Omarchy и версия.

`WidgetLogic.qml` запускает `bootstrap.sh`, затем опрашивает CLI:

- каждые 1 с, если попап открыт или идёт воспроизведение;
- каждые 3 с в остальных случаях.

Команды UI выполняются через один `actionProcess`; после завершения запускается короткий settle refresh.

### Backend

- Источник: `backend/backend.py`.
- Установленная копия: `~/.local/share/omarchy-yandex-music/backend.py`.
- Python venv: `~/.local/share/omarchy-yandex-music/venv/`; installer не обновляет `pip` и ставит только полный hash-pinned binary lock из `requirements.txt`, включая vendored wheel `yandex-music`.
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
- `search <query>` и `artist <id>` как compatibility redirects в единый каталог;
- `catalog_search <type> <query>`, `catalog_suggest <generation> <query>`, `catalog_load_more`;
- `catalog_album <id>`, `catalog_artist <id>`, `catalog_playlist <uuid> <owner> <kind>`, `catalog_back`;
- `catalog_artist_more <albums|singles>`, `catalog_entity_more`, `play_catalog_track <source> <index>`;
- `library_section <personal|history|albums|artists|playlists|stations>`, `library_section_more`, `library_retry`, `library_back`;
- `browse_personal <daily|missedLikes|recentTracks|neverHeard>`, `play_library_hub_track <index>`, `play_station <id> <title>`;
- `playlist_memberships <source> <index> <trackId> <albumId>`, `playlist_add_track <kind> <source> <index> <trackId> <albumId>`, `playlist_create <source> <index> <trackId> <albumId> <title>`;
- `playlist_delete_track <kind> <source> <index> <trackId> <albumId>`, `playlist_recommendations <kind> <title>`, `collection_clear`;
- `play_queue <index>`, `play_library_track <index>`;
- `pause`, `next`, `previous`, `seek`, `volume`, `mute`, `mode`, `like`, `dislike`, `stop`;
- `setting <key> <value>`.

`status` отдаёт компактное состояние. `details` дополнительно формирует queue/library lists и snapshots каталога, персонализации и управления коллекцией. Для collection flow частый `status` содержит только `collectionRevision`, а локальные ошибки, сообщения и recommendation rows входят только в `details`. Тексты и credits не входят ни в один из этих ответов: `lyrics` и `track_info` возвращают отдельные snapshots текущего трека и при необходимости запускают фоновую загрузку, а команды с суффиксом `_refresh` сбрасывают соответствующую кэшированную запись для ручного повтора. Не переносить тяжёлые списки в частый bar polling.

## 4.1. Единый каталог

- Каталог живёт только во вкладке «Поиск» (`page == 2`); legacy artist browse больше не подменяет очередь «Сейчас».
- Search state (field text, filter, query, page и четыре секции models) хранится независимо от открытой entity page и не сбрасывается при Back.
- Suggestions и catalog workers проходят через общий `_api_call()`/`api_lock`, используют generation/client guards и не записывают ошибки в глобальный `state.error`.
- Поиск поддерживает SDK-типы `all`, `track`, `artist`, `album`, `playlist`; `all` всегда сериализуется четырьмя секциями.
- Album, artist и playlist loaders не вызывают `_set_queue()`. Только `play_catalog_track` является явной границей запуска воспроизведения.
- Очередь, явно запущенная из популярных треков исполнителя, хранит `queueArtistId`/page/hasMore, заранее запрашивает следующие страницы `artists_tracks` через `_api_call()` и дедуплицирует их перед append.
- Entity/search models и bounded entity cache хранятся только в памяти и очищаются при logout/restart.
- `CatalogController.qml` содержит testable debounce/navigation state без зависимостей Quickshell; production rendering остаётся в `Panel.qml` и использует один виртуализированный внутренний `ListView`.
- `CatalogImage.qml` повторяет временные ошибки CDN/HTTP2 с ограниченным backoff и cache-busting nonce; после трёх неудач остаётся локальная fallback-иконка.

## 4.2. Персонализация медиатеки

- `LibraryController.qml` строит виртуализированные home/section rows и отделяет навигацию по сущностям от явных playback actions.
- Плейлист дня, Тайник, Премьера, Дежавю, история, любимые альбомы/исполнители/плейлисты и станции загружаются отдельными ленивыми командами; открытие вкладки не вызывает все endpoint одновременно. Если generated playlist приходит с `ready=false`, его неполная модель не кэшируется, а строка отображается приглушённой и не активируется до следующего успешного обновления раздела.
- Все новые SDK-запросы проходят через `_api_call()`/`api_lock`, используют client/generation guards и сохраняют ошибки внутри `libraryHub`, не меняя глобальную ошибку работающего плеера.
- История сначала получает только лёгкие ссылки через `music_history(full_models_count=0)`, затем дополняет метаданные batch-вызовами `music_history_items()` страницами по 50 элементов; треки истории хранятся отдельно от JSON snapshot и запускаются только явным выбором.
- Личный персональный плейлист открывается как track collection без автозапуска и переиспользует постраничную библиотечную очередь. Любимые album/artist/playlist открывают существующие catalog entity pages и Back возвращает во вкладку «Медиатека».
- Backend одним ленивым `rotor_stations_list()` передаёт полный каталог станций; `LibraryController.qml` локально фильтрует его по названию/подзаголовку и раскрывает страницы по 50 элементов у конца `ListView`, не выполняя дополнительных API-запросов. Станция получает очередь только через явный `play_station`; дальнейшее продолжение и feedback используют общий radio-chain protocol.
- Section snapshots, track models и generated playlist models имеют ограниченный десятиминутный in-memory cache и полностью очищаются при logout/restart. В `status` попадает только revision, а сами rows — только в `details`.

## 4.3. Управление коллекцией

- UI передаёт не ссылку на QML delegate, а immutable snapshot цели: `source/index/trackId/albumId`; backend повторно сверяет ID с текущей model collection перед чтением membership и записью.
- При каждом открытии action dialog `playlist_memberships` одним batch-вызовом проверяет собственные плейлисты; неполный playlist model разрешается отдельно только при необходимости. Membership map остаётся details-only, защищён generation/client/target guards и очищается вместе с dialog. Уже содержащий трек плейлист блокируется в UI, а backend повторно предотвращает duplicate insert.
- Источники ограничены queue, collection browse, history, catalog search/entity и текущими recommendations. Операции не вызывают `_set_queue()` и не меняют активную очередь.
- Создание из action dialog всегда создаёт приватный плейлист. Add/delete сначала получают свежую модель собственного плейлиста и используют её `revision`; insert при явном conflict можно безопасно повторить один раз, delete после conflict только обновляет открытый список и требует нового подтверждения.
- Удаление адресуется half-open диапазоном `[index, index + 1)` и учитывает номер появления дублирующегося `trackId:albumId` в открытом списке.
- Recommendations загружаются только по кнопке, ограничиваются первой страницей, хранят track models только в памяти и очищаются при закрытии, logout или restart.
- После подтверждённой mutation обновляются summary собственных плейлистов и открытая страница, а связанные collection/catalog/library caches инвалидируются. Очередь остаётся playback snapshot и не заменяется.
- Pins и presaves не входят в Stage 5: без отдельного экрана быстрых контекстов и будущих релизов их состояние и обратное действие были бы непонятны.

## 8. OAuth, файлы и безопасность

- Device OAuth открывает браузер только для авторизации.
- Токен автоматически обновляется.
- Файлы создаются atomic write и с правами `600`:
  - `~/.config/omarchy-yandex-music/token.json`;
  - `~/.config/omarchy-yandex-music/state.json`;
  - `~/.config/omarchy-yandex-music/preferences.json`.
- Прямые HTTP JSON-ответы читаются потоково с пределом 1 МиБ; runtime-кэш обложек уведомлений: `$XDG_RUNTIME_DIR/omarchy-yandex-music-covers/`, максимум 30 файлов, body пишется потоково и ограничен 5 МБ.
- Входящий service IPC ограничен 64 КиБ, ответы CLI — 8 МиБ, ответы `mpv` IPC — 1 МиБ; все сообщения обязаны завершаться `\n`.
- MPRIS публикует метаданные и обложку, но никогда временный URL аудиопотока.
- systemd unit использует `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict`, `ProtectHome=read-only` и точечные `ReadWritePaths`.

## 9. Воспроизведение

- Используется отдельный headless `mpv`; браузер после OAuth не нужен.
- Сохраняются очередь, индекс, источник коллекции (`queueCollectionKey`), контекст продолжения популярных треков исполнителя, позиция, пауза, громкость и preferences.
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

- Карточка загружается только после открытия явной вкладки «О треке»; список заменяется областью той же фиксированной высоты, а вкладка «Список» возвращает очередь.
- Worker последовательно вызывает через `_api_call()` методы `tracks_full_info(track_id)` и `tracks_credits(track_id)`.
- Backend нормализует альбом, дату/год релиза, жанр, лейблы, позицию на диске, длительность, версию, explicit, aliases, описание и пары role/value из `Credits`.
- Частичный сбой одного endpoint сохраняет доступную часть ответа и локальное предупреждение с повтором; общий `state.error` не меняется.
- Отдельный LRU-кэш максимум на восемь треков хранится только в памяти, очищается при logout/restart и защищён generation/client check от stale worker.

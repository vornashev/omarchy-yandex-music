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
- `status`, `details`, `network`;
- `auth`, `logout`;
- `likes`, `playlist <kind>`, `load_more_library`, `close_library`;
- `wave`;
- `search <query>`, `play_search <index>`;
- `artist <id>`, `play_artist_track <index>`, `close_artist`;
- `play_queue <index>`, `play_library_track <index>`;
- `pause`, `next`, `previous`, `seek`, `volume`, `mute`, `mode`, `stop`;
- `setting <key> <value>`.

`status` отдаёт компактное состояние. `details` дополнительно формирует queue/library/artist lists. Не переносить тяжёлые списки в частый bar polling.

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
- «Моя волна» лениво расширяется; настройки: mood, diversity, language.
- `settings2` принимает JSON body напрямую; form encoding ранее приводил к HTTP 415 `unsupported-media-type`.
- При снятии лайка с текущего трека очереди likes `detached_track` позволяет убрать строку, не прерывая уже запущенное аудио, и сохранить корректную навигацию.
- При обрыве/неоткрытии потока есть повторные попытки. Не публиковать direct link в state, logs или MPRIS.

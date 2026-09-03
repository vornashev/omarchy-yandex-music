# Установка, локальная разработка и проверки

> Часть постоянного handoff из [README.md](README.md).

## 10. Установка и обновление

Единственная рекомендуемая установка для пользователя:

```bash
omarchy plugin add https://github.com/vornashev/omarchy-yandex-music.git --enable
```

Не требовать ручных `git clone`, `cd` или `sudo`.

Обновление:

```bash
omarchy plugin update vornashev.yandex-music
```

Механизм bootstrap:

- `WidgetLogic.qml` запускает `bootstrap.sh`.
- `bootstrap.sh` вызывает `install.sh --backend-only`.
- `install.sh` использует `flock`, marker `.installed-version` и fast path.
- Backend, venv, CLI и systemd user unit ставятся автоматически.
- При несовпадении marker и `manifest.json` backend синхронизируется и сервис перезапускается.
- Сохранять совместимость со старой ручной установкой.

Позиционирование после часов выполняется при enable через:

```bash
omarchy plugin enable vornashev.yandex-music --after omarchy.clock
```

## 11. Локальная установка исходников для проверки

Обычный способ:

```bash
cd ~/Projects/omarchy-yandex-music
./install.sh --backend-only
omarchy-restart-shell
```

Важно: если marker уже совпадает с версией, backend-only fast path не копирует изменённый backend повторно. При разработке либо временно удалить marker и снова выполнить installer, либо точечно установить файлы:

```bash
install -m 755 backend/backend.py ~/.local/share/omarchy-yandex-music/backend.py
install -m 755 backend/backend.py ~/.config/omarchy/plugins/vornashev.yandex-music/backend/backend.py
install -m 644 Panel.qml manifest.json ~/.config/omarchy/plugins/vornashev.yandex-music/
systemctl --user restart omarchy-yandex-music.service
omarchy-restart-shell
```

После теста убедиться, что не изменены пользовательские настройки, очередь, лайки или playback state без необходимости.

Проверка фактических версий:

```bash
jq -r .version ~/.config/omarchy/plugins/vornashev.yandex-music/manifest.json
cat ~/.local/share/omarchy-yandex-music/.installed-version
omarchy-yandex-music status | jq -r .version
```

## 12. Обязательные проверки

Перед отчётом о готовности:

```bash
cd ~/Projects/omarchy-yandex-music
python -m py_compile backend/backend.py
bash -n bootstrap.sh install.sh uninstall.sh bin/omarchy-yandex-music
git diff --check
omarchy plugin validate .
systemctl --user is-active omarchy-yandex-music.service
omarchy-shell shell ping
omarchy-yandex-music status | jq
```

Дополнительно:

1. Проверить совпадение `manifest.json.version` и `APP_VERSION`.
2. После QML-изменений перезапустить shell, открыть плагин и проверить journal на `TypeError`, `ReferenceError`, `SyntaxError`, anchor/assignment errors.
3. Для пагинации проверить 50/100/остаток, отсутствие дублей и исходный порядок.
4. Для 429 fake-test проверить:
   - успех после нескольких 429;
   - ровно заданные повторы;
   - сериализацию нескольких threads (`peak active == 1`);
   - coalescing двух `_get_liked_rows()` в один API call;
   - отсутствие raw response в финальной ошибке.
5. Не запускать destructive тесты лайков/плейлистов на реальном аккаунте без явной необходимости.
6. Проверять, что открытие likes/playlist/artist не меняет воспроизведение до выбора трека.
7. Проверять, что service active и QuickShell отвечает после installer/shell restart.

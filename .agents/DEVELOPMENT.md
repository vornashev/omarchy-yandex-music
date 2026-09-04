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
install -m 644 Panel.qml CatalogController.qml CatalogImage.qml manifest.json ~/.config/omarchy/plugins/vornashev.yandex-music/
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
python -m compileall -q backend tests
TEST_HOME="$(mktemp -d)"
trap 'rm -rf "$TEST_HOME"' EXIT
HOME="$TEST_HOME" ~/.local/share/omarchy-yandex-music/venv/bin/python -m unittest discover -s tests -v
rm -rf "$TEST_HOME"
trap - EXIT
bash -n bootstrap.sh install.sh uninstall.sh bin/omarchy-yandex-music
omarchy plugin validate .
QMLTESTRUNNER="$(command -v qmltestrunner || command -v qmltestrunner6 || { test -x /usr/lib/qt6/bin/qmltestrunner && printf '%s\n' /usr/lib/qt6/bin/qmltestrunner; })"
QML_TEST_DIR="$(find tests -type f -name 'tst_*.qml' -printf '%h\n' | sort -u | head -n 1)"
QT_QPA_PLATFORM=offscreen "$QMLTESTRUNNER" -input "$QML_TEST_DIR" -import .
git diff --check
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
6. Для playback reporting и радио fake-тестами проверить порядок start/end и finished/skip, сохранение одного `play_id`, отсутствие повторного старта при переоткрытии потока, взаимное снятие like/dislike и запуск `track:<currentTrackId>` с сохранением `batch_id`.
7. Не проверять `play_audio`, radio feedback, like или dislike разрушительными действиями на реальном аккаунте без явной необходимости.
8. Проверять, что открытие likes/playlist/artist не меняет воспроизведение до выбора трека.
9. Для текстов fake-тестами проверить LRC timestamps/offset, fallback на `TEXT`, отсутствие общей ошибки плеера и ограничение in-memory LRU-кэша; реальный smoke test не должен печатать содержимое текста в отчёт или лог.
10. Для `track_info` проверить нормализацию album/release/labels/position/credits, сохранение частичного ответа без общей ошибки и отдельный LRU-кэш; реальный smoke test выводит только наличие полей и количество credits, не значения.
11. Для Stage 3 Catalog fake-тестами проверять typed/all search, stale suggestions/client generation, append+dedupe pagination, batch metadata, entity cache/logout, partial models, playlist UUID/owner+kind и non-autoplay navigation.
12. QML interaction-тестами проверять 300 ms debounce/минимум 2 символа, stale suggestions, четыре секции, load more, back-state и explicit-playback-only.
13. Проверять, что service active и QuickShell отвечает после installer/shell restart.
14. Любой тест `logout()` обязан подменять `TOKEN_FILE` и `STATE_FILE` путями из `TemporaryDirectory`; полный test suite не должен читать, изменять или удалять реальную OAuth-сессию разработчика.

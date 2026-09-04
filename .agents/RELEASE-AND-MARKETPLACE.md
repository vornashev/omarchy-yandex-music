# Релизы, Marketplace и публичные материалы

> Часть постоянного handoff из [README.md](README.md).

## 13. Версии, changelog и релиз

При подготовке новой версии:

1. Изменить `manifest.json::version`.
2. Изменить `backend/backend.py::APP_VERSION`.
3. Одновременно обновить `CHANGELOG.md` и `CHANGELOG.ru.md`.
4. При пользовательских изменениях обновить `README.md` и `README.ru.md` симметрично.
5. Проверить ссылки changelog compare/tag.
6. Выполнить полный набор проверок и реальный smoke test.
7. Показать владельцу итог и получить явное разрешение на публикацию.
8. Только после разрешения: commit, push, tag, GitHub Release.
9. После публикации проверить remote tag, release URL, публичные файлы и чистоту рабочего дерева.

Не включать `.installed-version` в репозиторий: это локальный marker установленного backend.

## 14. Marketplace

- Каталог: `https://plugins.omarchy.org/`.
- Репозиторий заявок: `https://github.com/omacom/omarchy-plugin-marketplace`.
- Предлагаемые metadata:
  - issue title: `[Plugin]: Yandex Music`;
  - category: `Widgets`;
  - tags: `Bar`, `Media`, `Quickshell`.
- Plugin ID `vornashev.yandex-music` ранее не был найден среди опубликованных записей и открытых заявок.
- Использовать `preview.webp` и WebP-галерею из `docs/screenshots/`; для v0.8.0 preview, Library, Search и Settings пересняты на синтетических demo-данных без доступа к пользовательской коллекции.
- Перед отправкой заново открыть актуальную форму и проверить требования; Marketplace может измениться.
- Submission заблокирован до отдельного явного подтверждения владельцем всех пяти официальных пунктов checklist, включая права на код и изображения.

## 15. Скриншоты и публичные материалы

- Главный preview: `preview.webp`.
- Галерея:
  - `docs/screenshots/library.webp`;
  - `docs/screenshots/search.webp`;
  - `docs/screenshots/settings.webp`;
  - `docs/screenshots/signed-out.webp`.
- Скриншоты не должны показывать OAuth-токен, приватные данные или временные audio URLs.
- OAuth device code допустим только как краткоживущий демонстрационный код; предпочтительно использовать уже подготовленный публичный screenshot.
- Сохранять WebP для размера и совместимости Marketplace.

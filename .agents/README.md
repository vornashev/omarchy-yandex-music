# Agent handoff: Yandex Music for Omarchy

Эта директория — постоянная документация для любого coding agent, продолжающего работу над проектом.

## Обязательный порядок чтения

1. [INSTRUCTIONS.md](INSTRUCTIONS.md) — жёсткие правила работы и запреты.
2. [STATUS.md](STATUS.md) — опубликованная версия, локальные изменения и следующие шаги.
3. [PROJECT.md](PROJECT.md) — назначение проекта и основные сведения.
4. [ARCHITECTURE.md](ARCHITECTURE.md) — QML/backend, IPC, OAuth, MPRIS и воспроизведение.
5. [UX-AND-DATA.md](UX-AND-DATA.md) — UX-инварианты, пагинация, кэш и HTTP 429.
6. [DEVELOPMENT.md](DEVELOPMENT.md) — установка, локальный deploy и обязательные проверки.
7. [RELEASE-AND-MARKETPLACE.md](RELEASE-AND-MARKETPLACE.md) — публикация, Marketplace и скриншоты.

## Как начать работу

```bash
cd ~/Projects/omarchy-yandex-music
git status --short
git diff --check
git diff
```

После этого прочитать все файлы выше. В рабочем дереве могут находиться незакоммиченные изменения других агентов — их нельзя откатывать или перезаписывать.

## Поддержка документации

- После существенных изменений обновлять соответствующий файл в `.agents/` и публичные README/changelog при необходимости.
- Текущий runtime/release status всегда отражать в `STATUS.md`.
- Новые неизменяемые UX-правила добавлять в `UX-AND-DATA.md`.
- Новые release constraints добавлять в `RELEASE-AND-MARKETPLACE.md`.
- Не хранить здесь токены, содержимое медиатеки, direct audio URLs и другие пользовательские секреты.

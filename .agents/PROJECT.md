# Проект

> Часть постоянного handoff из [README.md](README.md).

## 1. Проект

- Название: **Yandex Music for Omarchy**.
- Репозиторий: `/home/tema/Projects/omarchy-yandex-music`.
- GitHub: `https://github.com/vornashev/omarchy-yandex-music`.
- Plugin ID: `vornashev.yandex-music`.
- Назначение: нативный виджет Omarchy Shell для Яндекс Музыки.
- Браузер используется только для Device OAuth; воспроизведение идёт через фоновый `mpv`.
- API Яндекс Музыки неофициальный: wheel `yandex-music-api` из зафиксированного commit хранится в `vendor/`, а его SHA-256 и полный runtime lock — в `requirements.txt`.
- Основной язык общения с владельцем — русский. Публичная документация и changelog поддерживаются параллельно на русском и английском.

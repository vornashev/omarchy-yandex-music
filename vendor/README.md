# Vendored Python artifact

`yandex_music-3.1.0b2-py3-none-any.whl` is vendored because the required unreleased
Yandex Music API fixes are not available as a versioned PyPI release.

- Upstream: <https://github.com/MarshalX/yandex-music-api>
- Commit: `0fa54f2d32084a9e461bce41890d1c9ab70d91aa`
- Version: `3.1.0b2`
- License: LGPL-3.0 (the wheel includes `yandex_music-3.1.0b2.dist-info/licenses/LICENSE`)
- SHA-256: `2f200b887b2be33b37f4eb05a4762703b11fe334205c16d7fac29f24d8a52e31`

`yandex_music-3.1.0b2.origin.json` is pip's cached provenance record for the
wheel and records the exact requested and resolved VCS revision.

The installer accepts this exact artifact only through the hash-pinned
`requirements.txt`. To inspect it without executing package code:

```bash
python -m zipfile --list vendor/yandex_music-3.1.0b2-py3-none-any.whl
python -m zipfile --extract vendor/yandex_music-3.1.0b2-py3-none-any.whl /tmp/yandex-music-wheel
sha256sum vendor/yandex_music-3.1.0b2-py3-none-any.whl
```

When updating the upstream revision, build and review a new wheel, replace its
hash in `requirements.txt`, and update this file and `requirements.in` together.
`pip-compile` normalizes a local wheel to an absolute `file://` URL; before
committing, restore the portable bare path `./vendor/<wheel>` in the generated
lock file and verify it with the install command from `install.sh`.

# Vendored Python artifact

[Русский](README.ru.md)

`yandex_music-3.1.0b2-py3-none-any.whl` is vendored because the required unreleased
Yandex Music API fixes are not available as a versioned PyPI release.
The installer accepts this exact artifact through the hash-pinned
[`requirements.txt`](../requirements.txt); verification does not change installation.

## Provenance

- Upstream: <https://github.com/MarshalX/yandex-music-api>
- Pinned source: [`0fa54f2d32084a9e461bce41890d1c9ab70d91aa`](https://github.com/MarshalX/yandex-music-api/tree/0fa54f2d32084a9e461bce41890d1c9ab70d91aa)
- Declared distribution/version: `yandex-music` / `3.1.0b2`
- License: LGPL-3.0; upstream `LICENSE` is included at `yandex_music-3.1.0b2.dist-info/licenses/LICENSE`.
- Wheel SHA-256: `2f200b887b2be33b37f4eb05a4762703b11fe334205c16d7fac29f24d8a52e31`
- [Pinned codeload source archive](https://codeload.github.com/MarshalX/yandex-music-api/tar.gz/0fa54f2d32084a9e461bce41890d1c9ab70d91aa) SHA-256: `8f9adb3a49d05c606255357f9c620263c7d1dac1422c9689ed2a083e47c0e5fd`

[`yandex_music-3.1.0b2.origin.json`](yandex_music-3.1.0b2.origin.json) is pip's
cached provenance record containing the requested and resolved VCS revision.
It is supporting metadata, not a signed attestation or proof of wheel contents.
The wheel's `WHEEL` metadata declares `Generator: setuptools (84.0.0)`,
`Root-Is-Purelib: true` and `Tag: py3-none-any`. The original Python version,
operating system, complete build environment and invocation are not established
by that metadata.

## Verify without installing or executing the dependency

From the repository root, with Python 3.9+ and only its standard library:

```bash
python3 -B vendor/verify_wheel.py
```

This downloads the exact pinned commit archive over certificate-verified HTTPS.
Both archives are read in memory, without extraction, package imports, build
hooks, installation, cache files or repository/runtime changes.
For offline verification, obtain the exact archive beforehand:

```bash
curl --fail --location --proto '=https' --proto-redir '=https' \
  'https://codeload.github.com/MarshalX/yandex-music-api/tar.gz/0fa54f2d32084a9e461bce41890d1c9ab70d91aa' \
  --output /tmp/yandex-music-api-0fa54f2d32084a9e461bce41890d1c9ab70d91aa.tar.gz
python3 -B vendor/verify_wheel.py \
  --source-archive /tmp/yandex-music-api-0fa54f2d32084a9e461bce41890d1c9ab70d91aa.tar.gz
```

Only the explicit `curl` command writes an archive, outside the repository.
`--source-archive` disables the verifier's download; `--wheel /path/to/file.whl`
checks another local copy against the same immutable wheel hash. Neither option
can override the trusted hashes. Repacked or changed source archives fail,
even if their directory name contains the expected commit. If GitHub regenerates
its archive bytes, verification deliberately fails until the new archive is
independently reviewed; do not bypass the hash check.

The verifier exits nonzero on any mismatch and reports the commit, both archive
hashes and concrete counts. For this artifact it checks:

- Exact wheel and source archive SHA-256 pins.
- Duplicate and unsafe paths, encrypted ZIP entries, and non-regular archive
  members (including links); source directories are permitted.
- Complete path-set and byte correspondence of **526 files**: **308** under
  `yandex_music/` and **218** under `tests/`, plus the upstream license.
- Exactly five explained packaging files: `licenses/LICENSE`, `METADATA`,
  `WHEEL`, `top_level.txt` and `RECORD`, all under the expected `.dist-info`
  directory. No other payload, entry-point files, `.pth` hooks, bytecode,
  native libraries or scripts are allowed.
- `RECORD` covers all **531** wheel members exactly once; **530** SHA-256
  hashes and sizes match, and its own row has the required empty hash/size.
- Declared name/version/license file, purelib status, wheel tag, generator and
  top-level packages.

This establishes that the pinned wheel's entire package/test payload and license
match the pinned upstream archive, not merely that a local checksum agrees.
Trust still rests on the reviewed pins and GitHub's HTTPS source delivery;
this is not signed Git-commit authentication, a full source/security audit,
proof that upstream is safe, or a byte-reproducible wheel build. Generated
packaging metadata is checked as described, not independently regenerated.
Other dependencies and application behavior are outside this check.

## Updating the pin

When updating upstream, build and review a new wheel and its source, replace the
hash in `requirements.txt`, and update `requirements.in`, the provenance record,
verifier pins/expected metadata and both vendor READMEs together. Do not replace
the current wheel just to verify it.
`pip-compile` normalizes a local wheel to an absolute `file://` URL; before
committing, restore the portable bare path `./vendor/<wheel>` in the generated
lock file and verify it with the install command from `install.sh` in an isolated
environment.

# Vendored Python artifact

[Русский](README.ru.md)

`yandex_music-3.2.2-py3-none-any.whl` is vendored to ensure deterministic
and offline-capable installation of the Yandex Music client library.
The installer accepts this exact artifact through the hash-pinned
[`requirements.txt`](../requirements.txt); verification does not change installation.

## Provenance

- Upstream: <https://github.com/MarshalX/yandex-music-api>
- Pinned source: [`9ca132e5c18a72aab779c1fc68c169380a9357d0`](https://github.com/MarshalX/yandex-music-api/tree/9ca132e5c18a72aab779c1fc68c169380a9357d0)
- Declared distribution/version: `yandex-music` / `3.2.2`
- License: LGPL-3.0; upstream `LICENSE` is included at `yandex_music-3.2.2.dist-info/licenses/LICENSE`.
- Wheel SHA-256: `f2e603530c74a4affd2bead6f42e7b17c5e83732a2dda752206ef6c0d3dbf515`
- [Pinned codeload source archive](https://codeload.github.com/MarshalX/yandex-music-api/tar.gz/9ca132e5c18a72aab779c1fc68c169380a9357d0) SHA-256: `3366340c8b28c6212b00350ba7f79ff684cb2d7a17dee387bfcfa3aaae7b97c9`

[`yandex_music-3.2.2.origin.json`](yandex_music-3.2.2.origin.json) is pip's
cached provenance record containing the requested and resolved VCS revision.
It is supporting metadata, not a signed attestation or proof of wheel contents.
The wheel's `WHEEL` metadata declares `Generator: hatchling 1.32.4`,
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

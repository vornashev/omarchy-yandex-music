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
  'https://codeload.github.com/MarshalX/yandex-music-api/tar.gz/9ca132e5c18a72aab779c1fc68c169380a9357d0' \
  --output /tmp/yandex-music-api-9ca132e5c18a72aab779c1fc68c169380a9357d0.tar.gz
python3 -B vendor/verify_wheel.py \
  --source-archive /tmp/yandex-music-api-9ca132e5c18a72aab779c1fc68c169380a9357d0.tar.gz
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
- Complete path-set and byte correspondence of **341 files** under
  `yandex_music/`, plus the upstream license.
- Exactly four explained packaging files: `licenses/LICENSE`, `METADATA`,
  `WHEEL` and `RECORD`, all under the expected `.dist-info`
  directory. No other payload, entry-point files, `.pth` hooks, bytecode,
  native libraries or scripts are allowed.
- `RECORD` covers all **345** wheel members exactly once; **344** SHA-256
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

## Executable-payload review — 2026-10-14

This review concerns **3.2.2 and the exact hashes above**, not the older
3.1.0b2 wheel in the original marketplace request. It is source-review
evidence for a maintainer, **not marketplace approval or a security audit**.

Coverage and method:

- Parsed all **340 Python members** with the standard-library AST parser,
  inventoried imports, module-level statements, decorators and **2,539 call
  sites**, and inspected dynamic execution, network, deserialization,
  filesystem and logging boundaries. The remaining package file is `py.typed`.
  Review tooling did not import, install or execute dependency code.
- Manually inspected the shared sync/async request layers, Device OAuth,
  model construction/type resolution, JSON/XML handling, download/file-writing
  helpers and optional Ynison transport; traced the plugin's synchronous
  `Client`/`SessionRequest` and Device OAuth call sites. Endpoint/model families
  were structurally inventoried, not individually proven correct.
- Two additional, separately scoped **AI-assisted static source-review passes**
  read executable bodies/imports/decorators/aliases across the **57 core/client/
  Device OAuth Python modules**, with eight supporting utility modules, and
  separately inspected transport, direct-link XML, lyric retrieval, model/file
  helpers and optional Ynison paths. They confirmed the residual risks below;
  no additional confirmed blocker was established within those scopes.
  Repetitive endpoint documentation and parts of the larger model/Ynison state
  modules were not exhaustively read. These are not external human audits.
- No direct `eval`/`exec`, shell/subprocess execution, pickle loading, installer
  hook or import-time network/download call was found in that inventory.
  `base.py` resolves **package-defined** type annotations with `get_type_hints`;
  this is not evaluation of an API-provided source string.
- API defaults use `https://api.music.yandex.net`, Device OAuth uses
  `https://oauth.yandex.ru`; media URLs come from API/CDN responses. Request
  layers retain their HTTP libraries' certificate-verification defaults.
  API methods attach OAuth headers; raw `retrieve()` does not automatically
  attach those API headers. File helpers write the **caller-supplied filename**;
  the plugin does not call SDK media file-writing helpers, `ClientAsync` or Ynison.
  It **does** use SDK
  [`DownloadInfo.get_direct_link()`](https://github.com/MarshalX/yandex-music-api/blob/9ca132e5c18a72aab779c1fc68c169380a9357d0/yandex_music/download_info.py#L58-L88)
  (XML retrieval/parsing) and
  [`TrackLyrics.fetch_lyrics()`](https://github.com/MarshalX/yandex-music-api/blob/9ca132e5c18a72aab779c1fc68c169380a9357d0/yandex_music/track/track_lyrics.py#L36-L43)
  (text retrieval). These used paths share the HTTP response risks below.

Residual risks, **not fixed or waived by this review**:

1. **Response resource limits (conditional medium).** SDK transports collect
   complete bodies before parsing:
   [`utils/request.py:46–82`](https://github.com/MarshalX/yandex-music-api/blob/9ca132e5c18a72aab779c1fc68c169380a9357d0/yandex_music/utils/request.py#L46-L82)
   and [`utils/request_async.py:68–106`](https://github.com/MarshalX/yandex-music-api/blob/9ca132e5c18a72aab779c1fc68c169380a9357d0/yandex_music/utils/request_async.py#L68-L106).
   The plugin's `backend/backend.py::SessionRequest._request_wrapper` likewise
   returns `resp.content` without a byte cap. Its synchronous HTTP timeout
   limits inactivity, not the total transfer duration; a slow-drip responder
   can keep the serialized API worker occupied. The async SDK instead sets
   `aiohttp.ClientTimeout(total=...)`, but still has no response byte ceiling.
   A malicious/compromised trusted API/CDN could exhaust
   memory or occupy a worker. Ordinary attacker control of such a response
   was **not demonstrated**; the new clipboard limits do not protect this
   separate network boundary. XML/JSON parsing inherits this resource risk.
2. **Secrets in opt-in DEBUG logs (conditional low).**
   [`_client/__init__.py:12–25`](https://github.com/MarshalX/yandex-music-api/blob/9ca132e5c18a72aab779c1fc68c169380a9357d0/yandex_music/_client/__init__.py#L12-L25)
   logs method results, including decorated Device OAuth results; the async
   decorator does the same. `OAuthToken` inherits the model's full dictionary
   string representation, including access/refresh tokens. The plugin does
   not configure DEBUG logging. **Do not enable SDK DEBUG logging or share
   unredacted logs during authorization.**

This is a bounded static review, not exhaustive line-by-line verification,
fuzzing, a rebuild attestation, or a review of transitive dependencies.
Network destinations/redirects and downloaded content still require trust in
upstream/CDN behavior. A marketplace maintainer must assess these findings
and review the **new exact application commit** before approval; checksum
correspondence alone does not close the dependency-review requirement.

## Updating the pin

When updating upstream, build and review a new wheel and its source, replace the
hash in `requirements.txt`, and update `requirements.in`, the provenance record,
verifier pins/expected metadata and both vendor READMEs together. Do not replace
the current wheel just to verify it.
`pip-compile` normalizes a local wheel to an absolute `file://` URL; before
committing, restore the portable bare path `./vendor/<wheel>` in the generated
lock file and verify it with the install command from `install.sh` in an isolated
environment.

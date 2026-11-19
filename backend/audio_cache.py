"""Bounded, best-effort audio cache with one cancellable background downloader."""
from __future__ import annotations

import hashlib
import json
import math
import os
import re
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable
from urllib.parse import urlsplit

import requests

DEFAULT_BUDGET = 256 * 1024 * 1024
MAX_FILE_BYTES = 64 * 1024 * 1024
CHUNK_BYTES = 64 * 1024
DOWNLOAD_TIMEOUT = 120


class BackgroundBusy(RuntimeError):
    """Yield to foreground API work without applying the longer failure backoff."""


def cache_directory() -> Path:
    base = Path(os.environ.get("XDG_CACHE_HOME", ""))
    if not base.is_absolute():
        base = Path.home() / ".cache"
    return base / "omarchy-yandex-music" / "audio"


@dataclass(frozen=True)
class AudioSource:
    url: str
    codec: str
    bitrate: int
    key: str = field(default="", repr=False)


@dataclass(frozen=True)
class AudioIdentity:
    account: str
    track: str
    quality: str

    @classmethod
    def for_track(cls, account: str, track: str, quality: str) -> AudioIdentity:
        return cls(hashlib.sha256(account.encode()).hexdigest(), track, quality)


@dataclass
class CacheRequest:
    identity: AudioIdentity
    resolve: Callable[[], AudioSource]
    valid: Callable[[], bool]
    ready: Callable[[Path], None]
    retry_after: float = 0
    retry_delay: float = 30


class AudioCache:
    def __init__(self, directory: Path, budget: int = DEFAULT_BUDGET,
                 max_file: int = MAX_FILE_BYTES) -> None:
        self.directory = directory
        self.budget = budget
        self.max_file = min(max_file, budget)
        self.condition = threading.Condition(threading.RLock())
        self.download_lock = threading.Lock()
        self.entries: dict[str, dict] = {}
        self.protected: set[AudioIdentity] = set()
        self.protected_paths: set[Path] = set()
        self.pending: list[CacheRequest] = []
        self.active: CacheRequest | None = None
        self.cancelled = threading.Event()
        self.closed = False
        self.enabled = False
        try:
            if directory.is_symlink():
                raise OSError("cache directory is a symlink")
            directory.mkdir(parents=True, exist_ok=True, mode=0o700)
            directory.chmod(0o700)
            self._restore()
            self.enabled = True
        except (OSError, ValueError):
            pass
        self.worker = threading.Thread(target=self._worker, daemon=True)
        self.worker.start()

    def _restore(self) -> None:
        for path in self.directory.iterdir():
            if re.fullmatch(r"[0-9a-f]{64}\.(part|json\.part)", path.name):
                path.unlink(missing_ok=True)
        for path in self.directory.glob("*.json"):
            if not re.fullmatch(r"[0-9a-f]{64}\.json", path.name):
                continue
            name = path.stem
            try:
                if path.is_symlink() or path.stat().st_size > 4096:
                    raise ValueError("invalid manifest")
                entry = json.loads(path.read_text())
                identity = AudioIdentity(**entry["identity"])
                if (not isinstance(identity.account, str)
                        or not re.fullmatch(r"[0-9a-f]{64}", identity.account)
                        or not isinstance(identity.track, str) or not identity.track
                        or identity.quality not in ("best", "economy")
                        or not isinstance(entry["codec"], str) or len(entry["codec"]) > 32
                        or not isinstance(entry["bitrate"], int) or not 0 <= entry["bitrate"] <= 100000
                        or not isinstance(entry["used"], (int, float))
                        or not 0 <= entry["used"] <= 1e12 or not math.isfinite(entry["used"])
                        or not isinstance(entry["sha256"], str)
                        or not re.fullmatch(r"[0-9a-f]{64}", entry["sha256"])):
                    raise ValueError("invalid manifest fields")
                source = AudioSource("", entry["codec"], entry["bitrate"])
                if self._name(identity, source) != name or not self._verify(name, entry):
                    raise ValueError("invalid audio")
                entry["used"] = path.stat().st_mtime
                self.entries[name] = entry
            except (OSError, ValueError, KeyError, TypeError):
                self._remove(name)
        for path in self.directory.glob("*.audio"):
            if re.fullmatch(r"[0-9a-f]{64}\.audio", path.name) and path.stem not in self.entries:
                path.unlink(missing_ok=True)
        self._room(0)

    @staticmethod
    def _name(identity: AudioIdentity, source: AudioSource) -> str:
        value = [identity.account, identity.track, identity.quality, source.codec, source.bitrate]
        return hashlib.sha256(json.dumps(value).encode()).hexdigest()

    def _verify(self, name: str, entry: dict) -> bool:
        path = self.directory / f"{name}.audio"
        if path.is_symlink() or not path.is_file():
            return False
        size = path.stat().st_size
        if not 0 < size <= self.max_file or size != entry["size"]:
            return False
        with path.open("rb") as file:
            return hashlib.file_digest(file, "sha256").hexdigest() == entry["sha256"]

    def lookup(self, identity: AudioIdentity) -> Path | None:
        if not self.enabled:
            return None
        with self.condition:
            matches = [(name, entry) for name, entry in self.entries.items()
                       if entry["identity"] == vars(identity)]
            for name, entry in sorted(matches, key=lambda item: item[1]["used"], reverse=True):
                try:
                    if self._verify(name, entry):
                        entry["used"] = time.time()
                        manifest = self.directory / f"{name}.json"
                        os.utime(manifest, None)
                        return self.directory / f"{name}.audio"
                except OSError:
                    pass
                self._remove(name)
        return None

    def protect(self, identities: set[AudioIdentity], paths: set[Path] | None = None) -> None:
        with self.condition:
            self.protected = set(identities)
            self.protected_paths = set(paths or ())

    def schedule(self, requests_: list[CacheRequest]) -> None:
        """Replace the plan, coalescing identical requests and prioritizing the first."""
        with self.condition:
            unique = {}
            for request in requests_: unique.setdefault(request.identity, request)
            requests_ = list(unique.values())
            if self.active:
                if (not requests_ or requests_[0].identity != self.active.identity
                        or self.cancelled.is_set() or not self.active.valid()):
                    self.cancelled.set()
                else:
                    # The result belongs to the newest plan for this same file.
                    self.active.valid = requests_[0].valid
                    self.active.ready = requests_[0].ready
                    requests_ = requests_[1:]
            self.pending = requests_ if self.enabled and not self.closed else []
            self.condition.notify_all()

    def cancel(self) -> None:
        self.schedule([])

    def invalidate(self, path: Path) -> None:
        if path.parent == self.directory and re.fullmatch(r"[0-9a-f]{64}\.audio", path.name):
            with self.condition:
                self._remove(path.stem)

    def clear_account(self, account: str) -> None:
        self.cancel()
        digest = hashlib.sha256(account.encode()).hexdigest()
        with self.condition:
            for name, entry in list(self.entries.items()):
                if entry["identity"]["account"] == digest:
                    self._remove(name)

    def close(self) -> None:
        with self.condition:
            self.closed = True
            self.pending = []
            self.cancelled.set()
            self.condition.notify_all()

    def _remove(self, name: str) -> None:
        self.entries.pop(name, None)
        for suffix in ("audio", "json"):
            try:
                (self.directory / f"{name}.{suffix}").unlink(missing_ok=True)
            except OSError:
                pass

    def _room(self, extra: int) -> bool:
        # Includes partial downloads and manifests, not just published audio.
        total = sum(path.lstat().st_size for path in self.directory.iterdir()
                    if re.fullmatch(r"[0-9a-f]{64}\.(audio|json|part|json\.part)", path.name))
        for name, entry in sorted(list(self.entries.items()), key=lambda item: item[1]["used"]):
            if total + extra <= self.budget:
                return True
            if (AudioIdentity(**entry["identity"]) in self.protected
                    or self.directory / f"{name}.audio" in self.protected_paths):
                continue
            size = sum((self.directory / f"{name}.{suffix}").lstat().st_size
                       for suffix in ("audio", "json") if (self.directory / f"{name}.{suffix}").exists())
            self._remove(name)
            remaining = sum((self.directory / f"{name}.{suffix}").lstat().st_size
                            for suffix in ("audio", "json") if (self.directory / f"{name}.{suffix}").exists())
            total -= size - remaining
        return total + extra <= self.budget

    def _download(self, request: CacheRequest, cancel: threading.Event) -> Path | None:
        with self.download_lock:
            return self._download_serial(request, cancel)

    def _download_serial(self, request: CacheRequest, cancel: threading.Event) -> Path | None:
        response = None
        partial = manifest_partial = None
        published = False
        name = ""
        try:
            if cancel.is_set() or not request.valid():
                return None
            cached = self.lookup(request.identity)
            if cached:
                return cached
            source = request.resolve()
            if cancel.is_set() or not request.valid():
                return None
            if urlsplit(source.url).scheme not in ("https", "http"):
                return None
            name = self._name(request.identity, source)
            partial = self.directory / f"{name}.part"
            manifest_partial = self.directory / f"{name}.json.part"
            response = requests.get(source.url, timeout=(3, 5), stream=True,
                                    headers={"Accept-Encoding": "identity"})
            response.raise_for_status()
            length = int(response.headers.get("content-length", 0))
            if length < 0 or length > self.max_file:
                return None
            with self.condition:
                if not self._room(length + 4096 if length else 4096):
                    return None
            fd = os.open(partial, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            decryptor = None
            if source.key:
                from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
                decryptor = Cipher(algorithms.AES(bytes.fromhex(source.key)), modes.CTR(bytes(16))).decryptor()
            digest = hashlib.sha256()
            size = 0
            deadline = time.monotonic() + DOWNLOAD_TIMEOUT
            with os.fdopen(fd, "wb", buffering=0) as file:
                for chunk in response.iter_content(chunk_size=CHUNK_BYTES):
                    if cancel.is_set() or not request.valid() or time.monotonic() > deadline:
                        return None
                    if not chunk:
                        continue
                    if size + len(chunk) > self.max_file:
                        return None
                    with self.condition:
                        if not self._room(len(chunk) + 4096):
                            return None
                    if decryptor: chunk = decryptor.update(chunk)
                    if file.write(chunk) != len(chunk): return None
                    digest.update(chunk)
                    size += len(chunk)
            if (not size or partial.stat().st_size != size or (length and size != length)
                    or cancel.is_set() or not request.valid()):
                return None
            entry = {"identity": vars(request.identity), "codec": source.codec,
                     "bitrate": source.bitrate, "size": size,
                     "sha256": digest.hexdigest(), "used": time.time()}
            fd = os.open(manifest_partial, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            with os.fdopen(fd, "w") as file:
                json.dump(entry, file)
            with self.condition:
                if cancel.is_set():
                    return None
                partial.replace(self.directory / f"{name}.audio")
                manifest_partial.replace(self.directory / f"{name}.json")
                self.entries[name] = entry
                published = True
            return self.directory / f"{name}.audio"
        except Exception as exc:
            if isinstance(exc, BackgroundBusy): request.retry_delay = 1
            # Disk, network and API failures must never affect foreground playback.
            if name and not published:
                with self.condition:
                    self._remove(name)
            return None
        finally:
            if response is not None:
                response.close()
            for path in (partial, manifest_partial):
                if path:
                    try:
                        path.unlink(missing_ok=True)
                    except OSError:
                        pass

    def _worker(self) -> None:
        while True:
            with self.condition:
                self.condition.wait_for(lambda: self.closed or self.pending)
                if self.closed:
                    return
                now = time.monotonic()
                index = next((i for i, item in enumerate(self.pending) if item.retry_after <= now), None)
                if index is None:
                    self.condition.wait(max(.01, min(item.retry_after for item in self.pending) - now))
                    continue
                request = self.pending.pop(index)
                self.active = request
                request.retry_delay = 30
                self.cancelled = cancel = threading.Event()
            path = self._download(request, cancel)
            with self.condition:
                self.active = None
                if not path and not cancel.is_set() and not self.closed:
                    request.retry_after = time.monotonic() + request.retry_delay
                    self.pending.append(request)
            if path and not cancel.is_set() and request.valid():
                try:
                    request.ready(path)
                except Exception:
                    pass

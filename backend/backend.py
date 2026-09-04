#!/usr/bin/env python3
# pyright: reportOptionalMemberAccess=false, reportMissingImports=false, reportUndefinedVariable=false, reportFunctionMemberAccess=false, reportRedeclaration=false
"""Local, browser-free Yandex Music player backend for Omarchy."""
from __future__ import annotations

import asyncio
import copy
import hashlib
import json
import os
import queue as queue_module
import random
import re
import signal
import socket
import subprocess
import threading
import time
import uuid
from collections import OrderedDict
from pathlib import Path
from typing import Any, Callable

import requests
from dbus_next import Variant
from dbus_next.aio import MessageBus
from dbus_next.constants import PropertyAccess
from dbus_next.service import ServiceInterface, dbus_property, method, signal as dbus_signal
from yandex_music import Client
from yandex_music._client.device_auth import _DEFAULT_CLIENT_ID, _DEFAULT_CLIENT_SECRET, _OAUTH_BASE_URL

APP_VERSION = "0.8.0"
CONFIG = Path.home() / ".config/omarchy-yandex-music"
TOKEN_FILE = CONFIG / "token.json"
STATE_FILE = CONFIG / "state.json"
PREFERENCES_FILE = CONFIG / "preferences.json"
DEFAULT_PREFERENCES = {
    "autoResume": True,
    "restoreQueue": True,
    "restorePosition": True,
    "restoreVolume": True,
    "audioQuality": "best",
    "playbackMode": "repeatQueue",
    "waveMood": "all",
    "waveDiversity": "default",
    "waveLanguage": "any",
    "showControls": True,
    "showArtist": True,
    "showTitle": True,
    "showCover": True,
    "coverShape": "rounded",
    "showProgress": True,
    "barWidth": "normal",
    "longTitleMode": "scroll",
    "notifications": "off",
}
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
SOCKET = RUNTIME / "omarchy-yandex-music.sock"
MPV_SOCKET = RUNTIME / "omarchy-yandex-music-mpv.sock"
API_STATUS_URL = "https://api.music.yandex.net/account/status"
NETWORK_PROBE_TTL = 30
LIBRARY_PAGE_SIZE = 50
COLLECTION_CACHE_TTL = 10 * 60
COLLECTION_CACHE_MAX_ENTRIES = 8
RATE_LIMIT_DELAYS = (2, 5, 10)
RATE_LIMIT_MESSAGE = "Яндекс Музыка временно ограничила запросы. Подождите минуту и повторите."
PLAYBACK_REPORT_FROM = "desktop_win-home-playlist_of_the_day-playlist-default"
RADIO_REPORT_FROM = "mobile-radio-user-default"
TELEMETRY_QUEUE_SIZE = 100
LYRICS_CACHE_MAX_ENTRIES = 8
TRACK_INFO_CACHE_MAX_ENTRIES = 8
CATALOG_PAGE_SIZE = 20
CATALOG_TRACK_PAGE_SIZE = 50
CATALOG_CACHE_MAX_ENTRIES = 12
CATALOG_TYPES = ("all", "track", "artist", "album", "playlist")
CATALOG_SECTIONS = ("tracks", "artists", "albums", "playlists")
LIBRARY_HUB_SECTIONS = ("personal", "history", "albums", "artists", "playlists", "stations")
PERSONAL_PLAYLISTS = (
    ("daily", "Плейлист дня"),
    ("missedLikes", "Тайник"),
    ("recentTracks", "Премьера"),
    ("neverHeard", "Дежавю"),
)
LIBRARY_HUB_CACHE_TTL = 10 * 60
LIBRARY_HUB_CACHE_MAX_ENTRIES = len(LIBRARY_HUB_SECTIONS)


def atomic_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(value, ensure_ascii=False))
    tmp.chmod(0o600)
    tmp.replace(path)


class MprisRoot(ServiceInterface):
    def __init__(self) -> None:
        super().__init__("org.mpris.MediaPlayer2")

    @method()
    def Raise(self): pass

    @method()
    def Quit(self): pass

    @dbus_property(access=PropertyAccess.READ)
    def CanQuit(self) -> "b": return False

    @dbus_property(access=PropertyAccess.READ)
    def CanRaise(self) -> "b": return False

    @dbus_property(access=PropertyAccess.READ)
    def HasTrackList(self) -> "b": return False

    @dbus_property(access=PropertyAccess.READ)
    def Identity(self) -> "s": return "Yandex Music"

    @dbus_property(access=PropertyAccess.READ)
    def DesktopEntry(self) -> "s": return ""

    @dbus_property(access=PropertyAccess.READ)
    def SupportedUriSchemes(self) -> "as": return []  # type: ignore

    @dbus_property(access=PropertyAccess.READ)
    def SupportedMimeTypes(self) -> "as": return []  # type: ignore


class MprisPlayer(ServiceInterface):
    def __init__(self, player: Any) -> None:
        super().__init__("org.mpris.MediaPlayer2.Player")
        self.player = player
        self.last_properties: dict[str, Any] = {}

    def _state(self) -> dict[str, Any]:
        with self.player.lock:
            return dict(self.player.state)

    @staticmethod
    def _int(value: Any, fallback: int = 0) -> int:
        try: return int(value)
        except (TypeError, ValueError): return fallback

    @staticmethod
    def _float(value: Any, fallback: float = 0.0) -> float:
        try: return float(value)
        except (TypeError, ValueError): return fallback

    @method()
    def Next(self): self.player.next()

    @method()
    def Previous(self): self.player.previous()

    @method()
    def Pause(self):
        if self.player.state.get("playing"): self.player.pause()

    @method()
    def PlayPause(self): self.player.pause()

    @method()
    def Stop(self): self.player.stop()

    @method()
    def Play(self):
        if not self.player.state.get("playing"): self.player.pause()

    @method()
    def Seek(self, offset: "x"):
        state = self._state()
        self.player.seek(self._int(state.get("position", 0)) + self._int(offset) // 1_000_000)

    @method()
    def SetPosition(self, track_id: "o", position: "x"):
        if track_id == self._track_path(): self.player.seek(self._int(position) // 1_000_000)

    @method()
    def OpenUri(self, uri: "s"): pass

    @dbus_signal()
    def Seeked(self, position: "x") -> "x": return position

    def _track_path(self) -> str:
        with self.player.lock:
            track_id = self.player._track_id(self.player.queue[self.player.index]) \
                if 0 <= self.player.index < len(self.player.queue) else "none"
        safe_id = re.sub(r"[^A-Za-z0-9_]", "_", track_id) or "none"
        return f"/org/mpris/MediaPlayer2/track/{safe_id}"

    @dbus_property(access=PropertyAccess.READ)
    def PlaybackStatus(self) -> "s":
        state = self._state()
        if not state.get("title") or state.get("stopped"): return "Stopped"
        return "Playing" if state.get("playing") else "Paused"

    @dbus_property(access=PropertyAccess.READWRITE)
    def LoopStatus(self) -> "s":
        mode = self.player.preferences.get("playbackMode")
        return "Track" if mode == "repeatTrack" else ("Playlist" if mode == "repeatQueue" else "None")

    @LoopStatus.setter
    def LoopStatus(self, value: "s") -> None:
        mode = "repeatTrack" if value == "Track" else ("repeatQueue" if value == "Playlist" else "order")
        self.player.set_preference("playbackMode", mode)

    @dbus_property(access=PropertyAccess.READWRITE)
    def Rate(self) -> "d": return 1.0

    @Rate.setter
    def Rate(self, value: "d") -> None: pass

    @dbus_property(access=PropertyAccess.READWRITE)
    def Shuffle(self) -> "b": return self.player.preferences.get("playbackMode") == "shuffle"

    @Shuffle.setter
    def Shuffle(self, value: "b") -> None:
        self.player.set_preference("playbackMode", "shuffle" if value else "order")

    @dbus_property(access=PropertyAccess.READ)
    def Metadata(self) -> "a{sv}":  # type: ignore
        state = self._state()
        metadata = {
            "mpris:trackid": Variant("o", self._track_path()),
            "xesam:title": Variant("s", str(state.get("title", ""))),
            "xesam:artist": Variant("as", [str(a.get("name", "")) for a in state.get("artists", [])]),
            "xesam:album": Variant("s", str(state.get("album", ""))),
            "mpris:length": Variant("x", self._int(state.get("duration", 0)) * 1_000_000),
        }
        art_url = str(state.get("artUrl", ""))
        if art_url: metadata["mpris:artUrl"] = Variant("s", art_url)
        return metadata

    @dbus_property(access=PropertyAccess.READWRITE)
    def Volume(self) -> "d": return self._float(self.player.volume) / 100

    @Volume.setter
    def Volume(self, value: "d") -> None: self.player.set_volume(round(value * 100))

    @dbus_property(access=PropertyAccess.READ)
    def Position(self) -> "x": return self._int(self._state().get("position", 0)) * 1_000_000

    @dbus_property(access=PropertyAccess.READ)
    def MinimumRate(self) -> "d": return 1.0

    @dbus_property(access=PropertyAccess.READ)
    def MaximumRate(self) -> "d": return 1.0

    @dbus_property(access=PropertyAccess.READ)
    def CanGoNext(self) -> "b": return bool(self.player.queue)

    @dbus_property(access=PropertyAccess.READ)
    def CanGoPrevious(self) -> "b": return bool(self.player.queue)

    @dbus_property(access=PropertyAccess.READ)
    def CanPlay(self) -> "b": return bool(self.player.queue)

    @dbus_property(access=PropertyAccess.READ)
    def CanPause(self) -> "b": return bool(self.player.queue)

    @dbus_property(access=PropertyAccess.READ)
    def CanSeek(self) -> "b": return bool(self.player.queue)

    @dbus_property(access=PropertyAccess.READ)
    def CanControl(self) -> "b": return True

    def publish(self, seeked: bool = False) -> None:
        properties = {
            "PlaybackStatus": self.PlaybackStatus,
            "LoopStatus": self.LoopStatus,
            "Shuffle": self.Shuffle,
            "Metadata": self.Metadata,
            "Volume": self.Volume,
            "CanGoNext": self.CanGoNext,
            "CanGoPrevious": self.CanGoPrevious,
            "CanPlay": self.CanPlay,
            "CanPause": self.CanPause,
            "CanSeek": self.CanSeek,
        }
        changed = {key: value for key, value in properties.items()
                   if self.last_properties.get(key) != value}
        self.last_properties = properties
        if changed: self.emit_properties_changed(changed)
        if seeked: self.Seeked(self.Position)


class MprisBridge:
    def __init__(self, player: Any) -> None:
        self.player = player
        self.loop: asyncio.AbstractEventLoop | None = None
        self.interface: MprisPlayer | None = None
        threading.Thread(target=self._run, daemon=True).start()

    def _run(self) -> None:
        self.loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self.loop)
        self.loop.run_until_complete(self._setup())
        self.loop.run_forever()

    async def _setup(self) -> None:
        bus = await MessageBus().connect()
        root = MprisRoot()
        self.interface = MprisPlayer(self.player)
        bus.export("/org/mpris/MediaPlayer2", root)
        bus.export("/org/mpris/MediaPlayer2", self.interface)
        await bus.request_name("org.mpris.MediaPlayer2.omarchy_yandex_music")
        self.interface.publish()

    def publish(self, seeked: bool = False) -> None:
        if self.loop and self.interface:
            self.loop.call_soon_threadsafe(self.interface.publish, seeked)


class Player:
    def __init__(self) -> None:
        self.lock = threading.RLock()
        self.api_lock = threading.Lock()
        self.client: Client | None = None
        self.queue: list[Any] = []
        self.queue_source: list[Any] = []
        self.queue_extending = False
        self.queue_advance_pending = False
        self.queue_generation = 0
        self.queue_revision = 0
        self.queue_collection_key = ""
        self.queue_artist_id = ""
        self.queue_artist_page = 0
        self.queue_artist_has_more = False
        self.queue_advance_automatic = False
        self.detached_track: Any | None = None
        self.library_revision = 0
        self.library_hub_generation = 0
        self.library_hub_revision = 0
        self.library_hub = self._empty_library_hub()
        self.library_hub_tracks: list[Any] = []
        self.library_hub_source: list[tuple[Any, str]] = []
        self.library_hub_offset = 0
        self.library_hub_cache: OrderedDict[str, dict[str, Any]] = OrderedDict()
        self.personal_playlist_models: dict[str, Any] = {}
        self.index = -1
        self.playlists: list[dict[str, Any]] = []
        self.search_results: list[Any] = []
        self.catalog_generation = 0
        self.suggestion_generation = 0
        self.catalog_revision = 0
        self.catalog = self._empty_catalog()
        self.catalog_search_models: dict[str, list[Any]] = {
            section: [] for section in CATALOG_SECTIONS
        }
        self.catalog_entity_tracks: list[Any] = []
        self.catalog_entity_source: list[Any] = []
        self.catalog_entity_offset = 0
        self.catalog_cache: OrderedDict[str, dict[str, Any]] = OrderedDict()
        self.lyrics_cache: OrderedDict[str, dict[str, Any]] = OrderedDict()
        self.lyrics_loading: set[str] = set()
        self.lyrics_generation = 0
        self.track_info_cache: OrderedDict[str, dict[str, Any]] = OrderedDict()
        self.track_info_loading: set[str] = set()
        self.track_info_generation = 0
        self.artist_results: list[Any] = []
        self.library_results: list[Any] = []
        self.library_source: list[Any] = []
        self.library_offset = 0
        self.library_generation = 0
        self.active_library_cache_key = ""
        self.collection_cache: dict[str, dict[str, Any]] = {}
        self.liked_ids: set[str] = set()
        self.liked_rows: list[Any] = []
        self.liked_rows_at = 0.0
        self.disliked_ids: set[str] = set()
        self.radio_station = ""
        self.radio_batch_id = ""
        self.radio_track_batches: dict[str, str] = {}
        self.radio_extending = False
        self.radio_advance_pending = False
        self.playback_report: dict[str, Any] | None = None
        self.telemetry_queue: queue_module.Queue[Any] = queue_module.Queue(maxsize=TELEMETRY_QUEUE_SIZE)
        self.mpv: subprocess.Popen | None = None
        self.had_file = False
        self.active_ticks = 0
        self.play_generation = 0
        self.consecutive_failures = 0
        self.last_saved_at = 0.0
        self.volume = 70
        self.muted = False
        self.preferences = self._load_preferences()
        self.network: dict[str, Any] = {
            "checking": False, "available": None, "latencyMs": None,
            "serviceAvailable": None, "region": None, "checkedAt": 0, "error": "",
        }
        self.state: dict[str, Any] = {
            "version": APP_VERSION,
            "authenticated": False, "connecting": False, "authPending": False,
            "authUrl": "", "authCode": "", "error": "", "playing": False,
            "loading": False, "loadingKind": "", "loadingStage": "",
            "title": "", "trackId": "", "artist": "", "album": "",
            "artUrl": "", "artistId": "", "artists": [], "queueName": "", "artistBrowseName": "",
            "libraryBrowseName": "", "libraryTotal": 0,
            "libraryHasMore": False, "libraryLoadingMore": False, "libraryFromCache": False,
            "position": 0.0, "positionObservedAt": 0.0, "duration": 0, "stopped": True,
            "volume": self.volume, "muted": self.muted,
            "liked": False, "disliked": False, "restoring": False,
            "preferences": dict(self.preferences),
        }
        self.mpris = MprisBridge(self)
        threading.Thread(target=self._telemetry_worker, daemon=True).start()
        threading.Thread(target=self._restore, daemon=True).start()
        threading.Thread(target=self._monitor, daemon=True).start()

    def _publish_mpris(self, seeked: bool = False) -> None:
        self.mpris.publish(seeked)

    @staticmethod
    def _is_rate_limit_error(exc: Any) -> bool:
        message = str(exc).lower()
        return "429" in message or "too-many-requests" in message or "too many requests" in message

    @classmethod
    def _friendly_error(cls, exc: Any) -> str:
        if cls._is_rate_limit_error(exc): return RATE_LIMIT_MESSAGE
        return str(exc).replace("\n", " ")[:300]

    def _set_error(self, exc: Any) -> None:
        with self.lock:
            self.state["error"] = self._friendly_error(exc)
            self.state["loading"] = False
            self.state["loadingKind"] = ""
            self.state["loadingStage"] = ""
            self.state["connecting"] = False

    def _api_call(self, function: Callable[[], Any], *, retry_rate_limit: bool = True,
                  update_loading: bool = True) -> Any:
        """Serialize library calls and optionally retry Yandex Music HTTP 429 responses."""
        delays = RATE_LIMIT_DELAYS if retry_rate_limit else ()
        with self.api_lock:
            for attempt in range(len(delays) + 1):
                try:
                    result = function()
                    if update_loading:
                        with self.lock:
                            if self.state.get("loadingStage") == "rateLimit":
                                self.state["loadingStage"] = ""
                    return result
                except Exception as exc:
                    rate_limited = self._is_rate_limit_error(exc)
                    if not rate_limited:
                        raise
                    if attempt >= len(delays):
                        raise RuntimeError(RATE_LIMIT_MESSAGE) from exc
                    if update_loading:
                        with self.lock: self.state["loadingStage"] = "rateLimit"
                    threading.Event().wait(delays[attempt])
        raise RuntimeError(RATE_LIMIT_MESSAGE)

    def _enqueue_telemetry(self, *operations: Callable[[], Any]) -> None:
        """Queue ordered best-effort analytics without blocking playback controls."""
        for operation in operations:
            try: self.telemetry_queue.put_nowait(operation)
            except queue_module.Full: break

    def _telemetry_worker(self) -> None:
        while True:
            operation = self.telemetry_queue.get()
            try:
                # Analytics must remain serialized with foreground API calls, but
                # must not amplify a rate limit or expose a background error in UI.
                self._api_call(operation, retry_rate_limit=False, update_loading=False)
            except Exception:
                continue
            finally:
                self.telemetry_queue.task_done()

    def _report_radio_started(self, station: str, batch_id: str) -> None:
        with self.lock: client = self.client
        if not client or not station: return
        account_uid = getattr(client, "account_uid", None)
        source = f"mobile-radio-user-{account_uid}" if account_uid else RADIO_REPORT_FROM
        self._enqueue_telemetry(lambda client=client, station=station, batch_id=batch_id,
                               source=source:
            client.rotor_station_feedback_radio_started(
                station, from_=source, batch_id=batch_id or None))

    def _update_playback_clock_locked(self, playing: bool, now: float | None = None) -> None:
        report = self.playback_report
        if not report: return
        current = time.monotonic() if now is None else now
        elapsed = max(0.0, min(5.0, current - self._float(report["lastTick"])))
        if report["playing"]: report["playedSeconds"] += elapsed
        report["lastTick"] = current
        report["playing"] = playing

    def _begin_playback_reporting(self, track: Any) -> None:
        track_id = self._track_id(track)
        if not track_id: return
        now = time.monotonic()
        with self.lock:
            if self.playback_report and self.playback_report.get("trackId") == track_id:
                self._update_playback_clock_locked(True, now)
                return
            client = self.client
            if not client: return
            albums = list(getattr(track, "albums", None) or [])
            album_id = str(getattr(albums[0], "id", "")) if albums else ""
            duration = max(0, self._int(getattr(track, "duration_ms", 0)) // 1000)
            station = self.radio_station
            batch_id = self.radio_track_batches.get(track_id, self.radio_batch_id)
            play_id = uuid.uuid4().hex
            self.playback_report = {
                "client": client, "trackId": track_id, "albumId": album_id,
                "duration": duration, "station": station, "batchId": batch_id,
                "playId": play_id, "playedSeconds": 0.0,
                "lastTick": now, "playing": True,
            }
        operations: list[Callable[[], Any]] = []
        if album_id:
            operations.append(lambda client=client, track_id=track_id, album_id=album_id,
                              play_id=play_id, duration=duration:
                client.play_audio(track_id, from_=PLAYBACK_REPORT_FROM, album_id=album_id,
                    play_id=play_id, track_length_seconds=0, total_played_seconds=0,
                    end_position_seconds=duration))
        if station:
            operations.append(lambda client=client, station=station, track_id=track_id,
                              batch_id=batch_id:
                client.rotor_station_feedback_track_started(
                    station, track_id, batch_id=batch_id or None))
        self._enqueue_telemetry(*operations)

    def _finish_playback_reporting(self, *, finished: bool) -> None:
        with self.lock:
            report = self.playback_report
            if not report: return
            self._update_playback_clock_locked(False)
            self.playback_report = None
            position = self._int(self.state.get("position", 0))
            duration = self._int(report["duration"] or self.state.get("duration", 0))
            played = max(0, self._int(round(self._float(report["playedSeconds"]))))
            end_position = duration if finished and duration else max(0, position)
            client = report["client"]
            track_id = str(report["trackId"])
            album_id = str(report["albumId"])
            play_id = str(report["playId"])
            station = str(report["station"])
            batch_id = str(report["batchId"])
        operations: list[Callable[[], Any]] = []
        if album_id:
            operations.append(lambda client=client, track_id=track_id, album_id=album_id,
                              play_id=play_id, duration=duration, played=played,
                              end_position=end_position:
                client.play_audio(track_id, from_=PLAYBACK_REPORT_FROM, album_id=album_id,
                    play_id=play_id, track_length_seconds=duration,
                    total_played_seconds=played, end_position_seconds=end_position))
        if station:
            if finished:
                operations.append(lambda client=client, station=station, track_id=track_id,
                                  played=played, batch_id=batch_id:
                    client.rotor_station_feedback_track_finished(
                        station, track_id, self._float(played), batch_id=batch_id or None))
            else:
                operations.append(lambda client=client, station=station, track_id=track_id,
                                  played=played, batch_id=batch_id:
                    client.rotor_station_feedback_skip(
                        station, track_id, self._float(played), batch_id=batch_id or None))
        self._enqueue_telemetry(*operations)

    def _get_liked_rows(self) -> list[Any]:
        def fetch() -> list[Any]:
            with self.lock:
                fresh = self.liked_rows_at and time.monotonic() - self.liked_rows_at < COLLECTION_CACHE_TTL
                if fresh: return list(self.liked_rows)
                client = self.client
            if not client: return []
            liked = client.users_likes_tracks()
            rows = list(liked.tracks or []) if liked else []
            with self.lock:
                self.liked_rows = rows
                self.liked_rows_at = time.monotonic()
            return list(rows)
        return self._api_call(fetch)

    def network_status(self, start: bool = False) -> dict[str, Any]:
        now = self._int(time.time())
        with self.lock:
            fresh = self.network["checkedAt"] and now - self._int(self.network["checkedAt"]) < NETWORK_PROBE_TTL
            should_start = start and not self.network["checking"] and not fresh
            if should_start:
                self.network.update(checking=True, error="")
            snapshot = dict(self.network)
        if should_start:
            threading.Thread(target=self._probe_network, daemon=True).start()
        return snapshot

    def _probe_network(self) -> None:
        started = time.monotonic()
        result: dict[str, Any] = {
            "checking": False, "available": False, "latencyMs": None,
            "serviceAvailable": None, "region": None,
            "checkedAt": self._int(time.time()), "error": "",
        }
        try:
            response = requests.get(API_STATUS_URL, timeout=(3, 5))
            result["latencyMs"] = max(1, round((time.monotonic() - started) * 1000))
            response.raise_for_status()
            account = (response.json().get("result") or {}).get("account") or {}
            result.update(available=True, serviceAvailable=account.get("serviceAvailable"),
                          region=account.get("region"))
        except Exception as exc:
            if isinstance(exc, requests.exceptions.Timeout):
                result["error"] = "таймаут"
            elif isinstance(exc, requests.exceptions.SSLError):
                result["error"] = "ошибка TLS"
            elif isinstance(exc, requests.exceptions.HTTPError):
                status = exc.response.status_code if exc.response is not None else ""
                result["error"] = f"HTTP {status}".strip()
            elif isinstance(exc, requests.exceptions.ConnectionError):
                result["error"] = "ошибка соединения"
            elif isinstance(exc, (ValueError, TypeError, AttributeError)):
                result["error"] = "некорректный ответ"
            else:
                result["error"] = "неизвестная ошибка"
        with self.lock:
            self.network.update(result)

    def _load_preferences(self) -> dict[str, Any]:
        preferences = dict(DEFAULT_PREFERENCES)
        try:
            saved = json.loads(PREFERENCES_FILE.read_text()) if PREFERENCES_FILE.exists() else {}
            if isinstance(saved, dict): preferences.update(saved)
        except Exception:
            saved = {}
        bool_keys = ("autoResume", "restoreQueue", "restorePosition", "restoreVolume",
                     "showControls", "showArtist", "showTitle", "showCover", "showProgress")
        for key in bool_keys: preferences[key] = bool(preferences.get(key, DEFAULT_PREFERENCES[key]))
        allowed = {
            "audioQuality": ("best", "economy"),
            "playbackMode": ("order", "shuffle", "repeatQueue", "repeatTrack"),
            "waveMood": ("all", "fun", "active", "calm", "sad"),
            "waveDiversity": ("default", "favorite", "popular", "discover"),
            "waveLanguage": ("any", "russian", "not-russian"),
            "coverShape": ("square", "rounded", "circle"),
            "barWidth": ("compact", "normal", "wide"),
            "longTitleMode": ("truncate", "scroll"),
            "notifications": ("off", "all"),
        }
        for key, values in allowed.items():
            if preferences.get(key) not in values: preferences[key] = DEFAULT_PREFERENCES[key]
        return preferences

    def set_preference(self, key: str, value: Any) -> None:
        if key not in DEFAULT_PREFERENCES: raise ValueError(f"Неизвестная настройка: {key}")
        bool_keys = ("autoResume", "restoreQueue", "restorePosition", "restoreVolume",
                     "showControls", "showArtist", "showTitle", "showCover", "showProgress")
        allowed = {
            "audioQuality": ("best", "economy"),
            "playbackMode": ("order", "shuffle", "repeatQueue", "repeatTrack"),
            "waveMood": ("all", "fun", "active", "calm", "sad"),
            "waveDiversity": ("default", "favorite", "popular", "discover"),
            "waveLanguage": ("any", "russian", "not-russian"),
            "coverShape": ("square", "rounded", "circle"),
            "barWidth": ("compact", "normal", "wide"),
            "longTitleMode": ("truncate", "scroll"),
            "notifications": ("off", "all"),
        }
        if key in bool_keys:
            value = str(value).lower() in ("1", "true", "yes", "on")
        elif key in allowed and value not in allowed[key]:
            raise ValueError(f"Недопустимое значение настройки {key}")
        with self.lock:
            self.preferences[key] = value
            self.state["preferences"] = dict(self.preferences)
            self.state["error"] = ""
        atomic_json(PREFERENCES_FILE, self.preferences)
        if key == "playbackMode": self._publish_mpris()

    def _load_token(self) -> dict[str, Any]:
        try:
            return json.loads(TOKEN_FILE.read_text())
        except (OSError, json.JSONDecodeError) as exc:
            raise RuntimeError("Не удалось прочитать сохранённую сессию") from exc

    def _save_token(self, token: Any, previous_refresh: str | None = None) -> None:
        atomic_json(TOKEN_FILE, {
            "access_token": token.access_token,
            "refresh_token": token.refresh_token or previous_refresh,
            "expires_in": token.expires_in,
            "saved_at": self._int(time.time()),
        })

    def _refresh_token(self, saved: dict[str, Any]) -> str:
        refresh = saved.get("refresh_token")
        if not refresh:
            raise RuntimeError("Срок авторизации истёк — войдите снова")
        response = requests.post(f"{_OAUTH_BASE_URL}/token", data={
            "grant_type": "refresh_token", "refresh_token": refresh,
            "client_id": _DEFAULT_CLIENT_ID, "client_secret": _DEFAULT_CLIENT_SECRET,
        }, timeout=20)
        response.raise_for_status()
        data = response.json()
        saved.update({
            "access_token": data["access_token"],
            "refresh_token": data.get("refresh_token", refresh),
            "expires_in": data.get("expires_in"), "saved_at": self._int(time.time()),
        })
        atomic_json(TOKEN_FILE, saved)
        return saved["access_token"]

    def _restore(self) -> None:
        if not TOKEN_FILE.exists(): return
        try:
            saved = self._load_token()
            expires = int(saved.get("expires_in") or 0)
            token = saved["access_token"]
            if expires and time.time() >= int(saved.get("saved_at") or 0) + expires - 86400:
                token = self._refresh_token(saved)
            self._connect(token)
            self._restore_queue()
        except Exception as exc:
            self._set_error(f"Не удалось восстановить сессию: {exc}")

    def _connect(self, token: str) -> None:
        with self.lock: self.state.update(connecting=True, error="")
        client = Client(token).init()
        with self.lock:
            self.client = client
            self.state.update(authenticated=True, connecting=False, authPending=False, authCode="")
        self._load_playlists()
        self._load_liked_ids()
        self._load_disliked_ids()

    def authenticate(self) -> None:
        with self.lock:
            if self.state["authPending"]: return
            self.state.update(authPending=True, authUrl="", authCode="", error="")
        def worker() -> None:
            try:
                client = Client()
                def got_code(code: Any) -> None:
                    with self.lock: self.state.update(authUrl=code.verification_url, authCode=code.user_code)
                token = client.device_auth(on_code=got_code)
                self._save_token(token)
                self._connect(token.access_token)
            except Exception as exc:
                with self.lock: self.state["authPending"] = False
                self._set_error(f"Ошибка авторизации: {exc}")
        threading.Thread(target=worker, daemon=True).start()

    def logout(self) -> None:
        self.stop()
        with self.lock:
            self.client = None; self.playlists = []; self.artist_results = []; self.library_results = []
            self.search_results = []
            self.catalog_generation += 1; self.suggestion_generation += 1; self.catalog_revision += 1
            self.catalog = self._empty_catalog(); self.catalog["revision"] = self.catalog_revision
            self.catalog_search_models = {section: [] for section in CATALOG_SECTIONS}
            self.catalog_entity_tracks = []; self.catalog_entity_source = []
            self.catalog_entity_offset = 0; self.catalog_cache.clear()
            self.lyrics_cache.clear(); self.lyrics_loading.clear(); self.lyrics_generation += 1
            self.track_info_cache.clear(); self.track_info_loading.clear(); self.track_info_generation += 1
            self.library_source = []; self.library_offset = 0
            self.library_generation += 1; self.library_revision += 1
            self.active_library_cache_key = ""; self.collection_cache = {}
            self.library_hub_generation += 1; self.library_hub_revision += 1
            self.library_hub = self._empty_library_hub(); self.library_hub["revision"] = self.library_hub_revision
            self.library_hub_tracks = []; self.library_hub_source = []; self.library_hub_offset = 0
            self.library_hub_cache.clear(); self.personal_playlist_models.clear()
            self.liked_ids = set(); self.liked_rows = []; self.liked_rows_at = 0
            self.disliked_ids = set()
            self.queue = []; self.queue_source = []; self.queue_extending = False
            self.queue_advance_pending = False; self.queue_generation += 1; self.queue_revision += 1; self.index = -1
            self.queue_collection_key = ""; self.queue_artist_id = ""
            self.queue_artist_page = 0; self.queue_artist_has_more = False
            self.queue_advance_automatic = False; self.detached_track = None
            self.radio_station = ""; self.radio_batch_id = ""; self.radio_track_batches = {}
            self.radio_extending = False; self.playback_report = None
            self.state.update(authenticated=False, authPending=False, authUrl="", authCode="",
                              title="", trackId="", artist="", artistId="", artists=[], album="", artUrl="", queueName="",
                              artistBrowseName="", libraryBrowseName="", libraryTotal=0,
                              libraryHasMore=False, libraryLoadingMore=False, libraryFromCache=False,
                              loading=False, loadingKind="", playing=False, stopped=True,
                              position=0.0, positionObservedAt=time.time(),
                              liked=False, disliked=False, error="")
        self._publish_mpris()
        TOKEN_FILE.unlink(missing_ok=True); STATE_FILE.unlink(missing_ok=True)

    def _load_playlists(self) -> None:
        try:
            assert self.client
            rows = self._api_call(lambda: self.client.users_playlists_list()) or []
            with self.lock:
                self.playlists = [{"kind": str(p.kind), "title": p.title,
                                   "count": int(p.track_count or 0)} for p in rows]
        except Exception as exc: self._set_error(f"Не удалось загрузить плейлисты: {exc}")

    @staticmethod
    def _track_from_short(item: Any) -> Any:
        return item.track if getattr(item, "track", None) else item.fetch_track()

    @staticmethod
    def _short_track_id(row: Any) -> str:
        value = getattr(row, "track_id", None)
        if value is not None and not isinstance(value, (str, int)):
            value = getattr(value, "track_id", None) or getattr(value, "id", None)
        text = str(value if value is not None else getattr(row, "id", "") or "")
        return text.split(":", 1)[0]

    def _tracks_from_short_page(self, rows: list[Any], client: Client | None = None,
                                *, update_loading: bool = True) -> list[Any]:
        """Resolve one collection page in one API request while retaining source order."""
        client = client or self.client
        assert client
        def embedded(row: Any) -> Any:
            value = getattr(row, "track", None)
            if value is not None: return value
            if getattr(row, "title", None) is not None and getattr(row, "artists", None) is not None:
                return row
            return None

        missing_ids = [self._short_track_id(row) for row in rows if embedded(row) is None]
        track_ids = list(dict.fromkeys(track_id for track_id in missing_ids if track_id))
        fetched = (self._api_call(lambda: client.tracks(track_ids), update_loading=update_loading)
                   if track_ids else [])
        by_id = {str(getattr(track, "id", "")): track for track in (fetched or [])}
        tracks = []
        for row in rows:
            track = embedded(row) or by_id.get(self._short_track_id(row))
            if track is not None:
                tracks.append(track)
        return tracks

    def _reset_library_locked(self) -> int:
        self.library_generation += 1
        self.library_revision += 1
        self.library_source = []
        self.library_results = []
        self.library_offset = 0
        self.active_library_cache_key = ""
        self.state.update(libraryBrowseName="", libraryTotal=0,
                          libraryHasMore=False, libraryLoadingMore=False, libraryFromCache=False)
        return self.library_generation

    def _store_collection_cache_locked(self) -> None:
        key = self.active_library_cache_key
        if not key or not self.library_source or not self.library_results: return
        now = time.monotonic()
        self.collection_cache[key] = {
            "source": list(self.library_source),
            "results": list(self.library_results),
            "offset": self.library_offset,
            "title": str(self.state.get("libraryBrowseName", "")),
            "storedAt": now,
            "accessedAt": now,
        }
        while len(self.collection_cache) > COLLECTION_CACHE_MAX_ENTRIES:
            oldest = min(self.collection_cache,
                         key=lambda cache_key: self.collection_cache[cache_key]["accessedAt"])
            self.collection_cache.pop(oldest, None)

    def _activate_collection_cache_locked(self, key: str) -> bool:
        cached = self.collection_cache.get(key)
        if not cached: return False
        now = time.monotonic()
        if now - self._float(cached.get("storedAt", 0)) > COLLECTION_CACHE_TTL:
            self.collection_cache.pop(key, None)
            return False
        self.active_library_cache_key = key
        self.library_source = list(cached["source"])
        self.library_results = list(cached["results"])
        self.library_offset = min(self._int(cached["offset"]), len(self.library_source))
        cached["accessedAt"] = now
        self.library_revision += 1
        self.state.update(libraryBrowseName=str(cached["title"]),
                          libraryTotal=len(self.library_source),
                          libraryHasMore=self.library_offset < len(self.library_source),
                          libraryLoadingMore=False, libraryFromCache=True,
                          loading=False, loadingKind="", error="")
        return True

    @staticmethod
    def _track_id(track: Any) -> str:
        return str(getattr(track, "id", ""))

    def _current_track_locked(self) -> Any | None:
        return self.detached_track or (
            self.queue[self.index] if 0 <= self.index < len(self.queue) else None)

    def _update_likes_collection_locked(self, track: Any, liked: bool) -> None:
        """Apply a confirmed like change to loaded lists and their in-memory cache."""
        track_id = self._track_id(track)
        if not track_id: return

        def update(source: list[Any], results: list[Any], offset: int) -> tuple[list[Any], list[Any], int]:
            source_ids = [self._track_id(row) for row in source]
            if liked:
                if track_id not in source_ids:
                    source.insert(0, track)
                    offset += 1
                if all(self._track_id(item) != track_id for item in results):
                    results.insert(0, track)
            else:
                removed_before_offset = sum(
                    1 for index, item_id in enumerate(source_ids)
                    if index < offset and item_id == track_id)
                source[:] = [row for row in source if self._track_id(row) != track_id]
                results[:] = [item for item in results if self._track_id(item) != track_id]
                offset -= removed_before_offset
            return source, results, max(0, min(offset, len(source)))

        # Keep the complete liked-row snapshot usable, so reopening “My Likes”
        # does not need to fetch and resolve the whole collection again.
        if self.liked_rows_at:
            if liked:
                if all(self._track_id(row) != track_id for row in self.liked_rows):
                    self.liked_rows.insert(0, track)
            else:
                self.liked_rows = [row for row in self.liked_rows if self._track_id(row) != track_id]

        cached = self.collection_cache.get("likes")
        if cached:
            source, results, offset = update(
                list(cached["source"]), list(cached["results"]), self._int(cached["offset"]))
            if source and results:
                cached.update(source=source, results=results, offset=offset,
                              storedAt=time.monotonic(), accessedAt=time.monotonic())
            else:
                self.collection_cache.pop("likes", None)

        if self.active_library_cache_key != "likes": return
        self.library_source, self.library_results, self.library_offset = update(
            self.library_source, self.library_results, self.library_offset)
        self.library_revision += 1
        self.state.update(libraryTotal=len(self.library_source),
                          libraryHasMore=self.library_offset < len(self.library_source),
                          libraryLoadingMore=False, libraryFromCache=False)
        if self.library_source and self.library_results:
            self._store_collection_cache_locked()
        else:
            self.collection_cache.pop("likes", None)

    def _save_state(self, force: bool = False) -> None:
        if not force and time.monotonic() - self.last_saved_at < 5: return
        with self.lock:
            current = self._current_track_locked()
            current_batch = self.radio_track_batches.get(
                self._track_id(current), self.radio_batch_id) if current is not None else self.radio_batch_id
            value = {"queue": [self._track_id(t) for t in self.queue if self._track_id(t)],
                     "index": self.index, "queueName": self.state["queueName"],
                     "position": self.state["position"], "playing": self.state["playing"],
                     "volume": self.volume, "muted": self.muted,
                     "radioStation": self.radio_station, "radioBatchId": current_batch}
            value["queueCollectionKey"] = self.queue_collection_key
            value["queueArtistId"] = self.queue_artist_id
            value["queueArtistPage"] = self.queue_artist_page
            value["queueArtistHasMore"] = self.queue_artist_has_more
        atomic_json(STATE_FILE, value); self.last_saved_at = time.monotonic()

    def _restore_queue(self) -> None:
        if not STATE_FILE.exists() or not self.client: return
        try:
            saved = json.loads(STATE_FILE.read_text())
            ids = [str(x) for x in saved.get("queue", []) if x]
            if self.preferences["restoreVolume"]:
                self.volume = max(0, min(100, int(saved.get("volume", 70))))
                self.muted = bool(saved.get("muted", False))
            with self.lock: self.state.update(volume=self.volume, muted=self.muted)
            if not ids or not self.preferences["restoreQueue"]: return
            with self.lock: self.state["restoring"] = True
            tracks = self._api_call(lambda: self.client.tracks(ids)) or []
            with self.lock:
                queue_name = str(saved.get("queueName", ""))
                saved_collection_key = str(saved.get("queueCollectionKey", ""))
                collection_key = saved_collection_key or (
                    "likes" if queue_name == "Мне нравится" else "")
                saved_index = max(0, min(int(saved.get("index", 0)), len(tracks) - 1))
                if collection_key == "likes" and self.liked_rows_at:
                    current_id = self._track_id(tracks[saved_index]) if tracks else ""
                    kept_before = sum(
                        1 for track in tracks[:saved_index]
                        if self._track_id(track) in self.liked_ids)
                    tracks = [track for track in tracks if self._track_id(track) in self.liked_ids]
                    if current_id in self.liked_ids:
                        saved_index = kept_before
                    else:
                        saved_index = min(kept_before, max(0, len(tracks) - 1))
                self.queue = tracks
                self.queue_revision += 1
                self.index = max(0, min(saved_index, len(tracks) - 1))
                self.radio_station = str(saved.get("radioStation", ""))
                self.radio_batch_id = str(saved.get("radioBatchId", ""))
                self.radio_track_batches = ({self._track_id(track): self.radio_batch_id for track in tracks}
                                            if self.radio_station and self.radio_batch_id else {})
                self.state["queueName"] = queue_name
                self.queue_collection_key = collection_key
                self.queue_artist_id = str(saved.get("queueArtistId", ""))
                self.queue_artist_page = self._int(saved.get("queueArtistPage", 0))
                self.queue_artist_has_more = bool(saved.get("queueArtistHasMore", False))
                self.queue_advance_automatic = False
                self.detached_track = None
            should_resume = bool(saved.get("playing", False)) and bool(self.preferences["autoResume"])
            resume_position = int(saved.get("position", 0)) if self.preferences["restorePosition"] else 0
            if should_resume and self.radio_station:
                self._report_radio_started(self.radio_station, self.radio_batch_id)
            self._play_current(resume_position=resume_position, start_paused=not should_resume)
        except Exception as exc: self._set_error(f"Не удалось восстановить очередь: {exc}")
        finally:
            with self.lock: self.state["restoring"] = False

    def _loading(self, function: Callable[[], None], kind: str) -> None:
        with self.lock:
            if not self.state["authenticated"] or self.state["loading"]: return
            self.state.update(loading=True, loadingKind=kind, loadingStage="", error="")
        threading.Thread(target=function, daemon=True).start()

    def _load_liked_ids(self) -> None:
        try:
            assert self.client
            rows = self._get_liked_rows()
            with self.lock:
                self.liked_ids = {str(getattr(row, "id", "")) for row in rows if getattr(row, "id", "")}
                current = self._current_track_locked()
                if current is not None:
                    self.state["liked"] = self._track_id(current) in self.liked_ids
        except Exception as exc:
            self._set_error(f"Не удалось получить отметки «Мне нравится»: {exc}")

    def _load_disliked_ids(self) -> None:
        try:
            assert self.client
            disliked = self._api_call(lambda: self.client.users_dislikes_tracks())
            rows = list(disliked.tracks or []) if disliked else []
            with self.lock:
                self.disliked_ids = {
                    str(getattr(row, "id", "")) for row in rows if getattr(row, "id", "")
                } - self.liked_ids
                current = self._current_track_locked()
                if current is not None:
                    self.state["disliked"] = self._track_id(current) in self.disliked_ids
        except Exception as exc:
            self._set_error(f"Не удалось получить отметки «Не рекомендовать»: {exc}")

    def play_likes(self) -> None:
        with self.lock:
            self.artist_results = []
            generation = self._reset_library_locked()
            self.state["artistBrowseName"] = ""
            if self._activate_collection_cache_locked("likes"): return
        def load() -> None:
            try:
                assert self.client
                rows = self._get_liked_rows()
                tracks = self._tracks_from_short_page(rows[:LIBRARY_PAGE_SIZE])
                if not tracks: raise RuntimeError("В списке нет доступных треков")
                with self.lock:
                    if generation != self.library_generation: return
                    self.liked_ids = {str(getattr(row, "id", "")) for row in rows if getattr(row, "id", "")}
                    self.library_source = rows
                    self.library_results = tracks
                    self.library_offset = min(LIBRARY_PAGE_SIZE, len(rows))
                    self.active_library_cache_key = "likes"
                    self.library_revision += 1
                    self.state.update(libraryBrowseName="Мне нравится", libraryTotal=len(rows),
                                      libraryHasMore=self.library_offset < len(rows),
                                      libraryLoadingMore=False, libraryFromCache=False,
                                      loading=False, loadingKind="", error="")
                    self._store_collection_cache_locked()
            except Exception as exc:
                with self.lock:
                    if generation != self.library_generation: return
                self._set_error(f"Не удалось загрузить любимые треки: {exc}")
        self._loading(load, "likes")

    def _update_likes_queue_locked(self, track: Any, liked: bool) -> None:
        """Keep a queue started from “My Likes” in sync without stopping playback."""
        if self.queue_collection_key != "likes": return
        track_id = self._track_id(track)
        if not track_id: return

        self.queue_source = [row for row in self.queue_source if self._track_id(row) != track_id]
        if liked:
            if self.detached_track is not None and self._track_id(self.detached_track) == track_id:
                insert_at = max(0, min(self.index + 1, len(self.queue)))
                self.queue.insert(insert_at, track)
                self.index = insert_at
                self.detached_track = None
                self.queue_revision += 1
            return

        current = self.detached_track or (
            self.queue[self.index] if 0 <= self.index < len(self.queue) else None)
        if current is None or self._track_id(current) != track_id: return
        old_index = self.index
        self.queue = [item for item in self.queue if self._track_id(item) != track_id]
        self.index = sum(1 for item in self.queue[:old_index] if self._track_id(item) != track_id) - 1
        # The audio keeps playing, but its row is no longer part of the liked queue.
        # The virtual index remains immediately before the next queue item.
        self.detached_track = track
        self.queue_revision += 1

    def toggle_like(self) -> None:
        try:
            assert self.client
            with self.lock:
                track = self._current_track_locked()
                if track is None: return
                track_id = self._track_id(track)
                was_liked = track_id in self.liked_ids
            if not track_id: return
            changed = self._api_call(lambda: self.client.users_likes_tracks_remove(track_id)
                                     if was_liked else self.client.users_likes_tracks_add(track_id))
            if not changed: raise RuntimeError("Яндекс не подтвердил изменение")
            with self.lock:
                if was_liked:
                    self.liked_ids.discard(track_id)
                else:
                    self.liked_ids.add(track_id)
                    self.disliked_ids.discard(track_id)
                self._update_likes_collection_locked(track, not was_liked)
                self._update_likes_queue_locked(track, not was_liked)
                current = self._current_track_locked()
                if current is not None and self._track_id(current) == track_id:
                    self.state.update(liked=not was_liked,
                                      disliked=track_id in self.disliked_ids)
                self.state["error"] = ""
            self._save_state(True)
        except Exception as exc:
            self._set_error(f"Не удалось изменить отметку «Мне нравится»: {exc}")

    def toggle_dislike(self) -> None:
        try:
            assert self.client
            with self.lock:
                track = self._current_track_locked()
                if track is None: return
                track_id = self._track_id(track)
                was_disliked = track_id in self.disliked_ids
                was_liked = track_id in self.liked_ids
                advance_radio = bool(self.radio_station) and not was_disliked
            if not track_id: return
            changed = self._api_call(lambda: self.client.users_dislikes_tracks_remove(track_id)
                                     if was_disliked else self.client.users_dislikes_tracks_add(track_id))
            if not changed: raise RuntimeError("Яндекс не подтвердил изменение")
            with self.lock:
                if was_disliked:
                    self.disliked_ids.discard(track_id)
                else:
                    self.disliked_ids.add(track_id)
                    if was_liked:
                        self.liked_ids.discard(track_id)
                        self._update_likes_collection_locked(track, False)
                        self._update_likes_queue_locked(track, False)
                current = self._current_track_locked()
                if current is not None and self._track_id(current) == track_id:
                    self.state.update(liked=track_id in self.liked_ids,
                                      disliked=not was_disliked)
                self.state["error"] = ""
            self._save_state(True)
            if advance_radio: self.next()
        except Exception as exc:
            self._set_error(f"Не удалось изменить отметку «Не рекомендовать»: {exc}")

    def play_wave(self) -> None:
        def load() -> None:
            try:
                assert self.client
                station = "user:onyourwave"
                # The current settings2 endpoint requires JSON, while the
                # unofficial client's helper still submits form data.
                def update_settings() -> requests.Response:
                    response = requests.post(
                        f"{self.client.base_url}/rotor/station/{station}/settings2",
                        headers=dict(self.client._request.headers),
                        proxies=self.client._request.proxies,
                        json={"moodEnergy": str(self.preferences["waveMood"]),
                              "diversity": str(self.preferences["waveDiversity"]),
                              "language": str(self.preferences["waveLanguage"]), "type": "rotor"},
                        timeout=20)
                    response.raise_for_status()
                    return response
                settings_response = self._api_call(update_settings)
                if settings_response.json().get("result") != "ok":
                    raise RuntimeError("Яндекс не подтвердил настройки волны")
                result = self._api_call(lambda: self.client.rotor_station_tracks(station))
                tracks = [row.track for row in (result.sequence if result else [])
                          if getattr(row, "track", None)]
                if not tracks: raise RuntimeError("Яндекс не вернул треки для «Моей волны»")
                batch_id = str(result.batch_id or "") if result else ""
                self._set_queue(tracks, "Моя волна", station, batch_id)
            except Exception as exc:
                self._set_error(f"Не удалось запустить «Мою волну»: {exc}")
        self._loading(load, "wave")

    def play_track_radio(self) -> None:
        with self.lock:
            track = self._current_track_locked()
            track_id = self._track_id(track) if track is not None else ""
        if not track_id: return

        def load() -> None:
            try:
                assert self.client
                station = f"track:{track_id}"
                result = self._api_call(lambda: self.client.rotor_station_tracks(station))
                tracks = [row.track for row in (result.sequence if result else [])
                          if getattr(row, "track", None)]
                if not tracks: raise RuntimeError("Яндекс не вернул рекомендации для этого трека")
                batch_id = str(result.batch_id or "") if result else ""
                self._set_queue(tracks, "Радио по треку", station, batch_id)
            except Exception as exc:
                self._set_error(f"Не удалось запустить радио по треку: {exc}")
        self._loading(load, "radio")

    def _extend_radio(self, advance: bool = False) -> None:
        with self.lock:
            if not self.radio_station or not self.client: return
            if self.radio_extending:
                self.radio_advance_pending = self.radio_advance_pending or advance
                return
            self.radio_extending = True
            self.radio_advance_pending = advance
            if advance:
                loading_kind = "wave" if self.radio_station == "user:onyourwave" else "radio"
                self.state.update(loading=True, loadingKind=loading_kind, loadingStage="", error="")
            station = self.radio_station
            queue_id = self._track_id(self.queue[-1]) if self.queue else ""
            generation = self.queue_generation

        def load() -> None:
            should_advance = False
            failed_to_advance = False
            try:
                assert self.client
                # The radio protocol expects finish/skip feedback before the
                # request that advances the station sequence.
                self.telemetry_queue.join()
                result = self._api_call(
                    lambda: self.client.rotor_station_tracks(station, queue=queue_id or None))
                incoming = [row.track for row in (result.sequence if result else [])
                            if getattr(row, "track", None)]
                with self.lock:
                    if generation != self.queue_generation or station != self.radio_station: return
                    existing = {self._track_id(track) for track in self.queue}
                    fresh = [track for track in incoming if self._track_id(track) not in existing]
                    old_length = len(self.queue)
                    self.queue.extend(fresh)
                    if fresh: self.queue_revision += 1
                    if result:
                        self.radio_batch_id = str(result.batch_id or "")
                        for track in fresh:
                            self.radio_track_batches[self._track_id(track)] = self.radio_batch_id
                    should_advance = self.radio_advance_pending and bool(fresh) and self.index >= old_length - 1
                    failed_to_advance = self.radio_advance_pending and not fresh and self.index >= old_length - 1
                    if should_advance: self.index = old_length
                    self.radio_advance_pending = False
                    self.radio_extending = False
                if failed_to_advance:
                    raise RuntimeError("Яндекс не вернул новые треки для радио")
                if should_advance:
                    self._play_current()
                else:
                    with self.lock:
                        if self.state.get("loadingKind") in ("wave", "radio"):
                            self.state.update(loading=False, loadingKind="", loadingStage="")
                self._save_state(True)
            except Exception as exc:
                with self.lock:
                    self.radio_extending = False; self.radio_advance_pending = False
                self._set_error(f"Не удалось продолжить радио: {exc}")
        threading.Thread(target=load, daemon=True).start()

    def _extend_collection(self, advance: bool = False) -> None:
        with self.lock:
            if not self.queue_source or not self.client: return
            if self.queue_extending:
                self.queue_advance_pending = self.queue_advance_pending or advance
                return
            self.queue_extending = True
            self.queue_advance_pending = advance
            rows = list(self.queue_source[:LIBRARY_PAGE_SIZE])
            generation = self.queue_generation

        def load() -> None:
            should_advance = False
            try:
                tracks = self._tracks_from_short_page(rows)
                with self.lock:
                    if generation != self.queue_generation: return
                    old_length = len(self.queue)
                    self.queue.extend(tracks)
                    if tracks: self.queue_revision += 1
                    del self.queue_source[:len(rows)]
                    should_advance = self.queue_advance_pending and bool(tracks) and self.index >= old_length - 1
                    if should_advance: self.index = old_length
                    retry_advance = self.queue_advance_pending and not tracks and bool(self.queue_source)
                    self.queue_advance_pending = False
                    self.queue_extending = False
                self._save_state(True)
                if should_advance:
                    self._play_current()
                elif retry_advance:
                    self._extend_collection(advance=True)
            except Exception as exc:
                with self.lock:
                    if generation != self.queue_generation: return
                    self.queue_extending = False; self.queue_advance_pending = False
                self._set_error(f"Не удалось продолжить плейлист: {exc}")
        threading.Thread(target=load, daemon=True).start()

    def _extend_artist_queue(self, advance: bool = False,
                             automatic: bool = False) -> None:
        with self.lock:
            if not self.queue_artist_id or not self.queue_artist_has_more or not self.client:
                return
            if self.queue_extending:
                self.queue_advance_pending = self.queue_advance_pending or advance
                self.queue_advance_automatic = self.queue_advance_automatic or automatic
                return
            self.queue_extending = True
            self.queue_advance_pending = advance
            self.queue_advance_automatic = automatic
            artist_id = self.queue_artist_id
            page = self.queue_artist_page + 1
            client = self.client
            generation = self.queue_generation

        def load() -> None:
            try:
                result = self._api_call(
                    lambda: client.artists_tracks(
                        artist_id, page=page, page_size=CATALOG_PAGE_SIZE),
                    update_loading=False)
                rows = self._safe_rows(getattr(result, "tracks", None))
                tracks = self._tracks_from_short_page(
                    rows, client, update_loading=False)
                has_more = bool(rows) and self._page_has_more(
                    result, rows, page, CATALOG_PAGE_SIZE)
                should_advance = False
                retry_advance = False
                finish_advance = False
                advance_automatic = False
                with self.lock:
                    if generation != self.queue_generation: return
                    if self.client is not client: return
                    old_length = len(self.queue)
                    known = {self._track_id(track) for track in self.queue}
                    appended = []
                    for track in tracks:
                        track_id = self._track_id(track)
                        if track_id and track_id in known: continue
                        if track_id: known.add(track_id)
                        appended.append(track)
                    self.queue.extend(appended)
                    if appended: self.queue_revision += 1
                    self.queue_artist_page = page
                    self.queue_artist_has_more = has_more
                    requested_advance = self.queue_advance_pending
                    advance_automatic = self.queue_advance_automatic
                    should_advance = (requested_advance and bool(appended)
                                      and self.index >= old_length - 1)
                    if should_advance: self.index = old_length
                    retry_advance = requested_advance and not appended and has_more
                    finish_advance = requested_advance and not appended and not has_more
                    self.queue_advance_pending = False
                    self.queue_advance_automatic = False
                    self.queue_extending = False
                self._save_state(True)
                if should_advance:
                    self._play_current()
                elif retry_advance:
                    self._extend_artist_queue(True, advance_automatic)
                elif finish_advance:
                    self.next(automatic=advance_automatic)
            except Exception as exc:
                with self.lock:
                    if generation != self.queue_generation: return
                    if self.client is not client: return
                    self.queue_extending = False
                    self.queue_advance_pending = False
                    self.queue_advance_automatic = False
                self._set_error(f"Не удалось продолжить треки исполнителя: {exc}")
        threading.Thread(target=load, daemon=True).start()

    def _maybe_extend_collection(self) -> None:
        with self.lock:
            should_extend = bool(self.queue_source) and len(self.queue) - self.index <= 5
            should_extend_artist = (not should_extend and bool(self.queue_artist_id)
                                    and self.queue_artist_has_more
                                    and len(self.queue) - self.index <= 5)
        if should_extend:
            self._extend_collection()
        elif should_extend_artist:
            self._extend_artist_queue()

    def play_playlist(self, kind: str) -> None:
        cache_key = f"playlist:{kind}"
        with self.lock:
            self.artist_results = []
            generation = self._reset_library_locked()
            self.state["artistBrowseName"] = ""
            if self._activate_collection_cache_locked(cache_key): return
        def load() -> None:
            try:
                assert self.client
                playlist = self._api_call(lambda: self.client.users_playlists(kind))
                rows = list(self._api_call(playlist.fetch_tracks))
                tracks = self._tracks_from_short_page(rows[:LIBRARY_PAGE_SIZE])
                if not tracks: raise RuntimeError("В плейлисте нет доступных треков")
                with self.lock:
                    if generation != self.library_generation: return
                    self.library_source = rows
                    self.library_results = tracks
                    self.library_offset = min(LIBRARY_PAGE_SIZE, len(rows))
                    self.active_library_cache_key = cache_key
                    self.library_revision += 1
                    self.state.update(libraryBrowseName=playlist.title, libraryTotal=len(rows),
                                      libraryHasMore=self.library_offset < len(rows),
                                      libraryLoadingMore=False, libraryFromCache=False,
                                      loading=False, loadingKind="", error="")
                    self._store_collection_cache_locked()
            except Exception as exc:
                with self.lock:
                    if generation != self.library_generation: return
                self._set_error(f"Не удалось загрузить плейлист: {exc}")
        self._loading(load, "playlist")

    def load_more_library(self) -> None:
        with self.lock:
            if (not self.library_source or self.state["libraryLoadingMore"]
                    or self.library_offset >= len(self.library_source)):
                return
            start = self.library_offset
            rows = list(self.library_source[start:start + LIBRARY_PAGE_SIZE])
            generation = self.library_generation
            self.state.update(libraryLoadingMore=True, error="")

        def load() -> None:
            try:
                tracks = self._tracks_from_short_page(rows)
                with self.lock:
                    if generation != self.library_generation: return
                    self.library_results.extend(tracks)
                    self.library_offset = start + len(rows)
                    self.library_revision += 1
                    self.state.update(libraryHasMore=self.library_offset < len(self.library_source),
                                      libraryLoadingMore=False, libraryFromCache=False, error="")
                    self._store_collection_cache_locked()
            except Exception as exc:
                with self.lock:
                    if generation != self.library_generation: return
                    self.state["libraryLoadingMore"] = False
                self._set_error(f"Не удалось загрузить следующую страницу: {exc}")
        threading.Thread(target=load, daemon=True).start()

    @staticmethod
    def _empty_library_hub() -> dict[str, Any]:
        return {"view": "home", "section": "", "loading": False,
                "loadingMore": False, "hasMore": False, "total": 0,
                "error": "", "warning": "", "items": [], "revision": 0}

    def _library_hub_touch_locked(self) -> None:
        self.library_hub_revision += 1
        self.library_hub["revision"] = self.library_hub_revision

    def _library_hub_current(self, client: Any, generation: int) -> bool:
        return self.client is client and generation == self.library_hub_generation

    @classmethod
    def _station_metadata(cls, result: Any) -> dict[str, Any]:
        station = getattr(result, "station", None) or result
        station_id = getattr(station, "id", None)
        type_ = cls._text(getattr(station_id, "type", ""))
        tag = cls._text(getattr(station_id, "tag", ""))
        identifier = type_ + ":" + tag if type_ and tag else cls._text(
            getattr(station, "id_for_from", ""))
        icon = getattr(station, "icon", None)
        art_url = cls._text(getattr(station, "full_image_url", "")
                            or getattr(icon, "image_url", ""))
        if art_url:
            art_url = art_url.replace("%%", "400x400")
            if art_url.startswith("//"): art_url = "https:" + art_url
            elif not art_url.startswith(("http://", "https://")):
                art_url = "https://" + art_url.lstrip("/")
        return {"entityType": "station", "stationId": identifier,
                "title": cls._text(getattr(station, "name", "")
                                   or getattr(result, "rup_title", "")
                                   or getattr(result, "custom_name", "") or "Радиостанция"),
                "subtitle": cls._text(getattr(result, "explanation", "")
                                      or getattr(result, "rup_description", "")),
                "artUrl": art_url}

    @classmethod
    def _history_item_key(cls, item: Any) -> str:
        type_ = cls._text(getattr(item, "type", ""))
        data = getattr(item, "data", None)
        item_id = getattr(data, "item_id", None)
        if type_ == "track":
            return f"track:{cls._text(getattr(item_id, 'track_id', ''))}:{cls._text(getattr(item_id, 'album_id', ''))}"
        if type_ == "playlist":
            return f"playlist:{cls._text(getattr(item_id, 'uid', ''))}:{cls._text(getattr(item_id, 'kind', ''))}"
        if type_ == "wave":
            return "wave:" + ":".join(cls._text(value) for value in cls._safe_rows(
                getattr(item_id, "seeds", None)))
        return type_ + ":" + cls._text(getattr(item_id, "id", ""))

    def _history_source(self, client: Any) -> list[tuple[Any, str]]:
        history = self._api_call(lambda: client.music_history(full_models_count=0),
                                 update_loading=False)
        raw: list[tuple[Any, str]] = []
        seen: set[str] = set()
        for tab in self._safe_rows(getattr(history, "history_tabs", None)):
            date = self._text(getattr(tab, "date", ""))
            for group in self._safe_rows(getattr(tab, "items", None)):
                values = []
                context = getattr(group, "context", None)
                if context is not None: values.append(context)
                values.extend(self._safe_rows(getattr(group, "tracks", None)))
                for item in values:
                    key = self._history_item_key(item)
                    if key and key not in seen:
                        seen.add(key); raw.append((item, date))
        return raw

    def _history_items(self, client: Any, raw: list[tuple[Any, str]],
                       track_index_offset: int = 0) -> tuple[list[dict[str, Any]], list[Any], str]:
        missing = [(item, date) for item, date in raw
                   if getattr(getattr(item, "data", None), "full_model", None) is None]
        warning = ""
        if missing:
            track_ids: list[tuple[str, str]] = []
            album_ids: list[str] = []
            artist_ids: list[str] = []
            playlist_ids: list[tuple[str, str]] = []
            wave_seeds: list[list[str]] = []
            for item, _date in missing:
                type_ = self._text(getattr(item, "type", ""))
                item_id = getattr(getattr(item, "data", None), "item_id", None)
                if type_ == "track":
                    track_id = self._text(getattr(item_id, "track_id", ""))
                    album_id = self._text(getattr(item_id, "album_id", ""))
                    if track_id: track_ids.append((track_id, album_id))
                elif type_ == "album":
                    value = self._text(getattr(item_id, "id", ""))
                    if value: album_ids.append(value)
                elif type_ == "artist":
                    value = self._text(getattr(item_id, "id", ""))
                    if value: artist_ids.append(value)
                elif type_ == "playlist":
                    owner = self._text(getattr(item_id, "uid", ""))
                    kind = self._text(getattr(item_id, "kind", ""))
                    if owner and kind: playlist_ids.append((owner, kind))
                elif type_ == "wave":
                    seeds = [self._text(value) for value in self._safe_rows(
                        getattr(item_id, "seeds", None)) if self._text(value)]
                    if seeds: wave_seeds.append(seeds)
            try:
                resolved = self._api_call(lambda: client.music_history_items(
                    track_ids=track_ids or None, album_ids=album_ids or None,
                    artist_ids=artist_ids or None, playlist_ids=playlist_ids or None,
                    wave_seeds=wave_seeds or None), update_loading=False)
                by_key = {self._history_item_key(item): item for item in self._safe_rows(
                    getattr(resolved, "items", None))}
                raw = [(by_key.get(self._history_item_key(item), item), date)
                       if getattr(getattr(item, "data", None), "full_model", None) is None
                       else (item, date) for item, date in raw]
            except Exception:
                warning = "Некоторые элементы истории пока недоступны."

        rows: list[dict[str, Any]] = []
        tracks: list[Any] = []
        seen: set[str] = set()
        for item, date in raw:
            key = self._history_item_key(item)
            if not key or key in seen: continue
            seen.add(key)
            type_ = self._text(getattr(item, "type", ""))
            data = getattr(item, "data", None)
            item_id = getattr(data, "item_id", None)
            full_model = getattr(data, "full_model", None)
            if type_ == "track":
                track = full_model
                if track is None or not getattr(track, "id", None): continue
                index = track_index_offset + len(tracks); tracks.append(track)
                rows.append({**self._metadata(track), "entityType": "track",
                             "trackIndex": index, "historyDate": date})
                continue
            container = full_model
            if type_ == "album":
                model = getattr(container, "album", None)
                if model is None and getattr(container, "id", None): model = container
                row = self._album_metadata(model) if model is not None else {
                    "entityType": "album", "id": self._text(getattr(item_id, "id", "")),
                    "title": "Альбом", "artUrl": ""}
            elif type_ == "artist":
                model = getattr(container, "artist", None)
                if model is None and getattr(container, "id", None): model = container
                row = self._artist_metadata(model) if model is not None else {
                    "entityType": "artist", "id": self._text(getattr(item_id, "id", "")),
                    "name": "Исполнитель", "artUrl": ""}
            elif type_ == "playlist":
                model = getattr(container, "playlist", None)
                row = self._playlist_metadata(model) if model is not None else {
                    "entityType": "playlist", "uuid": "",
                    "owner": self._text(getattr(item_id, "uid", "")),
                    "kind": self._text(getattr(item_id, "kind", "")),
                    "title": "Плейлист", "artUrl": "", "trackCount": 0}
            elif type_ == "wave":
                seeds = [self._text(value) for value in self._safe_rows(
                    getattr(item_id, "seeds", None)) if self._text(value)]
                station_id = seeds[0] if seeds else ""
                wave = getattr(container, "wave", None)
                row = {"entityType": "station", "stationId": station_id,
                       "title": self._text(getattr(wave, "title", "") or "Радио из истории"),
                       "subtitle": "", "artUrl": self._text(
                           getattr(container, "simple_wave_foreground_image_url", ""))}
            else:
                continue
            row["historyDate"] = date
            rows.append(row)
        return rows, tracks, warning

    def library_section(self, section: str, *, force: bool = False) -> None:
        section = self._text(section)
        if section not in LIBRARY_HUB_SECTIONS: return
        with self.lock:
            client = self.client
            if not client: return
            self.library_hub_generation += 1
            generation = self.library_hub_generation
            cached = None if force else self.library_hub_cache.get(section)
            if cached and time.monotonic() - self._float(cached.get("storedAt", 0)) <= LIBRARY_HUB_CACHE_TTL:
                cached["accessedAt"] = time.monotonic()
                self.library_hub_tracks = list(cached.get("tracks", []))
                self.library_hub_source = list(cached.get("source", []))
                self.library_hub_offset = min(self._int(cached.get("offset", 0)),
                                              len(self.library_hub_source))
                self.library_hub = {"view": "section", "section": section, "loading": False,
                    "loadingMore": False,
                    "hasMore": self.library_hub_offset < len(self.library_hub_source),
                    "total": len(self.library_hub_source) if self.library_hub_source
                    else len(cached.get("items", [])),
                    "error": "", "warning": str(cached.get("warning", "")),
                    "items": copy.deepcopy(cached.get("items", [])), "revision": 0}
                self._library_hub_touch_locked()
                return
            self.library_hub = {"view": "section", "section": section, "loading": True,
                "loadingMore": False, "hasMore": False, "total": 0,
                "error": "", "warning": "", "items": [], "revision": 0}
            self.library_hub_tracks = []; self.library_hub_source = []; self.library_hub_offset = 0
            self._library_hub_touch_locked()

        def load() -> None:
            items: list[dict[str, Any]] = []
            tracks: list[Any] = []
            warning = ""
            source: list[tuple[Any, str]] = []
            offset = 0
            personal_models: dict[str, Any] = {}
            try:
                if section == "personal":
                    failures = 0
                    for playlist_id, fallback_title in PERSONAL_PLAYLISTS:
                        try:
                            generated = self._api_call(
                                lambda value=playlist_id: client.playlists_personal(value),
                                update_loading=False)
                            playlist = getattr(generated, "data", None)
                            if playlist is None:
                                failures += 1
                                continue
                            personal_models[playlist_id] = playlist
                            items.append({**self._playlist_metadata(playlist),
                                "personalId": playlist_id,
                                "title": self._text(getattr(playlist, "title", "")) or fallback_title,
                                "available": bool(getattr(generated, "ready", True))})
                        except Exception:
                            failures += 1
                    if failures: warning = "Некоторые персональные подборки пока недоступны."
                    if not items and failures: raise RuntimeError("personal playlists unavailable")
                elif section == "history":
                    source = self._history_source(client)
                    offset = min(LIBRARY_PAGE_SIZE, len(source))
                    items, tracks, warning = self._history_items(client, source[:offset])
                elif section == "albums":
                    likes = self._api_call(lambda: client.users_likes_albums(), update_loading=False) or []
                    items = [self._album_metadata(getattr(like, "album", None)) for like in likes
                             if getattr(like, "album", None) is not None]
                elif section == "artists":
                    likes = self._api_call(lambda: client.users_likes_artists(), update_loading=False) or []
                    items = [self._artist_metadata(getattr(like, "artist", None)) for like in likes
                             if getattr(like, "artist", None) is not None]
                elif section == "playlists":
                    likes = self._api_call(lambda: client.users_likes_playlists(), update_loading=False) or []
                    items = [self._playlist_metadata(getattr(like, "playlist", None)) for like in likes
                             if getattr(like, "playlist", None) is not None]
                else:
                    values = self._api_call(lambda: client.rotor_stations_list(), update_loading=False) or []
                    items = [self._station_metadata(value) for value in values]
                    items = [row for row in items if row["stationId"]]
                unique: list[dict[str, Any]] = []
                seen: set[str] = set()
                for row in items:
                    key = self._catalog_key(
                        "playlists" if row.get("entityType") == "playlist"
                        else str(row.get("entityType", "")) + "s", row)
                    if row.get("entityType") == "station": key = str(row.get("stationId", ""))
                    if key and key not in seen: seen.add(key); unique.append(row)
                items = unique
                with self.lock:
                    if not self._library_hub_current(client, generation): return
                    if personal_models: self.personal_playlist_models.update(personal_models)
                    self.library_hub_tracks = tracks
                    self.library_hub_source = source
                    self.library_hub_offset = offset
                    now = time.monotonic()
                    self.library_hub_cache[section] = {"items": copy.deepcopy(items),
                        "tracks": list(tracks), "source": list(source), "offset": offset,
                        "warning": warning, "storedAt": now, "accessedAt": now}
                    self.library_hub_cache.move_to_end(section)
                    while len(self.library_hub_cache) > LIBRARY_HUB_CACHE_MAX_ENTRIES:
                        self.library_hub_cache.popitem(last=False)
                    self.library_hub.update(loading=False, loadingMore=False,
                        items=items, total=len(source) if source else len(items),
                        hasMore=offset < len(source), warning=warning, error="")
                    self._library_hub_touch_locked()
            except Exception as exc:
                with self.lock:
                    if not self._library_hub_current(client, generation): return
                    self.library_hub.update(loading=False, loadingMore=False,
                        hasMore=False, items=[], warning="",
                        error=self._catalog_error(exc, "Раздел медиатеки"))
                    self._library_hub_touch_locked()
        threading.Thread(target=load, daemon=True).start()

    def library_section_more(self) -> None:
        with self.lock:
            if (self.library_hub.get("section") != "history"
                    or self.library_hub.get("loadingMore")
                    or self.library_hub_offset >= len(self.library_hub_source)
                    or not self.client):
                return
            client = self.client; generation = self.library_hub_generation
            start = self.library_hub_offset
            page = list(self.library_hub_source[start:start + LIBRARY_PAGE_SIZE])
            track_offset = len(self.library_hub_tracks)
            self.library_hub["loadingMore"] = True
            self._library_hub_touch_locked()

        def load() -> None:
            try:
                items, tracks, warning = self._history_items(
                    client, page, track_index_offset=track_offset)
                with self.lock:
                    if not self._library_hub_current(client, generation): return
                    self.library_hub["items"].extend(items)
                    self.library_hub_tracks.extend(tracks)
                    self.library_hub_offset = start + len(page)
                    if warning: self.library_hub["warning"] = warning
                    self.library_hub.update(loadingMore=False,
                        hasMore=self.library_hub_offset < len(self.library_hub_source), error="")
                    now = time.monotonic()
                    self.library_hub_cache["history"] = {
                        "items": copy.deepcopy(self.library_hub["items"]),
                        "tracks": list(self.library_hub_tracks),
                        "source": list(self.library_hub_source), "offset": self.library_hub_offset,
                        "warning": str(self.library_hub.get("warning", "")),
                        "storedAt": now, "accessedAt": now}
                    self._library_hub_touch_locked()
            except Exception as exc:
                with self.lock:
                    if not self._library_hub_current(client, generation): return
                    self.library_hub.update(loadingMore=False,
                        error=self._catalog_error(exc, "Следующая страница истории"))
                    self._library_hub_touch_locked()
        threading.Thread(target=load, daemon=True).start()

    def library_back(self) -> None:
        with self.lock:
            self.library_hub_generation += 1
            self.library_hub = self._empty_library_hub()
            self.library_hub_tracks = []; self.library_hub_source = []; self.library_hub_offset = 0
            self._library_hub_touch_locked()

    def browse_personal_playlist(self, playlist_id: str) -> None:
        playlist_id = self._text(playlist_id)
        if playlist_id not in {value for value, _title in PERSONAL_PLAYLISTS}: return
        cache_key = f"personal:{playlist_id}"
        with self.lock:
            client = self.client
            if not client: return
            self.artist_results = []
            generation = self._reset_library_locked()
            self.state["artistBrowseName"] = ""
            if self._activate_collection_cache_locked(cache_key): return
            playlist = self.personal_playlist_models.get(playlist_id)

        def load() -> None:
            try:
                nonlocal playlist
                if playlist is None:
                    generated = self._api_call(lambda: client.playlists_personal(playlist_id))
                    playlist = getattr(generated, "data", None)
                if playlist is None: raise RuntimeError("404")
                rows = self._safe_rows(getattr(playlist, "tracks", None))
                if not rows and callable(getattr(playlist, "fetch_tracks", None)):
                    rows = self._safe_rows(self._api_call(playlist.fetch_tracks))
                tracks = self._tracks_from_short_page(rows[:LIBRARY_PAGE_SIZE], client)
                if not tracks: raise RuntimeError("В подборке нет доступных треков")
                with self.lock:
                    if self.client is not client or generation != self.library_generation: return
                    self.personal_playlist_models[playlist_id] = playlist
                    self.library_source = rows; self.library_results = tracks
                    self.library_offset = min(LIBRARY_PAGE_SIZE, len(rows))
                    self.active_library_cache_key = cache_key
                    self.library_revision += 1
                    self.state.update(libraryBrowseName=self._text(getattr(playlist, "title", ""))
                                      or dict(PERSONAL_PLAYLISTS)[playlist_id],
                                      libraryTotal=len(rows), libraryHasMore=self.library_offset < len(rows),
                                      libraryLoadingMore=False, libraryFromCache=False,
                                      loading=False, loadingKind="", error="")
                    self._store_collection_cache_locked()
            except Exception as exc:
                with self.lock:
                    if self.client is not client: return
                    if generation != self.library_generation: return
                self._set_error(self._catalog_error(exc, "Персональная подборка"))
        self._loading(load, "personal")

    def play_library_hub_track(self, index: int) -> None:
        with self.lock:
            tracks = list(self.library_hub_tracks)
            client = self.client; generation = self.library_hub_generation
            title = "Недавно слушали"
        if not client or not (0 <= index < len(tracks)): return
        track = tracks[index]

        def prepare() -> None:
            try:
                url = self._url(track, update_loading=False)
                with self.lock:
                    if not self._library_hub_current(client, generation): return
                self._set_queue(tracks, title, start_index=index, prepared_url=url)
            except Exception as exc:
                with self.lock:
                    if not self._library_hub_current(client, generation): return
                    self.library_hub["error"] = self._catalog_error(exc, "Трек")
                    self._library_hub_touch_locked()
        threading.Thread(target=prepare, daemon=True).start()

    def play_station(self, station: str, title: str = "") -> None:
        station = self._text(station); title = self._text(title) or "Радиостанция"
        if not station: return

        def load() -> None:
            try:
                assert self.client
                result = self._api_call(lambda: self.client.rotor_station_tracks(station))
                tracks = [row.track for row in self._safe_rows(getattr(result, "sequence", None))
                          if getattr(row, "track", None) is not None]
                if not tracks: raise RuntimeError("Яндекс не вернул треки радиостанции")
                batch_id = self._text(getattr(result, "batch_id", ""))
                self._set_queue(tracks, title, station, batch_id)
            except Exception as exc:
                self._set_error(self._catalog_error(exc, "Радиостанция"))
        self._loading(load, "station")

    @staticmethod
    def _empty_catalog() -> dict[str, Any]:
        return {
            "view": "search", "revision": 0,
            "search": {
                "fieldText": "", "query": "", "filter": "all", "page": -1,
                "loading": False, "loadingMore": False, "error": "",
                "sections": {
                    name: {"items": [], "total": 0, "hasMore": False}
                    for name in CATALOG_SECTIONS
                },
            },
            "suggestions": {
                "query": "", "generation": 0, "loading": False,
                "items": [], "error": "",
            },
            "entity": {},
        }

    @staticmethod
    def _catalog_error(exc: Any, context: str) -> str:
        text = str(exc).lower()
        if Player._is_rate_limit_error(exc): return RATE_LIMIT_MESSAGE
        if "401" in text or "unauthor" in text:
            return "Сессия истекла. Войдите в Яндекс Музыку снова."
        if "404" in text or "not-found" in text or "not found" in text:
            return f"{context} не найден или недоступен."
        if "415" in text or "unsupported-media-type" in text:
            return f"{context} временно недоступен."
        return f"Не удалось загрузить {context.lower()}. Повторите позже."

    @staticmethod
    def _text(value: Any) -> str:
        return str(value if value is not None else "").strip()

    @staticmethod
    def _cover_url(model: Any, size: str = "400x400") -> str:
        if model is None: return ""
        for method_name in ("get_cover_url", "get_og_image_url", "get_op_image_url"):
            method = getattr(model, method_name, None)
            if callable(method):
                try:
                    value = method(size)
                    if value: return str(value)
                except Exception:
                    continue
        cover = getattr(model, "cover", None)
        get_url = getattr(cover, "get_url", None)
        if callable(get_url):
            try:
                value = get_url(size=size)
                if value: return str(value)
            except Exception:
                value = None
        candidates = [getattr(model, "cover_uri", None), getattr(model, "og_image", None),
                      getattr(model, "op_image", None), getattr(model, "image", None),
                      getattr(cover, "uri", None)]
        items_uri = getattr(cover, "items_uri", None) or []
        if isinstance(items_uri, (list, tuple)) and items_uri: candidates.append(items_uri[0])
        for candidate in candidates:
            if not candidate or not isinstance(candidate, (str, int)): continue
            value = str(candidate).replace("%%", size)
            return value if value.startswith(("http://", "https://")) else "https://" + value.lstrip("/")
        return ""

    @classmethod
    def _artist_metadata(cls, artist: Any) -> dict[str, Any]:
        genres = getattr(artist, "genres", None) or []
        if not isinstance(genres, (list, tuple)): genres = []
        return {"entityType": "artist", "id": cls._text(getattr(artist, "id", "")),
                "name": cls._text(getattr(artist, "name", "")),
                "artUrl": cls._cover_url(artist),
                "genres": [cls._text(value) for value in genres if cls._text(value)]}

    @classmethod
    def _album_metadata(cls, album: Any) -> dict[str, Any]:
        artists = [cls._artist_metadata(artist)
                   for artist in (getattr(album, "artists", None) or [])
                   if artist is not None]
        year = getattr(album, "year", None) or getattr(album, "original_release_year", None) or ""
        if isinstance(year, (dict, list, tuple)): year = ""
        return {"entityType": "album", "id": cls._text(getattr(album, "id", "")),
                "title": cls._text(getattr(album, "title", "")),
                "artist": ", ".join(row["name"] for row in artists if row["name"]),
                "artists": artists, "artUrl": cls._cover_url(album), "year": cls._text(year),
                "releaseDate": cls._text(getattr(album, "release_date", ""))[:10],
                "genre": cls._text(getattr(album, "genre", "")),
                "releaseType": cls._text(getattr(album, "type", "")),
                "trackCount": cls._int(getattr(album, "track_count", 0))}

    @classmethod
    def _playlist_metadata(cls, playlist: Any) -> dict[str, Any]:
        owner = getattr(playlist, "owner", None)
        owner_id = (getattr(owner, "uid", None) or getattr(owner, "login", None)
                    or getattr(playlist, "uid", None) or "")
        owner_name = (getattr(owner, "name", None) or getattr(owner, "display_name", None)
                      or getattr(owner, "login", None) or "")
        return {"entityType": "playlist",
                "uuid": cls._text(getattr(playlist, "playlist_uuid", "")),
                "owner": cls._text(owner_id), "ownerName": cls._text(owner_name),
                "kind": cls._text(getattr(playlist, "kind", "")),
                "title": cls._text(getattr(playlist, "title", "")),
                "artUrl": cls._cover_url(playlist),
                "trackCount": cls._int(getattr(playlist, "track_count", 0))}

    @staticmethod
    def _catalog_key(section: str, row: dict[str, Any]) -> str:
        if section == "tracks": return str(row.get("trackId") or row.get("title") or "")
        if section == "artists": return str(row.get("id") or row.get("name") or "").lower()
        if section == "albums": return str(row.get("id") or row.get("title") or "").lower()
        return str(row.get("uuid") or (str(row.get("owner", "")) + ":" + str(row.get("kind", "")))
                   or row.get("title") or "").lower()

    @staticmethod
    def _safe_rows(value: Any) -> list[Any]:
        try: return list(value or [])
        except Exception: return []

    @staticmethod
    def _int(value: Any, fallback: int = 0) -> int:
        try: return int(value if value is not None else fallback)
        except (TypeError, ValueError): return fallback

    @staticmethod
    def _float(value: Any, fallback: float = 0.0) -> float:
        try: return float(value if value is not None else fallback)
        except (TypeError, ValueError): return fallback

    @classmethod
    def _release_is_single(cls, album: Any) -> bool:
        values = " ".join(cls._text(getattr(album, name, "")).lower()
                          for name in ("type", "meta_type"))
        return values.strip() == "ep" or any(
            token in values for token in ("single", "сингл", " ep", "ep "))

    def _catalog_touch_locked(self) -> None:
        self.catalog_revision += 1
        self.catalog["revision"] = self.catalog_revision

    def _catalog_current(self, client: Any, generation: int) -> bool:
        return generation == self.catalog_generation and self.client is client

    def _search_page(self, result: Any) -> dict[str, dict[str, Any]]:
        parsed: dict[str, dict[str, Any]] = {}
        normalizers = {
            "tracks": self._metadata, "artists": self._artist_metadata,
            "albums": self._album_metadata, "playlists": self._playlist_metadata,
        }
        for section in CATALOG_SECTIONS:
            container = getattr(result, section, None) if result is not None else None
            models = self._safe_rows(getattr(container, "results", None))
            items = []
            valid_models = []
            for model in models:
                try: row = normalizers[section](model)
                except Exception: continue
                key = self._catalog_key(section, row)
                if not key: continue
                items.append(row); valid_models.append(model)
            total = max(len(items), self._int(getattr(container, "total", 0)))
            per_page = self._int(getattr(container, "per_page", 0))
            parsed[section] = {"items": items, "models": valid_models,
                               "total": total, "perPage": per_page}
        return parsed

    def catalog_search(self, query: str, type_: str = "all") -> None:
        query = self._text(query)
        type_ = type_ if type_ in CATALOG_TYPES else "all"
        with self.lock:
            client = self.client
            self.catalog_generation += 1; generation = self.catalog_generation
            self.catalog["view"] = "search"; self.catalog["entity"] = {}
            search = self.catalog["search"]
            search.update(fieldText=query, query=query, filter=type_, page=-1,
                          loading=bool(query and client), loadingMore=False, error="")
            search["sections"] = {name: {"items": [], "total": 0, "hasMore": False}
                                  for name in CATALOG_SECTIONS}
            self.catalog_search_models = {name: [] for name in CATALOG_SECTIONS}
            self.search_results = []
            self._catalog_touch_locked()
        if not query or not client: return

        def load() -> None:
            try:
                result = self._api_call(
                    lambda: client.search(query, type_=type_, page=0), update_loading=False)
                page = self._search_page(result)
                with self.lock:
                    if generation != self.catalog_generation or self.client is not client: return
                    for section in CATALOG_SECTIONS:
                        value = page[section]
                        self.catalog_search_models[section] = list(value["models"])
                        count = len(value["items"])
                        has_more = value["total"] > count or (
                            value["perPage"] > 0 and count >= value["perPage"])
                        self.catalog["search"]["sections"][section] = {
                            "items": value["items"], "total": value["total"],
                            "hasMore": has_more,
                        }
                    self.search_results = list(self.catalog_search_models["tracks"])
                    self.catalog["search"].update(page=0, loading=False, error="")
                    self._catalog_touch_locked()
            except Exception as exc:
                with self.lock:
                    if not self._catalog_current(client, generation): return
                    self.catalog["search"].update(
                        loading=False, error=self._catalog_error(exc, "Результаты поиска"))
                    self._catalog_touch_locked()
        threading.Thread(target=load, daemon=True).start()

    def catalog_load_more(self) -> None:
        with self.lock:
            search = self.catalog["search"]
            if (self.catalog.get("view") != "search" or search.get("loading")
                    or search.get("loadingMore") or not search.get("query")):
                return
            if not any(section.get("hasMore") for section in search["sections"].values()): return
            client = self.client; generation = self.catalog_generation
            query = str(search["query"]); type_ = str(search["filter"])
            next_page = self._int(search.get("page", -1), -1) + 1
            search.update(loadingMore=True, error=""); self._catalog_touch_locked()
        if not client: return

        def load() -> None:
            try:
                result = self._api_call(
                    lambda: client.search(query, type_=type_, page=next_page), update_loading=False)
                page = self._search_page(result)
                with self.lock:
                    if generation != self.catalog_generation or self.client is not client: return
                    for section in CATALOG_SECTIONS:
                        target = self.catalog["search"]["sections"][section]
                        seen = {self._catalog_key(section, row) for row in target["items"]}
                        for model, row in zip(page[section]["models"], page[section]["items"]):
                            key = self._catalog_key(section, row)
                            if key in seen: continue
                            seen.add(key); target["items"].append(row)
                            self.catalog_search_models[section].append(model)
                        target["total"] = max(int(target.get("total", 0)), page[section]["total"])
                        received = len(page[section]["items"])
                        target["hasMore"] = (target["total"] > len(target["items"])
                                             and received > 0)
                    self.search_results = list(self.catalog_search_models["tracks"])
                    self.catalog["search"].update(page=next_page, loadingMore=False, error="")
                    self._catalog_touch_locked()
            except Exception as exc:
                with self.lock:
                    if not self._catalog_current(client, generation): return
                    self.catalog["search"].update(
                        loadingMore=False, error=self._catalog_error(exc, "Следующую страницу"))
                    self._catalog_touch_locked()
        threading.Thread(target=load, daemon=True).start()

    def _finish_catalog_suggestions(self, client: Any, generation: int, query: str,
                                    items: list[str], error: str = "") -> None:
        with self.lock:
            current = self.catalog["suggestions"]
            is_current = generation == self.suggestion_generation
            if not is_current or self.client is not client: return
            if current.get("query") != query: return
            current.update(loading=False, items=items, error=error)
            self._catalog_touch_locked()

    def catalog_suggest(self, query: str, request_generation: int = 0) -> None:
        query = self._text(query)
        with self.lock:
            client = self.client
            self.suggestion_generation += 1; generation = self.suggestion_generation
            suggestions = self.catalog["suggestions"]
            self.catalog["search"]["fieldText"] = query
            suggestions.update(query=query, generation=request_generation,
                               loading=len(query) >= 2 and client is not None,
                               items=[], error="")
            self._catalog_touch_locked()
        if len(query) < 2 or not client: return

        def load() -> None:
            try:
                result = self._api_call(lambda: client.search_suggest(query), update_loading=False)
                values = []
                for value in self._safe_rows(getattr(result, "suggestions", None)):
                    text = self._text(value)
                    if text and text not in values: values.append(text)
                self._finish_catalog_suggestions(client, generation, query, values)
            except Exception as exc:
                self._finish_catalog_suggestions(
                    client, generation, query, [], self._catalog_error(exc, "Подсказки"))
        threading.Thread(target=load, daemon=True).start()

    def catalog_clear_suggestions(self, field_text: str = "") -> None:
        with self.lock:
            self.suggestion_generation += 1
            self.catalog["search"]["fieldText"] = self._text(field_text)
            self.catalog["suggestions"].update(query="", loading=False, items=[], error="")
            self._catalog_touch_locked()

    def _store_catalog_entity_locked(self, key: str) -> None:
        self.catalog_cache[key] = {
            "entity": copy.deepcopy(self.catalog.get("entity", {})),
            "tracks": list(self.catalog_entity_tracks),
            "source": list(self.catalog_entity_source), "offset": self.catalog_entity_offset,
        }
        self.catalog_cache.move_to_end(key)
        while len(self.catalog_cache) > CATALOG_CACHE_MAX_ENTRIES:
            self.catalog_cache.popitem(last=False)

    def _activate_catalog_entity_locked(self, key: str) -> bool:
        cached = self.catalog_cache.get(key)
        if not cached: return False
        self.catalog_cache.move_to_end(key)
        self.catalog["entity"] = copy.deepcopy(cached["entity"])
        self.catalog["entity"]["loading"] = False
        self.catalog["view"] = str(self.catalog["entity"].get("type", "search"))
        self.catalog_entity_tracks = list(cached["tracks"])
        self.catalog_entity_source = list(cached["source"])
        self.catalog_entity_offset = self._int(cached["offset"])
        self._catalog_touch_locked(); return True

    def _begin_catalog_entity(self, type_: str, entity_id: str, cache_key: str) -> tuple[Any, int] | None:
        with self.lock:
            client = self.client
            self.catalog_generation += 1; generation = self.catalog_generation
            self.catalog["view"] = type_
            self.catalog["entity"] = {"type": type_, "id": entity_id,
                                      "loading": bool(client), "loadingMore": False,
                                      "error": "", "warning": "", "tracks": [], "hasMore": False}
            self.catalog_entity_tracks = []; self.catalog_entity_source = []
            self.catalog_entity_offset = 0
            if client and self._activate_catalog_entity_locked(cache_key): return None
            self._catalog_touch_locked()
        return (client, generation) if client else None

    def _finish_catalog_entity(self, client: Any, generation: int, cache_key: str,
                               entity: dict[str, Any], tracks: list[Any],
                               source: list[Any] | None = None, offset: int | None = None) -> None:
        with self.lock:
            if generation != self.catalog_generation or self.client is not client: return
            self.catalog["entity"] = entity
            self.catalog["view"] = str(entity.get("type", "search"))
            self.catalog_entity_tracks = list(tracks)
            self.catalog_entity_source = list(source or tracks)
            self.catalog_entity_offset = len(tracks) if offset is None else offset
            self._catalog_touch_locked(); self._store_catalog_entity_locked(cache_key)

    def _fail_catalog_entity(self, client: Any, generation: int, type_: str,
                             entity_id: str, exc: Any, context: str) -> None:
        with self.lock:
            if generation != self.catalog_generation or self.client is not client: return
            self.catalog["entity"] = {"type": type_, "id": entity_id, "loading": False,
                                      "loadingMore": False, "tracks": [], "hasMore": False,
                                      "error": self._catalog_error(exc, context), "warning": ""}
            self._catalog_touch_locked()

    def catalog_album(self, album_id: str) -> None:
        album_id = self._text(album_id)
        if not album_id: return
        cache_key = f"album:{album_id}"
        started = self._begin_catalog_entity("album", album_id, cache_key)
        if not started: return
        client, generation = started

        def load() -> None:
            errors = []
            summary = detailed = None
            try:
                rows = self._api_call(lambda: client.albums(album_id), update_loading=False) or []
                summary = rows[0] if rows else None
            except Exception as exc: errors.append(exc)
            try:
                detailed = self._api_call(
                    lambda: client.albums_with_tracks(album_id), update_loading=False)
            except Exception as exc: errors.append(exc)
            album = detailed or summary
            if album is None:
                self._fail_catalog_entity(client, generation, "album", album_id,
                                          errors[0] if errors else RuntimeError("empty"), "Альбом")
                return
            source = []
            for volume in self._safe_rows(getattr(detailed, "volumes", None)):
                source.extend(self._safe_rows(volume))
            try:
                tracks = self._tracks_from_short_page(
                    source[:CATALOG_TRACK_PAGE_SIZE], client, update_loading=False)
            except Exception as exc: errors.append(exc); tracks = []
            entity = {**self._album_metadata(album), "type": "album", "loading": False,
                      "loadingMore": False, "tracks": [
                          {**self._metadata(track), "index": index}
                          for index, track in enumerate(tracks)],
                      "hasMore": len(source) > len(source[:CATALOG_TRACK_PAGE_SIZE]),
                      "error": "", "warning": ("Часть данных альбома недоступна."
                                                   if errors and (tracks or summary) else "")}
            self._finish_catalog_entity(client, generation, cache_key, entity, tracks,
                                        source, min(len(source), CATALOG_TRACK_PAGE_SIZE))
        threading.Thread(target=load, daemon=True).start()

    def _page_has_more(self, result: Any, rows: list[Any], page: int,
                       fallback_page_size: int) -> bool:
        pager = getattr(result, "pager", None)
        total = self._int(getattr(pager, "total", 0))
        per_page = self._int(
            getattr(pager, "per_page", fallback_page_size), fallback_page_size)
        per_page = max(1, per_page)
        if total > 0:
            return (page + 1) * per_page < total
        return len(rows) >= per_page

    def _artist_release_page(self, client: Any, artist_id: str, page: int) -> tuple[list[Any], bool, list[Any]]:
        releases = []; errors = []; has_more = False
        for method_name in ("artists_direct_albums", "artists_discography_albums"):
            try:
                method = getattr(client, method_name)
                result = self._api_call(
                    lambda method=method: method(artist_id, page=page,
                                                 page_size=CATALOG_PAGE_SIZE),
                    update_loading=False)
                rows = self._safe_rows(getattr(result, "albums", None))
                releases.extend(rows)
                has_more = has_more or self._page_has_more(
                    result, rows, page, CATALOG_PAGE_SIZE)
            except Exception as exc: errors.append(exc)
        unique = []
        seen = set()
        for album in releases:
            row = self._album_metadata(album)
            key = self._catalog_key("albums", row)
            if key and key not in seen: seen.add(key); unique.append(album)
        return unique, has_more, errors

    @classmethod
    def _description_text(cls, *values: Any) -> str:
        for value in values:
            if value is None: continue
            text = value if isinstance(value, str) else getattr(value, "text", "")
            text = cls._text(text)
            if text: return text
        return ""

    def catalog_artist(self, artist_id: str) -> None:
        artist_id = self._text(artist_id)
        if not artist_id: return
        cache_key = f"artist:{artist_id}"
        started = self._begin_catalog_entity("artist", artist_id, cache_key)
        if not started: return
        client, generation = started

        def load() -> None:
            errors = []
            def call(method_name: str, *args: Any, **kwargs: Any) -> Any:
                try:
                    method = getattr(client, method_name)
                    return self._api_call(lambda: method(*args, **kwargs), update_loading=False)
                except Exception as exc:
                    errors.append(exc); return None
            brief = call("artists_brief_info", artist_id)
            info = call("artists_info", artist_id)
            about = call("artists_about", artist_id)
            track_page = call("artists_tracks", artist_id, page=0, page_size=CATALOG_PAGE_SIZE)
            releases, releases_more, release_errors = self._artist_release_page(client, artist_id, 0)
            errors.extend(release_errors)
            similar_result = call("artists_similar", artist_id)
            artist = (getattr(brief, "artist", None) or getattr(info, "artist", None)
                      or getattr(about, "artist", None) or getattr(similar_result, "artist", None))
            if artist is None and not any((brief, info, about, track_page, releases, similar_result)):
                self._fail_catalog_entity(client, generation, "artist", artist_id,
                                          errors[0] if errors else RuntimeError("empty"), "Исполнитель")
                return
            page_tracks = self._safe_rows(getattr(track_page, "tracks", None))
            popular_source = page_tracks or self._safe_rows(getattr(brief, "popular_tracks", None))
            popular_has_more = bool(page_tracks) and self._page_has_more(
                track_page, page_tracks, 0, CATALOG_PAGE_SIZE)
            try:
                tracks = self._tracks_from_short_page(
                    popular_source, client, update_loading=False)
            except Exception as exc: errors.append(exc); tracks = []
            similar = (self._safe_rows(getattr(similar_result, "similar_artists", None))
                       or self._safe_rows(getattr(brief, "similar_artists", None)))[:10]
            albums = []; singles = []
            for release in releases:
                try:
                    (singles if self._release_is_single(release) else albums).append(
                        self._album_metadata(release))
                except Exception:
                    continue
            identity = self._artist_metadata(artist)
            covers = (self._safe_rows(getattr(info, "covers", None))
                      or self._safe_rows(getattr(about, "covers", None))
                      or self._safe_rows(getattr(brief, "all_covers", None)))
            if not identity["artUrl"] and covers: identity["artUrl"] = self._cover_url(covers[0])
            description = self._description_text(
                getattr(about, "description", None), getattr(info, "description", None),
                getattr(artist, "hand_made_description", None), getattr(artist, "description", None))
            entity = {**identity, "type": "artist", "id": artist_id or identity["id"],
                      "description": description, "loading": False, "loadingMore": False,
                      "tracks": [{**self._metadata(track), "index": index}
                                 for index, track in enumerate(tracks)],
                      "similar": [self._artist_metadata(value) for value in similar if value is not None],
                      "albums": albums, "singles": singles,
                      "releasePages": {"albums": 0, "singles": 0},
                      "releaseHasMore": {"albums": releases_more, "singles": releases_more},
                      "releaseLoading": {"albums": False, "singles": False},
                      "releaseErrors": {"albums": "", "singles": ""},
                      "popularPage": 0, "popularHasMore": popular_has_more,
                      "hasMore": False, "error": "",
                      "warning": "Часть сведений об исполнителе недоступна." if errors else ""}
            self._finish_catalog_entity(client, generation, cache_key, entity, tracks)
        threading.Thread(target=load, daemon=True).start()

    def catalog_artist_more(self, section: str) -> None:
        if section not in ("albums", "singles"): return
        with self.lock:
            entity = self.catalog.get("entity", {})
            if (entity.get("type") != "artist" or entity.get("loading")
                    or entity.get("releaseLoading", {}).get(section)
                    or not entity.get("releaseHasMore", {}).get(section)): return
            client = self.client; generation = self.catalog_generation
            artist_id = str(entity.get("id", ""))
            page = self._int(entity.get("releasePages", {}).get(section, 0)) + 1
            entity["releaseLoading"][section] = True
            entity["releaseErrors"][section] = ""; self._catalog_touch_locked()
        if not client: return

        def load() -> None:
            releases, has_more, errors = self._artist_release_page(client, artist_id, page)
            with self.lock:
                entity = self.catalog.get("entity", {})
                if (generation != self.catalog_generation or self.client is not client
                        or entity.get("type") != "artist" or entity.get("id") != artist_id): return
                target = entity[section]
                seen = {self._catalog_key("albums", row) for row in target}
                for release in releases:
                    if (section == "singles") != self._release_is_single(release): continue
                    row = self._album_metadata(release); key = self._catalog_key("albums", row)
                    if key and key not in seen: seen.add(key); target.append(row)
                entity["releasePages"][section] = page
                entity["releaseHasMore"][section] = has_more
                entity["releaseLoading"][section] = False
                entity["releaseErrors"][section] = (
                    "Не удалось загрузить часть дискографии." if errors and not releases else "")
                self._catalog_touch_locked(); self._store_catalog_entity_locked(f"artist:{artist_id}")
        threading.Thread(target=load, daemon=True).start()

    def catalog_playlist(self, uuid_: str = "", owner: str = "", kind: str = "") -> None:
        uuid_ = self._text(uuid_); owner = self._text(owner); kind = self._text(kind)
        entity_id = uuid_ or (owner + ":" + kind if owner and kind else "")
        if not entity_id:
            with self.lock:
                self.catalog["view"] = "playlist"
                self.catalog["entity"] = {"type": "playlist", "loading": False,
                    "tracks": [], "hasMore": False, "warning": "",
                    "error": "Не удалось определить идентификатор плейлиста."}
                self._catalog_touch_locked()
            return
        cache_key = f"playlist:{entity_id}"
        started = self._begin_catalog_entity("playlist", entity_id, cache_key)
        if not started: return
        client, generation = started

        def load() -> None:
            try:
                if uuid_:
                    playlist = self._api_call(lambda: client.playlist(uuid_), update_loading=False)
                else:
                    playlist = self._api_call(
                        lambda: client.users_playlists(kind, user_id=owner), update_loading=False)
                if isinstance(playlist, (list, tuple)): playlist = playlist[0] if playlist else None
                if playlist is None: raise RuntimeError("404")
                source = self._safe_rows(getattr(playlist, "tracks", None))
                if not source and callable(getattr(playlist, "fetch_tracks", None)):
                    source = self._safe_rows(self._api_call(playlist.fetch_tracks, update_loading=False))
                tracks = self._tracks_from_short_page(
                    source[:CATALOG_TRACK_PAGE_SIZE], client, update_loading=False)
                entity = {**self._playlist_metadata(playlist), "type": "playlist", "id": entity_id,
                          "loading": False, "loadingMore": False,
                          "description": self._text(getattr(playlist, "description_formatted", None)
                                                    or getattr(playlist, "description", None)),
                          "tracks": [{**self._metadata(track), "index": index}
                                     for index, track in enumerate(tracks)],
                          "hasMore": len(source) > CATALOG_TRACK_PAGE_SIZE,
                          "error": "", "warning": ""}
                self._finish_catalog_entity(client, generation, cache_key, entity, tracks,
                                            source, min(len(source), CATALOG_TRACK_PAGE_SIZE))
            except Exception as exc:
                self._fail_catalog_entity(client, generation, "playlist", entity_id, exc, "Плейлист")
                with self.lock:
                    if not self._catalog_current(client, generation): return
                    self.catalog["entity"].update(uuid=uuid_, owner=owner, kind=kind)
                    self._catalog_touch_locked()
        threading.Thread(target=load, daemon=True).start()

    def catalog_entity_more(self) -> None:
        with self.lock:
            entity = self.catalog.get("entity", {})
            if (entity.get("type") not in ("album", "playlist") or entity.get("loadingMore")
                    or not entity.get("hasMore")): return
            client = self.client; generation = self.catalog_generation
            start = self.catalog_entity_offset
            rows = list(self.catalog_entity_source[start:start + CATALOG_TRACK_PAGE_SIZE])
            entity["loadingMore"] = True; entity["error"] = ""; self._catalog_touch_locked()
        if not client: return

        def load() -> None:
            try:
                tracks = self._tracks_from_short_page(rows, client, update_loading=False)
                with self.lock:
                    entity = self.catalog.get("entity", {})
                    if generation != self.catalog_generation or self.client is not client: return
                    base = len(self.catalog_entity_tracks)
                    known = {self._track_id(track) for track in self.catalog_entity_tracks}
                    for track in tracks:
                        if self._track_id(track) in known: continue
                        known.add(self._track_id(track)); self.catalog_entity_tracks.append(track)
                        entity["tracks"].append({**self._metadata(track), "index": base})
                        base += 1
                    self.catalog_entity_offset = start + len(rows)
                    entity["hasMore"] = self.catalog_entity_offset < len(self.catalog_entity_source)
                    entity["loadingMore"] = False; self._catalog_touch_locked()
                    self._store_catalog_entity_locked(f"{entity['type']}:{entity.get('id', '')}")
            except Exception as exc:
                with self.lock:
                    if not self._catalog_current(client, generation): return
                    self.catalog["entity"].update(
                        loadingMore=False, error=self._catalog_error(exc, "Следующую страницу"))
                    self._catalog_touch_locked()
        threading.Thread(target=load, daemon=True).start()

    def catalog_back(self) -> None:
        with self.lock:
            self.catalog_generation += 1
            self.catalog["view"] = "search"; self.catalog["entity"] = {}
            self.catalog_entity_tracks = []; self.catalog_entity_source = []
            self.catalog_entity_offset = 0; self._catalog_touch_locked()

    def play_catalog_track(self, source: str, index: int) -> None:
        with self.lock:
            entity = self.catalog.get("entity", {})
            tracks = list(self.catalog_search_models.get("tracks", [])) if source == "search" \
                else list(self.catalog_entity_tracks)
            name = ("Результаты поиска" if source == "search"
                    else str(entity.get("title") or entity.get("name") or "Каталог"))
            is_artist = source == "entity" and entity.get("type") == "artist"
            artist_id = str(entity.get("id", "")) if is_artist else ""
            artist_page = self._int(entity.get("popularPage", 0)) if is_artist else 0
            artist_has_more = bool(entity.get("popularHasMore", False)) if is_artist else False
            client = self.client; generation = self.catalog_generation
        if not client or not (0 <= index < len(tracks)): return
        track = tracks[index]

        def prepare() -> None:
            try:
                url = self._url(track, update_loading=False)
                with self.lock:
                    if not self._catalog_current(client, generation): return
                self._set_queue(
                    tracks, name, start_index=index, prepared_url=url,
                    artist_id=artist_id, artist_page=artist_page,
                    artist_has_more=artist_has_more)
            except Exception as exc:
                with self.lock:
                    if not self._catalog_current(client, generation): return
                    target = (self.catalog["search"] if source == "search"
                              else self.catalog["entity"])
                    target["error"] = self._catalog_error(exc, "Трек")
                    self._catalog_touch_locked()
        threading.Thread(target=prepare, daemon=True).start()

    def search(self, query: str) -> None:
        self.catalog_search(query, "all")

    def play_search(self, index: int) -> None:
        self.play_catalog_track("search", index)

    @classmethod
    def _parse_lrc(cls, content: str) -> list[dict[str, Any]]:
        """Parse standard LRC timestamps into ordered, seekable lyric lines."""
        timestamp = re.compile(r"\[(\d{1,3}):([0-5]?\d)(?:[\.:](\d{1,3}))?\]")
        enhanced_timestamp = re.compile(r"<\d{1,3}:[0-5]?\d(?:[\.:]\d{1,3})?>")
        offset_match = re.search(r"(?im)^\[offset:([+-]?\d+)\]\s*$", content)
        offset = cls._int(offset_match.group(1)) / 1000 if offset_match else 0.0
        lines: list[dict[str, Any]] = []
        for source_index, raw_line in enumerate(content.splitlines()):
            matches = list(timestamp.finditer(raw_line))
            if not matches: continue
            text = enhanced_timestamp.sub("", timestamp.sub("", raw_line)).strip()
            if not text: continue
            for match in matches:
                fraction_text = match.group(3) or ""
                fraction = cls._int(fraction_text) / (10 ** len(fraction_text)) if fraction_text else 0.0
                seconds = cls._int(match.group(1)) * 60 + cls._int(match.group(2)) + fraction + offset
                lines.append({"time": round(max(0.0, seconds), 3), "text": text,
                              "sourceIndex": source_index})
        lines.sort(key=lambda line: (line["time"], line["sourceIndex"]))
        for line in lines: line.pop("sourceIndex", None)
        return lines

    @staticmethod
    def _plain_lyrics_lines(content: str) -> list[dict[str, Any]]:
        lines = [line.rstrip() for line in content.replace("\r\n", "\n").replace("\r", "\n").split("\n")]
        while lines and not lines[0].strip(): lines.pop(0)
        while lines and not lines[-1].strip(): lines.pop()
        return [{"time": -1, "text": line} for line in lines]

    @staticmethod
    def _is_not_found_error(exc: Any) -> bool:
        return exc.__class__.__name__ == "NotFoundError" or bool(re.search(r"\b404\b", str(exc)))

    def _fetch_lyrics_format(self, client: Client, track_id: str,
                             format_: str) -> tuple[str, list[str]]:
        lyrics = self._api_call(lambda: client.tracks_lyrics(track_id, format_=format_))
        if not lyrics: return "", []
        content = self._api_call(lyrics.fetch_lyrics)
        writers = [str(writer) for writer in (getattr(lyrics, "writers", None) or []) if writer]
        return str(content or ""), writers

    def _lyrics_text_failure(self, lrc_content: str, lrc_writers: list[str],
                             lrc_error: Exception | None, exc: Exception) -> dict[str, Any]:
        if lrc_content.strip():
            plain_lines = self._plain_lyrics_lines(lrc_content)
            if plain_lines:
                return {"available": True, "synced": False, "format": "TEXT",
                        "writers": lrc_writers, "lines": plain_lines, "error": ""}
        if self._is_not_found_error(exc) and (
                lrc_error is None or self._is_not_found_error(lrc_error)):
            return {"available": False, "synced": False, "format": "",
                    "writers": [], "lines": [], "error": ""}
        raise exc

    def _lyrics_entry(self, client: Client, track_id: str) -> dict[str, Any]:
        lrc_content = ""
        lrc_writers: list[str] = []
        lrc_error: Exception | None = None
        try:
            lrc_content, lrc_writers = self._fetch_lyrics_format(client, track_id, "LRC")
        except Exception as exc:
            if self._is_rate_limit_error(exc): raise
            lrc_error = exc

        synced_lines = self._parse_lrc(lrc_content)
        if synced_lines:
            return {"available": True, "synced": True, "format": "LRC",
                    "writers": lrc_writers, "lines": synced_lines, "error": ""}

        try:
            text_content, text_writers = self._fetch_lyrics_format(client, track_id, "TEXT")
        except Exception as exc:
            return self._lyrics_text_failure(lrc_content, lrc_writers, lrc_error, exc)

        plain_lines = self._plain_lyrics_lines(text_content)
        if plain_lines:
            return {"available": True, "synced": False, "format": "TEXT",
                    "writers": text_writers or lrc_writers, "lines": plain_lines, "error": ""}
        if lrc_error and not self._is_not_found_error(lrc_error): raise lrc_error
        return {"available": False, "synced": False, "format": "",
                "writers": [], "lines": [], "error": ""}

    @staticmethod
    def _lyrics_response(track_id: str, entry: dict[str, Any] | None = None,
                         *, loading: bool = False) -> dict[str, Any]:
        value = entry or {}
        return {"trackId": track_id, "loading": loading,
                "available": bool(value.get("available", False)),
                "synced": bool(value.get("synced", False)),
                "format": str(value.get("format", "")),
                "writers": list(value.get("writers", [])),
                "lines": [dict(line) for line in value.get("lines", [])],
                "error": str(value.get("error", ""))}

    def _store_lyrics_locked(self, track_id: str, entry: dict[str, Any]) -> None:
        self.lyrics_cache[track_id] = entry
        self.lyrics_cache.move_to_end(track_id)
        while len(self.lyrics_cache) > LYRICS_CACHE_MAX_ENTRIES:
            self.lyrics_cache.popitem(last=False)

    def lyrics(self, *, force: bool = False) -> dict[str, Any]:
        """Return current lyrics or start an on-demand, in-memory-only load."""
        with self.lock:
            track = self._current_track_locked()
            track_id = self._track_id(track) if track is not None else ""
            client = self.client
            if not track_id or not client: return self._lyrics_response(track_id)
            if force: self.lyrics_cache.pop(track_id, None)
            cached = self.lyrics_cache.get(track_id)
            if cached is not None:
                self.lyrics_cache.move_to_end(track_id)
                return self._lyrics_response(track_id, cached)
            if track_id in self.lyrics_loading:
                return self._lyrics_response(track_id, loading=True)
            self.lyrics_loading.add(track_id)
            generation = self.lyrics_generation

        def load() -> None:
            try:
                entry = self._lyrics_entry(client, track_id)
            except Exception as exc:
                entry = {"available": False, "synced": False, "format": "",
                         "writers": [], "lines": [],
                         "error": f"Не удалось загрузить текст: {self._friendly_error(exc)}"}
            with self.lock:
                if generation != self.lyrics_generation or self.client is not client: return
                self.lyrics_loading.discard(track_id)
                self._store_lyrics_locked(track_id, entry)

        threading.Thread(target=load, daemon=True).start()
        return self._lyrics_response(track_id, loading=True)

    def _track_info_entry(self, client: Client, track_id: str,
                          fallback_track: Any) -> dict[str, Any]:
        errors: list[str] = []
        full_info = None
        credits_result = None
        try:
            full_info = self._api_call(lambda: client.tracks_full_info(track_id))
        except Exception as exc:
            if self._is_rate_limit_error(exc): raise
            if not self._is_not_found_error(exc): errors.append(self._friendly_error(exc))
        try:
            credits_result = self._api_call(lambda: client.tracks_credits(track_id))
        except Exception as exc:
            if self._is_rate_limit_error(exc): raise
            if not self._is_not_found_error(exc): errors.append(self._friendly_error(exc))

        track = getattr(full_info, "track", None) or fallback_track
        albums = list(getattr(track, "albums", None) or [])
        album = albums[0] if albums else None
        artists = [{"id": str(getattr(artist, "id", "")),
                    "name": str(getattr(artist, "name", ""))}
                   for artist in (getattr(track, "artists", None) or [])
                   if getattr(artist, "name", None)]
        labels = []
        for label in (getattr(album, "labels", None) or []):
            name = label if isinstance(label, str) else getattr(label, "name", "")
            if name and str(name) not in labels: labels.append(str(name))
        major_name = str(getattr(getattr(track, "major", None), "name", "") or "")
        if major_name and major_name not in labels: labels.append(major_name)
        track_position = getattr(album, "track_position", None)
        aliases = [str(alias) for alias in (getattr(full_info, "aliases", None) or []) if alias]
        credits = [{"title": str(getattr(credit, "title", "") or ""),
                    "value": str(getattr(credit, "value", "") or "")}
                   for credit in (getattr(credits_result, "credits", None) or [])
                   if getattr(credit, "title", None) or getattr(credit, "value", None)]
        year = getattr(album, "year", None) or getattr(album, "original_release_year", None) or ""
        if isinstance(year, (dict, list, tuple)): year = ""
        description = (getattr(track, "short_description", None)
                       or getattr(album, "description", None)
                       or getattr(album, "short_description", None) or "")
        release_date = str(getattr(album, "release_date", "") or "")[:10]
        entry = {
            "available": bool(track or credits),
            "title": str(getattr(track, "title", "") or ""),
            "artists": artists,
            "album": str(getattr(album, "title", "") or ""),
            "albumId": str(getattr(album, "id", "") or ""),
            "year": str(year), "releaseDate": release_date,
            "genre": str(getattr(album, "genre", "") or ""),
            "labels": labels,
            "trackNumber": self._int(getattr(track_position, "index", 0)),
            "discNumber": self._int(getattr(track_position, "volume", 0)),
            "duration": self._int(getattr(track, "duration_ms", 0)) // 1000,
            "version": str(getattr(track, "version", "") or ""),
            "explicit": bool(getattr(track, "explicit", False)
                             or getattr(track, "content_warning", "") == "explicit"),
            "aliases": aliases, "description": str(description), "credits": credits,
            "error": ("Часть сведений недоступна: " + "; ".join(dict.fromkeys(errors)))
                     if errors else "",
        }
        return entry

    @classmethod
    def _track_info_response(cls, track_id: str, entry: dict[str, Any] | None = None,
                             *, loading: bool = False) -> dict[str, Any]:
        value = entry or {}
        return {"trackId": track_id, "loading": loading,
                "available": bool(value.get("available", False)),
                "title": str(value.get("title", "")),
                "artists": [dict(artist) for artist in value.get("artists", [])],
                "album": str(value.get("album", "")),
                "albumId": str(value.get("albumId", "")),
                "year": str(value.get("year", "")),
                "releaseDate": str(value.get("releaseDate", "")),
                "genre": str(value.get("genre", "")),
                "labels": list(value.get("labels", [])),
                "trackNumber": cls._int(value.get("trackNumber", 0)),
                "discNumber": cls._int(value.get("discNumber", 0)),
                "duration": cls._int(value.get("duration", 0)),
                "version": str(value.get("version", "")),
                "explicit": bool(value.get("explicit", False)),
                "aliases": list(value.get("aliases", [])),
                "description": str(value.get("description", "")),
                "credits": [dict(credit) for credit in value.get("credits", [])],
                "error": str(value.get("error", ""))}

    def _store_track_info_locked(self, track_id: str, entry: dict[str, Any]) -> None:
        self.track_info_cache[track_id] = entry
        self.track_info_cache.move_to_end(track_id)
        while len(self.track_info_cache) > TRACK_INFO_CACHE_MAX_ENTRIES:
            self.track_info_cache.popitem(last=False)

    def track_info(self, *, force: bool = False) -> dict[str, Any]:
        """Return current track details or start an isolated on-demand load."""
        with self.lock:
            track = self._current_track_locked()
            track_id = self._track_id(track) if track is not None else ""
            client = self.client
            if not track_id or not client: return self._track_info_response(track_id)
            if force: self.track_info_cache.pop(track_id, None)
            cached = self.track_info_cache.get(track_id)
            if cached is not None:
                self.track_info_cache.move_to_end(track_id)
                return self._track_info_response(track_id, cached)
            if track_id in self.track_info_loading:
                return self._track_info_response(track_id, loading=True)
            self.track_info_loading.add(track_id)
            generation = self.track_info_generation

        def load() -> None:
            try:
                entry = self._track_info_entry(client, track_id, track)
            except Exception as exc:
                entry = {"available": False,
                         "error": f"Не удалось загрузить сведения: {self._friendly_error(exc)}"}
            with self.lock:
                if generation != self.track_info_generation or self.client is not client: return
                self.track_info_loading.discard(track_id)
                self._store_track_info_locked(track_id, entry)

        threading.Thread(target=load, daemon=True).start()
        return self._track_info_response(track_id, loading=True)

    def play_queue(self, index: int) -> None:
        with self.lock:
            if not (0 <= index < len(self.queue)): return
        self._finish_playback_reporting(finished=False)
        with self.lock:
            if not (0 <= index < len(self.queue)): return
            self.artist_results = []
            self._reset_library_locked()
            self.state["artistBrowseName"] = ""
            self.index = index
        self._save_state(True)
        self._play_current()

    def play_library_track(self, index: int) -> None:
        with self.lock:
            tracks = list(self.library_results)
            remaining = list(self.library_source[self.library_offset:])
            name = str(self.state.get("libraryBrowseName", "Медиатека"))
            collection_key = self.active_library_cache_key
        if 0 <= index < len(tracks):
            self._set_queue(tracks, name, start_index=index, remaining_rows=remaining,
                            collection_key=collection_key)

    def close_library(self) -> None:
        with self.lock:
            self._reset_library_locked()

    def play_artist(self, artist_id: str) -> None:
        """Compatibility entry point: artist browsing now lives in Search."""
        self.catalog_artist(artist_id)

    def play_artist_track(self, index: int) -> None:
        self.play_catalog_track("entity", index)

    def close_artist(self) -> None:
        self.catalog_back()

    def _set_queue(self, tracks: list[Any], name: str, station: str = "", batch_id: str = "",
                   start_index: int = 0, remaining_rows: list[Any] | None = None,
                   collection_key: str = "", prepared_url: str = "",
                   artist_id: str = "", artist_page: int = 0,
                   artist_has_more: bool = False) -> None:
        if not tracks: raise RuntimeError("В списке нет доступных треков")
        self._finish_playback_reporting(finished=False)
        with self.lock:
            self.queue = tracks; self.index = max(0, min(start_index, len(tracks) - 1))
            self.queue_source = list(remaining_rows or [])
            self.queue_extending = False; self.queue_advance_pending = False
            self.queue_generation += 1; self.queue_revision += 1
            self.queue_collection_key = collection_key
            self.queue_artist_id = artist_id
            self.queue_artist_page = artist_page
            self.queue_artist_has_more = artist_has_more
            self.queue_advance_automatic = False
            self.detached_track = None
            self.artist_results = []
            self._reset_library_locked()
            self.state["artistBrowseName"] = ""
            self.radio_station = station; self.radio_batch_id = batch_id
            self.radio_track_batches = ({self._track_id(track): batch_id for track in tracks}
                                        if station and batch_id else {})
            self.radio_extending = False; self.radio_advance_pending = False
            self.state.update(queueName=name, loading=False, loadingKind="")
        if station: self._report_radio_started(station, batch_id)
        self._save_state(True); self._play_current(initial_url=prepared_url)

    def _metadata(self, track: Any) -> dict[str, Any]:
        track_artists = self._safe_rows(getattr(track, "artists", None))
        artist_rows = [self._artist_metadata(artist) for artist in track_artists if artist is not None]
        artist_rows = [row for row in artist_rows if row["id"] or row["name"]]
        albums = self._safe_rows(getattr(track, "albums", None))
        album = albums[0] if albums else None
        return {"entityType": "track", "title": self._text(getattr(track, "title", "")),
                "trackId": self._track_id(track),
                "artist": ", ".join(row["name"] for row in artist_rows if row["name"]),
                "artistId": artist_rows[0]["id"] if artist_rows else "",
                "artists": artist_rows,
                "album": self._text(getattr(album, "title", "")),
                "albumId": self._text(getattr(album, "id", "")),
                "artUrl": self._cover_url(track),
                "duration": self._int(getattr(track, "duration_ms", 0)) // 1000}

    def _url(self, track: Any, *, update_loading: bool = True) -> str:
        infos = self._api_call(
            lambda: track.get_download_info(get_direct_links=True),
            update_loading=update_loading) or []
        if not infos: raise RuntimeError("Яндекс не вернул ссылку на аудио")
        if self.preferences["audioQuality"] == "economy":
            infos.sort(key=lambda x: (x.bitrate_in_kbps or 10_000, x.codec not in ("aac", "mp3")))
        else:
            infos.sort(key=lambda x: (x.codec in ("mp3", "aac"), x.bitrate_in_kbps or 0), reverse=True)
        return infos[0].direct_link or self._api_call(
            infos[0].get_direct_link, update_loading=update_loading)

    def _ensure_mpv(self) -> None:
        if self.mpv and self.mpv.poll() is None and MPV_SOCKET.exists(): return
        MPV_SOCKET.unlink(missing_ok=True)
        self.mpv = subprocess.Popen(["/usr/bin/mpv", "--idle=yes", "--no-video", "--audio-display=no",
            "--no-terminal", "--load-scripts=no", "--audio-client-name=Yandex Music",
            f"--input-ipc-server={MPV_SOCKET}", "--force-window=no", f"--volume={self.volume}"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(60):
            if MPV_SOCKET.exists(): return
            time.sleep(.05)
        raise RuntimeError("Не удалось запустить mpv")

    def _mpv_command(self, command: list[Any], start: bool = True) -> Any:
        if start: self._ensure_mpv()
        elif not self.mpv or self.mpv.poll() is not None or not MPV_SOCKET.exists(): return None
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.settimeout(3); sock.connect(str(MPV_SOCKET))
            sock.sendall((json.dumps({"command": command}) + "\n").encode())
            data = b""
            while b"\n" not in data: data += sock.recv(65536)
        try:
            response = json.loads(data.splitlines()[0])
        except (IndexError, json.JSONDecodeError) as exc:
            raise RuntimeError("mpv вернул некорректный ответ") from exc
        if response.get("error") != "success": raise RuntimeError(response.get("error", "mpv error"))
        return response.get("data")

    def _wait_mpv_ready(self, timeout: float = 8) -> None:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                idle = bool(self._mpv_command(["get_property", "idle-active"], False))
                duration = float(self._mpv_command(["get_property", "duration"], False) or 0)
                if not idle and duration > 0: return
            except Exception:
                idle = True
                duration = 0.0
            time.sleep(.15)
        raise RuntimeError("mpv не успел открыть аудиопоток")

    def _play_current(self, resume_position: int = 0, start_paused: bool = False,
                      initial_url: str = "") -> None:
        with self.lock:
            self.detached_track = None
            self.play_generation += 1; generation = self.play_generation
        def load() -> None:
            last_error: Exception | None = None
            for attempt in range(3):
                try:
                    with self.lock:
                        if generation != self.play_generation or not (0 <= self.index < len(self.queue)): return
                        track = self.queue[self.index]
                        self.state.update(loading=True, loadingKind="track", error="")
                    meta = self._metadata(track)
                    with self.lock: self.state["loadingStage"] = "downloadInfo"
                    url = initial_url if attempt == 0 and initial_url else self._url(track)
                    with self.lock: self.state["loadingStage"] = "audioStream"
                    self._mpv_command(["loadfile", url, "replace"])
                    self._wait_mpv_ready()
                    self._mpv_command(["set_property", "force-media-title", f"{meta['title']} — {meta['artist']}"])
                    if resume_position > 0: self._mpv_command(["seek", resume_position, "absolute"])
                    self._mpv_command(["set_property", "mute", self.muted])
                    self._mpv_command(["set_property", "pause", bool(start_paused)])
                    position = float(self._mpv_command(
                        ["get_property", "time-pos"], False) or resume_position)
                    position_observed_at = time.time()
                    with self.lock:
                        if generation != self.play_generation: return
                        track_id = self._track_id(track)
                        self.state.update(meta); self.state.update(playing=not start_paused,
                            stopped=False, loading=False, loadingKind="", loadingStage="",
                            position=position, positionObservedAt=position_observed_at,
                            duration=self._int(getattr(track, "duration_ms", 0)) // 1000,
                            liked=track_id in self.liked_ids, disliked=track_id in self.disliked_ids,
                            error="")
                        # The monitor marks the file active only after mpv has
                        # actually left its transient idle state. This avoids
                        # skipping a restored track while it is still opening.
                        self.had_file = False; self.active_ticks = 0; self.consecutive_failures = 0
                    if not start_paused: self._begin_playback_reporting(track)
                    self._publish_mpris(); self._notify_track(meta)
                    self._save_state(True); self._maybe_extend_collection(); return
                except Exception as exc:
                    last_error = exc; time.sleep(1.5 * (attempt + 1))
            with self.lock: self.consecutive_failures += 1
            self._set_error(f"Не удалось воспроизвести трек после 3 попыток: {last_error}")
            if self.queue and self.consecutive_failures < min(3, len(self.queue)): self.next()
        threading.Thread(target=load, daemon=True).start()

    def _notification_cover(self, url: str) -> str:
        if not url: return "audio-x-generic"
        try:
            cover_dir = RUNTIME / "omarchy-yandex-music-covers"
            cover_dir.mkdir(mode=0o700, exist_ok=True)
            cover = cover_dir / f"{hashlib.sha256(url.encode()).hexdigest()[:24]}.jpg"
            if not cover.exists():
                response = requests.get(url, timeout=10)
                response.raise_for_status()
                content_type = response.headers.get("content-type", "")
                if not content_type.startswith("image/") or len(response.content) > 5_000_000:
                    return "audio-x-generic"
                cover.write_bytes(response.content)
                cover.chmod(0o600)
                cached = sorted(cover_dir.glob("*.jpg"), key=lambda item: item.stat().st_mtime, reverse=True)
                for old_cover in cached[30:]: old_cover.unlink(missing_ok=True)
            return str(cover)
        except Exception:
            return "audio-x-generic"

    def _notify_track(self, metadata: dict[str, Any]) -> None:
        if self.preferences.get("notifications") != "all": return
        try:
            icon = self._notification_cover(str(metadata.get("artUrl", "")))
            subprocess.Popen(["/usr/bin/notify-send", "--app-name=Yandex Music",
                f"--icon={icon}", str(metadata.get("title", "Яндекс Музыка")),
                str(metadata.get("artist", ""))], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            return

    def cycle_mode(self) -> None:
        modes = ["order", "shuffle", "repeatQueue", "repeatTrack"]
        current = str(self.preferences.get("playbackMode", "repeatQueue"))
        self.set_preference("playbackMode", modes[(modes.index(current) + 1) % len(modes)])

    def pause(self) -> None:
        try:
            idle = bool(self._mpv_command(["get_property", "idle-active"]))
            if idle:
                with self.lock: has_track = bool(self.queue)
                if has_track: self._play_current()
                return
            paused = bool(self._mpv_command(["get_property", "pause"]))
            self._mpv_command(["set_property", "pause", not paused])
            position = float(self._mpv_command(["get_property", "time-pos"], False)
                             or self.state.get("position", 0) or 0)
            with self.lock:
                self.state.update(playing=paused, stopped=False, position=position,
                                  positionObservedAt=time.time())
                self._update_playback_clock_locked(paused)
                track = self._current_track_locked() if paused and not self.playback_report else None
            if track is not None: self._begin_playback_reporting(track)
            self._publish_mpris(); self._save_state(True)
        except Exception as exc: self._set_error(exc)

    def seek(self, seconds: int) -> None:
        try:
            target = max(0, min(int(seconds), int(self.state["duration"] or seconds)))
            self._mpv_command(["seek", target, "absolute"])
            with self.lock:
                self.state.update(position=float(target), positionObservedAt=time.time())
            self._publish_mpris(seeked=True); self._save_state(True)
        except Exception as exc: self._set_error(exc)

    def set_volume(self, value: int) -> None:
        self.volume = max(0, min(100, self._int(value)))
        self.muted = False
        try:
            self._mpv_command(["set_property", "volume", self.volume])
            self._mpv_command(["set_property", "mute", False])
        except Exception as exc: self._set_error(exc)
        with self.lock: self.state.update(volume=self.volume, muted=False)
        self._publish_mpris(); self._save_state(True)

    def toggle_mute(self) -> None:
        try:
            self.muted = not bool(self._mpv_command(["get_property", "mute"]))
            self._mpv_command(["set_property", "mute", self.muted])
            with self.lock: self.state["muted"] = self.muted
            self._save_state(True)
        except Exception as exc: self._set_error(exc)

    def next(self, automatic: bool = False) -> None:
        end_queue = False
        with self.lock:
            if not self.queue: return
        self._finish_playback_reporting(finished=automatic)
        with self.lock:
            if not self.queue: return
            mode = str(self.preferences.get("playbackMode", "repeatQueue"))
            detached = self.detached_track is not None
            extend_radio = False
            extend_collection = False
            extend_artist = False
            if automatic and mode == "repeatTrack" and not detached:
                pass
            elif self.radio_station and self.index >= len(self.queue) - 1:
                extend_radio = True
            elif self.queue_source and self.index >= len(self.queue) - 1:
                extend_collection = True
            elif (self.queue_artist_id and self.queue_artist_has_more
                  and self.index >= len(self.queue) - 1):
                extend_artist = True
            elif mode == "shuffle" and len(self.queue) > 1:
                choices = [i for i in range(len(self.queue)) if i != self.index]
                self.index = random.choice(choices)
            elif self.index < len(self.queue) - 1:
                self.index += 1
            elif mode == "repeatQueue":
                self.index = 0
            else:
                end_queue = True
        if end_queue:
            self.stop(); return
        if extend_radio:
            self._extend_radio(advance=True); return
        if extend_collection:
            self._extend_collection(advance=True); return
        if extend_artist:
            self._extend_artist_queue(advance=True, automatic=automatic); return
        self._save_state(True); self._play_current()

    def previous(self) -> None:
        try:
            if float(self._mpv_command(["get_property", "time-pos"], False) or 0) > 5:
                self.seek(0); return
        except Exception:
            position = 0.0
        with self.lock:
            if not self.queue: return
        self._finish_playback_reporting(finished=False)
        with self.lock:
            if not self.queue: return
            if self.detached_track is not None:
                self.index %= len(self.queue)
            else:
                self.index = (self.index - 1) % len(self.queue)
        self._save_state(True); self._play_current()

    def stop(self) -> None:
        self._finish_playback_reporting(finished=False)
        try: self._mpv_command(["stop"], False)
        except Exception:
            stopped = False
        with self.lock:
            self.had_file = False
            self.active_ticks = 0
            self.state.update(playing=False, stopped=True, position=0.0,
                              positionObservedAt=time.time())
        self._publish_mpris(); self._save_state(True)

    def shutdown(self) -> None:
        self._save_state(True)
        try: self._mpv_command(["quit"], False)
        except Exception:
            return

    def _monitor(self) -> None:
        while True:
            time.sleep(1)
            try:
                if not self.mpv or self.mpv.poll() is not None or not MPV_SOCKET.exists(): continue
                with self.lock:
                    if self.state["loading"]: continue
                idle = bool(self._mpv_command(["get_property", "idle-active"], False))
                if idle:
                    with self.lock:
                        was_active = self.had_file
                        position = self._int(self.state["position"])
                        duration = self._int(self.state["duration"])
                        should_play = bool(self.state["playing"])
                        self.had_file = False; self.active_ticks = 0
                        self._update_playback_clock_locked(False)
                    if was_active:
                        if duration > 0 and position >= duration - 5:
                            self.next(automatic=True)
                        else:
                            # An unexpected idle state means the stream was
                            # interrupted, not that the track ended. Reopen a
                            # fresh short-lived URL at the saved position.
                            self._play_current(resume_position=position, start_paused=not should_play)
                    continue

                paused = bool(self._mpv_command(["get_property", "pause"], False))
                position = self._float(self._mpv_command(["get_property", "time-pos"], False))
                position_observed_at = time.time()
                duration = self._int(self._float(self._mpv_command(["get_property", "duration"], False)))
                volume = self._int(self._float(
                    self._mpv_command(["get_property", "volume"], False) or self.volume))
                muted = bool(self._mpv_command(["get_property", "mute"], False))
                with self.lock:
                    self.active_ticks += 1
                    self.had_file = self.active_ticks >= 2 and position >= 3
                    self._update_playback_clock_locked(not paused)
                    self.volume = volume; self.muted = muted
                    self.state.update(playing=not paused, position=position,
                                      positionObservedAt=position_observed_at,
                                      duration=duration, volume=volume, muted=muted)
                self._publish_mpris(); self._save_state()
            except Exception:
                continue

    def status(self, include_queue: bool = False) -> dict[str, Any]:
        with self.lock:
            data = dict(self.state); data["playlists"] = list(self.playlists)
            data["network"] = dict(self.network)
            data["queueRevision"] = self.queue_revision
            data["libraryRevision"] = self.library_revision
            data["libraryHubRevision"] = self.library_hub_revision
            data["catalogRevision"] = self.catalog_revision
            data["searchResults"] = [{**self._metadata(t), "index": i} for i,t in enumerate(self.search_results)]
            data["queueIndex"] = (self.index + 1
                                  if self.detached_track is None and self.index >= 0 else 0)
            data["queueCount"] = len(self.queue)
            if include_queue:
                data["catalog"] = copy.deepcopy(self.catalog)
                data["libraryHub"] = copy.deepcopy(self.library_hub)
                data["libraryTracks"] = [
                    {**self._metadata(track), "index": i,
                     "duration": self._int(getattr(track, "duration_ms", 0)) // 1000,
                     "current": False}
                    for i, track in enumerate(self.library_results)]
                rows = []
                for i, track in enumerate(self.queue):
                    meta = self._metadata(track)
                    rows.append({**meta, "index": i,
                                 "duration": self._int(getattr(track, "duration_ms", 0)) // 1000,
                                 "current": self.detached_track is None and i == self.index})
                data["queueTracks"] = rows
            return data

    def handle(self, req: dict[str, Any]) -> dict[str, Any]:
        cmd = req.get("command", "status")
        if cmd == "status": return self.status()
        if cmd == "details": return self.status(include_queue=True)
        if cmd == "network": return self.network_status(start=True)
        if cmd == "lyrics": return self.lyrics()
        if cmd == "lyrics_refresh": return self.lyrics(force=True)
        if cmd == "track_info": return self.track_info()
        if cmd == "track_info_refresh": return self.track_info(force=True)
        if cmd == "auth": self.authenticate()
        elif cmd == "logout": self.logout()
        elif cmd == "likes": self.play_likes()
        elif cmd == "wave": self.play_wave()
        elif cmd == "track_radio": self.play_track_radio()
        elif cmd == "like": self.toggle_like()
        elif cmd == "dislike": self.toggle_dislike()
        elif cmd == "playlist": self.play_playlist(str(req.get("kind", "")))
        elif cmd == "load_more_library": self.load_more_library()
        elif cmd == "library_section": self.library_section(str(req.get("section", "")))
        elif cmd == "library_retry": self.library_section(
            str(req.get("section", "")), force=True)
        elif cmd == "library_back": self.library_back()
        elif cmd == "library_section_more": self.library_section_more()
        elif cmd == "browse_personal": self.browse_personal_playlist(
            str(req.get("playlistId", "")))
        elif cmd == "play_library_hub_track": self.play_library_hub_track(
            self._int(req.get("index", -1), -1))
        elif cmd == "play_station": self.play_station(
            str(req.get("station", "")), str(req.get("title", "")))
        elif cmd == "search": self.search(str(req.get("query", "")))
        elif cmd == "catalog_search": self.catalog_search(
            str(req.get("query", "")), str(req.get("type", "all")))
        elif cmd == "catalog_load_more": self.catalog_load_more()
        elif cmd == "catalog_suggest": self.catalog_suggest(
            str(req.get("query", "")), self._int(req.get("generation", 0)))
        elif cmd == "catalog_clear_suggestions": self.catalog_clear_suggestions(
            str(req.get("fieldText", "")))
        elif cmd == "catalog_album": self.catalog_album(str(req.get("albumId", "")))
        elif cmd == "catalog_artist": self.catalog_artist(str(req.get("artistId", "")))
        elif cmd == "catalog_artist_more": self.catalog_artist_more(str(req.get("section", "")))
        elif cmd == "catalog_playlist": self.catalog_playlist(
            str(req.get("uuid", "")), str(req.get("owner", "")), str(req.get("kind", "")))
        elif cmd == "catalog_entity_more": self.catalog_entity_more()
        elif cmd == "catalog_back": self.catalog_back()
        elif cmd == "play_catalog_track": self.play_catalog_track(
            str(req.get("source", "")), self._int(req.get("index", -1), -1))
        elif cmd == "play_search": self.play_search(self._int(req.get("index", -1), -1))
        elif cmd == "play_queue": self.play_queue(self._int(req.get("index", -1), -1))
        elif cmd == "play_library_track": self.play_library_track(
            self._int(req.get("index", -1), -1))
        elif cmd == "close_library": self.close_library()
        elif cmd == "artist": self.play_artist(str(req.get("artistId", "")))
        elif cmd == "play_artist_track": self.play_artist_track(
            self._int(req.get("index", -1), -1))
        elif cmd == "close_artist": self.close_artist()
        elif cmd == "pause": self.pause()
        elif cmd == "next": self.next()
        elif cmd == "previous": self.previous()
        elif cmd == "seek": self.seek(self._int(req.get("value", 0)))
        elif cmd == "volume": self.set_volume(self._int(req.get("value", self.volume)))
        elif cmd == "mute": self.toggle_mute()
        elif cmd == "mode": self.cycle_mode()
        elif cmd == "setting": self.set_preference(str(req.get("key", "")), req.get("value"))
        elif cmd == "stop": self.stop()
        else: return {"error": f"unknown command: {cmd}"}
        return {"ok": True}


def serve() -> None:
    SOCKET.unlink(missing_ok=True)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); server.bind(str(SOCKET)); os.chmod(SOCKET, 0o600)
    server.listen(10); player = Player()
    def shutdown(*_: Any) -> None:
        player.shutdown(); SOCKET.unlink(missing_ok=True); raise SystemExit(0)
    signal.signal(signal.SIGTERM, shutdown); signal.signal(signal.SIGINT, shutdown)
    while True:
        conn, _ = server.accept()
        with conn:
            try:
                raw = b""
                while b"\n" not in raw:
                    chunk = conn.recv(65536)
                    if not chunk: break
                    raw += chunk
                response = player.handle(json.loads(raw.splitlines()[0] or b"{}"))
            except Exception as exc: response = {"error": str(exc)}
            conn.sendall((json.dumps(response, ensure_ascii=False) + "\n").encode())

if __name__ == "__main__": serve()

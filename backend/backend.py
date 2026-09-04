#!/usr/bin/env python3
"""Local, browser-free Yandex Music player backend for Omarchy."""
from __future__ import annotations

import asyncio
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
    def SupportedUriSchemes(self) -> "as": return []

    @dbus_property(access=PropertyAccess.READ)
    def SupportedMimeTypes(self) -> "as": return []


class MprisPlayer(ServiceInterface):
    def __init__(self, player: Any) -> None:
        super().__init__("org.mpris.MediaPlayer2.Player")
        self.player = player
        self.last_properties: dict[str, Any] = {}

    def _state(self) -> dict[str, Any]:
        with self.player.lock:
            return dict(self.player.state)

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
        self.player.seek(int(state.get("position", 0)) + int(offset) // 1_000_000)

    @method()
    def SetPosition(self, track_id: "o", position: "x"):
        if track_id == self._track_path(): self.player.seek(int(position) // 1_000_000)

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
    def Metadata(self) -> "a{sv}":
        state = self._state()
        metadata = {
            "mpris:trackid": Variant("o", self._track_path()),
            "xesam:title": Variant("s", str(state.get("title", ""))),
            "xesam:artist": Variant("as", [str(a.get("name", "")) for a in state.get("artists", [])]),
            "xesam:album": Variant("s", str(state.get("album", ""))),
            "mpris:length": Variant("x", int(state.get("duration", 0)) * 1_000_000),
        }
        art_url = str(state.get("artUrl", ""))
        if art_url: metadata["mpris:artUrl"] = Variant("s", art_url)
        return metadata

    @dbus_property(access=PropertyAccess.READWRITE)
    def Volume(self) -> "d": return float(self.player.volume) / 100

    @Volume.setter
    def Volume(self, value: "d") -> None: self.player.set_volume(round(value * 100))

    @dbus_property(access=PropertyAccess.READ)
    def Position(self) -> "x": return int(self._state().get("position", 0)) * 1_000_000

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
        self.detached_track: Any | None = None
        self.library_revision = 0
        self.index = -1
        self.playlists: list[dict[str, Any]] = []
        self.search_results: list[Any] = []
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
                    if not self._is_rate_limit_error(exc) or attempt >= len(delays):
                        if self._is_rate_limit_error(exc): raise RuntimeError(RATE_LIMIT_MESSAGE) from exc
                        raise
                    if update_loading:
                        with self.lock: self.state["loadingStage"] = "rateLimit"
                    time.sleep(delays[attempt])
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
                pass
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
        elapsed = max(0.0, min(5.0, current - float(report["lastTick"])))
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
            duration = max(0, int(getattr(track, "duration_ms", 0) or 0) // 1000)
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
            position = int(self.state.get("position", 0) or 0)
            duration = int(report["duration"] or self.state.get("duration", 0) or 0)
            played = max(0, int(round(float(report["playedSeconds"]))))
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
                        station, track_id, float(played), batch_id=batch_id or None))
            else:
                operations.append(lambda client=client, station=station, track_id=track_id,
                                  played=played, batch_id=batch_id:
                    client.rotor_station_feedback_skip(
                        station, track_id, float(played), batch_id=batch_id or None))
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
        now = int(time.time())
        with self.lock:
            fresh = self.network["checkedAt"] and now - int(self.network["checkedAt"]) < NETWORK_PROBE_TTL
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
            "checkedAt": int(time.time()), "error": "",
        }
        try:
            response = requests.get(API_STATUS_URL, timeout=(3, 5))
            result["latencyMs"] = max(1, round((time.monotonic() - started) * 1000))
            response.raise_for_status()
            account = (response.json().get("result") or {}).get("account") or {}
            result.update(available=True, serviceAvailable=account.get("serviceAvailable"),
                          region=account.get("region"))
        except requests.exceptions.Timeout:
            result["error"] = "таймаут"
        except requests.exceptions.SSLError:
            result["error"] = "ошибка TLS"
        except requests.exceptions.HTTPError as exc:
            status = exc.response.status_code if exc.response is not None else ""
            result["error"] = f"HTTP {status}".strip()
        except requests.exceptions.ConnectionError:
            result["error"] = "ошибка соединения"
        except (ValueError, TypeError, AttributeError):
            result["error"] = "некорректный ответ"
        except Exception:
            result["error"] = "неизвестная ошибка"
        with self.lock:
            self.network.update(result)

    def _load_preferences(self) -> dict[str, Any]:
        preferences = dict(DEFAULT_PREFERENCES)
        try:
            saved = json.loads(PREFERENCES_FILE.read_text()) if PREFERENCES_FILE.exists() else {}
            if isinstance(saved, dict): preferences.update(saved)
        except Exception:
            pass
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
        return json.loads(TOKEN_FILE.read_text())

    def _save_token(self, token: Any, previous_refresh: str | None = None) -> None:
        atomic_json(TOKEN_FILE, {
            "access_token": token.access_token,
            "refresh_token": token.refresh_token or previous_refresh,
            "expires_in": token.expires_in,
            "saved_at": int(time.time()),
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
            "expires_in": data.get("expires_in"), "saved_at": int(time.time()),
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
            self.lyrics_cache.clear(); self.lyrics_loading.clear(); self.lyrics_generation += 1
            self.track_info_cache.clear(); self.track_info_loading.clear(); self.track_info_generation += 1
            self.library_source = []; self.library_offset = 0
            self.library_generation += 1; self.library_revision += 1
            self.active_library_cache_key = ""; self.collection_cache = {}
            self.liked_ids = set(); self.liked_rows = []; self.liked_rows_at = 0
            self.disliked_ids = set()
            self.queue = []; self.queue_source = []; self.queue_extending = False
            self.queue_advance_pending = False; self.queue_generation += 1; self.queue_revision += 1; self.index = -1
            self.queue_collection_key = ""; self.detached_track = None
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

    def _tracks_from_short_page(self, rows: list[Any]) -> list[Any]:
        """Resolve one collection page in one API request while retaining source order."""
        assert self.client
        missing = [row for row in rows if not getattr(row, "track", None)]
        track_ids = [str(getattr(row, "track_id", getattr(row, "id", ""))) for row in missing]
        fetched = self._api_call(lambda: self.client.tracks(track_ids)) if missing else []
        by_id = {str(getattr(track, "id", "")): track for track in fetched}
        tracks = []
        for row in rows:
            track = getattr(row, "track", None) or by_id.get(str(getattr(row, "id", "")))
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
        if now - float(cached.get("storedAt", 0)) > COLLECTION_CACHE_TTL:
            self.collection_cache.pop(key, None)
            return False
        self.active_library_cache_key = key
        self.library_source = list(cached["source"])
        self.library_results = list(cached["results"])
        self.library_offset = min(int(cached["offset"]), len(self.library_source))
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
                list(cached["source"]), list(cached["results"]), int(cached["offset"]))
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

    def _maybe_extend_collection(self) -> None:
        with self.lock:
            should_extend = bool(self.queue_source) and len(self.queue) - self.index <= 5
        if should_extend: self._extend_collection()

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

    def search(self, query: str) -> None:
        query = query.strip()
        if not query: return
        def load() -> None:
            try:
                assert self.client
                result = self._api_call(lambda: self.client.search(query, type_="track"))
                with self.lock:
                    self.search_results = list(result.tracks.results or [])[:30] if result and result.tracks else []
                    self.state.update(loading=False, loadingKind="")
            except Exception as exc: self._set_error(f"Ошибка поиска: {exc}")
        self._loading(load, "search")

    def play_search(self, index: int) -> None:
        with self.lock: tracks = list(self.search_results)
        if 0 <= index < len(tracks): self._set_queue(tracks[index:] + tracks[:index], "Результаты поиска")

    @staticmethod
    def _parse_lrc(content: str) -> list[dict[str, Any]]:
        """Parse standard LRC timestamps into ordered, seekable lyric lines."""
        timestamp = re.compile(r"\[(\d{1,3}):([0-5]?\d)(?:[\.:](\d{1,3}))?\]")
        enhanced_timestamp = re.compile(r"<\d{1,3}:[0-5]?\d(?:[\.:]\d{1,3})?>")
        offset_match = re.search(r"(?im)^\[offset:([+-]?\d+)\]\s*$", content)
        offset = int(offset_match.group(1)) / 1000 if offset_match else 0.0
        lines: list[dict[str, Any]] = []
        for source_index, raw_line in enumerate(content.splitlines()):
            matches = list(timestamp.finditer(raw_line))
            if not matches: continue
            text = enhanced_timestamp.sub("", timestamp.sub("", raw_line)).strip()
            if not text: continue
            for match in matches:
                fraction_text = match.group(3) or ""
                fraction = int(fraction_text) / (10 ** len(fraction_text)) if fraction_text else 0.0
                seconds = int(match.group(1)) * 60 + int(match.group(2)) + fraction + offset
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
            if lrc_content.strip():
                plain_lines = self._plain_lyrics_lines(lrc_content)
                if plain_lines:
                    return {"available": True, "synced": False, "format": "TEXT",
                            "writers": lrc_writers, "lines": plain_lines, "error": ""}
            if self._is_not_found_error(exc) and (lrc_error is None or self._is_not_found_error(lrc_error)):
                return {"available": False, "synced": False, "format": "",
                        "writers": [], "lines": [], "error": ""}
            raise

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
            "trackNumber": int(getattr(track_position, "index", 0) or 0),
            "discNumber": int(getattr(track_position, "volume", 0) or 0),
            "duration": int(getattr(track, "duration_ms", 0) or 0) // 1000,
            "version": str(getattr(track, "version", "") or ""),
            "explicit": bool(getattr(track, "explicit", False)
                             or getattr(track, "content_warning", "") == "explicit"),
            "aliases": aliases, "description": str(description), "credits": credits,
            "error": ("Часть сведений недоступна: " + "; ".join(dict.fromkeys(errors)))
                     if errors else "",
        }
        return entry

    @staticmethod
    def _track_info_response(track_id: str, entry: dict[str, Any] | None = None,
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
                "trackNumber": int(value.get("trackNumber", 0)),
                "discNumber": int(value.get("discNumber", 0)),
                "duration": int(value.get("duration", 0)),
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
        if not artist_id: return
        with self.lock:
            self.artist_results = []
            self._reset_library_locked()
            self.state["artistBrowseName"] = ""
        def load() -> None:
            try:
                assert self.client
                result = self._api_call(
                    lambda: self.client.artists_tracks(artist_id, page=0, page_size=100))
                tracks = list(result.tracks or []) if result else []
                if not tracks: raise RuntimeError("У исполнителя нет доступных треков")
                artists = self._api_call(lambda: self.client.artists(artist_id)) or []
                name = artists[0].name if artists else "Треки исполнителя"
                with self.lock:
                    self.artist_results = tracks
                    self.state.update(artistBrowseName=name, loading=False, loadingKind="", error="")
            except Exception as exc:
                self._set_error(f"Не удалось загрузить треки исполнителя: {exc}")
        self._loading(load, "artist")

    def play_artist_track(self, index: int) -> None:
        with self.lock:
            tracks = list(self.artist_results)
            name = str(self.state.get("artistBrowseName", "Треки исполнителя"))
        if 0 <= index < len(tracks): self._set_queue(tracks, name, start_index=index)

    def close_artist(self) -> None:
        with self.lock:
            self.artist_results = []
            self.state["artistBrowseName"] = ""

    def _set_queue(self, tracks: list[Any], name: str, station: str = "", batch_id: str = "",
                   start_index: int = 0, remaining_rows: list[Any] | None = None,
                   collection_key: str = "") -> None:
        if not tracks: raise RuntimeError("В списке нет доступных треков")
        self._finish_playback_reporting(finished=False)
        with self.lock:
            self.queue = tracks; self.index = max(0, min(start_index, len(tracks) - 1))
            self.queue_source = list(remaining_rows or [])
            self.queue_extending = False; self.queue_advance_pending = False
            self.queue_generation += 1; self.queue_revision += 1
            self.queue_collection_key = collection_key; self.detached_track = None
            self.artist_results = []
            self._reset_library_locked()
            self.state["artistBrowseName"] = ""
            self.radio_station = station; self.radio_batch_id = batch_id
            self.radio_track_batches = ({self._track_id(track): batch_id for track in tracks}
                                        if station and batch_id else {})
            self.radio_extending = False; self.radio_advance_pending = False
            self.state.update(queueName=name, loading=False, loadingKind="")
        if station: self._report_radio_started(station, batch_id)
        self._save_state(True); self._play_current()

    def _metadata(self, track: Any) -> dict[str, str]:
        track_artists = list(track.artists or [])
        artists = ", ".join(a.name for a in track_artists)
        artist_id = str(track_artists[0].id) if track_artists else ""
        album = track.albums[0].title if getattr(track, "albums", None) else ""
        try: cover = track.get_cover_url("400x400") or ""
        except Exception:
            uri = getattr(track, "cover_uri", "") or ""
            cover = "https://" + uri.replace("%%", "400x400") if uri else ""
        artist_rows = [{"id": str(a.id), "name": a.name} for a in track_artists]
        return {"title": track.title or "", "trackId": self._track_id(track),
                "artist": artists, "artistId": artist_id,
                "artists": artist_rows, "album": album, "artUrl": cover}

    def _url(self, track: Any) -> str:
        infos = self._api_call(lambda: track.get_download_info(get_direct_links=True)) or []
        if not infos: raise RuntimeError("Яндекс не вернул ссылку на аудио")
        if self.preferences["audioQuality"] == "economy":
            infos.sort(key=lambda x: (x.bitrate_in_kbps or 10_000, x.codec not in ("aac", "mp3")))
        else:
            infos.sort(key=lambda x: (x.codec in ("mp3", "aac"), x.bitrate_in_kbps or 0), reverse=True)
        return infos[0].direct_link or self._api_call(infos[0].get_direct_link)

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
        response = json.loads(data.splitlines()[0])
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
                pass
            time.sleep(.15)
        raise RuntimeError("mpv не успел открыть аудиопоток")

    def _play_current(self, resume_position: int = 0, start_paused: bool = False) -> None:
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
                    url = self._url(track)
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
                            duration=int(getattr(track, "duration_ms", 0) or 0)//1000,
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
            pass

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
        self.volume = max(0, min(100, int(value)))
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
            if automatic and mode == "repeatTrack" and not detached:
                pass
            elif self.radio_station and self.index >= len(self.queue) - 1:
                extend_radio = True
            elif self.queue_source and self.index >= len(self.queue) - 1:
                extend_collection = True
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
        self._save_state(True); self._play_current()

    def previous(self) -> None:
        try:
            if float(self._mpv_command(["get_property", "time-pos"], False) or 0) > 5:
                self.seek(0); return
        except Exception: pass
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
        except Exception: pass
        with self.lock:
            self.had_file = False
            self.active_ticks = 0
            self.state.update(playing=False, stopped=True, position=0.0,
                              positionObservedAt=time.time())
        self._publish_mpris(); self._save_state(True)

    def shutdown(self) -> None:
        self._save_state(True)
        try: self._mpv_command(["quit"], False)
        except Exception: pass

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
                        position = int(self.state["position"] or 0)
                        duration = int(self.state["duration"] or 0)
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
                position = float(self._mpv_command(["get_property", "time-pos"], False) or 0)
                position_observed_at = time.time()
                duration = int(float(self._mpv_command(["get_property", "duration"], False) or 0))
                volume = int(float(self._mpv_command(["get_property", "volume"], False) or self.volume))
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
            except Exception: pass

    def status(self, include_queue: bool = False) -> dict[str, Any]:
        with self.lock:
            data = dict(self.state); data["playlists"] = list(self.playlists)
            data["network"] = dict(self.network)
            data["queueRevision"] = self.queue_revision
            data["libraryRevision"] = self.library_revision
            data["searchResults"] = [{**self._metadata(t), "index": i} for i,t in enumerate(self.search_results)]
            data["queueIndex"] = (self.index + 1
                                  if self.detached_track is None and self.index >= 0 else 0)
            data["queueCount"] = len(self.queue)
            if include_queue:
                data["artistTracks"] = [
                    {**self._metadata(track), "index": i,
                     "duration": int(getattr(track, "duration_ms", 0) or 0) // 1000,
                     "current": False}
                    for i, track in enumerate(self.artist_results)]
                data["libraryTracks"] = [
                    {**self._metadata(track), "index": i,
                     "duration": int(getattr(track, "duration_ms", 0) or 0) // 1000,
                     "current": False}
                    for i, track in enumerate(self.library_results)]
                rows = []
                for i, track in enumerate(self.queue):
                    meta = self._metadata(track)
                    rows.append({**meta, "index": i,
                                 "duration": int(getattr(track, "duration_ms", 0) or 0) // 1000,
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
        elif cmd == "search": self.search(str(req.get("query", "")))
        elif cmd == "play_search": self.play_search(int(req.get("index", -1)))
        elif cmd == "play_queue": self.play_queue(int(req.get("index", -1)))
        elif cmd == "play_library_track": self.play_library_track(int(req.get("index", -1)))
        elif cmd == "close_library": self.close_library()
        elif cmd == "artist": self.play_artist(str(req.get("artistId", "")))
        elif cmd == "play_artist_track": self.play_artist_track(int(req.get("index", -1)))
        elif cmd == "close_artist": self.close_artist()
        elif cmd == "pause": self.pause()
        elif cmd == "next": self.next()
        elif cmd == "previous": self.previous()
        elif cmd == "seek": self.seek(int(req.get("value", 0)))
        elif cmd == "volume": self.set_volume(int(req.get("value", self.volume)))
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

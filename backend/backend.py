#!/usr/bin/env python3
"""Local, browser-free Yandex Music player backend for Omarchy."""
from __future__ import annotations

import asyncio
import json
import os
import re
import signal
import socket
import subprocess
import threading
import time
from pathlib import Path
from typing import Any, Callable

import requests
from dbus_next import Variant
from dbus_next.aio import MessageBus
from dbus_next.constants import PropertyAccess
from dbus_next.service import ServiceInterface, dbus_property, method, signal as dbus_signal
from yandex_music import Client
from yandex_music._client.device_auth import _DEFAULT_CLIENT_ID, _DEFAULT_CLIENT_SECRET, _OAUTH_BASE_URL

CONFIG = Path.home() / ".config/omarchy-yandex-music"
TOKEN_FILE = CONFIG / "token.json"
STATE_FILE = CONFIG / "state.json"
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
SOCKET = RUNTIME / "omarchy-yandex-music.sock"
MPV_SOCKET = RUNTIME / "omarchy-yandex-music-mpv.sock"


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
        if not state.get("title"): return "Stopped"
        return "Playing" if state.get("playing") else "Paused"

    @dbus_property(access=PropertyAccess.READWRITE)
    def LoopStatus(self) -> "s": return "None"

    @LoopStatus.setter
    def LoopStatus(self, value: "s") -> None: pass

    @dbus_property(access=PropertyAccess.READWRITE)
    def Rate(self) -> "d": return 1.0

    @Rate.setter
    def Rate(self, value: "d") -> None: pass

    @dbus_property(access=PropertyAccess.READWRITE)
    def Shuffle(self) -> "b": return False

    @Shuffle.setter
    def Shuffle(self, value: "b") -> None: pass

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
        self.client: Client | None = None
        self.queue: list[Any] = []
        self.index = -1
        self.playlists: list[dict[str, Any]] = []
        self.search_results: list[Any] = []
        self.liked_ids: set[str] = set()
        self.radio_station = ""
        self.radio_batch_id = ""
        self.radio_extending = False
        self.radio_advance_pending = False
        self.mpv: subprocess.Popen | None = None
        self.had_file = False
        self.active_ticks = 0
        self.play_generation = 0
        self.consecutive_failures = 0
        self.last_saved_at = 0.0
        self.volume = 70
        self.muted = False
        self.state: dict[str, Any] = {
            "authenticated": False, "connecting": False, "authPending": False,
            "authUrl": "", "authCode": "", "error": "", "playing": False,
            "loading": False, "title": "", "artist": "", "album": "",
            "artUrl": "", "artistId": "", "artists": [], "queueName": "", "position": 0, "duration": 0,
            "volume": self.volume, "muted": self.muted, "liked": False, "restoring": False,
        }
        self.mpris = MprisBridge(self)
        threading.Thread(target=self._restore, daemon=True).start()
        threading.Thread(target=self._monitor, daemon=True).start()

    def _publish_mpris(self, seeked: bool = False) -> None:
        self.mpris.publish(seeked)

    def _set_error(self, exc: Any) -> None:
        with self.lock:
            self.state["error"] = str(exc).replace("\n", " ")[:300]
            self.state["loading"] = False
            self.state["connecting"] = False

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
            self.client = None; self.playlists = []; self.liked_ids = set(); self.queue = []; self.index = -1
            self.radio_station = ""; self.radio_batch_id = ""; self.radio_extending = False
            self.state.update(authenticated=False, authPending=False, authUrl="", authCode="",
                              title="", artist="", artistId="", artists=[], album="", artUrl="", queueName="",
                              liked=False, error="")
        self._publish_mpris()
        TOKEN_FILE.unlink(missing_ok=True); STATE_FILE.unlink(missing_ok=True)

    def _load_playlists(self) -> None:
        try:
            assert self.client
            rows = self.client.users_playlists_list() or []
            with self.lock:
                self.playlists = [{"kind": str(p.kind), "title": p.title,
                                   "count": int(p.track_count or 0)} for p in rows]
        except Exception as exc: self._set_error(f"Не удалось загрузить плейлисты: {exc}")

    @staticmethod
    def _track_from_short(item: Any) -> Any:
        return item.track if getattr(item, "track", None) else item.fetch_track()

    @staticmethod
    def _track_id(track: Any) -> str:
        return str(getattr(track, "id", ""))

    def _save_state(self, force: bool = False) -> None:
        if not force and time.monotonic() - self.last_saved_at < 5: return
        with self.lock:
            value = {"queue": [self._track_id(t) for t in self.queue if self._track_id(t)],
                     "index": self.index, "queueName": self.state["queueName"],
                     "position": self.state["position"], "playing": self.state["playing"],
                     "volume": self.volume, "muted": self.muted,
                     "radioStation": self.radio_station, "radioBatchId": self.radio_batch_id}
        atomic_json(STATE_FILE, value); self.last_saved_at = time.monotonic()

    def _restore_queue(self) -> None:
        if not STATE_FILE.exists() or not self.client: return
        try:
            saved = json.loads(STATE_FILE.read_text())
            ids = [str(x) for x in saved.get("queue", []) if x]
            self.volume = max(0, min(100, int(saved.get("volume", 70))))
            self.muted = bool(saved.get("muted", False))
            with self.lock: self.state.update(volume=self.volume, muted=self.muted)
            if not ids: return
            with self.lock: self.state["restoring"] = True
            tracks = self.client.tracks(ids) or []
            with self.lock:
                self.queue = tracks
                self.index = max(0, min(int(saved.get("index", 0)), len(tracks) - 1))
                self.radio_station = str(saved.get("radioStation", ""))
                self.radio_batch_id = str(saved.get("radioBatchId", ""))
                self.state["queueName"] = str(saved.get("queueName", ""))
            self._play_current(resume_position=int(saved.get("position", 0)),
                               start_paused=not bool(saved.get("playing", False)))
        except Exception as exc: self._set_error(f"Не удалось восстановить очередь: {exc}")
        finally:
            with self.lock: self.state["restoring"] = False

    def _loading(self, function: Callable[[], None]) -> None:
        with self.lock:
            if not self.state["authenticated"] or self.state["loading"]: return
            self.state.update(loading=True, error="")
        threading.Thread(target=function, daemon=True).start()

    def _load_liked_ids(self) -> None:
        try:
            assert self.client
            liked = self.client.users_likes_tracks()
            rows = list(liked.tracks or []) if liked else []
            with self.lock:
                self.liked_ids = {str(getattr(row, "id", "")) for row in rows if getattr(row, "id", "")}
                if 0 <= self.index < len(self.queue):
                    self.state["liked"] = self._track_id(self.queue[self.index]) in self.liked_ids
        except Exception as exc:
            self._set_error(f"Не удалось получить отметки «Мне нравится»: {exc}")

    def play_likes(self) -> None:
        def load() -> None:
            try:
                assert self.client
                liked = self.client.users_likes_tracks()
                rows = list(liked.tracks or []) if liked else []
                with self.lock:
                    self.liked_ids = {str(getattr(row, "id", "")) for row in rows if getattr(row, "id", "")}
                self._set_queue([self._track_from_short(x) for x in rows], "Мне нравится")
            except Exception as exc: self._set_error(f"Не удалось загрузить любимые треки: {exc}")
        self._loading(load)

    def toggle_like(self) -> None:
        try:
            assert self.client
            with self.lock:
                if not (0 <= self.index < len(self.queue)): return
                track_id = self._track_id(self.queue[self.index])
                was_liked = track_id in self.liked_ids
            if not track_id: return
            changed = (self.client.users_likes_tracks_remove(track_id) if was_liked
                       else self.client.users_likes_tracks_add(track_id))
            if not changed: raise RuntimeError("Яндекс не подтвердил изменение")
            with self.lock:
                if was_liked: self.liked_ids.discard(track_id)
                else: self.liked_ids.add(track_id)
                if 0 <= self.index < len(self.queue) and self._track_id(self.queue[self.index]) == track_id:
                    self.state["liked"] = not was_liked
                self.state["error"] = ""
        except Exception as exc:
            self._set_error(f"Не удалось изменить отметку «Мне нравится»: {exc}")

    def play_wave(self) -> None:
        def load() -> None:
            try:
                assert self.client
                station = "user:onyourwave"
                result = self.client.rotor_station_tracks(station)
                tracks = [row.track for row in (result.sequence if result else [])
                          if getattr(row, "track", None)]
                self._set_queue(tracks, "Моя волна", station, result.batch_id if result else "")
            except Exception as exc:
                self._set_error(f"Не удалось запустить «Мою волну»: {exc}")
        self._loading(load)

    def _extend_wave(self, advance: bool = False) -> None:
        with self.lock:
            if not self.radio_station or not self.client: return
            if self.radio_extending:
                self.radio_advance_pending = self.radio_advance_pending or advance
                return
            self.radio_extending = True
            self.radio_advance_pending = advance
            station = self.radio_station
            queue_id = self._track_id(self.queue[-1]) if self.queue else ""

        def load() -> None:
            should_advance = False
            try:
                assert self.client
                result = self.client.rotor_station_tracks(station, queue=queue_id or None)
                incoming = [row.track for row in (result.sequence if result else [])
                            if getattr(row, "track", None)]
                with self.lock:
                    existing = {self._track_id(track) for track in self.queue}
                    fresh = [track for track in incoming if self._track_id(track) not in existing]
                    old_length = len(self.queue)
                    self.queue.extend(fresh)
                    if result: self.radio_batch_id = result.batch_id
                    should_advance = self.radio_advance_pending and bool(fresh) and self.index >= old_length - 1
                    if should_advance: self.index = old_length
                    self.radio_advance_pending = False
                    self.radio_extending = False
                if should_advance:
                    self._play_current()
                self._save_state(True)
            except Exception as exc:
                with self.lock:
                    self.radio_extending = False; self.radio_advance_pending = False
                self._set_error(f"Не удалось продолжить «Мою волну»: {exc}")
        threading.Thread(target=load, daemon=True).start()

    def _maybe_extend_wave(self) -> None:
        with self.lock:
            should_extend = bool(self.radio_station) and len(self.queue) - self.index <= 5
        if should_extend: self._extend_wave()

    def play_playlist(self, kind: str) -> None:
        def load() -> None:
            try:
                assert self.client
                playlist = self.client.users_playlists(kind)
                self._set_queue([self._track_from_short(x) for x in playlist.fetch_tracks()], playlist.title)
            except Exception as exc: self._set_error(f"Не удалось загрузить плейлист: {exc}")
        self._loading(load)

    def search(self, query: str) -> None:
        query = query.strip()
        if not query: return
        def load() -> None:
            try:
                assert self.client
                result = self.client.search(query, type_="track")
                with self.lock:
                    self.search_results = list(result.tracks.results or [])[:30] if result and result.tracks else []
                    self.state["loading"] = False
            except Exception as exc: self._set_error(f"Ошибка поиска: {exc}")
        self._loading(load)

    def play_search(self, index: int) -> None:
        with self.lock: tracks = list(self.search_results)
        if 0 <= index < len(tracks): self._set_queue(tracks[index:] + tracks[:index], "Результаты поиска")

    def play_queue(self, index: int) -> None:
        with self.lock:
            if not (0 <= index < len(self.queue)): return
            self.index = index
        self._save_state(True)
        self._play_current()

    def play_artist(self, artist_id: str) -> None:
        if not artist_id: return
        def load() -> None:
            try:
                assert self.client
                result = self.client.artists_tracks(artist_id, page=0, page_size=100)
                tracks = list(result.tracks or []) if result else []
                artists = self.client.artists(artist_id) or []
                name = artists[0].name if artists else "Треки исполнителя"
                self._set_queue(tracks, name)
            except Exception as exc:
                self._set_error(f"Не удалось загрузить треки исполнителя: {exc}")
        self._loading(load)

    def _set_queue(self, tracks: list[Any], name: str, station: str = "", batch_id: str = "") -> None:
        if not tracks: raise RuntimeError("В списке нет доступных треков")
        with self.lock:
            self.queue = tracks; self.index = 0
            self.radio_station = station; self.radio_batch_id = batch_id
            self.radio_extending = False; self.radio_advance_pending = False
            self.state.update(queueName=name, loading=False)
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
        return {"title": track.title or "", "artist": artists, "artistId": artist_id,
                "artists": artist_rows, "album": album, "artUrl": cover}

    def _url(self, track: Any) -> str:
        infos = track.get_download_info(get_direct_links=True) or []
        if not infos: raise RuntimeError("Яндекс не вернул ссылку на аудио")
        infos.sort(key=lambda x: (x.codec in ("mp3", "aac"), x.bitrate_in_kbps or 0), reverse=True)
        return infos[0].direct_link or infos[0].get_direct_link()

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
            self.play_generation += 1; generation = self.play_generation
        def load() -> None:
            last_error: Exception | None = None
            for attempt in range(3):
                try:
                    with self.lock:
                        if generation != self.play_generation or not (0 <= self.index < len(self.queue)): return
                        track = self.queue[self.index]; self.state["loading"] = True
                    meta, url = self._metadata(track), self._url(track)
                    self._mpv_command(["loadfile", url, "replace"])
                    self._wait_mpv_ready()
                    self._mpv_command(["set_property", "force-media-title", f"{meta['title']} — {meta['artist']}"])
                    if resume_position > 0: self._mpv_command(["seek", resume_position, "absolute"])
                    self._mpv_command(["set_property", "mute", self.muted])
                    if start_paused: self._mpv_command(["set_property", "pause", True])
                    with self.lock:
                        if generation != self.play_generation: return
                        self.state.update(meta); self.state.update(playing=not start_paused, loading=False,
                            position=resume_position, duration=int(getattr(track, "duration_ms", 0) or 0)//1000,
                            liked=self._track_id(track) in self.liked_ids, error="")
                        # The monitor marks the file active only after mpv has
                        # actually left its transient idle state. This avoids
                        # skipping a restored track while it is still opening.
                        self.had_file = False; self.active_ticks = 0; self.consecutive_failures = 0
                    self._publish_mpris(); self._save_state(True); self._maybe_extend_wave(); return
                except Exception as exc:
                    last_error = exc; time.sleep(1.5 * (attempt + 1))
            with self.lock: self.consecutive_failures += 1
            self._set_error(f"Не удалось воспроизвести трек после 3 попыток: {last_error}")
            if self.queue and self.consecutive_failures < min(3, len(self.queue)): self.next()
        threading.Thread(target=load, daemon=True).start()

    def pause(self) -> None:
        try:
            paused = bool(self._mpv_command(["get_property", "pause"]))
            self._mpv_command(["set_property", "pause", not paused])
            with self.lock: self.state["playing"] = paused
            self._publish_mpris(); self._save_state(True)
        except Exception as exc: self._set_error(exc)

    def seek(self, seconds: int) -> None:
        try:
            target = max(0, min(int(seconds), int(self.state["duration"] or seconds)))
            self._mpv_command(["seek", target, "absolute"])
            with self.lock: self.state["position"] = target
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

    def next(self) -> None:
        with self.lock:
            if not self.queue: return
            if self.radio_station and self.index >= len(self.queue) - 1:
                extend_wave = True
            else:
                extend_wave = False
                self.index = (self.index + 1) % len(self.queue)
        if extend_wave:
            self._extend_wave(advance=True); return
        self._save_state(True); self._play_current()

    def previous(self) -> None:
        try:
            if float(self._mpv_command(["get_property", "time-pos"], False) or 0) > 5:
                self.seek(0); return
        except Exception: pass
        with self.lock:
            if not self.queue: return
            self.index = (self.index - 1) % len(self.queue)
        self._save_state(True); self._play_current()

    def stop(self) -> None:
        try: self._mpv_command(["stop"], False)
        except Exception: pass
        with self.lock: self.had_file = False; self.state["playing"] = False
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
                    if was_active:
                        if duration > 0 and position >= duration - 5:
                            self.next()
                        else:
                            # An unexpected idle state means the stream was
                            # interrupted, not that the track ended. Reopen a
                            # fresh short-lived URL at the saved position.
                            self._play_current(resume_position=position, start_paused=not should_play)
                    continue

                paused = bool(self._mpv_command(["get_property", "pause"], False))
                position = int(float(self._mpv_command(["get_property", "time-pos"], False) or 0))
                duration = int(float(self._mpv_command(["get_property", "duration"], False) or 0))
                volume = int(float(self._mpv_command(["get_property", "volume"], False) or self.volume))
                muted = bool(self._mpv_command(["get_property", "mute"], False))
                with self.lock:
                    self.active_ticks += 1
                    self.had_file = self.active_ticks >= 2 and position >= 3
                    self.volume = volume; self.muted = muted
                    self.state.update(playing=not paused, position=position, duration=duration,
                                      volume=volume, muted=muted)
                self._publish_mpris(); self._save_state()
            except Exception: pass

    def status(self, include_queue: bool = False) -> dict[str, Any]:
        with self.lock:
            data = dict(self.state); data["playlists"] = list(self.playlists)
            data["searchResults"] = [{**self._metadata(t), "index": i} for i,t in enumerate(self.search_results)]
            data["queueIndex"] = self.index + 1 if self.index >= 0 else 0; data["queueCount"] = len(self.queue)
            if include_queue:
                rows = []
                for i, track in enumerate(self.queue):
                    meta = self._metadata(track)
                    rows.append({**meta, "index": i,
                                 "duration": int(getattr(track, "duration_ms", 0) or 0) // 1000,
                                 "current": i == self.index})
                data["queueTracks"] = rows
            return data

    def handle(self, req: dict[str, Any]) -> dict[str, Any]:
        cmd = req.get("command", "status")
        if cmd == "status": return self.status()
        if cmd == "details": return self.status(include_queue=True)
        if cmd == "auth": self.authenticate()
        elif cmd == "logout": self.logout()
        elif cmd == "likes": self.play_likes()
        elif cmd == "wave": self.play_wave()
        elif cmd == "like": self.toggle_like()
        elif cmd == "playlist": self.play_playlist(str(req.get("kind", "")))
        elif cmd == "search": self.search(str(req.get("query", "")))
        elif cmd == "play_search": self.play_search(int(req.get("index", -1)))
        elif cmd == "play_queue": self.play_queue(int(req.get("index", -1)))
        elif cmd == "artist": self.play_artist(str(req.get("artistId", "")))
        elif cmd == "pause": self.pause()
        elif cmd == "next": self.next()
        elif cmd == "previous": self.previous()
        elif cmd == "seek": self.seek(int(req.get("value", 0)))
        elif cmd == "volume": self.set_volume(int(req.get("value", self.volume)))
        elif cmd == "mute": self.toggle_mute()
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

#!/usr/bin/env python3
"""Synthetic account only. Every CLI call updates one locked, isolated state file."""
import copy
import fcntl
import json
import os
from pathlib import Path
import sys

STATE = Path(os.environ["NAV_STATE"])
ART_URL = STATE.parent.joinpath("cover.svg").as_uri()
ARTIST = {"id": "ccr", "name": "Creedence Clearwater Revival", "artUrl": ART_URL}


def track(index):
    titles = ["Have You Ever Seen The Rain", "Fortunate Son", "Bad Moon Rising", "Down On The Corner", "Proud Mary"]
    return {"index": index, "trackId": f"track-{index}", "id": f"track-{index}",
            "albumId": "pendulum", "title": titles[index % 5] + (f" · {index + 1}" if index > 4 else ""),
            "artist": ARTIST["name"], "artists": [ARTIST], "album": "Pendulum",
            "duration": 160 + index, "artUrl": ART_URL, "liked": True, "entityType": "track"}


def section(items, more=False):
    return {"items": items, "total": 78 if more else len(items), "hasMore": more, "page": 0}


def home():
    return {"view": "home", "section": "", "homeLoaded": True, "loading": False,
            "items": [{"entityType": "personal", "personalId": key, "title": title,
                       "ready": True, "trackCount": 50, "count": 50, "artUrl": ""}
                      for key, title in [("daily", "Плейлист дня"), ("missedLikes", "Тайник"),
                                         ("recentTracks", "Премьера"), ("neverHeard", "Дежавю"),
                                         ("podcasts", "Подкасты недели")]], "revision": 1}


def entity(kind, ident):
    return {"type": kind, "id": ident, "name": ARTIST["name"],
            "title": ARTIST["name"] if kind == "artist" else "Pendulum", "loading": False, "artUrl": ART_URL,
            "description": "Американская рок-группа · 1967–1972", "tracks": [track(i) for i in range(20)],
            "albums": [{"id": f"album-{i}", "title": title, "year": 1969 + i,
                        "artists": [ARTIST], "artUrl": ART_URL} for i, title in enumerate(
                            ["Green River", "Willy And The Poor Boys", "Cosmo’s Factory", "Pendulum"])],
            "singles": [{"id": "single-1", "title": "Travelin’ Band", "artists": [ARTIST]}],
            "similar": [{"id": "doors", "name": "The Doors"}], "releaseHasMore": {"albums": False, "singles": False}}


def initial():
    return {"authenticated": True, "version": "0.11.0", "title": track(0)["title"],
            "artist": ARTIST["name"], "artists": [ARTIST], "artistId": "ccr", "albumId": "pendulum",
            "album": "Pendulum", "artUrl": ART_URL, "trackId": "track-0", "playing": False, "position": 42,
            "duration": 160, "volume": 65, "liked": True, "loading": False, "error": "",
            "preferences": {"popupLayout": os.environ.get("NAV_LAYOUT", "wide"), "playbackMode": "order"},
            "queueName": "Мне нравится", "queueSourceName": "Мне нравится", "queueSourceKind": "likes",
            "queueSourceArg": "", "queueIndex": 1, "queueTotal": 78, "queueRevision": 1,
            "queueTracks": [track(i) for i in range(50)], "likesTotal": 78,
            "playlists": [{"kind": "7", "title": "В дороге", "count": 24, "artUrl": ""}],
            "libraryRevision": 1, "libraryTracks": [], "libraryBrowseKind": "", "libraryBrowseArg": "",
            "libraryHubRevision": 1, "libraryHub": home(), "catalogRevision": 1,
            "catalog": {"view": "search", "entity": {}, "suggestions": {},
                        "search": {"fieldText": "", "query": "", "filter": "all", "page": 0,
                                   "sections": {k: section([]) for k in ("tracks", "artists", "albums", "playlists")}}},
            "collectionRevision": 1, "collection": {}, "testPlaybackCount": 0, "testStaleReads": 0}


def bump(state, name):
    state[name] = state.get(name, 0) + 1


def execute(state, command, args):
    if command in ("status", "details"):
        result = copy.deepcopy(state)
        if command == "details" and state.get("testStaleKind"):
            bump(state, "testStaleReads")
            result["testStaleReads"] = state["testStaleReads"]
            if state["testStaleKind"] == "entity":
                result["catalog"] = copy.deepcopy(state["catalog"])
                result["catalog"].update(view="artist", entity=entity("artist", "wrong-stale-id"))
                result["catalog"]["entity"]["title"] = "STALE ENTITY MUST NOT APPEAR"
                result["catalogRevision"] += 1000
            else:
                result.update(libraryBrowseKind="playlist", libraryBrowseArg="wrong-stale-id",
                              libraryTracks=[dict(track(0), title="STALE COLLECTION MUST NOT APPEAR")],
                              libraryRevision=state["libraryRevision"] + 1000)
        return result
    if command == "test_stale":
        state["testStaleKind"] = args[0] if args else ""
    elif command == "catalog_suggest":
        return {"query": args[1], "generation": int(args[0]), "items": []}
    elif command == "catalog_clear_suggestions":
        state["catalog"]["search"]["fieldText"] = args[0] if args else ""
        state["catalog"]["suggestions"] = {}
        bump(state, "catalogRevision")
    elif command in ("library_home", "library_home_refresh", "library_back"):
        state["libraryHub"] = home()
        bump(state, "libraryHubRevision")
        state["libraryHub"]["revision"] = state["libraryHubRevision"]
    elif command == "library_section":
        state["libraryHub"] = {"view": "section", "section": args[0], "loading": False,
                               "items": [track(i) for i in range(50)] if args[0] == "history" else [],
                               "hasMore": False, "total": 50, "revision": state["libraryHubRevision"] + 1}
        bump(state, "libraryHubRevision")
    elif command in ("likes", "playlist", "browse_personal"):
        key = command + ":" + (args[0] if args else "")
        loaded = state.setdefault("_browsePages", {}).get(key, 50)
        state.update(libraryBrowseKind=command, libraryBrowseArg=args[0] if args else "",
                     libraryBrowseName="Мне нравится" if command == "likes" else "В дороге",
                     libraryTracks=[track(i) for i in range(loaded)], libraryTotal=78,
                     libraryHasMore=loaded < 78, libraryLoading=False, libraryLoadingMore=False,
                     libraryError="", libraryDuration=17040, libraryEditable=command == "playlist",
                     libraryPlaylistKind=args[0] if args else "")
        bump(state, "libraryRevision")
    elif command == "load_more_library":
        key = state["libraryBrowseKind"] + ":" + state["libraryBrowseArg"]
        state.setdefault("_browsePages", {})[key] = 78
        state.update(libraryTracks=[track(i) for i in range(78)], libraryHasMore=False)
        bump(state, "libraryRevision")
    elif command == "catalog_search":
        filt, query = args[0], args[1]
        state["catalog"]["view"] = "search"
        state["catalog"]["search"] = {"fieldText": query, "query": query, "filter": filt, "page": 0,
            "loading": False, "sections": {"tracks": section([track(i) for i in range(40)], True),
                "artists": section([ARTIST]), "albums": section(entity("artist", "ccr")["albums"]), "playlists": section([])}}
        bump(state, "catalogRevision")
    elif command == "catalog_load_more":
        state["catalog"]["search"]["sections"]["tracks"] = section([track(i) for i in range(78)])
        state["catalog"]["search"]["page"] += 1
        bump(state, "catalogRevision")
    elif command in ("catalog_artist", "catalog_album", "catalog_playlist"):
        kind = command.removeprefix("catalog_")
        state["catalog"].update(view=kind, entity=entity(kind, args[0]))
        bump(state, "catalogRevision")
    elif command == "catalog_back":
        state["catalog"]["view"] = "search"
        bump(state, "catalogRevision")
    elif command == "playlist_memberships":
        state["collection"] = {"membershipTrackId": args[2], "membershipAlbumId": args[3],
                               "memberships": {"7": False}, "loading": False}
        bump(state, "collectionRevision")
    elif command == "collection_clear":
        state["collection"] = {}
        bump(state, "collectionRevision")
    elif command == "setting":
        state["preferences"][args[0]] = args[1]
    elif command.startswith("play_") or command in ("wave", "pause", "next", "previous", "stop"):
        bump(state, "testPlaybackCount")
        if command == "play_library_track":
            selected = state["libraryTracks"][int(args[0])]
            state.update(title=selected["title"], trackId=selected["trackId"], playing=True)
    elif command not in ("network", "lyrics", "track_info"):
        raise ValueError(f"Unsupported synthetic CLI command: {command}")
    return copy.deepcopy(state)


STATE.parent.mkdir(parents=True, exist_ok=True)
ART_FILE = STATE.parent / "cover.svg"
with STATE.with_suffix(".lock").open("w") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    if not ART_FILE.exists():
        ART_FILE.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="320" height="320">'
                           '<defs><linearGradient id="g" x2="1" y2="1">'
                           '<stop stop-color="#A99BD6"/><stop offset="1" stop-color="#364266"/>'
                           '</linearGradient></defs><rect width="320" height="320" fill="url(#g)"/>'
                           '<circle cx="160" cy="160" r="92" fill="#16161f" opacity=".6"/>'
                           '<circle cx="160" cy="160" r="28" fill="#DCDCE6"/></svg>', encoding="utf-8")
    state = json.loads(STATE.read_text()) if STATE.exists() else initial()
    command, *args = sys.argv[1:]
    result = execute(state, command, args)
    STATE.write_text(json.dumps(state, ensure_ascii=False))
    with STATE.with_suffix(".commands").open("a") as log:
        log.write(json.dumps([command, *args], ensure_ascii=False) + "\n")
print(json.dumps(result, ensure_ascii=False))

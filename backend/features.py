"""On-demand catalogue additions. Models stay in memory; writes are never retried."""
from __future__ import annotations

import copy
import json
import threading
import time
from collections import OrderedDict
from yandex_music import Pin
from yandex_music.utils.difference import Difference

PAGE = 50


class Cancelled(Exception):
    pass


class Features:
    def __init__(self, player):
        self.p = player
        self.generation = 0
        self.revision = 0
        self.client = None
        self.work_lock = threading.Lock()
        self.busy = False
        self.spec = {}
        self.snapshot = {}
        self.pending_spec = None
        self.models = []
        self.source = []
        self.rows = []
        self.track_mode = False
        self.visible_count = PAGE
        self.entity = None
        self.cache = OrderedDict()
        self.cache_snapshot = False

    def clear(self):
        with self.p.lock:
            self.generation += 1
            self.client = None
            self.snapshot = {}
            self.cache.clear()
            self.cache_snapshot = False
            self.pending_spec = None
            self.models = []; self.source = []; self.rows = []; self.entity = None
            self.revision += 1

    def current(self, client, generation):
        return self.p.client is client and self.client is client and self.generation == generation

    def call(self, client, generation, fn, write=False):
        def guarded():
            with self.p.lock:
                if not self.current(client, generation): raise Cancelled()
            return fn()
        result = self.p._api_call(guarded, update_loading=False, retry_rate_limit=not write)
        with self.p.lock:
            if not self.current(client, generation): raise Cancelled()
        return result

    def publish(self, client, generation, **fields):
        with self.p.lock:
            if not self.current(client, generation): return
            self.snapshot.update(fields)
            self.revision += 1
            self.snapshot['revision'] = self.revision

    def open(self, spec, *, confirmed_pins=None):
        if not isinstance(spec, dict): raise ValueError('Некорректный запрос')
        force = spec.get('force') is True and isinstance(spec.get('request'), dict)
        if isinstance(spec.get('request'), dict): spec = dict(spec['request'])
        identity = json.dumps(spec, sort_keys=True, ensure_ascii=False, separators=(',', ':'))
        view = str(spec.get('view', 'overview'))
        if view not in ('overview', 'chart', 'releases', 'genres', 'genre', 'similar', 'podcasts',
                        'pins', 'blocked', 'wave', 'streams', 'entity', 'quality'):
            raise ValueError('Неизвестный раздел')
        with self.p.lock:
            if self.busy:
                self.pending_spec = {'request': dict(spec), 'force': force}; return
            client = self.p.client
            refreshing_pins = (view == 'pins' and client is not None and client is self.client
                               and identity == self.snapshot.get('identity'))
            previous_rows = self.snapshot['rows'] if refreshing_pins else []
            if client is not self.client:
                self.cache.clear()
            elif self.cache_snapshot and not self.snapshot.get('loading') and not self.snapshot.get('error'):
                self.cache[self.snapshot['identity']] = (time.monotonic(), dict(self.spec), copy.deepcopy(self.snapshot), list(self.models), list(self.source), list(self.rows), self.track_mode, self.visible_count)
                self.cache.move_to_end(self.snapshot['identity'])
                while len(self.cache) > 8: self.cache.popitem(last=False)
            self.client = client
            self.generation += 1; generation = self.generation
            self.spec = dict(spec)
            self.cache_snapshot = view not in ('pins', 'wave')
            self.models = []; self.source = []; self.entity = None
            if not refreshing_pins:
                self.rows = []
            self.track_mode = False; self.visible_count = PAGE
            cached = self.cache.get(identity)
            if client and self.cache_snapshot and not force and cached and time.monotonic() - cached[0] < 600:
                _, self.spec, self.snapshot, self.models, self.source, self.rows, self.track_mode, self.visible_count = cached
                self.snapshot = copy.deepcopy(self.snapshot)
                self.publish(client, generation, loading=False, busy=False)
                return
            self.snapshot = {'identity': identity,
                             'view': view, 'title': spec.get('title', ''), 'loading': bool(client),
                             'error': '' if client else 'Войдите в Яндекс Музыку', 'message': '',
                             'rows': previous_rows, 'hasMore': False, 'busy': False}
            self.revision += 1
            self.snapshot['revision'] = self.revision
        if not client: return
        def load():
            try:
                with self.work_lock:
                    if not self.current(client, generation): return
                    if confirmed_pins is None:
                        self.load(client, generation, spec)
                    else:
                        self.show(client, generation, confirmed_pins, 'Закреплённое')
                self.publish(client, generation, loading=False)
            except Cancelled: pass
            except Exception as exc:
                self.publish(client, generation, loading=False,
                             error=self.p._catalog_error(exc, 'Раздел'))
        threading.Thread(target=load, daemon=True).start()

    def row(self, model, type_):
        p = self.p
        if type_ == 'track':
            result = p._metadata(model)
            result.update(entityType='track', duration=p._int(getattr(model, 'duration_ms', 0)) // 1000)
        elif type_ == 'artist': result = p._artist_metadata(model)
        elif type_ == 'album': result = p._album_metadata(model)
        else: result = p._playlist_metadata(model)
        result['title'] = result.get('title') or result.get('name') or 'Без названия'
        result['subtitle'] = result.get('artist') or result.get('ownerName') or ''
        return result

    def show(self, client, generation, rows, title='', **fields):
        with self.p.lock:
            if not self.current(client, generation): raise Cancelled()
            self.rows = rows[:2000]
            shown = copy.deepcopy(self.rows[:self.visible_count])
            for i, r in enumerate(shown): r['index'] = i
            self.publish(client, generation, rows=shown, title=title or self.snapshot.get('title', ''),
                         hasMore=fields.pop('hasMore', len(self.rows) > self.visible_count), **fields)

    def tracks(self, client, generation, source, title):
        source = list(source)
        tracks = self.p._tracks_from_short_page(source[:PAGE], client, update_loading=False)
        with self.p.lock:
            if not self.current(client, generation): raise Cancelled()
            self.source = source; self.models = tracks; self.track_mode = True
        self.show(client, generation, [self.row(t, 'track') for t in tracks], title,
                  hasMore=len(source) > len(tracks))

    @staticmethod
    def action_row(title, action, subtitle=''):
        return {'title': title, 'subtitle': subtitle, 'entityType': 'action', 'action': action}

    def playlist_rows(self, source, models):
        by_id = {self.p._playlist_track_ref(t): t for t in models}
        rows = []
        for ref in source:
            model = by_id.get(self.p._playlist_track_ref(ref))
            rows.append(self.row(model, 'track') if model else {'title':'Недоступный трек', 'entityType':'unavailable', 'available':False})
        return rows

    def station_row(self, station):
        sid = getattr(station, 'id', None)
        value = ':'.join(str(v) for v in (getattr(sid, 'type', ''), getattr(sid, 'tag', '')))
        return self.action_row(getattr(station, 'name', '') or 'Радиостанция',
                               {'op': 'station', 'station': value}, 'Включить станцию')

    @staticmethod
    def wave_pin_seeds(value):
        seeds = value.split(',') if isinstance(value, str) else value
        if isinstance(seeds, list) and 0 < len(seeds) <= 10 and all(
                isinstance(seed, str) and ':' in seed and ',' not in seed
                and all(seed.split(':', 1)) for seed in seeds):
            return seeds
        return []

    def wave_pinned(self, seeds, rows=None):
        waves = [row for row in (self.rows if rows is None else rows) if row.get('entityType') == 'action']
        if any(row.get('action', {}).get('seeds') == seeds for row in waves):
            return True
        if any(row.get('available') is False for row in waves):
            return None
        return False

    def pin_rows(self, c, g, include_wave=False):
        result = self.call(c, g, c.pins)
        if result is None:
            raise ValueError('Не удалось загрузить закрепления')
        pins = [(pin, []) for pin in getattr(result, 'pins', None) or []]
        if include_wave and any(str(pin.type).removesuffix('_item') == 'wave' for pin, _ in pins):
            # PinData in the pinned SDK omits seeds. Use the raw list when
            # available so each context stays paired with its own metadata.
            try:
                raw = self.call(c, g, lambda: c.request.get(c.base_url + '/pins'))
                if isinstance(raw, dict) and isinstance(raw.get('pins'), list):
                    pins = [(Pin.de_json(pin, None), self.wave_pin_seeds((pin.get('data') or {}).get('seeds')))
                            for pin in raw['pins'] if isinstance(pin, dict)]
            except Cancelled:
                raise
            except Exception:
                pass
        rows = []
        labels = {'album': 'Альбом', 'artist': 'Исполнитель', 'playlist': 'Плейлист', 'wave': 'Волна'}
        for pin, seeds in pins:
            if not pin or not pin.data:
                continue
            data = pin.data
            type_ = str(pin.type).removesuffix('_item')
            if type_ not in labels:
                continue
            id_, owner, kind = (self.p._text(getattr(data, field, None)) for field in ('id', 'uid', 'kind'))
            row = {'entityType': type_, 'title': getattr(data, 'title', None) or getattr(data, 'name', None) or labels[type_],
                   'subtitle': labels[type_], 'id': id_, 'owner': owner, 'kind': kind,
                   'uuid': self.p._text(getattr(data, 'playlist_uuid', None)), 'artUrl': self.p._cover_url(data)}
            if type_ == 'wave':
                if not include_wave:
                    continue
                seeds = seeds or self.wave_pin_seeds(id_)
                row.update(entityType='action', available=bool(seeds))
                if seeds:
                    row.update(action={'op': 'wave', 'seeds': seeds},
                               trailing={'op': 'pinWave', 'seeds': seeds, 'value': False, 'title': 'Открепить'})
                else:
                    row['subtitle'] = 'Волна · контекст недоступен'
            else:
                args = [owner, kind] if type_ == 'playlist' else [id_]
                if all(args):
                    row['trailing'] = {'op': 'unpin', 'type': type_, 'args': args, 'title': 'Открепить'}
                else:
                    row['available'] = False
            rows.append(row)
        return rows

    def load(self, c, g, s):
        call = lambda fn: self.call(c, g, fn)
        view = s.get('view', 'overview')
        if view == 'overview':
            self.show(c, g, [self.action_row(title, {'view': v}) for v, title in
                            [('chart', 'Чарт'), ('releases', 'Новые релизы'), ('genres', 'Жанры')]], 'Обзор')
        elif view == 'chart':
            result = call(c.chart)
            self.tracks(c, g, getattr(getattr(result, 'chart', None), 'tracks', None) or [], 'Чарт')
        elif view == 'releases':
            result = call(lambda: c.landing('new-releases'))
            rows = [self.row(e.data, 'album') for b in (getattr(result, 'blocks', None) or [])
                    for e in (getattr(b, 'entities', None) or []) if getattr(e, 'type', '') == 'album']
            self.show(c, g, rows, 'Новые релизы')
        elif view == 'genres':
            rows = []
            for genre in call(c.genres) or []:
                for item in [genre] + list(getattr(genre, 'sub_genres', None) or []):
                    rows.append(self.action_row(item.title, {'view': 'genre', 'id': str(item.id), 'title': item.title}))
            self.show(c, g, rows, 'Жанры')
        elif view == 'genre':
            # The SDK exposes genre radio, not a paginated genre-album endpoint.
            stations = call(lambda: c.rotor_station_info('genre:' + str(s.get('id', '')))) or []
            self.show(c, g, [self.station_row(x.station) for x in stations if getattr(x, 'station', None)], s.get('title', 'Жанр'))
        elif view == 'similar':
            type_, id_ = s.get('type'), str(s.get('id', ''))
            if type_ == 'track':
                result = call(lambda: c.tracks_similar(id_))
                self.tracks(c, g, getattr(result, 'similar_tracks', None) or [], 'Похожие треки')
            else:
                result = call(lambda: c.albums_similar_entities(id_)) if type_ == 'album' else call(
                    lambda: c.playlist_similar_entities(str(s.get('uuid', ''))))
                rows = []
                for item in getattr(result, 'items', None) or []:
                    wave = getattr(getattr(item, 'data', None), 'wave', None)
                    if wave and getattr(wave, 'seeds', None):
                        seeds = list(wave.seeds)
                        first = str(seeds[0]).split(':')
                        row = self.action_row(wave.name or 'Похожая музыка',
                            {'op': 'wave', 'seeds': seeds}, wave.description or 'Включить подборку')
                        if len(seeds) == 1 and len(first) == 2 and first[0] in ('album', 'artist'):
                            row.update(entityType=first[0], id=first[1], artUrl=self.p._cover_url(getattr(getattr(item, 'data', None), 'agent', None)))
                            row.pop('action')
                        elif len(seeds) == 1 and first[0] == 'playlist' and len(first) in (2, 3):
                            row.update(entityType='playlist', uuid=first[1] if len(first) == 2 else '', owner=first[1] if len(first) == 3 else '', kind=first[2] if len(first) == 3 else '')
                            row.pop('action')
                        rows.append(row)
                self.show(c, g, rows, 'Похожая музыка')
        elif view == 'podcasts':
            query = str(s.get('query', '')).strip()
            if not query:
                self.show(c, g, [], 'Подкасты', message='Найдите шоу или выпуск'); return
            type_ = 'podcast_episode' if s.get('episodes') else 'podcast'
            page = max(0, min(100, int(s.get('page', 0))))
            result = call(lambda: c.search(query, type_=type_, page=page))
            section = getattr(result, 'podcast_episodes' if s.get('episodes') else 'podcasts', None)
            models = list(getattr(section, 'results', None) or [])
            if s.get('episodes'):
                self.models = models; self.track_mode = True
            self.show(c, g, [self.row(t, 'track' if s.get('episodes') else 'album') for t in models], 'Подкасты',
                      hasMore=(page + 1) * int(getattr(section, 'per_page', None) or len(models) or 20) < int(getattr(section, 'total', 0) or 0))
        elif view == 'pins':
            self.show(c, g, self.pin_rows(c, g, include_wave=True), 'Закреплённое')
        elif view == 'blocked':
            models = call(c.users_dislikes_artists) or []
            self.show(c, g, [dict(self.row(getattr(a, 'artist', None) or a, 'artist'),
                                trailing={'op': 'block', 'type': 'artist', 'id': str(getattr(a, 'id', '')), 'value': False})
                            for a in models], 'Не рекомендовать')
        elif view == 'streams':
            self.show(c, g, [self.action_row(title, {'op': 'stream', 'station': 'generative:' + id_, 'title': title},
                                               'Заменить текущую музыку') for id_, title in
                            [('focus', 'Фокус'), ('energy', 'Энергия'), ('calm', 'Спокойствие'), ('relax', 'Отдых')]], 'Музыка для занятий')
        elif view == 'wave':
            result = call(lambda: c.rotor_wave_settings(['user:onyourwave']))
            rows = []
            last = call(c.rotor_wave_last)
            if last and getattr(last, 'seeds', None):
                rows.append(self.action_row('Продолжить: ' + (last.name or 'Последняя волна'), {'op': 'wave', 'seeds': last.seeds}))
            rows.append(self.action_row('Моя волна', {'op': 'wave', 'seeds': ['user:onyourwave']}))
            for block in getattr(result, 'blocks', None) or []:
                for station in getattr(block, 'items', None) or []: rows.append(self.station_row(station))
            dashboard = call(c.rotor_stations_dashboard)
            for station in getattr(dashboard, 'stations', None) or []:
                if getattr(station, 'station', None): rows.append(self.station_row(station.station))
            try:
                pinned = {tuple(row['action']['seeds']) for row in self.pin_rows(c, g, include_wave=True)
                          if row.get('action')}
            except Cancelled:
                raise
            except Exception:
                self.show(c, g, rows, 'Занятия и станции Волны', warning='Не удалось проверить закрепления. Обновите список.')
                return
            for row in rows:
                action = row['action']
                seeds = self.wave_pin_seeds(action.get('seeds') or [action.get('station')])
                if seeds:
                    value = tuple(seeds) not in pinned
                    row['trailing'] = {'op': 'pinWave', 'seeds': seeds, 'value': value,
                                       'title': 'Закрепить' if value else 'Открепить'}
            self.show(c, g, rows, 'Занятия и станции Волны')
        elif view == 'entity': self.load_entity(c, g, s)
        elif view == 'quality':
            self.show(c, g, [], 'Качество аудио', message='Желаемое качество применяется к следующему запуску трека.')

    def load_entity(self, c, g, s):
        type_, id_ = s.get('type'), str(s.get('id', ''))
        call = lambda fn: self.call(c, g, fn)
        if type_ not in ('album', 'artist', 'playlist'): raise ValueError('Неизвестный тип')
        fields = {'entityType': type_, 'id': id_, 'owner': s.get('owner', ''), 'kind': s.get('kind', ''), 'uuid': s.get('uuid', ''),
                  'favoriteKnown': False, 'pinnedKnown': False, 'editable': False}
        rows = []
        if type_ == 'playlist':
            pl = call(lambda: c.users_playlists(s.get('kind', id_), user_id=s.get('owner') or None))
            if not pl: raise ValueError('Плейлист недоступен')
            self.entity = pl
            fields.update(self.row(pl, 'playlist'), editable=self.p._playlist_is_mine(c, pl),
                          description=getattr(pl, 'description', '') or '', visibility=getattr(pl, 'visibility', '') or 'private',
                          playlistRevision=self.p._playlist_revision(pl))
            self.source = list(getattr(pl, 'tracks', None) or [])
            if fields['editable'] and not s.get('actionsOnly'):
                limit = max(PAGE, self.visible_count)
                models = self.p._tracks_from_short_page(self.source[:limit], c, update_loading=False)
                rows = self.playlist_rows(self.source[:limit], models)
                self.models = models
        try:
            likes = call(getattr(c, 'users_likes_' + {'album': 'albums', 'artist': 'artists', 'playlist': 'playlists'}[type_])) or []
            def match(value):
                value = getattr(value, type_, None) or value
                if type_ == 'playlist':
                    m = self.p._playlist_metadata(value)
                    return m.get('owner') == fields.get('owner') and m.get('kind') == fields.get('kind')
                return str(getattr(value, 'id', '')) == id_
            fields.update(favoriteKnown=True, favorite=any(match(x) for x in likes))
        except Cancelled: raise
        except Exception: fields['statusWarning'] = 'Не удалось проверить избранное'
        try:
            args = [fields['owner'], fields['kind']] if type_ == 'playlist' else [id_]
            if all(args):
                fields.update(pinnedKnown=True, pinned=any(
                    pin.get('trailing', {}).get('type') == type_
                    and pin['trailing']['args'] == args for pin in self.pin_rows(c, g)))
        except Cancelled: raise
        except Exception: fields['statusWarning'] = 'Не удалось проверить закрепления'
        if type_ == 'artist':
            try:
                values = call(c.users_dislikes_artists) or []
                fields.update(blockKnown=True, blocked=any(str(getattr(x, 'id', '')) == id_ for x in values))
            except Cancelled: raise
            except Exception: fields['blockKnown'] = False
        self.show(c, g, rows, s.get('title') or fields.get('title') or 'Действия', entity=fields,
                  hasMore=fields['editable'] and not s.get('actionsOnly') and len(self.source) > self.visible_count)

    def more(self):
        with self.p.lock:
            if self.snapshot.get('loading') or self.busy: return
            spec = dict(self.spec)
            if spec.get('view') == 'podcasts':
                # Search has server pages; retain accumulated results below.
                previous_rows, previous_models = list(self.rows), list(self.models)
                spec['page'] = int(spec.get('page', 0)) + 1
            else: previous_rows = previous_models = None
            c, g = self.client, self.generation
            self.publish(c, g, loading=True, error='')
        def load():
            with self.work_lock:
                if not self.current(c, g): return
                load_serial()
        def load_serial():
            try:
                if previous_rows is not None:
                    self.load(c, g, spec)
                    with self.p.lock:
                        if not self.current(c, g): return
                        self.spec = spec
                        self.models = list({self.p._track_id(t): t for t in reversed(previous_models + self.models)}.values())[::-1]
                        more = self.snapshot['hasMore']
                        self.visible_count += PAGE
                        if spec.get('episodes'):
                            rows = [self.row(t, 'track') for t in self.models]
                        else:
                            rows = []
                            seen = set()
                            for row in previous_rows + self.rows:
                                key = (row.get('entityType'), row.get('id'))
                                if key not in seen: rows.append(row); seen.add(key)
                        self.show(c, g, rows, hasMore=more)
                elif self.source and (self.track_mode or self.snapshot.get('entity', {}).get('editable')):
                    start = self.visible_count
                    extra = self.p._tracks_from_short_page(self.source[start:start + PAGE], c, update_loading=False)
                    with self.p.lock:
                        if not self.current(c, g): return
                        self.models += extra; self.visible_count += PAGE
                        count = self.visible_count
                        rows = self.playlist_rows(self.source[:count], self.models) if self.snapshot.get('entity', {}).get('editable') else [self.row(t, 'track') for t in self.models]
                        self.show(c, g, rows, hasMore=count < len(self.source))
                else:
                    self.visible_count += PAGE
                    self.show(c, g, self.rows)
                self.publish(c, g, loading=False)
            except Cancelled: pass
            except Exception as exc: self.publish(c, g, loading=False, error=self.p._catalog_error(exc, 'Следующая страница'))
        threading.Thread(target=load, daemon=True).start()

    def action(self, request):
        if not isinstance(request, dict): raise ValueError('Некорректное действие')
        if request.get('identity') != self.snapshot.get('identity'): return False
        if request.get('op') == 'more': self.more(); return True
        with self.p.lock:
            if self.busy or self.snapshot.get('loading') or self.client is not self.p.client: return False
            c, g = self.client, self.generation
            if not c: return False
            if request.get('identity') != self.snapshot.get('identity'): return False
            self.busy = True
            self.publish(c, g, busy=True, error='', message='')
            entity = copy.deepcopy(self.snapshot.get('entity', {}))
        def run():
            try:
                with self.work_lock:
                    self.mutate(c, g, request, entity)
                with self.p.lock:
                    if self.current(c, g):
                        self.p.catalog_cache.clear(); self.p.library_hub_cache.clear(); self.p.collection_cache.clear()
                        self.cache.clear()
                        for name in ('features', 'entity_features'):
                            manager = getattr(self.p, name, None)
                            if manager is not None: manager.cache.clear()
                self.publish(c, g, message='Готово')
            except Cancelled: pass
            except Exception as exc:
                message = 'Не удалось выполнить действие. Проверьте состояние перед повтором.'
                if self.p._revision_conflict(exc): message = 'Плейлист изменился. Обновите его и подтвердите действие снова.'
                if self.p._is_rate_limit_error(exc): message = self.p._catalog_error(exc, 'Действие')
                if isinstance(exc, ValueError): message = str(exc)
                self.publish(c, g, error=message)
            finally:
                with self.p.lock:
                    self.publish(c, g, busy=False)
                    self.busy = False
                    pending, self.pending_spec = self.pending_spec, None
                    if pending is not None: self.open(pending)
        threading.Thread(target=run, daemon=True).start()
        return True

    def write_pin(self, c, g, type_, args, value, expected_wave=None):
        def write():
            if expected_wave is not None:
                with self.p.lock:
                    if self.p.current_wave_seeds() != expected_wave:
                        raise ValueError('Текущая Волна сменилась. Обновите закрепление.')
            if type_ == 'wave':
                # SDK 3.2.2 sends a string; this endpoint accepts a JSON array.
                send = c.request.put if value else c.request.delete
                result = send(c.base_url + '/pin/wave', json={'seeds': args})
                return result if value else result == 'ok'
            return getattr(c, ('pin_' if value else 'unpin_') + type_)(*args)
        try:
            result = self.call(c, g, write, write=True)
            if not result and type_ != 'wave':
                raise ValueError('Сервис не подтвердил закрепление')
            return bool(result)
        finally:
            # Even a lost response can mean the server applied the write.
            with self.p.lock:
                if self.p.client is c:
                    for name in ('features', 'entity_features'):
                        manager = getattr(self.p, name, None)
                        if manager is not None:
                            manager.cache.clear()
                            manager.cache_snapshot = False
                    rail = getattr(self.p, 'rail_pins', None)
                    if type_ != 'wave' and rail is not None and rail is not self and rail.client is c:
                        rail.open({'view': 'pins'})

    def confirm_wave_pin(self, c, g, seeds, value, acknowledged):
        for delay in (0, .35, .75):
            if delay:
                time.sleep(delay)
            rows = self.pin_rows(c, g, include_wave=True)
            visible = self.wave_pinned(seeds, rows)
            if visible is value or (not value and visible is None and acknowledged):
                rail = getattr(self.p, 'rail_pins', None)
                with self.p.lock:
                    if rail is not None and rail is not self and rail.client is c and self.current(c, g):
                        rail.open({'view': 'pins'}, confirmed_pins=rows)
                return rows
        raise ValueError('Яндекс пока не подтвердил изменение в списке закреплений.')

    def mutate(self, c, g, r, e):
        call = lambda fn: self.call(c, g, fn, write=True)
        op = r.get('op')
        if op == 'currentWavePin':
            seeds, value = r.get('seeds'), r.get('value')
            if self.spec.get('view') != 'pins' or not isinstance(seeds, list) or not self.wave_pin_seeds(seeds) or type(value) is not bool:
                raise ValueError('Обновите закрепление текущей Волны')
            pinned = self.wave_pinned(seeds)
            if pinned is None:
                raise ValueError('Статус закрепления Волны неизвестен')
            if pinned != value:
                acknowledged = self.write_pin(c, g, 'wave', seeds, value, expected_wave=seeds)
                self.show(c, g, self.confirm_wave_pin(c, g, seeds, value, acknowledged), 'Закреплённое')
        elif op == 'unpin':
            if self.spec.get('view') != 'pins':
                raise ValueError('Откройте список закреплений')
            target = next((row['trailing'] for row in self.rows if 'trailing' in row
                           and all(row['trailing'].get(key) == r.get(key) for key in ('op', 'type', 'args'))), None)
            if not target:
                raise ValueError('Закрепление изменилось. Обновите список.')
            self.write_pin(c, g, target['type'], target['args'], False)
            self.show(c, g, [row for row in self.rows if row.get('trailing') != target])
        elif op == 'pinWave':
            seeds = r.get('seeds')
            value = r.get('value')
            if not self.wave_pin_seeds(seeds) or type(value) is not bool or not any(
                    row.get('trailing', {}).get('seeds') == seeds and row['trailing']['value'] is value
                    for row in self.rows):
                raise ValueError('Контекст изменился. Обновите список.')
            acknowledged = self.write_pin(c, g, 'wave', seeds, value)
            confirmed = self.confirm_wave_pin(c, g, seeds, value, acknowledged)
            if self.spec.get('view') == 'pins':
                self.show(c, g, confirmed)
                return
            rows = copy.deepcopy(self.rows)
            for row in rows:
                if row.get('trailing', {}).get('seeds') == seeds:
                    row['trailing'].update(value=not value, title='Открепить' if value else 'Закрепить')
            self.show(c, g, rows)
        elif op in ('favorite', 'pin', 'block'):
            type_ = e.get('entityType') or r.get('type')
            id_ = str(e.get('id') or r.get('id', ''))
            value = r.get('value') is True
            if type_ not in ('album', 'artist', 'playlist', 'wave'): raise ValueError('Неподдерживаемая сущность')
            if op == 'favorite':
                if not e.get('favoriteKnown'): raise ValueError('Сначала обновите статус избранного')
                arg = str(e.get('owner')) + ':' + str(e.get('kind')) if type_ == 'playlist' else id_
                name = 'users_likes_' + {'album': 'albums', 'artist': 'artists', 'playlist': 'playlists'}[type_] + ('_add' if value else '_remove')
                result = call(lambda: getattr(c, name)(arg)); key = 'favorite'
            elif op == 'pin':
                if not e.get('pinnedKnown'): raise ValueError('Сначала обновите статус закрепления')
                if e.get('pinned') is value: return
                args = (e.get('owner'), e.get('kind')) if type_ == 'playlist' else (id_,)
                self.write_pin(c, g, type_, args, value)
                result = True; key = 'pinned'
            else:
                if type_ != 'artist': raise ValueError('Нужен исполнитель')
                result = call(lambda: getattr(c, 'users_dislikes_artists_' + ('add' if value else 'remove'))(id_)); key = 'blocked'
            if not result: raise ValueError('Сервис не подтвердил изменение')
            if e:
                e[key] = value; self.publish(c, g, entity=e)
            elif op == 'block':
                self.show(c, g, [x for x in self.rows if str(x.get('id')) != id_])
        elif op in ('savePlaylist', 'deletePlaylist', 'move'):
            if not e.get('editable'): raise ValueError('Изменять плейлист может только владелец')
            if r.get('playlistRevision') != e['playlistRevision']: raise ValueError('Плейлист изменился. Обновите состояние перед действием.')
            kind = e['kind']
            fresh = self.call(c, g, lambda: c.users_playlists(kind))
            if not self.p._playlist_is_mine(c, fresh): raise ValueError('Нет прав владельца')
            revision = self.p._playlist_revision(fresh)
            if revision != e['playlistRevision']: raise ValueError('Плейлист изменился. Обновите его перед сохранением.')
            if op == 'deletePlaylist':
                if r.get('confirmed') is not True: raise ValueError('Подтвердите удаление')
                if not call(lambda: c.users_playlists_delete(kind)): raise ValueError('Удаление не подтверждено')
                with self.p.lock:
                    self.p.playlists = [p for p in self.p.playlists if str(p.get('kind')) != str(kind)]
                self.show(c, g, [], 'Плейлист удалён', entity={}); return
            if op == 'savePlaylist':
                title, description = str(r.get('title', '')).strip(), str(r.get('description', ''))
                visibility = r.get('visibility')
                if not title or len(title) > 200 or len(description) > 2000: raise ValueError('Проверьте название и описание')
                if visibility not in ('private', 'public'): raise ValueError('Выберите видимость')
                if visibility == 'public' and e.get('visibility') != 'public' and not r.get('confirmed'):
                    raise ValueError('Подтвердите публикацию плейлиста')
                if title != getattr(fresh, 'title', '') and not call(lambda: c.users_playlists_name(kind, title)): raise ValueError('Сервис не подтвердил название')
                if description != (getattr(fresh, 'description', '') or '') and not call(lambda: c.users_playlists_description(kind, description)): raise ValueError('Сервис не подтвердил описание')
                if visibility != getattr(fresh, 'visibility', 'private') and not call(lambda: c.users_playlists_visibility(kind, visibility)): raise ValueError('Сервис не подтвердил видимость')
            else:
                start, end = int(r.get('from', -1)), int(r.get('to', -1))
                source = list(getattr(fresh, 'tracks', None) or [])
                if not 0 <= start < len(source) or not 0 <= end < len(source): raise ValueError('Неверная позиция трека')
                tid, aid = self.p._playlist_track_ref(source[start])
                if not tid or not aid: raise ValueError('Трек недоступен для перемещения')
                diff = Difference().add_delete(start, start + 1).add_insert(end, {'id': tid, 'album_id': aid})
                if not call(lambda: c.users_playlists_change(kind, diff.to_json(), revision=revision)):
                    raise ValueError('Изменение порядка не подтверждено')
            updated = self.call(c, g, lambda: c.users_playlists(kind))
            self.p._refresh_open_playlist_views(c, updated)
            self.load_entity(c, g, self.spec)
        elif op == 'play':
            index = int(r.get('index', -1))
            if not self.track_mode or not 0 <= index < len(self.models): raise ValueError('Обновите список треков')
            tracks = list(self.models)
            with self.p.control_lock:
                if not self.current(c, g): raise Cancelled()
                self.p._set_queue(tracks, self.snapshot.get('title', 'Подборка'), start_index=index, remaining_rows=self.source[len(tracks):])
        elif op == 'station':
            if self.spec.get('view') == 'wave':
                self.p.play_wave_seeds([str(r.get('station', ''))] + self.p._wave_seeds()[1:])
            else:
                self.p.play_station(str(r.get('station', '')), str(r.get('title', 'Радиостанция')))
        elif op == 'wave':
            seeds = r.get('seeds')
            if not isinstance(seeds, list) or not seeds or len(seeds) > 10: raise ValueError('Настройка недоступна')
            if self.spec.get('view') == 'pins' and not any(
                    row.get('action', {}).get('seeds') == seeds for row in self.rows):
                raise ValueError('Закрепление изменилось. Обновите список.')
            self.p.play_wave_seeds([str(x) for x in seeds])
        elif op == 'stream':
            if r.get('confirmed') is not True: raise ValueError('Подтвердите замену музыки')
            self.p.play_stream(str(r.get('station', '')), str(r.get('title', 'Поток')))
        else: raise ValueError('Неизвестное действие')

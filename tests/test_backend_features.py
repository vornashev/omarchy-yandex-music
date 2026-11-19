import json
import threading
import time
import unittest
from types import SimpleNamespace as NS
from unittest.mock import Mock, patch
from pathlib import Path
from tempfile import TemporaryDirectory
from backend.features import Features
from backend.audio_cache import AudioCache, AudioIdentity, AudioSource, CacheRequest
import test_backend_collection as fixtures


class FeatureTests(unittest.TestCase):
    def make(self):
        c = fixtures.FakeCollectionClient()
        c.current.description = 'Description'; c.current.visibility = 'private'
        original = c.users_playlists
        c.users_playlists = lambda kind, user_id=None: original(kind)
        for name in ('users_likes_albums', 'users_likes_artists', 'users_likes_playlists', 'users_dislikes_artists'):
            setattr(c, name, lambda: [])
        c.base_url = "https://api.example.invalid"
        c.request = Mock()
        c.pins = lambda: NS(pins=[])
        p = fixtures.CollectionTests().make_player(c)
        p.features = f = Features(p); p.control_lock = threading.RLock(); p._set_queue = Mock()
        return p, c, f

    def wait(self, f):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if not f.snapshot.get('loading') and not f.busy: return
            time.sleep(.005)
        self.fail('feature worker did not finish')

    def open(self, f, **spec):
        f.open(spec); self.wait(f)
        self.assertFalse(f.snapshot.get('error'), f.snapshot)

    def action(self, f, **request):
        if f.snapshot.get('entity', {}).get('editable'): request['playlistRevision'] = f.snapshot['entity']['playlistRevision']
        f.action(dict(request, identity=f.snapshot['identity'])); self.wait(f)

    def test_chart_pages_are_lazy_and_browse_never_starts_music(self):
        p,c,f = self.make()
        c.chart = lambda: NS(chart=NS(tracks=[fixtures.short(str(i)) for i in range(101)]))
        self.open(f, view='chart'); self.assertEqual(len(f.snapshot['rows']),50)
        self.assertTrue(f.snapshot['hasMore']); p._set_queue.assert_not_called()
        self.action(f,op='more'); self.assertEqual(len(f.snapshot['rows']),100)
        self.action(f,op='more'); self.assertEqual(len(f.snapshot['rows']),101)
        self.assertFalse(f.snapshot['hasMore'])
        self.action(f,op='play',index=100)
        self.assertEqual(p._set_queue.call_args.kwargs['start_index'],100)

    def test_podcast_typed_search_preserves_pages(self):
        p,c,f=self.make(); calls=[]
        def search(q,type_,page):
            calls.append((q,type_,page))
            return NS(podcast_episodes=NS(results=[fixtures.track(str(page))],total=2,per_page=1))
        c.search=search
        self.open(f,view='podcasts',query='Наука',episodes=True); self.action(f,op='more')
        self.assertEqual(calls,[('Наука','podcast_episode',0),('Наука','podcast_episode',1)])
        self.assertEqual(len(f.snapshot['rows']),2); self.assertFalse(f.snapshot['hasMore'])
        p._set_queue.assert_not_called()

    def test_slow_response_cannot_replace_new_route(self):
        p,c,f=self.make(); started=threading.Event(); release=threading.Event()
        def chart(): started.set(); release.wait(2); return NS(chart=NS(tracks=[fixtures.short('1')]))
        c.chart=chart; f.open({'view':'chart'}); self.assertTrue(started.wait(1))
        f.open({'view':'overview'}); release.set(); self.wait(f)
        self.assertEqual(f.snapshot['view'],'overview'); self.assertEqual(f.snapshot['title'],'Обзор')
        f.clear(); self.assertEqual(f.snapshot,{})

    def test_favorite_changes_only_on_server_confirmation(self):
        p,c,f=self.make(); c.users_likes_albums_add=Mock(return_value=False)
        self.open(f,view='entity',type='album',id='10'); self.action(f,op='favorite',value=True)
        self.assertFalse(f.snapshot['entity']['favorite']); self.assertTrue(f.snapshot['error'])
        c.users_likes_albums_add.return_value=True; self.action(f,op='favorite',value=True)
        self.assertTrue(f.snapshot['entity']['favorite']); p._set_queue.assert_not_called()

    def test_write_rate_limit_is_not_retried(self):
        p,c,f=self.make(); c.pin_album=Mock(side_effect=RuntimeError('429 too-many-requests'))
        self.open(f,view='entity',type='album',id='10'); self.action(f,op='pin',value=True)
        self.assertEqual(c.pin_album.call_count,1); self.assertFalse(f.snapshot['entity']['pinned'])

    def test_old_identity_cannot_mutate_new_entity(self):
        p,c,f=self.make(); c.pin_album=Mock(return_value=True)
        self.open(f,view='entity',type='album',id='10'); old=f.snapshot['identity']
        self.open(f,view='entity',type='album',id='11')
        f.action({'op':'pin','value':True,'identity':old}); self.wait(f); c.pin_album.assert_not_called()

    def test_playlist_delete_requires_owner_confirmation_and_fresh_revision(self):
        p,c,f=self.make(); c.users_playlists_delete=Mock(return_value=True)
        c.current.owner.uid='99'; self.open(f,view='entity',type='playlist',kind='7',owner='99')
        self.action(f,op='deletePlaylist',confirmed=True); c.users_playlists_delete.assert_not_called()
        c.current.owner.uid='42'; self.open(f,view='entity',type='playlist',kind='7')
        self.action(f,op='deletePlaylist'); c.users_playlists_delete.assert_not_called()
        c.current.revision+=1; self.action(f,op='deletePlaylist',confirmed=True)
        c.users_playlists_delete.assert_not_called()
        self.open(f,view='entity',type='playlist',kind='7'); self.action(f,op='deletePlaylist',confirmed=True)
        c.users_playlists_delete.assert_called_once_with('7'); self.assertEqual(f.snapshot['entity'],{})

    def test_reorder_is_one_atomic_diff_and_does_not_change_queue(self):
        p,c,f=self.make(); c.current.tracks=[fixtures.short('1'),fixtures.short('2'),fixtures.short('1')]
        c.users_playlists_change=Mock(return_value=c.current)
        self.open(f,view='entity',type='playlist',kind='7'); self.action(f,op='move',**{'from':2,'to':0})
        self.assertEqual(c.users_playlists_change.call_args.kwargs,{'revision':5})
        self.assertEqual(json.loads(c.users_playlists_change.call_args.args[1]),[
            {'op':'delete','from':2,'to':3},{'op':'insert','at':0,'tracks':[{'id':'1','albumId':'10'}]}])
        p._set_queue.assert_not_called()

    def test_missing_track_preserves_playlist_occurrence_positions(self):
        p,c,f=self.make(); c.current.tracks=[fixtures.short('missing'),fixtures.short('2')]
        c.tracks=lambda ids:[fixtures.track('2')]
        self.open(f,view='entity',type='playlist',kind='7')
        self.assertEqual(f.snapshot['rows'][0]['entityType'],'unavailable')
        self.assertEqual(f.snapshot['rows'][1]['trackId'],'2')

    def test_publication_and_empty_name_are_guarded_before_writes(self):
        p,c,f=self.make(); c.users_playlists_name=Mock(return_value=c.current)
        c.users_playlists_visibility=Mock(return_value=c.current)
        self.open(f,view='entity',type='playlist',kind='7')
        self.action(f,op='savePlaylist',title='',description='',visibility='private')
        self.action(f,op='savePlaylist',title='Public',description='Description',visibility='public')
        c.users_playlists_name.assert_not_called(); c.users_playlists_visibility.assert_not_called()
        self.assertTrue(f.snapshot['error'])

    def test_server_wave_settings_and_similar_are_browse_only(self):
        p,c,f=self.make(); p.play_station=Mock(); p.play_wave_seeds=Mock()
        c.tracks_similar=lambda id:NS(similar_tracks=[fixtures.track('9')])
        self.open(f,view='similar',type='track',id='1'); self.assertEqual(f.snapshot['rows'][0]['trackId'],'9')
        c.rotor_wave_settings=lambda seeds:NS(blocks=[]); c.rotor_wave_last=lambda:NS(name='Last',seeds=['artist:1'])
        c.rotor_stations_dashboard=lambda:NS(stations=[])
        self.open(f,view='wave'); p.play_station.assert_not_called(); p.play_wave_seeds.assert_not_called()
        self.action(f,op='wave',seeds=['artist:1']); p.play_wave_seeds.assert_called_once_with(['artist:1'])

    def test_streams_require_explicit_confirmation(self):
        p,c,f=self.make(); p.play_stream=Mock()
        self.open(f,view='streams'); self.action(f,op='stream',station='generative:focus')
        p.play_stream.assert_not_called()
        self.action(f,op='stream',station='generative:focus',confirmed=True); p.play_stream.assert_called_once()

    def test_lossless_keeps_decryption_key_in_memory(self):
        p,c,f=self.make(); p.preferences={'audioQuality':'lossless'}
        info=NS(url='https://example.invalid/audio',codec='flac-mp4',bitrate=0,key='01'*16,transport='encraw')
        track=NS(get_file_info=Mock(return_value=NS(download_info=info)))
        source=p._audio_source(track); self.assertEqual(source.codec,'flac-mp4'); self.assertEqual(source.key,'01'*16)

    def test_encrypted_audio_is_decrypted_incrementally_without_persisting_secrets(self):
        from cryptography.hazmat.primitives.ciphers import Cipher,algorithms,modes
        key='01'*16; plain=b'synthetic-audio'*10000
        enc=Cipher(algorithms.AES(bytes.fromhex(key)),modes.CTR(bytes(16))).encryptor()
        encrypted=enc.update(plain)+enc.finalize()
        response=Mock(); response.headers={'content-length':str(len(encrypted))}
        response.iter_content=lambda chunk_size:iter([encrypted[:79],encrypted[79:10000],encrypted[10000:]])
        with TemporaryDirectory() as tmp, patch('backend.audio_cache.requests.get',return_value=response):
            cache=AudioCache(Path(tmp),budget=2_000_000,max_file=1_000_000)
            request=CacheRequest(AudioIdentity('account','track','lossless'),lambda:AudioSource('https://example.invalid/private','flac',0,key),lambda:True,lambda path:None)
            path=cache._download(request,threading.Event()); self.assertIsNotNone(path)
            self.assertEqual(path.read_bytes(),plain)
            manifest=next(Path(tmp).glob('*.json')).read_text(); self.assertNotIn(key,manifest); self.assertNotIn('https',manifest)
            cache.close()

    def test_feature_cache_retains_loaded_pages_and_force_refreshes(self):
        p,c,f=self.make(); c.chart=Mock(return_value=NS(chart=NS(tracks=[fixtures.short(str(i)) for i in range(101)])))
        self.open(f,view='chart'); self.action(f,op='more')
        self.open(f,view='overview'); self.open(f,view='chart')
        self.assertEqual(len(f.snapshot['rows']),100); self.assertEqual(c.chart.call_count,1)
        f.open({'request':{'view':'chart'},'force':True}); self.wait(f)
        self.assertEqual(c.chart.call_count,2); self.assertEqual(len(f.snapshot['rows']),50)

    def test_pin_item_types_are_normalized_and_wave_context_can_be_unpinned(self):
        p,c,f=self.make()
        d=NS(id='10',title='Pinned',name='',uid=None,kind=None,playlist_uuid=None,cover=None)
        wave=NS(id=None,title='Wave',name='',uid=None,kind=None,playlist_uuid=None,cover=None)
        c.pins=lambda:NS(pins=[NS(type='album_item',data=d),NS(type='wave_item',data=wave)])
        c.base_url='https://api.example.invalid'; c.request=Mock()
        c.request.get.return_value={'pins':[
            {'type':'album_item','data':{'id':10,'title':'Pinned'}},
            {'type':'wave_item','data':{'title':'Work','seeds':['activity:work']}},
            {'type':'wave_item','data':{'title':'Unavailable'}},
        ]}
        self.open(f,view='pins')
        self.assertEqual(f.snapshot['rows'][0]['entityType'],'album')
        self.assertEqual(f.snapshot['rows'][1]['action']['seeds'],['activity:work'])
        def unpin(_, *, json):
            c.request.get.return_value['pins'].pop(1)
            return 'ok'
        c.request.delete=Mock(side_effect=unpin)
        self.action(f,op='pinWave',seeds=['activity:work'],value=False)
        c.request.delete.assert_called_once_with(c.base_url + '/pin/wave', json={'seeds': ['activity:work']})
        self.assertEqual(len(f.snapshot['rows']),2)
        self.assertFalse(f.snapshot['rows'][1]['available'])

    def test_wave_pinning_does_not_start_playback(self):
        p,c,f=self.make(); p.play_wave_seeds=Mock()
        c.rotor_wave_settings=lambda seeds:NS(blocks=[]); c.rotor_wave_last=lambda:NS(name='Last',seeds=['artist:1'])
        c.rotor_stations_dashboard=lambda:NS(stations=[])
        pins = []
        c.pins = lambda: NS(pins=pins)
        c.request.put = Mock(side_effect=lambda _, **kw: pins.append(NS(type='wave_item', data=NS(id='artist:1'))) or True)
        self.open(f,view='wave'); self.action(f,op='pinWave',seeds=['artist:1'],value=True)
        c.request.put.assert_called_once_with(c.base_url + '/pin/wave', json={'seeds': ['artist:1']}); p.play_wave_seeds.assert_not_called()
        self.assertEqual(f.snapshot['rows'][0]['trailing']['title'],'Открепить')

    def test_activity_pin_confirms_from_pins_even_if_sdk_loses_write_acknowledgement(self):
        p, c, f = self.make()
        p.rail_pins = rail = Features(p)
        activity = NS(id=NS(type='activity', tag='dance'), name='Dance')
        c.rotor_wave_settings = lambda seeds: NS(blocks=[NS(items=[activity])])
        c.rotor_wave_last = lambda: None
        c.rotor_stations_dashboard = lambda: NS(stations=[])
        pinned = NS(type='wave_item', data=NS(id='activity:dance', title='Dance'))
        c.pins = Mock(side_effect=[NS(pins=[]), NS(pins=[]), NS(pins=[]), NS(pins=[pinned])])
        c.request.put = Mock(return_value=None)
        self.open(rail, view='pins')
        self.open(f, view='wave')
        self.action(f, **f.snapshot['rows'][1]['trailing'])
        self.wait(rail)
        c.request.put.assert_called_once_with(c.base_url + '/pin/wave', json={'seeds': ['activity:dance']})
        self.assertEqual(c.pins.call_count, 4)
        self.assertFalse(f.snapshot['error'])
        self.assertEqual(f.snapshot['rows'][1]['trailing']['title'], 'Открепить')
        self.assertEqual(rail.snapshot['rows'][0]['title'], 'Dance')
        p._set_queue.assert_not_called()

    def test_unpin_from_library_uses_typed_id_and_keeps_row_on_failure(self):
        p, c, f = self.make()
        pins = [
            NS(type='album_item', data=NS(id=7, title='Album')),
            NS(type='artist_item', data=NS(id=7, name='Artist')),
            NS(type='playlist_item', data=NS(uid=42, kind=7, playlist_uuid='playlist', title='Playlist')),
        ]
        c.pins = lambda: NS(pins=pins)
        c.unpin_album = Mock(return_value=False)
        c.unpin_artist = Mock(return_value=True)
        c.unpin_playlist = Mock(return_value=True)
        self.open(f, view='pins')
        album, artist, playlist = (row['trailing'] for row in f.snapshot['rows'])
        self.action(f, **dict(playlist, args=['99', '7']))
        c.unpin_playlist.assert_not_called()
        self.action(f, **album)
        c.unpin_album.assert_called_once_with('7')
        self.assertTrue(f.snapshot['error'])
        self.assertEqual(len(f.snapshot['rows']), 3)
        self.action(f, **artist)
        self.action(f, **playlist)
        c.unpin_artist.assert_called_once_with('7')
        c.unpin_playlist.assert_called_once_with('42', '7')
        self.assertEqual([row['entityType'] for row in f.snapshot['rows']], ['album'])
        p._set_queue.assert_not_called()

    def test_direct_unpin_invalidates_last_entity_snapshot_and_list_reopens_fresh(self):
        p, c, f = self.make()
        p.entity_features = entity = Features(p)
        p.rail_pins = rail = Features(p)
        pin = NS(type='artist_item', data=NS(id=7, name='Artist'))
        pins = []
        c.pins = Mock(side_effect=lambda: NS(pins=list(pins)))
        c.pin_artist = Mock(side_effect=lambda _, **kw: pins.append(pin) or pin)
        c.unpin_artist = Mock(side_effect=lambda _, **kw: pins.clear() or True)
        spec = {'view': 'entity', 'type': 'artist', 'id': '7', 'actionsOnly': True}
        self.open(f, view='pins')
        self.open(rail, view='pins')
        self.open(entity, **spec)
        self.action(entity, op='pin', value=True)
        self.wait(rail)
        self.assertEqual(rail.snapshot['rows'][0]['id'], '7')
        self.open(f, view='pins')
        self.assertEqual(f.snapshot['rows'][0]['id'], '7')
        self.action(f, **f.snapshot['rows'][0]['trailing'])
        self.wait(rail)
        self.assertEqual(rail.snapshot['rows'], [])
        self.open(entity, **spec)
        self.assertFalse(entity.snapshot['entity']['pinned'])
        self.open(f, view='pins')
        self.assertEqual(f.snapshot['rows'], [])

    def test_wave_load_restores_unpin_action_for_preexisting_pin(self):
        p, c, f = self.make()
        pins = [NS(type='wave_item', data=NS(id='user:onyourwave'))]
        c.pins = lambda: NS(pins=pins)
        c.rotor_wave_settings = lambda seeds: NS(blocks=[])
        c.rotor_wave_last = lambda: None
        c.rotor_stations_dashboard = lambda: NS(stations=[])
        c.base_url = 'https://api.example.invalid'
        c.request = Mock()
        c.request.get.side_effect = RuntimeError('Network error')
        c.request.delete = Mock(side_effect=lambda _, **kw: pins.clear() or True)
        self.open(f, view='wave')
        self.assertFalse(f.snapshot['rows'][0]['trailing']['value'])
        self.action(f, **f.snapshot['rows'][0]['trailing'])
        c.request.delete.assert_called_once_with(c.base_url + '/pin/wave', json={'seeds': ['user:onyourwave']})
        self.assertTrue(f.snapshot['rows'][0]['trailing']['value'])

    def test_current_wave_can_be_pinned_and_unpinned_without_changing_playback(self):
        p, c, _ = self.make()
        p.rail_pins = rail = Features(p)
        p.radio_station = 'artist:7'
        p.radio_seeds = ['artist:7', 'settingMoodEnergy:calm']
        seeds = list(p.radio_seeds)
        pin = NS(type='wave_item', data=NS(id=','.join(seeds), title='Artist'))
        pins = []
        c.pins = lambda: NS(pins=list(pins))
        c.request.put = Mock(side_effect=lambda _, **kw: pins.append(pin) or pin)
        c.request.delete = Mock(side_effect=lambda _, **kw: pins.clear() or True)
        self.open(rail, view='pins')
        self.action(rail, op='currentWavePin', seeds=['artist:8'], value=True)
        c.request.put.assert_not_called()
        self.open(rail, view='pins')
        self.action(rail, op='currentWavePin', seeds=seeds, value=True)
        c.request.put.assert_called_once_with(c.base_url + '/pin/wave', json={'seeds': seeds})
        self.assertTrue(rail.wave_pinned(seeds))
        self.action(rail, op='currentWavePin', seeds=seeds, value=False)
        c.request.delete.assert_called_once_with(c.base_url + '/pin/wave', json={'seeds': seeds})
        self.assertFalse(rail.wave_pinned(seeds))
        p._set_queue.assert_not_called()

    def test_current_wave_pin_waits_for_server_visibility_without_repeating_write(self):
        p, c, _ = self.make()
        p.rail_pins = rail = Features(p)
        p.radio_station = 'artist:7'
        seeds = ['artist:7']
        row = NS(type='wave_item', data=NS(id='artist:7', title='Artist'))
        c.pins = Mock(side_effect=[NS(pins=[]), NS(pins=[]), NS(pins=[row])])
        c.request.put = Mock(return_value=row)
        self.open(rail, view='pins')
        self.action(rail, op='currentWavePin', seeds=seeds, value=True)
        c.request.put.assert_called_once_with(c.base_url + '/pin/wave', json={'seeds': ['artist:7']})
        self.assertTrue(rail.wave_pinned(seeds))

    def test_rail_pins_stay_visible_until_menu_refresh_completes(self):
        p, c, rail = self.make()
        p.rail_pins = rail
        pinned = NS(type='artist_item', data=NS(id=7, name='Artist'))
        c.pins = lambda: NS(pins=[pinned])
        self.open(rail, view='pins')
        previous = rail.snapshot['rows']
        self.assertEqual(previous[0]['id'], '7')
        release = threading.Event()
        def refresh():
            release.wait(3)
            return NS(pins=[])
        c.pins = refresh
        try:
            rail.open({'view': 'pins'})
            self.assertTrue(rail.snapshot['loading'])
            self.assertEqual(rail.snapshot['rows'], previous)
        finally:
            release.set()
            self.wait(rail)
        self.assertEqual(rail.snapshot['rows'], [])

    def test_current_wave_pin_rejected_during_loading_returns_an_ipc_error(self):
        p, _, _ = self.make()
        p.rail_pins = rail = Features(p)
        rail.client = p.client
        rail.snapshot = {'identity': 'pins', 'loading': True}
        with self.assertRaisesRegex(ValueError, 'закреплен'):
            p.handle({'command': 'current_wave_pin',
                      'payload': {'identity': 'pins', 'seeds': ['artist:7'], 'value': True}})

    def test_similar_album_seed_is_browsable_without_autoplay(self):
        p,c,f=self.make()
        c.albums_similar_entities=lambda id:NS(items=[NS(data=NS(wave=NS(seeds=['album:42'],name='Similar',description=''),agent=None))])
        self.open(f,view='similar',type='album',id='10')
        self.assertEqual(f.snapshot['rows'][0]['entityType'],'album'); self.assertEqual(f.snapshot['rows'][0]['id'],'42')
        self.assertNotIn('action',f.snapshot['rows'][0]); p._set_queue.assert_not_called()

    def test_continuous_stream_preserves_queue_and_disables_track_operations(self):
        p,c,f=self.make(); queue=list(p.queue)
        c.rotor_station_stream=lambda station:NS(stream=NS(id='synthetic-stream',url='https://example.invalid/stream'))
        p.stop=Mock(); p._save_state=Mock(); p._mpv_command=Mock(); p.play_generation=4
        p.state.update(position=42,queueName='Music',queueSourceKind='likes')
        p.play_stream('generative:focus','Focus')
        deadline=time.monotonic()+2
        while p.state.get('loading') and time.monotonic()<deadline: time.sleep(.005)
        self.assertEqual(p.queue,queue); self.assertEqual(p.stream_resume_position,42)
        self.assertEqual(p.state['duration'],0); self.assertEqual(p.state['trackId'],'')
        self.assertTrue(p.state['playing']); p._mpv_command.reset_mock()
        p.seek(10); p.next(); p.previous(); p.toggle_like(); p.toggle_dislike()
        p._mpv_command.assert_not_called()
        self.assertFalse(p.lyrics()['available']); self.assertFalse(p.track_info()['available'])

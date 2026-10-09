"""Controller-written boundary checks independent of transport worker's tests."""
import json
import pathlib
import tempfile
import time
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch
import qa
import evidence
from tests_evidence import Archive, _by_scenario


class SafetyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)

    def test_vm_excludes_concurrent_operator(self):
        c={'evidence_root':self.tmp.name,'vm_name':'only-one'}
        with qa.vm_lock(c):
            with self.assertRaises(BlockingIOError):
                with qa.vm_lock(c):
                    self.fail('second operator acquired VM')

    def test_close_requires_exact_verified_focus(self):
        run=SimpleNamespace(call=Mock(return_value={'ok':True,'payload':{'exact_window_effect':{'verified':False}}}))
        r=qa.close_owned_window(run,{'pid':4,'window_id':5},['File','Close'])
        self.assertFalse(r['ok'])
        self.assertEqual(run.call.call_count,1)
        self.assertEqual(run.call.call_args.args[0],'bring_to_front')

    def test_closed_windowserver_cache_is_not_a_visible_window(self):
        target={'pid':4,'window_id':5}
        responses=[{'ok':True,'payload':{'exact_window_effect':{'verified':True}}},
                   {'ok':True,'payload':{'effect':'unverifiable'}},
                   {'ok':True,'payload':{'windows':[dict(target,is_on_screen=False)]}},
                   {'ok':True,'payload':{'background_input':{'exact_window':{'status':'ax_unresolved'}}}}]
        run=SimpleNamespace(call=Mock(side_effect=responses))
        self.assertTrue(qa.close_owned_window(run,target,['File','Close'])['ok'])
        self.assertEqual(run.call.call_args.args[0],'get_window_state')

    def test_hidden_but_ax_resolved_is_not_closed(self):
        target={'pid':4,'window_id':5}
        responses=[{'ok':True,'payload':{'exact_window_effect':{'verified':True}}},
                   {'ok':True,'payload':{}},
                   {'ok':True,'payload':{'windows':[dict(target,is_on_screen=False)]}},
                   {'ok':True,'payload':{'background_input':{'exact_window':{'status':'matched'}}}}]
        run=SimpleNamespace(call=Mock(side_effect=responses))
        with patch('qa.time.monotonic',side_effect=[0,10]):
            self.assertFalse(qa.close_owned_window(run,target,['File','Close'])['ok'])

    def test_raw_ax_identity_conflict_rejects_success_metadata(self):
        a=Archive(self.root)
        a.capture('before',start=a.created+1,end=a.created+2)
        a.capture('after',start=a.created+3,end=a.created+4)
        p=self.root/'events/after/ax.bin'
        data=json.loads(p.read_text());data['payload']['pid']=999;p.write_text(json.dumps(data))
        ep=self.root/'events/after/event.json';event=json.loads(ep.read_text())
        event['files']['ax']['sha256']=evidence.digest(p);ep.write_text(json.dumps(event))
        result=evidence.verify(self.root,a.review([a.attempt('peek-static',before='before',after='after')]))
        self.assertEqual(_by_scenario(result)['peek-static']['status'],'inconclusive')
        self.assertIn('AX evidence identity disagrees',' '.join(result['evidence_errors']))

    def test_recovery_outside_owned_title_strip_never_dispatches(self):
        a=Archive(self.root);a.capture('basis',start=time.time()-2,end=time.time()-1,desktop_payload_extra={'screen_width':1280,'screen_height':800})
        run=SimpleNamespace(root=self.root,meta=a.meta,call=Mock())
        with self.assertRaises(ValueError):
            qa.recover_strip(run,'basis',1000,700)
        run.call.assert_not_called()

    def test_cleanup_hidden_window_does_not_close_or_end_session(self):
        a=Archive(self.root)
        (self.root/'owned.json').write_text(json.dumps({'document':'/test/owned.txt'}))
        payload=a._ax_payload()
        payload['background_input']={'routes':[{'route':'window_pointer','status':'refused','reason':'minimized_or_hidden_window'}]}
        run=SimpleNamespace(root=self.root,meta=a.meta,c={},call=Mock(return_value={'ok':True,'payload':payload}))
        result=qa.cleanup(run)
        self.assertEqual(result['status'],'blocked')
        self.assertTrue(all(c.args[0] in ('get_window_state','list_windows') for c in run.call.call_args_list))
        self.assertFalse((self.root/'CLOSED.json').exists())

    def test_observation_failure_can_reference_actual_refusal(self):
        a=Archive(self.root);a.capture('before',start=a.created+1,end=a.created+2)
        a.dead_capture('failed',start=a.created+3,end=a.created+4)
        a.refused('refused',start=a.created+5,end=a.created+6)
        att=a.attempt('observation-failure',before='before',after='refused')
        result=evidence.verify(self.root,a.review([att]))
        self.assertEqual(_by_scenario(result)['observation-failure']['status'],'pass')

    def test_missing_live_counter_measurement_cannot_pass(self):
        a=Archive(self.root);a.capture('before',start=a.created+1,end=a.created+2)
        a.capture('after',start=a.created+3,end=a.created+4,png=b'\x89PNG\r\n\x1a\n'+b'\0'*4+b'IHDR'+(1280).to_bytes(4,'big')+(800).to_bytes(4,'big')+b'different')
        result=evidence.verify(self.root,a.review([a.attempt('peek-live',before='before',after='after')]))
        self.assertEqual(_by_scenario(result)['peek-live']['status'],'inconclusive')

    def test_later_review_cannot_erase_first_failure(self):
        a=Archive(self.root);a.capture('before',start=a.created+1,end=a.created+2)
        a.capture('after',start=a.created+3,end=a.created+4)
        first=a.attempt('peek-static',status='fail',before='before',after='after',reason='wrong visible content')
        (self.root/'review-1.json').write_text(json.dumps(a.review([first])))
        second=a.attempt('peek-static',before='before',after='after')
        rows=[r for r in evidence.verify(self.root,a.review([second]))['results'] if r['scenario']=='peek-static']
        self.assertEqual([r['status'] for r in rows],['fail','pass'])


if __name__=='__main__':unittest.main()

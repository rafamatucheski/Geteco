import sys
from pathlib import Path
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[1] / 'tools'))
from audit_directed_content_secondary import cached_rows, selected_rows


class FocusedSelection(unittest.TestCase):
    def row(self,character,sha,review=False,errors=None):
        return {'character_id':character,'waveform':{'sha256':sha},'language':'pt_BR',
                'expected':'Uma fala.','asr':{'review':review},'technical_errors':errors or []}

    def test_without_explicit_selection_only_primary_flags_are_read(self):
        rows=[self.row('a','1'),self.row('b','2',True)]
        self.assertEqual([r['character_id'] for r in selected_rows({'takes':rows},set(),set(),4)],['b'])

    def test_explicit_sha_can_select_high_similarity_semantic_concern(self):
        rows=[self.row('a','1'),self.row('a','2'),self.row('b','3',True)]
        self.assertEqual([r['waveform']['sha256'] for r in selected_rows({'takes':rows},set(),{'2'},4)],['2'])

    def test_batch_is_finite_and_technical_failures_are_excluded(self):
        rows=[self.row('a','1',True,['bad hash']),self.row('b','2',True),self.row('c','3',True)]
        self.assertEqual([r['character_id'] for r in selected_rows({'takes':rows},set(),set(),1)],['b'])

    def test_previous_batches_remain_cached_by_exact_signature(self):
        old={'cache_key':'old-sha-and-options','audio_sha256':'old'}
        current={'cache_key':'current-sha-and-options','audio_sha256':'new'}
        refreshed=dict(old,comparison='refreshed metadata')
        cache=cached_rows({'archived_takes':[old], 'takes':[current,refreshed]})
        self.assertEqual(len(cache),2)
        self.assertEqual(cache[old['cache_key']],refreshed)
        self.assertEqual(cache[current['cache_key']],current)


if __name__ == '__main__':
    unittest.main()

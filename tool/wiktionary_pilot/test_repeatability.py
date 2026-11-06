import tempfile,unittest
from pathlib import Path
from unittest.mock import patch
from repeatability import check,FILES
class ImmutableRepeatabilityTests(unittest.TestCase):
 def run_case(self,mismatch):
  with tempfile.TemporaryDirectory() as tmp:
   root=Path(tmp)
   for name in FILES: (root/name).write_bytes(b'original')
   for name in ['selected.jsonl','native-index.json','interlex-proto-production.json','civil-keys.json','historical-witnesses.jsonl']:(root/name).write_bytes(b'input')
   before={p.name:p.read_bytes() for p in root.iterdir()}
   def generate(args,**kwargs):
    check_root=Path(args[args.index('--root')+1]);self.assertNotEqual(check_root,root)
    for name in FILES:(check_root/name).write_bytes(b'changed' if mismatch else b'original')
   with patch('repeatability.subprocess.run',side_effect=generate):
    if mismatch:
     with self.assertRaisesRegex(AssertionError,'Non-reproducible'):check(root)
     self.assertFalse((root/'repeatability.json').exists())
    else:check(root);self.assertTrue((root/'repeatability.json').exists())
   for name,data in before.items():self.assertEqual((root/name).read_bytes(),data)
 def test_mismatch_leaves_reviewed_trial_untouched(self):self.run_case(True)
 def test_success_compares_temporary_outputs(self):self.run_case(False)
if __name__=='__main__':unittest.main()

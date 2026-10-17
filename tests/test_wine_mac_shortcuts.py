"""Source-only shortcut integration; never needs an engine or modifies a prefix."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
APP='@implementation WineApplicationController\n            [NSApp setMainMenu:mainMenu];\n'
WINDOW='static inline NSUInteger adjusted_modifiers_for_settings(NSUInteger modifiers)\n{}\n    - (void) postKeyEvent:(NSEvent *)theEvent\n    {\n        [self flagsChanged:theEvent];\n    }\n'

class WineMacShortcutSourceTests(unittest.TestCase):
    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory();self.addCleanup(self.temporary.cleanup)
        self.source=Path(self.temporary.name)/'source';self.driver=self.source/'dlls/winemac.drv';self.driver.mkdir(parents=True)
        (self.driver/'cocoa_app.m').write_text(APP);(self.driver/'cocoa_window.m').write_text(WINDOW)
    def run_patch(self,*extra):
        return subprocess.run(['/bin/bash',str(ROOT/'install_merlot.command'),'--mac-shortcuts','--source',str(self.source),*extra],capture_output=True,text=True,timeout=10)
    def test_patch_both_hooks_and_idempotence(self):
        result=self.run_patch();self.assertEqual(result.returncode,0,result.stderr)
        report=json.loads(result.stdout);self.assertFalse(report['engine_deployed']);self.assertEqual(len(report['changed']),4)
        self.assertEqual(len(list(self.driver.glob('*.before-chardonnay-*'))),2)
        for path,old in [('cocoa_app.m',APP),('cocoa_window.m',WINDOW)]:
            self.assertEqual(next(self.driver.glob(path+'.before-chardonnay-*')).read_text(),old)
        timestamps={p.name:p.stat().st_mtime_ns for p in self.driver.iterdir()}
        result=self.run_patch();self.assertEqual(result.returncode,0,result.stderr);self.assertEqual(json.loads(result.stdout)['changed'],[])
        self.assertEqual({p.name:p.stat().st_mtime_ns for p in self.driver.iterdir()},timestamps)
    def test_unknown_window_source_fails_before_any_write(self):
        (self.driver/'cocoa_window.m').write_text('unknown source')
        result=self.run_patch();self.assertNotEqual(result.returncode,0)
        self.assertEqual((self.driver/'cocoa_app.m').read_text(),APP);self.assertFalse(list(self.driver.glob('*.h')))
    def test_duplicate_menu_hook_rejected(self):
        (self.driver/'cocoa_app.m').write_text(APP+APP)
        self.assertNotEqual(self.run_patch().returncode,0);self.assertFalse(list(self.driver.glob('*.h')))
    def test_header_symlink_rejected_without_following(self):
        sentinel=self.source/'sentinel';sentinel.write_text('untouched')
        (self.driver/'chardonnay_shortcuts.h').symlink_to(sentinel)
        self.assertNotEqual(self.run_patch().returncode,0);self.assertEqual(sentinel.read_text(),'untouched')
        self.assertEqual((self.driver/'cocoa_app.m').read_text(),APP)
    def test_source_symlink_rejected(self):
        source=self.driver/'cocoa_window.m';source.unlink();source.symlink_to(self.driver/'cocoa_app.m')
        self.assertNotEqual(self.run_patch().returncode,0);self.assertEqual((self.driver/'cocoa_app.m').read_text(),APP)
    def test_diagnostics_are_explicit_and_compile_time_gated(self):
        result=self.run_patch('--test-probe');self.assertEqual(result.returncode,0,result.stderr)
        self.assertTrue((self.driver/'WineMacShortcutProbe.h').is_file())
        header=(self.driver/'chardonnay_shortcuts.h').read_text()
        self.assertIn('#ifdef CHARDONNAY_SHORTCUT_TESTING\n#include "WineMacShortcutProbe.h"',header)
    def test_default_patch_does_not_stage_test_header(self):
        self.assertEqual(self.run_patch().returncode,0);self.assertFalse((self.driver/'WineMacShortcutProbe.h').exists())

if __name__=='__main__':unittest.main()

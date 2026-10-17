"""Pinned Gecko cache prerequisites; no existing bottle/registry is changed here."""
import hashlib
from pathlib import Path
import tempfile
import types
import unittest
from unittest import mock

ROOT=Path(__file__).resolve().parents[1]
TEXT=(ROOT/'install_merlot.command').read_text()
M=types.ModuleType('gecko_prerequisite');M.__file__=str(ROOT/'install_merlot.command')
exec(compile(TEXT.split('# BEGIN BOTTLES PYTHON\n',1)[1].split('# END BOTTLES PYTHON',1)[0],M.__file__,'exec'),M.__dict__)

class GeckoPrerequisiteTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
        self.wine=self.root/'engine/bin/wine';self.wine.parent.mkdir(parents=True);self.wine.write_bytes(b'fixture')
        self.payloads={arch:('fixture package '+arch).encode() for arch in ['x86','x86_64']}
        self.pins={arch:hashlib.sha256(data).hexdigest() for arch,data in self.payloads.items()}
        for arch,pe_arch in [('x86','i386'),('x86_64','x86_64')]:
            p=self.root/'engine/lib/wine'/(pe_arch+'-windows')/'appwiz.cpl';p.parent.mkdir(parents=True)
            p.write_bytes(('wine-gecko-2.47.4-'+arch+'.msi').encode('utf-16-le')+self.pins[arch].encode())
        self.row={'wine':str(self.wine),'path':str(self.root/'must-not-create-prefix')};self.cache=self.root/'cache';self.downloads=[]
        self.patcher=mock.patch.object(M,'GECKO_PINS',{'2.47.4':self.pins},create=True);self.patcher.start();self.addCleanup(self.patcher.stop)

    def fetch(self,url,destination):
        self.downloads.append(url);arch='x86_64' if 'x86_64' in url else 'x86';Path(destination).write_bytes(self.payloads[arch])

    def ensure(self):
        self.assertTrue(hasattr(M,'ensure_gecko_cache'),'Gecko prerequisite implementation missing')
        return M.ensure_gecko_cache(self.row,self.cache,self.fetch)

    def test_downloads_both_architectures_matching_compiled_engine(self):
        result=self.ensure();self.assertTrue(result['ready']);self.assertEqual(len(self.downloads),2)
        self.assertTrue(all(url.startswith('https://dl.winehq.org/') for url in self.downloads))
        self.assertFalse(Path(self.row['path']).exists(),'cache preparation modified a live prefix')

    def test_verified_cache_is_idempotent_and_works_offline(self):
        self.ensure();self.downloads=[]
        with mock.patch.object(M,'download_gecko_package',side_effect=AssertionError('unexpected network')):
            self.assertTrue(M.ensure_gecko_cache(self.row,self.cache)['ready'])
        self.assertEqual(self.downloads,[])

    def test_hash_mismatch_is_not_published_as_a_package(self):
        self.assertTrue(hasattr(M,'ensure_gecko_cache'))
        def invalid(url,path):Path(path).write_bytes(b'not the pinned package')
        with self.assertRaises(RuntimeError):M.ensure_gecko_cache(self.row,self.cache,invalid)
        self.assertFalse(list(self.cache.glob('*.msi')))

    def test_failed_download_preserves_existing_invalid_file(self):
        self.cache.mkdir();old=self.cache/'wine-gecko-2.47.4-x86.msi';old.write_bytes(b'old invalid cache')
        def failed(url,path):raise RuntimeError('fixture network failure')
        with self.assertRaises(RuntimeError):M.ensure_gecko_cache(self.row,self.cache,failed)
        self.assertEqual(old.read_bytes(),b'old invalid cache')

    def test_unknown_engine_requirements_are_not_guessed(self):
        for p in (self.root/'engine/lib/wine').glob('*/appwiz.cpl'):p.write_bytes(b'unknown engine')
        with self.assertRaises(ValueError):self.ensure()
        self.assertEqual(self.downloads,[])

    def test_symlink_cache_target_is_rejected_without_touching_its_target(self):
        self.cache.mkdir();target=self.root/'user-file';target.write_bytes(b'preserve')
        (self.cache/'wine-gecko-2.47.4-x86.msi').symlink_to(target)
        with self.assertRaises(ValueError):self.ensure()
        self.assertEqual(target.read_bytes(),b'preserve')

if __name__=='__main__':unittest.main()

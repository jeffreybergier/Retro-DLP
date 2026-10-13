"""Exercise fresh and cached EJS provisioning without network access."""
import hashlib
import io
from pathlib import Path
import runpy
import shutil
import tempfile
import unittest
from unittest.mock import patch


class ProvisionEJSTest(unittest.TestCase):
    def test_fresh_assets_and_cached_assets_include_notice(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            script = root / '.github/scripts/provision-ejs.py'
            script.parent.mkdir(parents=True)
            shutil.copyfile(Path(__file__).with_name('provision-ejs.py'), script)
            shared = root / 'source/library/shared'
            (shared / 'include/retrodlp').mkdir(parents=True)
            (shared / 'include/retrodlp/assets.h').write_text(
                '#define RDLP_EJS_ASSET_VERSION "0.8.0"\n')
            assets = {'core.min.js': b'core fixture', 'lib.min.js': b'lib fixture'}
            (shared / 'rdlp_ejs_manifest.c').write_text('\n'.join(
                '{"%s", "https://example.invalid/" RDLP_EJS_ASSET_VERSION "/" '
                '"%s", %dU, "%s"}' %
                (name, name, len(data), hashlib.sha256(data).hexdigest())
                for name, data in assets.items()))
            destination = root / 'build/generated/ejs'
            with patch('sys.argv', [str(script), str(destination)]):
                with patch('urllib.request.urlopen', side_effect=lambda url, **kw:
                           io.BytesIO(assets[url.rsplit('/', 1)[1]])) as download:
                    runpy.run_path(str(script), run_name='__main__')
                    self.assertEqual(download.call_count, 2)
                for name, data in assets.items():
                    self.assertEqual((destination / name).read_bytes(), data)
                notice = destination / 'NOTICE.txt'
                self.assertIn('yt-dlp-ejs 0.8.0', notice.read_text())
                self.assertEqual(notice.stat().st_mode & 0o777, 0o644)
                notice.unlink()
                with patch('urllib.request.urlopen', side_effect=AssertionError(
                        'cached assets must not access the network')):
                    runpy.run_path(str(script), run_name='__main__')
                self.assertIn('Meriyah', notice.read_text())
                self.assertIn('Astring', notice.read_text())


if __name__ == '__main__':
    unittest.main()

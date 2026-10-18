import base64
import pathlib
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]

class AppcastTests(unittest.TestCase):
    def test_feed_order_validation_and_failed_write_preserves_feed(self):
        with tempfile.TemporaryDirectory() as directory:
            feed = pathlib.Path(directory) / 'feed.xml'
            def run(build, *extra):
                return subprocess.run(['python3', str(ROOT / 'scripts/update-appcast.py'),
                    '--appcast', str(feed), '--version', build, *extra], capture_output=True)
            self.assertEqual(run('1', '--validate-only').returncode, 0)
            self.assertFalse(feed.exists())
            args = ['--short-version', '0.1.0-beta.1', '--url', 'https://example.com/app.dmg',
                    '--length', '100', '--signature', base64.b64encode(bytes(64)).decode()]
            self.assertEqual(run('1', *args).returncode, 0)
            original = feed.read_bytes()
            for build in ['0', '1', '-1', '1.1', 'oops']:
                self.assertNotEqual(run(build, '--validate-only').returncode, 0)
                self.assertEqual(feed.read_bytes(), original)
            self.assertNotEqual(run('2', *args, '--url', 'https://example.com/app-local.dmg').returncode, 0)
            self.assertEqual(feed.read_bytes(), original)
            self.assertEqual(run('2', *args).returncode, 0)
            items = ET.parse(feed).findall('./channel/item')
            key = '{http://www.andymatuschak.org/xml-namespaces/sparkle}version'
            self.assertEqual([item.findtext(key) for item in items], ['2', '1'])

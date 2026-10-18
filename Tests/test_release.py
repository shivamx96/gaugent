"""Release input failures must happen before builds or signing access."""
import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class ReleaseInputs(unittest.TestCase):
    def test_invalid_versions_and_builds(self):
        for arguments in [[], ['0.1', '1'], ['0.1.0', '0'], ['0.1.0', '-1'],
                          ['0.1.0', '1.2'], ['0.1.0-beta', ''], ['../../bad', '1']]:
            with self.subTest(arguments=arguments):
                result = subprocess.run(['bash', 'scripts/release.sh', *arguments],
                                        cwd=ROOT, capture_output=True, text=True)
                self.assertEqual(result.returncode, 2, result.stderr)

if __name__ == '__main__':
    unittest.main()

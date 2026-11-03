"""Cloud packaging contract tests; no credentials, HBuilderX or network needed."""
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('native_build', Path(__file__).parents[1] / 'scripts/native-build.py')
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class NativeBuildTests(unittest.TestCase):
    def test_download_url_filters_docs_and_previous_builds(self):
        old = 'https://service.dcloud.net.cn/build/download/old'
        new = 'https://service.dcloud.net.cn/build/download/new'
        self.assertEqual(build.download_url(f'https://hx.dcloud.net.cn/cli/pack {old} {new}', {old}), new)
        self.assertIsNone(build.download_url('https://example.com/build/download/bad'))

    def run_pack(self, fail=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'src').mkdir()
            manifest = root / 'src/manifest.json'
            original = '{"appid":"__UNI__KAIFAN"}'
            manifest.write_text(original)
            cert = root / 'key'; cert.write_text('mock')
            commands = []
            def command(cli, *args):
                commands.append(args)
                if args[0] == 'pack' and args[1] == '--config':
                    config = json.loads(Path(args[2]).read_text())
                    self.assertEqual(config['project'], str(root))
                    self.assertEqual(config['android']['androidpacktype'], '0')
                    self.assertEqual(json.loads(manifest.read_text())['appid'], '__UNI__TEST')
                    if fail:
                        raise RuntimeError('mock failure')
                    return 'https://service.dcloud.net.cn/build/download/new'
                return ''
            env = {'HBUILDERX_CLI': '/mock/cli', 'DCLOUD_APP_ID': '__UNI__TEST',
                   'VITE_API_BASE_URL': 'https://api.example.com', 'NATIVE_TARGET': 'android',
                   'NATIVE_PACK_CONFIG': json.dumps({'android': {'packagename': 'test.app',
                     'certfile': str(cert), 'certalias': 'test', 'certpassword': 'secret'}})}
            with patch.dict(os.environ, env), patch.object(build, '__file__', str(root / 'scripts/native-build.py')), patch.object(build, 'command', side_effect=command), patch.object(build, 'urlopen', return_value=io.BytesIO(b'PKmock')):
                if fail:
                    with self.assertRaises(RuntimeError): build.main()
                else:
                    build.main()
                    self.assertTrue((root / 'dist/native/kaifan.apk.sha256').exists())
            self.assertEqual(manifest.read_text(), original)
            self.assertFalse((root / '.env.production.local').exists())

    def test_success_downloads_and_restores_configuration(self):
        self.run_pack()

    def test_failure_restores_configuration(self):
        self.run_pack(fail=True)


if __name__ == '__main__':
    unittest.main()

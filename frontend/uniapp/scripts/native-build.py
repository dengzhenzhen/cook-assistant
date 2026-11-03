"""Signed HBuilderX cloud builds on a provisioned macOS runner.

Credentials stay in a temporary config; raw CLI output is never logged because
it can contain certificate passwords or temporary download URLs.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
from urllib.parse import urlparse
from urllib.request import urlopen


def command(cli, *args):
    result = subprocess.run([cli, *args], capture_output=True, text=True, timeout=2400)
    if result.returncode:
        raise RuntimeError('HBuilderX command failed; inspect its local pack console on the runner.')
    return result.stdout + result.stderr


def download_url(output, excluded=()):
    # Ignore documentation links in warnings. DCloud returns extensionless URLs.
    for url in reversed(re.findall(r'https://[^\s<>"\'\u3000-\u303f]+', output)):
        url = url.rstrip(').,')
        if url in excluded:
            continue
        parsed = urlparse(url)
        if parsed.hostname and parsed.hostname.endswith('.dcloud.net.cn') and '/build/download/' in parsed.path:
            return url
    return None


def main():
    project = Path(__file__).resolve().parents[1]
    cli = os.environ['HBUILDERX_CLI']
    appid = os.environ.get('DCLOUD_APP_ID', '')
    base_url = os.environ.get('VITE_API_BASE_URL', '')
    target = os.environ.get('NATIVE_TARGET')
    if target not in ('android', 'ios', 'both'):
        raise ValueError('Select android, ios or both.')
    if not appid.startswith('__UNI__') or appid == '__UNI__KAIFAN':
        raise ValueError('Set DCLOUD_APP_ID to a real DCloud application ID.')
    if urlparse(base_url).scheme != 'https' or not urlparse(base_url).hostname:
        raise ValueError('Set UNIAPP_API_BASE_URL to the HTTPS backend URL.')
    config = json.loads(os.environ.get('NATIVE_PACK_CONFIG') or '{}')
    platforms = ['android', 'ios'] if target == 'both' else [target]
    for platform in platforms:
        settings = config.get(platform, {})
        required = ('packagename', 'certfile', 'certalias', 'certpassword') if platform == 'android' else ('bundle', 'profile', 'certfile', 'certpassword')
        if any(not settings.get(key) for key in required):
            raise ValueError(f'Missing {platform} signing settings in NATIVE_PACK_CONFIG.')
        for key in ('certfile', 'profile'):
            if settings.get(key) and not Path(settings[key]).is_file():
                raise ValueError(f'{platform} {key} does not exist on this runner.')
        if platform == 'android':
            settings['androidpacktype'] = '0'
    manifest_path = project / 'src/manifest.json'
    original = manifest_path.read_text()
    env_path = project / '.env.production.local'
    previous_env = env_path.read_bytes() if env_path.exists() else None
    try:
        manifest = json.loads(original)
        manifest['appid'] = appid
        manifest.setdefault('app-plus', {}).update({'usingComponents': True})
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
        # HBuilderX may compile in its own process, outside this shell environment.
        env_path.write_text('VITE_API_BASE_URL=' + json.dumps(base_url) + '\n')
        output_dir = project / 'dist/native'
        output_dir.mkdir(parents=True, exist_ok=True)
        command(cli, 'open')
        command(cli, 'project', 'open', '--path', str(project))
        with tempfile.TemporaryDirectory(prefix='kaifan-pack-') as temporary:
            for platform in platforms:
                pack = {**config, 'project': str(project), 'platform': platform,
                        'safemode': False, 'iscustom': False}
                path = Path(temporary) / 'pack.json'
                path.write_text(json.dumps(pack))
                path.chmod(0o600)
                print(f'Submitting {platform} signed cloud build.', flush=True)
                previous = command(cli, 'pack', 'status', '--project', str(project))
                excluded = set()
                while old_url := download_url(previous, excluded):
                    excluded.add(old_url)
                output = command(cli, 'pack', '--config', str(path))
                deadline = time.monotonic() + 2400
                url = download_url(output, excluded)
                while not url and time.monotonic() < deadline:
                    if re.search(r'打包失败|packaging failed|pack failed', output, re.I):
                        raise RuntimeError(f'{platform} cloud packaging failed; inspect HBuilderX on the runner.')
                    time.sleep(20)
                    output = command(cli, 'pack', 'status', '--project', str(project))
                    url = download_url(output, excluded)
                if not url:
                    raise RuntimeError(f'{platform} build did not return a download URL before timeout.')
                artifact = output_dir / ('kaifan.apk' if platform == 'android' else 'kaifan.ipa')
                with urlopen(url, timeout=120) as response, artifact.open('wb') as destination:
                    while chunk := response.read(1024 * 1024):
                        destination.write(chunk)
                with artifact.open('rb') as package:
                    if package.read(2) != b'PK':
                        raise RuntimeError('Cloud download is not an APK/IPA archive.')
                digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
                artifact.with_suffix(artifact.suffix + '.sha256').write_text(f'{digest}  {artifact.name}\n')
                print(f'{platform} artifact downloaded.', flush=True)
    finally:
        manifest_path.write_text(original)
        if previous_env is None:
            env_path.unlink(missing_ok=True)
        else:
            env_path.write_bytes(previous_env)


if __name__ == '__main__':
    main()

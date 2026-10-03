"""Tested conversion utility, NOT an AI model or a deployable FastAPI service.
Invoke in a sandboxed queue worker only after MIME probing, size/duration limits,
malware policy, ownership checks, and successful upload checksum verification.
"""
from pathlib import Path
import subprocess
import tempfile
import os


def convert(source: Path, output: Path, profile: str) -> Path:
    source = source.resolve(strict=True)
    output = output.resolve()
    if not source.is_file() or output.exists() or source == output:
        raise ValueError('Input must be a file; output must be new')
    profiles = {
        'analysis': ('.wav', ['-ac', '1', '-ar', '48000', '-c:a', 'pcm_s16le']),
        'speech_model': ('.wav', ['-ac', '1', '-ar', '16000', '-c:a', 'pcm_s16le']),
        'playback': ('.m4a', ['-ac', '1', '-ar', '48000', '-c:a', 'aac', '-b:a', '128k']),
    }
    if profile not in profiles:
        raise ValueError('Unknown conversion profile')
    suffix, codec = profiles[profile]
    if output.suffix != suffix:
        raise ValueError('Output extension does not match the codec/container')
    output.parent.mkdir(parents=True, exist_ok=True)
    # A private temporary directory avoids collisions and partial final files.
    with tempfile.TemporaryDirectory(dir=output.parent) as temporary:
        partial = Path(temporary) / ('encoded' + suffix)
        subprocess.run([
            'ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error',
            '-protocol_whitelist', 'file,pipe', '-i', str(source),
            '-map', '0:a:0', '-vn', '-map_metadata', '-1', *codec, str(partial),
        ], check=True, timeout=180, capture_output=True)
        # Hard link is atomic and refuses to overwrite a concurrent result.
        os.link(partial, output)
    return output

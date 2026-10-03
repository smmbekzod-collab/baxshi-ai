import math
from pathlib import Path
import struct
import tempfile
import unittest
import wave
from audio_worker import convert

class ConversionTests(unittest.TestCase):
    def test_conversion_profiles_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'original.wav'
            with wave.open(str(source), 'wb') as f:
                f.setnchannels(1); f.setsampwidth(2); f.setframerate(48000)
                f.writeframes(b''.join(struct.pack('<h', int(8000 * math.sin(2*math.pi*220*i/48000)))
                                      for i in range(48000)))
            analysis = convert(source, root/'analysis.wav', 'analysis')
            speech = convert(source, root/'speech.wav', 'speech_model')
            playback = convert(source, root/'playback.m4a', 'playback')
            with wave.open(str(analysis), 'rb') as f:
                self.assertEqual(f.getframerate(), 48000)
                self.assertEqual(f.getnframes(), 48000)
            with wave.open(str(speech), 'rb') as f:
                self.assertEqual(f.getframerate(), 16000)
            self.assertLess(playback.stat().st_size, source.stat().st_size)
            with self.assertRaises(ValueError):
                convert(source, analysis, 'analysis')
            with self.assertRaises(ValueError):
                convert(source, root/'wrong.mp3', 'analysis')
if __name__ == '__main__':
    unittest.main()

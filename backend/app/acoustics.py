"""Bounded deterministic acoustic baseline. These are not validated artistic grades."""

from pathlib import Path
from datetime import datetime, timezone
import subprocess, tempfile, wave
import numpy as np
from scipy.signal import correlate, find_peaks


class Rejected(Exception):
    pass


def decode(path):
    with open(path, "rb") as source:
        header = source.read(12)
    if header[:4] == b"RIFF" and header[8:12] == b"WAVE":
        demuxer = "wav"
    elif header[4:8] == b"ftyp":
        demuxer = "mov"
    else:
        raise Rejected("unsupported_container")
    with tempfile.TemporaryDirectory() as folder:
        out = Path(folder) / "mono.wav"
        try:
            subprocess.run(
                [
                    "ffmpeg",
                    "-nostdin",
                    "-hide_banner",
                    "-loglevel",
                    "error",
                    "-protocol_whitelist",
                    "file,pipe",
                    "-f",
                    demuxer,
                    "-i",
                    str(path),
                    "-map",
                    "0:a:0",
                    "-vn",
                    "-t",
                    "1201",
                    "-ac",
                    "1",
                    "-ar",
                    "16000",
                    "-c:a",
                    "pcm_s16le",
                    str(out),
                ],
                check=True,
                timeout=90,
                capture_output=True,
            )
            with wave.open(str(out), "rb") as f:
                x = (
                    np.frombuffer(f.readframes(f.getnframes()), dtype="<i2").astype(
                        np.float32
                    )
                    / 32768
                )
        except (OSError, wave.Error, subprocess.SubprocessError) as e:
            raise Rejected("invalid_audio") from e
    duration = len(x) / 16000
    if duration < 5:
        raise Rejected("audio_too_short")
    if duration > 1200:
        raise Rejected("audio_too_long")
    rms = float(np.sqrt(np.mean(x * x)))
    clipping = float(np.mean(abs(x) > 0.995))
    if rms < 0.003:
        raise Rejected("audio_too_quiet")
    if clipping > 0.02:
        raise Rejected("audio_clipping")
    return x, {
        "duration_seconds": round(duration, 2),
        "rms_dbfs": round(20 * np.log10(rms), 2),
        "clipping_ratio": clipping,
    }


def pitch(x):
    values = []
    hop = max(320, (len(x) - 640) // 2500)
    total = 0
    for start in range(0, len(x) - 640, hop):
        total += 1
        f = x[start : start + 640].astype(np.float64)
        f -= f.mean()
        if np.sqrt(np.mean(f * f)) < 0.005:
            continue
        f *= np.hanning(640)
        a = correlate(f, f, mode="full", method="fft")[639:]
        peaks, _ = find_peaks(a[27:200])
        if len(peaks) == 0 or a[0] < 1e-8:
            continue
        lag = int(peaks[np.argmax(a[27:200][peaks])] + 27)
        if a[lag] / a[0] > 0.6:
            values.append(16000 / lag)
    return np.array(values), len(values) / max(1, total)


def compare(a, b):
    a = a[np.linspace(0, len(a) - 1, min(300, len(a))).astype(int)]
    b = b[np.linspace(0, len(b) - 1, min(300, len(b))).astype(int)]
    a = 1200 * np.log2(a)
    b = 1200 * np.log2(b)
    a -= np.median(a)
    b -= np.median(b)
    n, m = len(a), len(b)
    cost = np.full((n + 1, m + 1), np.inf)
    cost[0, 0] = 0
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            cost[i, j] = abs(a[i - 1] - b[j - 1]) + min(
                cost[i - 1, j], cost[i, j - 1], cost[i - 1, j - 1]
            )
    i, j = n, m
    errors = []
    while i and j:
        errors.append(float(abs(a[i - 1] - b[j - 1])))
        step = int(np.argmin([cost[i - 1, j - 1], cost[i - 1, j], cost[i, j - 1]]))
        if step == 0:
            i -= 1
            j -= 1
        elif step == 1:
            i -= 1
        else:
            j -= 1
    errors.reverse()
    return float(100 * np.exp(-np.median(errors) / 150)), errors


def rhythm(x):
    n = len(x) // 800
    env = np.sqrt(np.mean(x[: n * 800].reshape(n, 800) ** 2, axis=1))
    peaks, _ = find_peaks(
        env, distance=4, prominence=max(0.005, float(np.std(env)) * 0.4)
    )
    return np.diff(peaks) * 0.05


def evaluate(source, reference, id, job):
    x, quality = decode(source)
    f, coverage = pitch(x)
    p = None
    r = None
    samples = []
    if reference:
        y, _ = decode(reference)
        g, _ = pitch(y)
        if len(f) >= 30 and len(g) >= 30:
            p, errors = compare(f, g)
            for i in np.linspace(0, len(errors) - 1, min(30, len(errors))).astype(int):
                samples.append(
                    {
                        "seconds": float(
                            i / max(1, len(errors) - 1) * quality["duration_seconds"]
                        ),
                        "user": round(float(100 * np.exp(-errors[i] / 150)), 2),
                        "reference": 100.0,
                    }
                )
        a, b = rhythm(x), rhythm(y)
        if len(a) >= 5 and len(b) >= 5:
            q = np.linspace(0, 1, 20)
            err = np.mean(
                abs(np.quantile(a / np.median(a), q) - np.quantile(b / np.median(b), q))
            )
            r = float(100 * np.exp(-err))
    metrics = []
    for kind, score, reason in [
        (
            "pitch",
            p,
            "Register-normalized contour estimate; expert calibration required.",
        ),
        ("rhythm", r, "Onset interval estimate; not a traditional-rhythm grade."),
        (
            "breath",
            None,
            "Physiological breath control cannot be established from this recording.",
        ),
        ("resonance", None, "Requires calibrated recordings and a validated model."),
        ("style", None, "No trained and validated school classifier is installed."),
    ]:
        metrics.append(
            {
                "kind": kind,
                "score": round(score, 2) if score is not None else None,
                "confidence": round(coverage, 3) if score is not None else 0,
                "reason": reason
                if score is not None or kind not in ["pitch", "rhythm"]
                else "Matching reference or voiced evidence is insufficient.",
            }
        )
    english = job["locale"] == "en"
    worst = min(samples, key=lambda s: s["user"])["seconds"] if samples else 0
    return {
        "schema_version": 1,
        "id": id,
        "school": job["school"],
        "reference_id": job["reference_id"] or "none",
        "source_asset_id": job["asset_id"],
        "model_version": "acoustic-baseline-0.2-unvalidated",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "demo": False,
        "audio_available": False,
        "quality": quality,
        "metrics": metrics,
        "samples": samples,
        "confidence_kind": "voiced_frame_coverage_not_probability",
        "coach_text": "Acoustic estimates require teacher review."
        if english
        else "Akustik taxminiy natijalarni ustoz bilan tekshiring. Bu badiiy mahoratning yakuniy bahosi emas.",
        "feedback": [
            {
                "start": round(worst, 2),
                "end": min(quality["duration_seconds"], round(worst + 3, 2)),
                "message": "Compare this phrase with the reference."
                if english
                else "Ushbu jumlani mos etalon bilan solishtiring.",
                "exercise": "Listen, repeat comfortably, record again."
                if english
                else "Parchani tinglang, qulay ovozda takrorlang va qayta yozing.",
            }
        ],
    }

#!/usr/bin/env python3
"""Generate 4 pleasant, iOS-native Core Audio Format (.caf) notification sounds.

Format: Apple CAF v1, Linear PCM 16-bit big-endian signed integer, 44.1 kHz, mono.
Duration: 1.6s - 2.6s (strictly <= 30s iOS UNNotificationSound limit).
"""
import math
import struct
from pathlib import Path

SAMPLE_RATE = 44100


def write_caf(path: Path, samples: list[float]) -> None:
    """Write normalized float samples [-1, 1] as 16-bit BE LPCM Core Audio Format (.caf)."""
    pcm_bytes = bytearray()
    for s in samples:
        clamped = max(-0.98, min(0.98, s))
        pcm_bytes.extend(struct.pack(">h", int(round(clamped * 32767.0))))

    # CAF file header: 'caff', version=1, flags=0
    header = struct.pack(">4sHH", b"caff", 1, 0)

    # Audio Description ('desc') chunk: 32 bytes payload
    # mFormatFlags = 0 => big-endian signed integer Linear PCM
    desc_payload = struct.pack(
        ">d4sIIIII",
        float(SAMPLE_RATE),  # mSampleRate
        b"lpcm",             # mFormatID
        0,                   # mFormatFlags (BE signed int)
        2,                   # mBytesPerPacket (16-bit mono)
        1,                   # mFramesPerPacket
        1,                   # mChannelsPerFrame
        16,                  # mBitsPerChannel
    )
    desc_chunk = struct.pack(">4sq", b"desc", len(desc_payload)) + desc_payload

    # Audio Data ('data') chunk: 4-byte edit count + raw PCM
    data_payload = struct.pack(">I", 0) + bytes(pcm_bytes)
    data_chunk = struct.pack(">4sq", b"data", len(data_payload)) + data_payload

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(header + desc_chunk + data_chunk)


def render_notes(
    duration_sec: float,
    notes: list[tuple[float, float, float, float]],
    harmonics: list[tuple[float, float]],
) -> list[float]:
    """Synthesize warm acoustic chime notes.

    notes: list of (start_sec, freq_hz, amp, decay_rate)
    harmonics: list of (multiplier, relative_amp)
    """
    n = int(SAMPLE_RATE * duration_sec)
    buf = [0.0] * n

    for start_sec, freq, amp, decay in notes:
        start_idx = int(start_sec * SAMPLE_RATE)
        attack_samples = int(0.008 * SAMPLE_RATE)
        for i in range(start_idx, n):
            t = (i - start_idx) / SAMPLE_RATE
            env = math.exp(-decay * t)
            if (i - start_idx) < attack_samples:
                env *= (i - start_idx) / attack_samples
            if env < 0.0005:
                break
            val = 0.0
            for mult, h_amp in harmonics:
                val += h_amp * math.sin(2.0 * math.pi * (freq * mult) * t)
            buf[i] += amp * env * val

    # Smooth tail fade-out on final 50ms to guarantee zero click
    fade = int(0.05 * SAMPLE_RATE)
    for k in range(fade):
        idx = n - fade + k
        if 0 <= idx < n:
            buf[idx] *= 1.0 - (k / fade)

    # Normalize peak to -2 dB (~0.78)
    peak = max((abs(x) for x in buf), default=1.0)
    if peak > 0.0:
        scale = 0.78 / peak
        buf = [x * scale for x in buf]
    return buf


def main() -> None:
    out_dir = Path("App/PLAApp/Resources/Sounds")

    # 1. pla_default.caf (1.6s): calm warm two-note chime (C5 -> G5)
    default_samples = render_notes(
        duration_sec=1.6,
        notes=[
            (0.02, 523.25, 0.70, 3.8),
            (0.20, 783.99, 0.85, 3.0),
        ],
        harmonics=[(1.0, 1.0), (2.0, 0.25), (3.0, 0.07)],
    )
    write_caf(out_dir / "pla_default.caf", default_samples)

    # 2. pla_urgent.caf (2.4s): crisp double-pulse triad alert (E5-G#5-B5 x2)
    urgent_samples = render_notes(
        duration_sec=2.4,
        notes=[
            (0.02, 659.25, 0.75, 4.5),
            (0.14, 830.61, 0.80, 4.5),
            (0.26, 987.77, 0.90, 3.5),
            (0.82, 659.25, 0.75, 4.5),
            (0.94, 830.61, 0.80, 4.5),
            (1.06, 987.77, 0.95, 2.8),
        ],
        harmonics=[(1.0, 1.0), (2.0, 0.35), (3.0, 0.14), (4.0, 0.05)],
    )
    write_caf(out_dir / "pla_urgent.caf", urgent_samples)

    # 3. pla_bill.caf (2.0s): clear bright bell triad (D5 -> A5 -> D6)
    bill_samples = render_notes(
        duration_sec=2.0,
        notes=[
            (0.02, 587.33, 0.65, 3.5),
            (0.18, 880.00, 0.78, 3.2),
            (0.36, 1174.66, 0.85, 2.4),
        ],
        harmonics=[(1.0, 1.0), (2.0, 0.30), (2.76, 0.12), (4.0, 0.06)],
    )
    write_caf(out_dir / "pla_bill.caf", bill_samples)

    # 4. pla_digest.caf (2.6s): soft morning sunrise arpeggio (C5-E5-G5-C6)
    digest_samples = render_notes(
        duration_sec=2.6,
        notes=[
            (0.02, 523.25, 0.60, 2.6),
            (0.22, 659.25, 0.65, 2.5),
            (0.42, 783.99, 0.70, 2.3),
            (0.66, 1046.50, 0.80, 1.9),
        ],
        harmonics=[(1.0, 1.0), (2.0, 0.20), (3.0, 0.05)],
    )
    write_caf(out_dir / "pla_digest.caf", digest_samples)

    for name in ["pla_default.caf", "pla_urgent.caf", "pla_bill.caf", "pla_digest.caf"]:
        p = out_dir / name
        print(f"Generated {p} ({p.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()

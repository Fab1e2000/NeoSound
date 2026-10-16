#!/usr/bin/env python3
"""生成 NeoSound 自有的合成测试素材：助眠音频（m4a）与 App 图标（png）。

全部由随机噪声合成，不含任何第三方内容。依赖 macOS 自带的 afconvert。
用法：python3 -I Tools/generate_assets.py
"""
import array
import math
import os
import random
import struct
import subprocess
import tempfile
import wave
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIO_DIR = os.path.join(ROOT, "NeoSound", "Resources", "Audio")
ICON_PATH = os.path.join(ROOT, "NeoSound", "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")
SR = 22050


def pink(n, rng):
    b0 = b1 = b2 = b3 = b4 = b5 = b6 = 0.0
    out = array.array("f", bytes(4 * n))
    for i in range(n):
        w = rng.random() * 2 - 1
        b0 = 0.99886 * b0 + w * 0.0555179
        b1 = 0.99332 * b1 + w * 0.0750759
        b2 = 0.96900 * b2 + w * 0.1538520
        b3 = 0.86650 * b3 + w * 0.3104856
        b4 = 0.55000 * b4 + w * 0.5329522
        b5 = -0.7616 * b5 - w * 0.0168980
        out[i] = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362
        b6 = w * 0.115926
    return out


def brown(n, rng, leak=0.997):
    y = 0.0
    out = array.array("f", bytes(4 * n))
    for i in range(n):
        y = leak * y + (rng.random() * 2 - 1) * 0.05
        out[i] = y
    return out


def lowpass(x, alpha):
    y = 0.0
    out = array.array("f", bytes(4 * len(x)))
    for i, v in enumerate(x):
        y += alpha * (v - y)
        out[i] = y
    return out


def add_bursts(buf, rng, rate, length_s, decay_s, amp_range, tone_hz=None):
    n = len(buf)
    t = 0.0
    duration = n / SR
    burst_len = int(length_s * SR)
    k = 1.0 / (decay_s * SR)
    while True:
        t += rng.expovariate(rate)
        if t >= duration:
            break
        start = int(t * SR)
        amp = rng.uniform(*amp_range)
        freq = rng.uniform(*tone_hz) if tone_hz else None
        for j in range(min(burst_len, n - start)):
            env = amp * math.exp(-j * k)
            if freq:
                s = math.sin(2 * math.pi * freq * j / SR) * 0.6 + (rng.random() * 2 - 1) * 0.4
            else:
                s = rng.random() * 2 - 1
            buf[start + j] += env * s


def finalize(x, target_rms=0.1, fade_s=3.0):
    n = len(x)
    mean = sum(x) / n
    rms = math.sqrt(sum((v - mean) ** 2 for v in x) / n) or 1.0
    gain = target_rms / rms
    fade = int(fade_s * SR)
    out = array.array("h", bytes(2 * n))
    for i in range(n):
        v = (x[i] - mean) * gain
        if i < fade:
            v *= i / fade
        elif i > n - fade:
            v *= (n - i) / fade
        v = max(-0.98, min(0.98, v))
        out[i] = int(v * 32767)
    return out


def rain(seconds, rng):
    n = seconds * SR
    base = pink(n, rng)
    low = lowpass(base, 0.08)
    buf = array.array("f", (base[i] - low[i] * 0.85 for i in range(n)))
    add_bursts(buf, rng, rate=35, length_s=0.012, decay_s=0.003, amp_range=(0.05, 0.35))
    add_bursts(buf, rng, rate=6, length_s=0.02, decay_s=0.005, amp_range=(0.1, 0.4), tone_hz=(1800, 4200))
    return buf


def waves(seconds, rng):
    n = seconds * SR
    body = lowpass(brown(n, rng, leak=0.999), 0.2)
    hiss = pink(n, rng)
    buf = array.array("f", bytes(4 * n))
    phase = 0.0
    period = 9.0
    for i in range(n):
        if i % SR == 0:
            period = max(7.0, min(12.0, period + rng.uniform(-0.4, 0.4)))
        phase += 1.0 / (period * SR)
        swell = 0.5 - 0.5 * math.cos(2 * math.pi * phase)
        env = 0.2 + 0.8 * swell * swell
        buf[i] = body[i] * env * 4 + hiss[i] * (swell ** 3) * 0.08
    return buf


def forest(seconds, rng):
    n = seconds * SR
    wind = lowpass(brown(n, rng, leak=0.998), 0.3)
    buf = array.array("f", bytes(4 * n))
    for i in range(n):
        t = i / SR
        gust = 0.65 + 0.35 * math.sin(2 * math.pi * t / 17.0) * math.sin(2 * math.pi * t / 6.3)
        buf[i] = wind[i] * gust
    return buf


def fire(seconds, rng):
    n = seconds * SR
    rumble = lowpass(brown(n, rng, leak=0.995), 0.15)
    buf = array.array("f", (v * 0.6 for v in rumble))
    add_bursts(buf, rng, rate=7, length_s=0.008, decay_s=0.0015, amp_range=(0.2, 1.0))
    add_bursts(buf, rng, rate=1.2, length_s=0.03, decay_s=0.006, amp_range=(0.3, 0.9))
    return buf


def write_m4a(name, samples):
    os.makedirs(AUDIO_DIR, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = os.path.join(tmp, name + ".wav")
        with wave.open(wav_path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(samples.tobytes())
        out = os.path.join(AUDIO_DIR, name + ".m4a")
        subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "64000", wav_path, out], check=True)
    print("wrote", out)


def write_icon(size=1024):
    bg = (0x17, 0x24, 0x3D)
    moon = (0xFF, 0x9F, 0x0A)
    cx1, cy1, r1 = 0.47 * size, 0.52 * size, 0.30 * size
    cx2, cy2, r2 = 0.60 * size, 0.42 * size, 0.25 * size
    rows = []
    for y in range(size):
        row = bytearray([0])
        for x in range(size):
            d1 = math.hypot(x + 0.5 - cx1, y + 0.5 - cy1)
            d2 = math.hypot(x + 0.5 - cx2, y + 0.5 - cy2)
            c1 = max(0.0, min(1.0, r1 - d1 + 0.5))
            c2 = max(0.0, min(1.0, r2 - d2 + 0.5))
            a = c1 * (1 - c2)
            row += bytes(int(bg[k] + (moon[k] - bg[k]) * a) for k in range(3))
        rows.append(bytes(row))
    raw = b"".join(rows)

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(ICON_PATH), exist_ok=True)
    with open(ICON_PATH, "wb") as f:
        f.write(png)
    print("wrote", ICON_PATH)


def main():
    rng = random.Random(20261016)
    write_icon()
    for name, fn, seconds in [
        ("rain", rain, 300),
        ("waves", waves, 300),
        ("forest", forest, 240),
        ("fire", fire, 240),
        ("pink", lambda s, r: pink(s * SR, r), 240),
    ]:
        write_m4a(name, finalize(fn(seconds, rng)))


if __name__ == "__main__":
    main()

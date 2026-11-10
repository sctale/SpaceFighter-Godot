#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""为 10 个星区生成 10 段可循环的「安静氛围」BGM（OGG Vorbis）。

设计目标：耐听、不刺耳——只用正弦，不用锯齿/方波主旋律，不要鼓点；
慢速（52-64 BPM）、长音 pad、轻低音、稀疏钟琴、极轻的噪声雾。
每区不同根音/调式/和弦，输出 assets/music/zone_01..10.ogg。
循环点 40ms 淡入淡出，峰值归一 0.55（背景音量）。

用法：python tools/gen_music.py [--out assets/music]
"""
import argparse
import math
import os
import subprocess
import tempfile
import wave

import numpy as np

SR = 44100
TAU = math.pi * 2

# 每区：文件名、标题、BPM、根音 MIDI、和弦进行（半音偏移）、亮度、回声
ZONES = [
    ("zone_01", "新曙光",   60, 57, [0, 9, 5, 7], 1.00, 0.10),
    ("zone_02", "玻璃海",   56, 60, [0, 5, 9, 7], 0.95, 0.18),
    ("zone_03", "紫电环",   64, 52, [0, 8, 3, 10], 1.05, 0.16),
    ("zone_04", "静默墓园", 52, 48, [0, 5, 8, 3], 0.80, 0.26),
    ("zone_05", "熔金带",   62, 53, [0, 7, 5, 9], 1.10, 0.12),
    ("zone_06", "零度之眼", 58, 55, [0, 8, 3, 7], 0.88, 0.28),
    ("zone_07", "回声廊",   54, 50, [0, 7, 5, 8], 0.92, 0.36),
    ("zone_08", "星屑风暴", 64, 59, [0, 9, 7, 5], 1.12, 0.14),
    ("zone_09", "虹吸井",   56, 48, [0, 3, 8, 5], 1.00, 0.30),
    ("zone_10", "无极之岸", 60, 45, [0, 7, 9, 5], 1.06, 0.20),
]

MAJOR = [0, 4, 7]
MINOR = [0, 3, 7]


def midi_freq(m):
    return 440.0 * (2.0 ** ((m - 69) / 12.0))


def _env(n, attack, release):
    a = max(1, min(int(attack * SR), n // 2))
    r = max(1, min(int(release * SR), n // 2))
    e = np.ones(n, dtype=np.float64)
    e[:a] = np.sin(np.linspace(0.0, math.pi * 0.5, a)) ** 2
    e[n - r:] = np.cos(np.linspace(0.0, math.pi * 0.5, r)) ** 2
    return e


def add_tone(buf, t0, dur, freq, amp, attack=1.4, release=2.2, detune=0.0):
    i0 = int(t0 * SR)
    n = min(int(dur * SR), buf.size - i0)
    if n <= 0:
        return
    t = np.arange(n) / SR
    w = np.sin(TAU * freq * t)
    if detune > 0.0:
        w = 0.62 * w + 0.38 * np.sin(TAU * freq * (1.0 + detune) * t + 0.7)
    buf[i0:i0 + n] += w * _env(n, attack, release) * amp


def add_noise_wash(buf, t0, dur, amp, seed=0):
    """极轻的低通噪声雾（FIR 平滑，不做逐样本循环）。"""
    i0 = int(t0 * SR)
    n = min(int(dur * SR), buf.size - i0)
    if n <= 0:
        return
    rng = np.random.default_rng(seed)
    white = rng.standard_normal(n)
    kernel = np.hanning(257)
    kernel /= kernel.sum()
    lp = np.convolve(white, kernel, mode="same")
    buf[i0:i0 + n] += lp * _env(n, dur * 0.45, dur * 0.5) * amp


def build_track(idx, title, bpm, root, progression, bright, echo):
    beat = 60.0 / bpm
    bar = beat * 4.0
    bars = 8
    total = int(bar * bars * SR)
    buf = np.zeros(total, dtype=np.float64)
    triad = MINOR if idx % 2 == 0 else MAJOR

    for b in range(bars):
        t0 = b * bar
        chord = progression[b % len(progression)]
        # pad：根音 + 三音 + 五音 + 高八度，持续两小节
        for semi in triad:
            add_tone(buf, t0, bar * 2.0 + 0.6,
                     midi_freq(root + chord + semi), 0.085 * bright,
                     attack=1.8, release=2.6, detune=0.0022)
        add_tone(buf, t0, bar * 2.0, midi_freq(root + chord + 12), 0.06 * bright,
                 attack=2.2, release=2.8, detune=0.0016)
        # bass：每两小节一个长音
        if b % 2 == 0:
            add_tone(buf, t0, bar * 2.0, midi_freq(root + chord - 12), 0.10,
                     attack=1.2, release=2.4)
        # 钟琴：每两拍一个和弦音，很轻
        for j in range(8):
            semi = triad[(b + j) % len(triad)]
            add_tone(buf, t0 + j * beat * 0.5, beat * 1.6,
                     midi_freq(root + chord + semi + 24), 0.020,
                     attack=0.02, release=beat * 1.4)
        # 噪声雾：每两小节一次极轻的涌
        if b % 2 == 0:
            add_noise_wash(buf, t0, bar * 2.0, 0.012, seed=idx * 31 + b)

    if echo > 0.0:
        d = int(0.23 * SR)
        wet = np.copy(buf)
        for n in range(1, 4):
            shifted = np.zeros_like(buf)
            shifted[d * n:] = buf[:-d * n] * (echo ** n) * 0.4
            wet += shifted
        buf = wet

    # 循环点 40ms 淡入淡出 + 峰值归一 0.55（背景音量）
    edge = int(0.040 * SR)
    buf[:edge] *= np.linspace(0.0, 1.0, edge)
    buf[-edge:] *= np.linspace(1.0, 0.0, edge)
    peak = float(np.max(np.abs(buf)))
    if peak > 0.0:
        buf = buf / peak * 0.55
    return buf.astype(np.float32)


def write_ogg(samples, out_path, tmp_dir):
    pcm = (np.clip(samples, -1.0, 1.0) * 32767.0).astype(np.int16)
    wav_path = os.path.join(tmp_dir, os.path.basename(out_path) + ".wav")
    with wave.open(wav_path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path,
         "-c:a", "libvorbis", "-q:a", "3", "-ar", str(SR), out_path],
        check=True,
    )
    os.remove(wav_path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="assets/music")
    args = ap.parse_args()
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = args.out if os.path.isabs(args.out) else os.path.join(root_dir, args.out)
    os.makedirs(out_dir, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for i, (name, title, bpm, root, prog, bright, echo) in enumerate(ZONES):
            buf = build_track(i, title, bpm, root, prog, bright, echo)
            path = os.path.join(out_dir, name + ".ogg")
            write_ogg(buf, path, tmp)
            print("MUSIC", name, title, "%.1fs" % (buf.size / SR),
                  "%d KB" % (os.path.getsize(path) // 1024))


if __name__ == "__main__":
    main()

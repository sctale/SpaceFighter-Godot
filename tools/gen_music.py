#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""为 10 个星区生成 10 段可循环的合成器 BGM（OGG Vorbis）。

不依赖任何版权素材：pad / bass / arp / lead / drums 全部用 numpy 加法合成，
每区不同的调式、速度、音色与回声，输出 assets/music/zone_01..10.ogg。
循环点做 20ms 淡入淡出，避免爆音。

用法：
  python tools/gen_music.py [--out assets/music]
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

# 每区：文件名、标题、BPM、根音 MIDI、调式、四和弦进行、音色亮度、回声
ZONES = [
    ("zone_01", "新曙光",   96, 57, "major", [0, 5, 7, 0], 1.00, 0.00),
    ("zone_02", "玻璃海",   84, 64, "major", [0, 7, 5, 9], 0.90, 0.15),
    ("zone_03", "紫电环",  112, 50, "minor", [0, 3, 7, 5], 1.10, 0.22),
    ("zone_04", "静默墓园",  72, 48, "minor", [0, 8, 5, 3], 0.75, 0.30),
    ("zone_05", "熔金带",  120, 53, "major", [0, 4, 9, 5], 1.20, 0.10),
    ("zone_06", "零度之眼",  90, 59, "minor", [0, 7, 3, 8], 0.85, 0.35),
    ("zone_07", "回声廊",  100, 55, "minor", [0, 5, 8, 3], 0.95, 0.55),
    ("zone_08", "星屑风暴", 126, 57, "major", [0, 9, 5, 7], 1.25, 0.18),
    ("zone_09", "虹吸井",  108, 54, "minor", [0, 3, 8, 5], 1.05, 0.42),
    ("zone_10", "无极之岸", 132, 50, "major", [0, 7, 9, 5], 1.15, 0.25),
]

MODES = {"major": [0, 4, 7], "minor": [0, 3, 7]}


def midi_freq(m):
    return 440.0 * (2.0 ** ((m - 69) / 12.0))


def osc(kind, freq, t, bright=1.0, phase=0.0):
    if kind == "sine":
        return np.sin(TAU * freq * t + phase)
    if kind == "triangle":
        return 2.0 / math.pi * np.arcsin(np.sin(TAU * freq * t + phase))
    if kind == "square":
        return np.tanh(np.sin(TAU * freq * t + phase) * 3.0)
    # saw：整数谐波叠加，bright 控制高频
    s = np.zeros_like(t)
    for k in range(1, 7):
        s += np.sin(TAU * freq * k * t + phase) * (bright ** (k - 1)) / k
    return s


def add_note(buf, t0, dur, freq, amp, kind="sine", bright=1.0, phase=0.0):
    i0 = int(t0 * SR)
    n = int(dur * SR)
    if i0 < 0:
        n += i0
        i0 = 0
    if n <= 0 or i0 >= buf.size:
        return
    n = min(n, buf.size - i0)
    t = np.arange(n) / SR
    env = np.minimum(1.0, t / 0.018) * np.minimum(1.0, (dur - t) / 0.10)
    env = np.clip(env, 0.0, 1.0)
    buf[i0:i0 + n] += osc(kind, freq, t, bright, phase) * env * amp


def add_kick(buf, t0, amp):
    dur = 0.14
    i0 = int(t0 * SR)
    n = min(int(dur * SR), buf.size - i0)
    if n <= 0:
        return
    t = np.arange(n) / SR
    f = 130.0 * np.exp(-t * 18.0) + 42.0
    buf[i0:i0 + n] += np.sin(TAU * np.cumsum(f) / SR) * np.exp(-t * 22.0) * amp


def add_noise(buf, t0, dur, amp, decay=40.0, tone=0.0, seed=0):
    rng = np.random.default_rng(seed)
    i0 = int(t0 * SR)
    n = min(int(dur * SR), buf.size - i0)
    if n <= 0:
        return
    t = np.arange(n) / SR
    noise = rng.uniform(-1.0, 1.0, n)
    noise = np.diff(np.concatenate(([0.0], noise)))  # 简易高通，更像镲片
    env = np.exp(-t * decay)
    buf[i0:i0 + n] += noise * env * amp
    if tone > 0.0:
        buf[i0:i0 + n] += np.sin(TAU * tone * t) * env * amp * 0.45


def build_track(idx, title, bpm, root, mode, prog, bright, echo):
    beat = 60.0 / bpm
    bar = beat * 4.0
    bars = 16
    total = bar * bars
    buf = np.zeros(int(total * SR) + 1, dtype=np.float64)
    triad = MODES[mode]
    rng = np.random.default_rng(1000 + idx)

    for b in range(bars):
        t0 = b * bar
        chord = prog[b % len(prog)]
        # pad：三音和弦，慢起音
        for k, off in enumerate(triad):
            add_note(buf, t0, bar * 0.96, midi_freq(root + chord + off),
                    0.075, "triangle", bright, phase=k * 0.4)
        # bass：每小节 1、3 拍，根音低八度
        for beat_i in (0, 2):
            add_note(buf, t0 + beat_i * beat, beat * 0.8,
                    midi_freq(root + chord - 12), 0.16, "square", 0.8)
        # arp：八分音符循环和弦音
        pattern = [0, 1, 2, 1]
        for j in range(8):
            note = triad[pattern[j % 4]]
            add_note(buf, t0 + j * beat * 0.5, beat * 0.42,
                    midi_freq(root + chord + note + 12), 0.045, "sine", 1.0,
                    phase=(j % 2) * math.pi)
        # 鼓：底鼓 1/3 拍；镲反拍；偶数小节加军鼓
        add_kick(buf, t0, 0.20)
        add_kick(buf, t0 + beat * 2.0, 0.17)
        for j in range(4):
            add_noise(buf, t0 + (j * 2 + 1) * beat * 0.5, 0.05, 0.030,
                      decay=55.0, seed=idx * 97 + b * 13 + j)
        if b % 2 == 1:
            add_noise(buf, t0 + beat, 0.10, 0.045, decay=26.0, tone=190.0,
                      seed=idx * 71 + b)
        # lead：第 4/8/12/16 小节进入，2 小节一句
        if b % 4 == 0:
            phrase = [0, 2, 4, 2, 5, 4, 2, 0]
            for j, deg in enumerate(phrase):
                scale = [0, 2, 4, 5, 7, 9, 11]
                off = scale[deg % 7] + (12 if deg >= 7 else 0)
                add_note(buf, t0 + j * beat * 0.5, beat * 0.46,
                        midi_freq(root + chord + off + 12), 0.060,
                        "saw" if b % 8 == 0 else "square", bright * 0.9,
                        phase=j * 0.25)

    if echo > 0.0:
        d = int(0.19 * SR)
        wet = np.copy(buf)
        for n in range(1, 4):
            shifted = np.zeros_like(buf)
            shifted[d * n:] = buf[:-d * n] * (echo ** n) * 0.45
            wet += shifted
        buf = wet

    # 循环点 20ms 淡入淡出 + 峰值归一
    edge = int(0.020 * SR)
    if edge > 0:
        buf[:edge] *= np.linspace(0.0, 1.0, edge)
        buf[-edge:] *= np.linspace(1.0, 0.0, edge)
    peak = float(np.max(np.abs(buf)))
    if peak > 0.0:
        buf = buf / peak * 0.86
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
        for i, (name, title, bpm, root, mode, prog, bright, echo) in enumerate(ZONES):
            buf = build_track(i, title, bpm, root, mode, prog, bright, echo)
            path = os.path.join(out_dir, name + ".ogg")
            write_ogg(buf, path, tmp)
            print("MUSIC", name, title, "%.1fs" % (buf.size / SR),
                  "%d KB" % (os.path.getsize(path) // 1024))


if __name__ == "__main__":
    main()

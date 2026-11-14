#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""为 10 个星区生成 10 段可循环 BGM（OGG Vorbis，立体声）。

v1.10.0 重做：不再是「纯正弦氛围垫」，改为 10 种可辨识风格的合成器编曲——
鼓组（kick/snare/hat/tom/timpani/metal）、有律动的贝斯、琶音、铜管 stab、
主题旋律、立体声铺底、回声/多抽头混响。BPM 84-126，每区 16 小节，
和声/配器/节奏型各不相同，但都保持柔和音头与低峰值，适合当背景音乐循环。

用法：python tools/gen_music.py [--out assets/music] [--only zone_03]
"""
import argparse
import math
import os
import subprocess
import tempfile
import wave

import numpy as np

SR = 44100
TAU = math.pi * 2.0

MAJOR = [0, 2, 4, 5, 7, 9, 11]
MINOR = [0, 2, 3, 5, 7, 8, 10]
DORIAN = [0, 2, 3, 5, 7, 9, 10]
SCALES = {"major": MAJOR, "minor": MINOR, "dorian": DORIAN}
TRIADS = {"maj": [0, 4, 7], "min": [0, 3, 7]}

# 每区: 文件名、标题、BPM、根音 MIDI、调式、和弦进行（相对根音的半音）、
# 亮度、回声湿度、配器参数
ZONES = [
    # 1 新曙光：明亮大调 + 4/4 轻鼓 + 主题旋律
    {"name": "zone_01", "title": "新曙光", "bpm": 112, "root": 60, "scale": "major",
     "prog": [0, 7, 9, 5], "quals": ["maj", "maj", "min", "maj"],
     "bright": 1.00, "echo": 0.16,
     "pad": 0.075, "bass": ("eighths", 0.105), "arp": ("8", 0.046),
     "drums": {"kick": [0.0, 2.0], "snare": [1.0, 3.0], "hat": 0.5},
     "lead": 0.052, "shimmer": 0.0},
    # 2 玻璃海：大调三连音琶音 + 玻璃钟琴
    {"name": "zone_02", "title": "玻璃海", "bpm": 96, "root": 57, "scale": "major",
     "prog": [0, 9, 5, 7], "quals": ["maj", "min", "maj", "maj"],
     "bright": 0.96, "echo": 0.30,
     "pad": 0.070, "bass": ("whole", 0.095), "arp": ("triplet", 0.044),
     "drums": {"kick": [0.0, 2.0], "rim": [1.0, 3.0], "hat": 0.75},
     "lead": 0.044, "shimmer": 0.022},
    # 3 紫电环：合成器波，16 分泵动贝斯 + 门限和弦
    {"name": "zone_03", "title": "紫电环", "bpm": 124, "root": 53, "scale": "minor",
     "prog": [0, 8, 3, 10], "quals": ["min", "maj", "maj", "maj"],
     "bright": 1.04, "echo": 0.18,
     "pad": 0.062, "bass": ("drive", 0.115), "arp": ("16", 0.038),
     "drums": {"kick": [0.0, 1.0, 2.0, 3.0], "snare": [1.0, 3.0], "hat": 0.25},
     "lead": 0.046, "shimmer": 0.0, "gate": 0.052},
    # 4 静默墓园：慢速、稀疏心跳鼓、低音持续音与远处钟声
    {"name": "zone_04", "title": "静默墓园", "bpm": 84, "root": 48, "scale": "minor",
     "prog": [0, 5, 3, 10], "quals": ["min", "min", "maj", "maj"],
     "bright": 0.72, "echo": 0.42,
     "pad": 0.088, "bass": ("whole", 0.105), "arp": ("off", 0.0),
     "drums": {"kick": [0.0, 2.5], "timpani": [3.5], "metal": [1.75]},
     "lead": 0.0, "shimmer": 0.020},
    # 5 熔金带：多利亚英雄主题，行军鼓与铜管 stab
    {"name": "zone_05", "title": "熔金带", "bpm": 124, "root": 50, "scale": "dorian",
     "prog": [0, 5, 10, 3], "quals": ["min", "maj", "maj", "maj"],
     "bright": 1.08, "echo": 0.14,
     "pad": 0.068, "bass": ("eighths", 0.110), "arp": ("off", 0.0),
     "drums": {"kick": [0.0, 1.0, 2.0, 3.0], "snare": [1.0, 3.0], "hat": 0.5,
               "tom": [3.75]},
     "lead": 0.058, "shimmer": 0.0, "stab": 0.038},
    # 6 零度之眼：冰晶 16 分琶音，无底鼓，只有细碎高频
    {"name": "zone_06", "title": "零度之眼", "bpm": 100, "root": 59, "scale": "minor",
     "prog": [0, 3, 8, 10], "quals": ["min", "maj", "maj", "maj"],
     "bright": 0.92, "echo": 0.36,
     "pad": 0.072, "bass": ("whole", 0.085), "arp": ("16", 0.044),
     "drums": {"kick": [0.0], "rim": [2.0], "hat": 0.5, "metal": [3.0]},
     "lead": 0.042, "shimmer": 0.026},
    # 7 回声廊：Dub 式切分贝斯 + 反拍拨弦 + 大回声
    {"name": "zone_07", "title": "回声廊", "bpm": 104, "root": 52, "scale": "minor",
     "prog": [0, 10, 8, 5], "quals": ["min", "maj", "maj", "min"],
     "bright": 0.90, "echo": 0.46,
     "pad": 0.064, "bass": ("sync", 0.118), "arp": ("off", 0.0),
     "drums": {"kick": [0.0, 2.5], "rim": [1.0, 3.0], "hat": 0.5},
     "lead": 0.042, "shimmer": 0.016, "skank": 0.040},
    # 8 星屑风暴：高速战斗曲，16 分琶音 + 密集鼓组 + 旋律
    {"name": "zone_08", "title": "星屑风暴", "bpm": 142, "root": 57, "scale": "minor",
     "prog": [0, 8, 3, 10], "quals": ["min", "maj", "maj", "maj"],
     "bright": 1.10, "echo": 0.16,
     "pad": 0.060, "bass": ("pulse", 0.112), "arp": ("16", 0.048),
     "drums": {"kick": [0.0, 1.0, 2.0, 2.5, 3.0], "snare": [1.0, 3.0], "hat": 0.25},
     "lead": 0.050, "shimmer": 0.0},
    # 9 虹吸井：工业金属，金属敲击 + 半拍底鼓 + 不协和铺底
    {"name": "zone_09", "title": "虹吸井", "bpm": 116, "root": 55, "scale": "minor",
     "prog": [0, 3, 8, 10], "quals": ["min", "maj", "maj", "maj"],
     "bright": 0.88, "echo": 0.24,
     "pad": 0.076, "bass": ("sync", 0.118), "arp": ("gallop", 0.036),
     "drums": {"kick": [0.0, 1.5, 2.5], "snare": [1.0, 3.0], "hat": 0.5,
               "metal": [0.75, 2.25], "tom": [3.5]},
     "lead": 0.044, "shimmer": 0.0, "tension": True},
    # 10 无极之岸：终章史诗，管风琴铺底 + 定音鼓 + 慢主题
    {"name": "zone_10", "title": "无极之岸", "bpm": 96, "root": 49, "scale": "minor",
     "prog": [0, 5, 8, 10], "quals": ["min", "min", "maj", "maj"],
     "bright": 1.02, "echo": 0.30,
     "pad": 0.082, "bass": ("whole", 0.110), "arp": ("8", 0.040),
     "drums": {"timpani": [0.0, 2.0], "kick": [0.0, 2.0],
               "snare": [1.0, 3.0], "hat": 1.0},
     "lead": 0.056, "shimmer": 0.018, "organ": 0.040},
]

# 4 小节旋律短句（起始拍、音阶级数、时值拍），A/B 两段
MELODIES = {
    "zone_01": (
        [(0.0, 4, 1.0), (1.0, 5, 1.0), (2.0, 7, 1.5), (3.5, 6, 0.5),
         (4.0, 4, 1.0), (5.0, 2, 1.0), (6.0, 4, 2.0)],
        [(0.0, 7, 0.75), (0.75, 6, 0.75), (1.5, 5, 0.5), (2.0, 4, 1.0),
         (3.0, 5, 1.0), (4.0, 6, 0.75), (4.75, 7, 0.75), (5.5, 8, 1.0),
         (6.5, 7, 1.5)],
    ),
    "zone_05": (
        [(0.0, 4, 0.5), (0.5, 4, 0.5), (1.0, 2, 1.0), (2.0, 4, 1.0),
         (3.0, 5, 1.0), (4.0, 7, 2.0), (6.0, 5, 1.0), (7.0, 4, 1.0)],
        [(0.0, 7, 1.0), (1.0, 8, 1.0), (2.0, 7, 1.0), (3.0, 5, 1.0),
         (4.0, 6, 1.5), (5.5, 5, 0.5), (6.0, 4, 2.0)],
    ),
    "zone_08": (
        [(0.0, 7, 0.5), (0.5, 6, 0.5), (1.0, 5, 0.5), (1.5, 4, 0.5),
         (2.0, 5, 1.0), (3.0, 7, 1.0), (4.0, 8, 0.5), (4.5, 7, 0.5),
         (5.0, 5, 1.0), (6.0, 4, 1.0), (7.0, 5, 1.0)],
        [(0.0, 4, 0.5), (0.5, 5, 0.5), (1.0, 7, 0.5), (1.5, 8, 0.5),
         (2.0, 9, 1.0), (3.0, 7, 1.0), (4.0, 5, 0.5), (4.5, 4, 0.5),
         (5.0, 5, 2.0), (7.0, 2, 1.0)],
    ),
    "zone_02": (
        [(0.0, 7, 1.0), (1.0, 8, 0.5), (1.5, 7, 0.5), (2.0, 6, 1.0), (3.0, 5, 1.0),
         (4.0, 4, 1.5), (5.5, 6, 0.5), (6.0, 7, 2.0)],
        [(0.0, 4, 0.5), (0.5, 5, 0.5), (1.0, 6, 0.5), (1.5, 7, 0.5), (2.0, 8, 2.0),
         (4.0, 7, 1.0), (5.0, 6, 1.0), (6.0, 5, 2.0)],
    ),
    "zone_03": (
        [(0.0, 7, 0.5), (0.5, 7, 0.5), (1.0, 6, 0.5), (1.5, 5, 0.5), (2.0, 4, 1.0),
         (3.0, 5, 1.0), (4.0, 7, 1.0), (5.0, 8, 1.0), (6.0, 7, 2.0)],
        [(0.0, 4, 1.0), (1.0, 7, 1.0), (2.0, 8, 1.0), (3.0, 7, 1.0),
         (4.0, 6, 1.0), (5.0, 5, 1.0), (6.0, 4, 2.0)],
    ),
    "zone_06": (
        [(0.0, 8, 2.0), (2.0, 7, 1.0), (3.0, 5, 1.0),
         (4.0, 6, 1.0), (5.0, 7, 1.0), (6.0, 8, 2.0)],
        [(0.0, 6, 1.0), (1.0, 8, 1.0), (2.0, 9, 2.0),
         (4.0, 7, 1.0), (5.0, 6, 1.0), (6.0, 5, 2.0)],
    ),
    "zone_07": (
        [(0.0, 5, 0.75), (0.75, 4, 0.75), (1.5, 5, 0.5), (2.0, 7, 1.0), (3.0, 6, 1.0),
         (4.0, 5, 1.5), (5.5, 4, 0.5), (6.0, 2, 2.0)],
        [(0.0, 7, 1.0), (1.0, 8, 1.0), (2.0, 7, 1.0), (3.0, 5, 1.0),
         (4.0, 4, 2.0), (6.0, 5, 2.0)],
    ),
    "zone_09": (
        [(0.0, 4, 0.5), (0.5, 4, 0.5), (1.0, 5, 0.5), (1.5, 4, 0.5), (2.0, 2, 1.0),
         (3.0, 4, 1.0), (4.0, 5, 1.0), (5.0, 7, 1.0), (6.0, 4, 2.0)],
        [(0.0, 7, 0.5), (0.5, 6, 0.5), (1.0, 5, 0.5), (1.5, 4, 0.5), (2.0, 2, 2.0),
         (4.0, 4, 1.0), (5.0, 5, 1.0), (6.0, 7, 2.0)],
    ),
    "zone_10": (
        [(0.0, 4, 2.0), (2.0, 5, 1.0), (3.0, 7, 1.0),
         (4.0, 6, 2.0), (6.0, 4, 2.0)],
        [(0.0, 7, 1.0), (1.0, 8, 1.0), (2.0, 7, 1.0), (3.0, 5, 1.0),
         (4.0, 4, 2.0), (6.0, 2, 2.0)],
    ),
}


# ---------------------------------------------------------------- 基础合成

def midi_freq(m):
    return 440.0 * (2.0 ** ((m - 69) / 12.0))


def _env(n, attack, release, sustain=1.0):
    """线性起音 + 余弦收尾的持续包络。"""
    a = max(1, min(int(attack * SR), n // 2))
    r = max(1, min(int(release * SR), n // 2))
    e = np.full(n, sustain, dtype=np.float64)
    e[:a] = np.sin(np.linspace(0.0, math.pi * 0.5, a)) ** 2 * sustain
    e[n - r:] = np.cos(np.linspace(0.0, math.pi * 0.5, r)) ** 2 * sustain
    return e


def _perc(n, decay, attack=0.002):
    """打击/拨弦包络：指数衰减。"""
    t = np.arange(n) / SR
    e = np.exp(-t / max(0.004, decay))
    a = max(1, int(attack * SR))
    e[:a] *= np.linspace(0.0, 1.0, a)
    return e


def _osc(freq, n, harms=6, tilt=1.5, detune=0.0, phase0=0.0):
    """加性带限振荡器（避免混叠），谐波按 1/k^tilt 衰减。"""
    t = np.arange(n) / SR
    w = np.zeros(n, dtype=np.float64)
    base = freq * (1.0 + detune)
    for k in range(1, harms + 1):
        f = base * k
        if f >= SR * 0.45:
            break
        w += np.sin(TAU * f * t + phase0 * k) / (k ** tilt)
    return w


def _add(buf, t0, wave, gain=1.0, pan=0.0):
    """按等功率声像写入立体声缓冲（越界自动裁剪）。"""
    i0 = int(round(t0 * SR))
    if i0 < 0:
        wave = wave[-i0:]
        i0 = 0
    n = min(wave.size, buf.shape[1] - i0)
    if n <= 0:
        return
    gl = math.sqrt((1.0 - pan) * 0.5)
    gr = math.sqrt((1.0 + pan) * 0.5)
    buf[0, i0:i0 + n] += wave[:n] * gain * gl
    buf[1, i0:i0 + n] += wave[:n] * gain * gr


# ---------------------------------------------------------------- 乐器

def pad(buf, t0, dur, midi, amp, bright=1.0, pan=0.0):
    """慢起音铺底：双失谐正弦 + 少量奇次谐波。"""
    n = int(dur * SR)
    if n <= 8:
        return
    f = midi_freq(midi)
    w = _osc(f * 0.9975, n, 4, 1.9, 0.0)
    w += _osc(f * 1.0025, n, 4, 1.9, 0.0, phase0=0.9)
    w *= _env(n, min(1.5, dur * 0.3), min(2.2, dur * 0.45))
    _add(buf, t0, w, amp * 0.5 * bright, pan)


def organ(buf, t0, dur, midi, amp, pan=0.0):
    """终章管风琴：1/2/3/4 次谐波持续音。"""
    n = int(dur * SR)
    if n <= 8:
        return
    f = midi_freq(midi)
    t = np.arange(n) / SR
    w = (np.sin(TAU * f * t) + 0.45 * np.sin(TAU * 2 * f * t) +
         0.22 * np.sin(TAU * 3 * f * t) + 0.12 * np.sin(TAU * 4 * f * t))
    w *= _env(n, 0.35, min(1.2, dur * 0.4))
    _add(buf, t0, w, amp * 0.55, pan)


def bass(buf, t0, dur, midi, amp, kind="round"):
    """贝斯：正弦根音 + 轻谐波；sub 更闷，drive 更亮。"""
    n = int(dur * SR)
    if n <= 8:
        return
    f = midi_freq(midi)
    t = np.arange(n) / SR
    if kind == "sub":
        w = np.sin(TAU * f * t) + 0.12 * np.sin(TAU * 2 * f * t)
    elif kind == "drive":
        w = 0.62 * np.sin(TAU * f * t) + 0.38 * _osc(f, n, 6, 1.35)
    else:
        w = 0.78 * np.sin(TAU * f * t) + 0.22 * _osc(f, n, 4, 1.9)
    w *= _env(n, 0.006, min(0.18, dur * 0.45))
    _add(buf, t0, w, amp)


def pluck(buf, t0, dur, midi, amp, pan=0.0, decay=0.26, harms=4):
    """拨弦/钟琴：短促指数衰减。"""
    n = int(dur * SR)
    if n <= 8:
        return
    w = _osc(midi_freq(midi), n, harms, 1.65)
    w *= _perc(n, decay, 0.003)
    _add(buf, t0, w, amp, pan)


def bell(buf, t0, dur, midi, amp, pan=0.0, decay=0.9):
    """非谐波钟声（玻璃海/零度之眼/墓园远景）。"""
    n = int(dur * SR)
    if n <= 8:
        return
    f = midi_freq(midi)
    t = np.arange(n) / SR
    w = np.zeros(n, dtype=np.float64)
    for k, a in ((1.0, 1.0), (2.01, 0.5), (3.02, 0.28), (4.07, 0.14), (5.41, 0.07)):
        if f * k < SR * 0.45:
            w += a * np.sin(TAU * f * k * t)
    w *= _perc(n, decay, 0.004)
    _add(buf, t0, w, amp * 0.7, pan)


def lead(buf, t0, dur, midi, amp, pan=0.0):
    """主旋律：带轻微颤音的窄带锯齿。"""
    n = int(dur * SR)
    if n <= 8:
        return
    f = midi_freq(midi)
    t = np.arange(n) / SR
    vib = 1.0 + 0.0045 * np.sin(TAU * 5.1 * t) * np.clip(t * 4.0, 0.0, 1.0)
    phase = TAU * np.cumsum(f * vib) / SR
    w = np.zeros(n, dtype=np.float64)
    for k in range(1, 7):
        if f * k < SR * 0.45:
            w += np.sin(k * phase) / (k ** 1.45)
    w *= _env(n, 0.025, min(0.35, dur * 0.5))
    _add(buf, t0, w, amp * 0.62, pan)


def stab(buf, t0, dur, midi, amp, pan=0.0):
    """铜管式和弦短音。"""
    n = int(dur * SR)
    if n <= 8:
        return
    w = _osc(midi_freq(midi), n, 8, 1.25)
    w *= _env(n, 0.018, min(0.22, dur * 0.6))
    _add(buf, t0, w, amp * 0.55, pan)


# ---------------------------------------------------------------- 鼓组

def _noise(n, rng):
    return rng.standard_normal(n)


def drum_kick(buf, t0, amp, rng):
    n = int(0.34 * SR)
    t = np.arange(n) / SR
    f = 118.0 * np.exp(-t * 26.0) + 46.0
    w = np.sin(TAU * np.cumsum(f) / SR) * np.exp(-t * 9.0)
    w += _noise(n, rng) * np.exp(-t * 190.0) * 0.25
    _add(buf, t0, w, amp)


def drum_snare(buf, t0, amp, rng):
    n = int(0.24 * SR)
    t = np.arange(n) / SR
    nz = _noise(n, rng)
    hp = np.diff(nz, prepend=0.0)
    w = hp * np.exp(-t * 24.0) * 0.55 + np.sin(TAU * 186.0 * t) * np.exp(-t * 32.0) * 0.4
    _add(buf, t0, w, amp)


def drum_hat(buf, t0, amp, rng, decay=0.032, pan=0.18):
    n = int(0.16 * SR)
    t = np.arange(n) / SR
    nz = _noise(n, rng)
    hp = np.diff(np.diff(nz, prepend=0.0), prepend=0.0)
    w = hp * np.exp(-t / decay)
    _add(buf, t0, w, amp * 0.5, pan)


def drum_rim(buf, t0, amp, rng):
    n = int(0.09 * SR)
    t = np.arange(n) / SR
    w = (_noise(n, rng) * np.exp(-t * 120.0) * 0.55 +
         np.sin(TAU * 1180.0 * t) * np.exp(-t * 55.0) * 0.45)
    _add(buf, t0, w, amp * 0.6, -0.25)


def drum_tom(buf, t0, amp, rng, pan=0.3):
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    f = 165.0 * np.exp(-t * 8.0) + 92.0
    w = np.sin(TAU * np.cumsum(f) / SR) * np.exp(-t * 10.0)
    w += _noise(n, rng) * np.exp(-t * 90.0) * 0.18
    _add(buf, t0, w, amp * 0.8, pan)


def drum_timpani(buf, t0, amp, rng):
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    f = 102.0 * np.exp(-t * 3.4) + 68.0
    w = np.sin(TAU * np.cumsum(f) / SR) * np.exp(-t * 4.2)
    w += _noise(n, rng) * np.exp(-t * 40.0) * 0.22
    _add(buf, t0, w, amp, 0.0)


def drum_metal(buf, t0, amp, rng):
    """工业金属敲击：非谐波分音 + 噪声瞬态。"""
    n = int(0.34 * SR)
    t = np.arange(n) / SR
    f = 218.0
    w = np.zeros(n, dtype=np.float64)
    for k in (1.0, 2.37, 3.61, 4.83, 6.19):
        w += np.sin(TAU * f * k * t) * (1.0 / k)
    w *= _perc(n, 0.11, 0.001)
    w += _noise(n, rng) * np.exp(-t * 140.0) * 0.25
    _add(buf, t0, w, amp * 0.55, -0.12)


# ---------------------------------------------------------------- 编曲

SCALE_ORDER = {"major": MAJOR, "minor": MINOR, "dorian": DORIAN}


def scale_note(root, scale, degree):
    sc = SCALE_ORDER[scale]
    octave = degree // 7
    return root + sc[degree % 7] + 12 * octave


def play_drums(buf, spec, t_bar, beat, bar_index, rng, energy=1.0):
    """按 4/4 小节铺鼓组；后半段（bar 8-15）加花。"""
    jitter = 1.0 + 0.06 * ((bar_index % 4) == 3)
    for pos in spec.get("kick", []):
        if pos < 4.0:
            drum_kick(buf, t_bar + pos * beat, 0.30 * energy * jitter, rng)
    for pos in spec.get("snare", []):
        drum_snare(buf, t_bar + pos * beat, 0.15 * energy, rng)
        if bar_index % 8 == 7 and pos >= 3.0:
            drum_snare(buf, t_bar + (pos + 0.25) * beat, 0.08 * energy, rng)
            drum_snare(buf, t_bar + (pos + 0.5) * beat, 0.10 * energy, rng)
    hat = float(spec.get("hat", 0.0))
    if hat > 0.0:
        steps = int(round(4.0 / hat))
        for i in range(steps):
            pos = i * hat
            accent = 1.0 if abs(pos - round(pos)) < 1e-6 else 0.72
            extra = 0.78 if bar_index < 8 else 1.0
            drum_hat(buf, t_bar + pos * beat, 0.095 * accent * extra, rng)
    for pos in spec.get("rim", []):
        drum_rim(buf, t_bar + pos * beat, 0.12, rng)
    for pos in spec.get("tom", []):
        drum_tom(buf, t_bar + pos * beat, 0.16, rng,
                 pan=0.3 if bar_index % 2 == 0 else -0.3)
    for pos in spec.get("timpani", []):
        drum_timpani(buf, t_bar + pos * beat, 0.22, rng)
    for pos in spec.get("metal", []):
        drum_metal(buf, t_bar + pos * beat, 0.12, rng)
    # 每 8 小节最后一拍加一个通鼓过门
    if bar_index % 8 == 7:
        for i in range(3):
            drum_tom(buf, t_bar + (3.0 + i * 0.25) * beat, 0.10 + i * 0.03, rng,
                     pan=-0.35 + i * 0.35)


def play_bass(buf, pattern, level, root_midi, chord, beat, t_bar):
    """贝斯律动：whole / eighths / drive / sync / pulse。"""
    base = root_midi + chord - 12
    if pattern == "whole":
        bass(buf, t_bar, beat * 3.9, base, level, "sub")
    elif pattern == "eighths":
        for i in range(8):
            note = base if i % 4 != 3 else base + 7
            bass(buf, t_bar + i * beat * 0.5, beat * 0.46, note,
                 level * (1.0 if i % 2 == 0 else 0.86))
    elif pattern == "drive":
        seq = [0, 0, 12, 0, 0, 12, 7, 0]
        for i in range(8):
            bass(buf, t_bar + i * beat * 0.5, beat * 0.42, base + seq[i],
                 level * (1.0 if i % 2 == 0 else 0.82), "drive")
    elif pattern == "sync":
        for pos, dur in ((0.0, 0.7), (0.75, 0.4), (1.5, 0.7), (2.5, 0.5), (3.25, 0.5)):
            note = base + (7 if pos >= 2.5 else 0)
            bass(buf, t_bar + pos * beat, dur * beat, note, level, "round")
    elif pattern == "pulse":
        for i in range(16):
            note = base + (12 if i % 4 == 2 else 0)
            bass(buf, t_bar + i * beat * 0.25, beat * 0.2, note,
                 level * (0.95 if i % 4 == 0 else 0.7), "drive")


def play_arp(buf, pattern, level, root_midi, triad, chord, bar, beat, t_bar):
    """琶音：8 / 16 / triplet / gallop；音序在 3 个和弦音上往返。"""
    if pattern == "off":
        return
    chord_tones = [root_midi + chord + x + 12 for x in triad]
    order = [0, 1, 2, 2, 1, 0]
    if pattern == "8":
        steps, step_beats = 8, 0.5
    elif pattern == "16":
        steps, step_beats = 16, 0.25
    elif pattern == "triplet":
        steps, step_beats = 12, 1.0 / 3.0
    else:  # gallop：每拍 x . xx
        steps, step_beats = 16, 0.25
    for i in range(steps):
        if pattern == "gallop" and i % 4 == 1:
            continue
        pos = i * step_beats
        note = chord_tones[order[i % len(order)]] + 12
        amp = level * (0.8 if i % 2 else 1.0)
        pan = 0.28 if i % 2 == 0 else -0.28
        octave_shift = 12 if bar >= 8 and pattern in ("16", "8") else 0
        pluck(buf, t_bar + pos * beat, step_beats * beat * 1.8,
              note + octave_shift, amp, pan, decay=0.22)


# ---------------------------------------------------------------- 效果与渲染

def add_echo(buf, delay_s, feedback, wet):
    """立体声反馈回声：左右延迟略有差异，制造宽度。"""
    d = int(delay_s * SR)
    if d <= 0:
        return
    dry = buf.copy()
    for ch, mul in ((0, 1.0), (1, 1.07)):
        src = dry[ch]
        dd = int(d * mul)
        for n in range(1, 4):
            shift = dd * n
            if shift >= src.size:
                break
            buf[ch, shift:] += src[:-shift] * (feedback ** n) * wet
    # 左右交叉一点点，回声不贴耳
    cross = buf[1].copy()
    buf[0] += cross * 0.06
    buf[1] += dry[0] * 0.06


def add_reverb(buf, wet):
    """多抽头短混响（Schroeder 风格近似），成本低且不糊。"""
    taps = ((0.031, 0.30), (0.047, 0.24), (0.071, 0.18), (0.103, 0.12), (0.137, 0.08))
    dry = buf.copy()
    for ch in (0, 1):
        for i, (sec, gain) in enumerate(taps):
            d = int(sec * SR * (1.0 + 0.05 * ch))
            if d >= dry.shape[1]:
                continue
            buf[ch, d:] += dry[ch, :-d] * gain * wet
    out = buf
    out[0] += dry[1] * 0.05 * wet
    out[1] += dry[0] * 0.05 * wet


def build_track(idx, spec):
    bpm = int(spec["bpm"])
    beat = 60.0 / bpm
    bar = beat * 4.0
    bars = 16
    total = int(bar * bars * SR)
    tail = int(2.4 * SR)
    buf = np.zeros((2, total + tail), dtype=np.float64)
    rng = np.random.default_rng(20261114 + idx * 977)
    scale = spec["scale"]
    root = int(spec["root"])
    prog = spec["prog"]
    quals = spec["quals"]
    mel = MELODIES.get(spec["name"])
    bright = float(spec["bright"])

    for b in range(bars):
        t_bar = b * bar
        chord = prog[b % len(prog)]
        triad = TRIADS[quals[b % len(quals)]]
        # --- 和声铺底：两小节一换，左右失谐分层
        if b % 2 == 0:
            for semi in triad:
                pad(buf, t_bar, bar * 2.0 + 0.3, root + chord + semi,
                    spec["pad"], bright, pan=-0.18)
            pad(buf, t_bar, bar * 2.0 + 0.3, root + chord + 12,
                spec["pad"] * 0.6, bright, pan=0.22)
        if spec.get("organ") and b % 2 == 0:
            organ(buf, t_bar, bar * 2.0, root + chord, spec["organ"], pan=0.0)
        # 工业区不协和张力音
        if spec.get("tension") and b % 4 == 0:
            pad(buf, t_bar + bar * 0.5, bar * 1.5, root + chord + 1,
                spec["pad"] * 0.5, 0.7, pan=0.0)
        # 紫电环：16 分门限和弦
        if spec.get("gate"):
            for i in range(8):
                stab(buf, t_bar + i * beat * 0.5, beat * 0.28,
                     root + chord + triad[1] + 12, spec["gate"] * 0.7, pan=0.3)
        # --- 低音 / 琶音 / 反拍拨弦
        play_bass(buf, spec["bass"][0], spec["bass"][1], root, chord, beat, t_bar)
        play_arp(buf, spec["arp"][0], spec["arp"][1], root, triad, chord, b, beat, t_bar)
        if spec.get("skank"):
            for i in range(4):
                pluck(buf, t_bar + (0.5 + i) * beat, beat * 0.42,
                      root + chord + triad[1] + 24, spec["skank"], -0.3, decay=0.15)
        # --- 铜管 stab
        if spec.get("stab"):
            for pos in ((1.5, 3.5) if b % 2 == 0 else (1.5,)):
                stab(buf, t_bar + pos * beat, beat * 0.34,
                     root + chord + triad[0] + 12, spec["stab"], -0.2)
        # --- 鼓组
        play_drums(buf, spec["drums"], t_bar, beat, b, rng)
        # --- 远景钟声
        if spec.get("shimmer") and b % 2 == 1:
            bell(buf, t_bar + beat * 2.5, beat * 2.2, root + chord + 24,
                 spec["shimmer"], pan=0.25, decay=0.75)
        # --- 主题旋律：第 4/6/12/14 小节各放 2 小节乐句
        if mel and b in (4, 6, 12, 14):
            phrase = mel[0] if b % 4 == 0 else mel[1]
            for (pos, deg, dur) in phrase:
                note = scale_note(root, scale, deg) + 12
                lead(buf, t_bar + pos * beat, dur * beat, note, spec["lead"])

    # --- 空间效果
    if spec.get("echo", 0.0) > 0.0:
        add_echo(buf, 0.31 if bpm >= 100 else 0.37, 0.42, float(spec["echo"]))
    add_reverb(buf, 0.32)

    # --- 循环接缝：把超出末尾的尾音折回开头
    out = buf[:, :total].copy()
    out[:, :tail] += buf[:, total:total + tail]
    peak = float(np.max(np.abs(out)))
    if peak > 0.0:
        out = out / peak * 0.55
    return out.astype(np.float32), out.shape[1] / SR


def write_ogg(samples, out_path, tmp_dir):
    pcm = (np.clip(samples.T, -1.0, 1.0) * 32767.0).astype(np.int16)
    wav_path = os.path.join(tmp_dir, os.path.basename(out_path) + ".wav")
    with wave.open(wav_path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path,
         "-c:a", "libvorbis", "-q:a", "3", "-ar", str(SR), "-ac", "2", out_path],
        check=True,
    )
    os.remove(wav_path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="assets/music")
    ap.add_argument("--only", default="", help="只生成指定星区，如 zone_03")
    args = ap.parse_args()
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = args.out if os.path.isabs(args.out) else os.path.join(root_dir, args.out)
    os.makedirs(out_dir, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for i, spec in enumerate(ZONES):
            if args.only and args.only != spec["name"]:
                continue
            samples, dur = build_track(i, spec)
            path = os.path.join(out_dir, spec["name"] + ".ogg")
            write_ogg(samples, path, tmp)
            rms = float(np.sqrt(np.mean(samples.astype(np.float64) ** 2)))
            print("MUSIC %s %-6s %5.1fs  rms=%.3f  %4d KB" % (
                spec["name"], spec["title"], dur, rms, os.path.getsize(path) // 1024))


if __name__ == "__main__":
    main()




class_name Sfx
extends Node

## 程序化音效：启动时生成几段 PCM 波形（射击/命中/爆炸/拾取/星爆），无需外部音频资源。

const RATE := 22050

var _players: Array[AudioStreamPlayer] = []
var enabled := true
var _shot: AudioStreamWAV
var _hit: AudioStreamWAV
var _boom: AudioStreamWAV
var _pick: AudioStreamWAV
var _nova: AudioStreamWAV
var _click: AudioStreamWAV


func _ready() -> void:
	for i in range(8):
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		_players.append(p)
	_shot = _tone(900.0, 0.05, 0.55, 18.0)
	_hit = _noise(0.06, 0.5, 9000.0)
	_boom = _noise(0.32, 0.85, 2200.0)
	_pick = _sweep(520.0, 1100.0, 0.12, 0.4)
	_nova = _sweep(180.0, 900.0, 0.45, 0.6)
	# UI 按钮轻点音：短促高频、低音量，与射击/拾取明显区分
	_click = _tone(1500.0, 0.035, 0.22, 70.0)


func _play(stream: AudioStream) -> void:
	if not enabled:
		return
	for p in _players:
		if not p.playing:
			p.stream = stream
			p.play()
			return


func play_shot() -> void:
	_play(_shot)


func play_hit() -> void:
	_play(_hit)


func play_boom() -> void:
	_play(_boom)


func play_pick() -> void:
	_play(_pick)


func play_nova() -> void:
	_play(_nova)


func play_click() -> void:
	_play(_click)


# ---- 波形生成 ----

static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	return s


static func _tone(freq: float, dur: float, vol: float, decay: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var t := float(i) / RATE
		var env := exp(-decay * t)
		out[i] = sin(TAU * freq * t) * vol * env
	return _wav(out)


static func _sweep(f0: float, f1: float, dur: float, vol: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in range(n):
		var t := float(i) / RATE
		var k := float(i) / n
		var f := lerpf(f0, f1, k)
		phase += TAU * f / RATE
		var env := sin(PI * k)
		out[i] = sin(phase) * vol * env
	return _wav(out)


static func _noise(dur: float, vol: float, cutoff: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var a := clampf(cutoff / RATE, 0.02, 0.9)
	for i in range(n):
		var k := float(i) / n
		var white := randf_range(-1.0, 1.0)
		lp = lerpf(lp, white, a)
		out[i] = lp * vol * pow(1.0 - k, 1.6)
	return _wav(out)
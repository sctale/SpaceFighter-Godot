class_name MusicPlayer
extends Node

## 每星区一段 BGM：assets/music/zone_01..10.ogg（tools/gen_music.py 生成）。
## 切区时直接换流并从 -40dB 淡入到 -12dB；暂停时冻结播放位置。

const ZONE_COUNT := 10
const TARGET_DB := -15.0

var _player: AudioStreamPlayer
var _zone := 0
var _fading := false
var _cache: Dictionary = {}
var enabled := true


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.volume_db = TARGET_DB
	add_child(_player)
	set_process(false)


func play_zone(z: int) -> void:
	if not enabled:
		stop()
		return
	z = clampi(z, 1, ZONE_COUNT)
	if z == _zone and _player.playing:
		return
	var stream := _load_zone(z)
	if stream == null:
		return
	_zone = z
	_player.stream = stream
	_player.volume_db = -40.0
	_player.play()
	_fading = true
	set_process(true)


func stop() -> void:
	_player.stop()
	_zone = 0
	_fading = false
	set_process(false)


func set_paused(p: bool) -> void:
	_player.stream_paused = p


func is_playing() -> bool:
	return _player.playing


func current_zone() -> int:
	return _zone


func _load_zone(z: int) -> AudioStream:
	if _cache.has(z):
		return _cache[z]
	var path := "res://assets/music/zone_%02d.ogg" % z
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path)
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
	_cache[z] = stream
	return stream


func _process(delta: float) -> void:
	if not _fading:
		return
	_player.volume_db = lerpf(_player.volume_db, TARGET_DB, 1.0 - exp(-3.0 * delta))
	if _player.volume_db >= TARGET_DB - 0.4:
		_player.volume_db = TARGET_DB
		_fading = false
		set_process(false)

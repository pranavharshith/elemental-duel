extends Node
## Tiny sound manager. play() for UI/global sounds, play_at() for positional ones.
##
## Performance: every stream is loaded at startup (loading on first use caused
## a hitch the first time each sound played mid-fight), and positional sounds
## reuse a fixed pool of AudioStreamPlayer3D nodes instead of creating and
## freeing a node per footstep / impact.

const SPELL_DIR := "res://assets/audio/spells/"
const KENNEY_DIR := "res://assets/audio/sfx/"
const POOL_3D := 24

const ALIASES := {
	"click": [KENNEY_DIR + "click1.ogg", KENNEY_DIR + "click2.ogg"],
	"hover": [KENNEY_DIR + "rollover1.ogg", KENNEY_DIR + "rollover2.ogg"],
	"hit": [KENNEY_DIR + "impactPunch_heavy_000.ogg", KENNEY_DIR + "impactPunch_medium_001.ogg", KENNEY_DIR + "impactPunch_medium_003.ogg"],
	"rock_hit": [KENNEY_DIR + "impactMining_002.ogg", KENNEY_DIR + "impactWood_heavy_000.ogg"],
	"wall_break": [KENNEY_DIR + "impactPlank_medium_000.ogg", KENNEY_DIR + "impactPlank_medium_002.ogg"],
	"shield_hit": [KENNEY_DIR + "impactMetal_heavy_001.ogg", KENNEY_DIR + "impactBell_heavy_002.ogg"],
	"step": [KENNEY_DIR + "footstep_concrete_000.ogg", KENNEY_DIR + "footstep_concrete_002.ogg"],
}

## While > 0, positional (in-world) sounds are skipped (shader warm-up).
var muted := 0

var _cache: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _next_3d := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	# World sounds pause with the game (offline pause menu), like before when
	# they were children of the current scene.
	var world := Node.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 14.0
		p.max_db = 3.0
		world.add_child(p)
		_players_3d.append(p)
	_preload()

func _preload() -> void:
	for list in ALIASES.values():
		for path in list:
			_load(path)
	var files: PackedStringArray = ResourceLoader.list_directory(SPELL_DIR)
	for f in files:
		if f.get_extension() == "wav":
			_load(SPELL_DIR + f)

func _load(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
	_cache[path] = s
	return s

func _stream(sound: String) -> AudioStream:
	var path := ""
	if ALIASES.has(sound):
		var list: Array = ALIASES[sound]
		path = list[randi() % list.size()]
	else:
		path = SPELL_DIR + sound + ".wav"
	return _load(path)

func play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var s := _stream(sound)
	if s == null:
		return
	for p in _players:
		if not p.playing:
			p.stream = s
			p.volume_db = volume_db
			p.pitch_scale = pitch * randf_range(0.96, 1.04)
			p.play()
			return

func play_at(sound: String, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if muted > 0:
		return
	var s := _stream(sound)
	if s == null or get_tree().current_scene == null:
		return
	var p := _free_player_3d()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.93, 1.07)
	p.global_position = pos
	p.play()

## An idle pooled player, or (when all are busy) the one started longest ago.
func _free_player_3d() -> AudioStreamPlayer3D:
	for i in _players_3d.size():
		var idx := (_next_3d + i) % _players_3d.size()
		if not _players_3d[idx].playing:
			_next_3d = (idx + 1) % _players_3d.size()
			return _players_3d[idx]
	var p := _players_3d[_next_3d]
	_next_3d = (_next_3d + 1) % _players_3d.size()
	return p

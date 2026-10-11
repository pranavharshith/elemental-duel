extends Node
## Tiny sound manager. play() for UI/global sounds, play_at() for positional ones.

const SPELL_DIR := "res://assets/audio/spells/"
const KENNEY_DIR := "res://assets/audio/sfx/"

const ALIASES := {
	"click": [KENNEY_DIR + "click1.ogg", KENNEY_DIR + "click2.ogg"],
	"hover": [KENNEY_DIR + "rollover1.ogg", KENNEY_DIR + "rollover2.ogg"],
	"hit": [KENNEY_DIR + "impactPunch_heavy_000.ogg", KENNEY_DIR + "impactPunch_medium_001.ogg", KENNEY_DIR + "impactPunch_medium_003.ogg"],
	"rock_hit": [KENNEY_DIR + "impactMining_002.ogg", KENNEY_DIR + "impactWood_heavy_000.ogg"],
	"wall_break": [KENNEY_DIR + "impactPlank_medium_000.ogg", KENNEY_DIR + "impactPlank_medium_002.ogg"],
	"shield_hit": [KENNEY_DIR + "impactMetal_heavy_001.ogg", KENNEY_DIR + "impactBell_heavy_002.ogg"],
	"step": [KENNEY_DIR + "footstep_concrete_000.ogg", KENNEY_DIR + "footstep_concrete_002.ogg"],
}

var _cache: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

func _stream(sound: String) -> AudioStream:
	var path := ""
	if ALIASES.has(sound):
		var list: Array = ALIASES[sound]
		path = list[randi() % list.size()]
	else:
		path = SPELL_DIR + sound + ".wav"
	if _cache.has(path):
		return _cache[path]
	var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
	_cache[path] = s
	return s

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
	var s := _stream(sound)
	var tree := get_tree()
	if s == null or tree.current_scene == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = volume_db
	p.unit_size = 14.0
	p.max_db = 3.0
	p.pitch_scale = pitch * randf_range(0.93, 1.07)
	tree.current_scene.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()

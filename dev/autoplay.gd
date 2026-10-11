extends Node
## Dev harness: runs a duel, steers the player toward the rival, casts a script
## of spells and saves screenshots to dev/shots/. Usage:
##   godot --path . res://dev/autoplay.tscn

const SCRIPT := [
	# [time, action, arg]
	[3.2, "shot", "start"],
	[3.6, "elems", ["fire"]], [3.7, "cast", null], [3.9, "shot", "fireball"],
	[4.6, "elems", ["lightning"]], [4.7, "cast", null], [5.2, "shot", "lightning_warn"], [5.5, "shot", "lightning_hit"],
	[6.6, "elems", ["earth"]], [6.7, "cast", null], [7.0, "shot", "wall"],
	[8.4, "elems", ["fire", "earth"]], [8.5, "cast", null], [9.2, "shot", "meteor_fall"], [9.65, "shot", "meteor_hit"],
	[10.5, "elems", ["water", "wind"]], [10.6, "cast", null], [10.75, "shot", "ice_shards"],
	[11.5, "elems", ["fire", "water"]], [11.6, "cast", null], [12.4, "shot", "steam"],
	[13.0, "jump", null], [13.05, "shot", "teleport"],
	[14.0, "elems", ["lightning", "lightning"]], [14.1, "cast", null], [14.15, "shot", "chain_bolt"],
	[15.5, "elems", ["water", "water"]], [15.6, "cast", null], [15.75, "shot", "tidal"],
	[17.0, "elems", ["fire", "wind"]], [17.1, "cast", null], [17.6, "shot", "tornado"],
	[18.5, "elems", ["earth", "earth"]], [18.6, "cast", null], [18.9, "shot", "stoneskin"],
	[20.0, "elems", ["fire", "fire", "fire"]], [20.1, "cast", null], [20.5, "shot", "sunflare"],
	[21.5, "spellbook", null], [21.7, "shot", "spellbook"], [21.8, "spellbook", null],
	[22.0, "shot", "late"],
	# Plan-style input: key presses only, the buffer resolves and fires.
	[22.5, "press", "fire"], [22.75, "report", "after single fire (expect fire)"],
	[23.6, "press", "water"], [23.65, "press", "wind"], [23.9, "shot", "buffered_ice"], [24.0, "report", "after water+wind (expect water+wind)"],
	[24.4, "hold", "move_right"], [25.0, "shot", "strafe"], [25.1, "release", "move_right"],
	[25.2, "hold", "move_back"], [25.7, "shot", "backpedal"], [25.8, "release", "move_back"],
	[26.0, "shot", "later"],
	[30.0, "quit", null],
]

var duel: Node
var _t := 0.0
var _i := 0
var _spellbook := false

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://dev/shots"))
	duel = (load("res://scenes/duel.tscn") as PackedScene).instantiate()
	add_child(duel)

func _process(delta: float) -> void:
	_t += delta
	var pc: PlayerController = duel.player_ctrl
	var p: Wizard = duel.player
	var e: Wizard = duel.enemy
	# Keep the camera pointed at the rival.
	if pc and e:
		var d := e.global_position - p.global_position
		pc.yaw = rad_to_deg(atan2(-d.x, -d.z))
		pc.pitch = -8.0
	if _spellbook:
		Input.action_press("spellbook")
	while _i < SCRIPT.size() and _t >= SCRIPT[_i][0]:
		_run(SCRIPT[_i])
		_i += 1

func _run(step: Array) -> void:
	var p: Wizard = duel.player
	match step[1]:
		"shot":
			var img := get_viewport().get_texture().get_image()
			img.save_png("res://dev/shots/%s.png" % step[2])
			print("shot %s  t=%.1f  player hp=%.0f mana=%.0f  enemy hp=%.0f" % [step[2], _t, p.hp, p.mana, duel.enemy.hp])
		"elems":
			p.clear_elements()
			for el in step[2]:
				p.queue_element(el)
		"cast":
			p.mana = 100.0
			p.cooldowns.clear()
			p.stun_time = 0.0
			var ok := p.try_cast()
			print("cast ok=", ok, " last=", p.last_spell, " aim=", p.aim_point, " me=", p.global_position, " enemy=", duel.enemy.global_position, " origin=", p.cast_origin())
		"jump":
			p.try_spatial_jump(Vector3(1, 0, 0))
		"press":
			p.mana = 100.0
			p.cooldowns.clear()
			p.stun_time = 0.0
			p.queue_element(step[2])
		"report":
			print("report %s: last=%s queued=%s" % [step[2], p.last_spell, p.elements])
		"hold":
			Input.action_press(step[2])
		"release":
			Input.action_release(step[2])
		"spellbook":
			_spellbook = not _spellbook
			if not _spellbook:
				Input.action_release("spellbook")
		"quit":
			get_tree().quit()

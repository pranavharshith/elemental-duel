extends Node
## Dev test: (1) player hides behind an earth wall -> the rival must not waste
## projectiles and should still threaten you; (2) player strafes in the open ->
## measure how often the rival lands hits. Saves screenshots to dev/shots/.
##   godot --path . res://dev/ai_test.tscn

var duel: Node
var _casts: Array = []
var _hits := 0
var _phase := ""

func _ready() -> void:
	Game.difficulty = Game.Difficulty.NORMAL
	duel = (load("res://scenes/duel.tscn") as PackedScene).instantiate()
	add_child(duel)
	_run()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://dev/shots/%s.png" % name)

func _run() -> void:
	await get_tree().create_timer(2.6).timeout
	var p: Wizard = duel.player
	var e: Wizard = duel.enemy
	var ai: AIController = duel.ai
	var pc: PlayerController = duel.player_ctrl
	e.spell_cast.connect(func(_w: Wizard, key: String) -> void:
		_casts.append([_phase, key, String(SpellBook.get_spell(key)["type"]), ai.has_line_of_sight(p)]))
	p.damaged.connect(func(_w: Wizard, _a: float) -> void:
		if _phase == "open":
			_hits += 1)
	_shot("arena_start")

	# ---------------- Phase 1: hide behind a durable wall.
	_phase = "hidden"
	ai.enabled = false
	p.global_position = Vector3(0, 0, 6)
	e.global_position = Vector3(0, 0, -6)
	await get_tree().physics_frame
	var wall := EarthWall.new()
	wall.setup(p, {"wall_hp": 99999.0, "duration": 60.0})
	duel.add_child(wall)
	wall.global_position = Vector3(0, 0, 4.2)
	wall.rotation.y = 0.0
	await get_tree().create_timer(0.4).timeout
	ai.enabled = true
	var e_start := e.global_position
	var t := 0.0
	while t < 7.0:
		# Keep the player tucked behind the wall and immortal for the test.
		p.hp = 100.0
		var to := e.global_position - p.global_position
		pc.yaw = rad_to_deg(atan2(-to.x, -to.z))
		pc.pitch = -10.0
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if absf(t - 3.0) < 0.01:
			_shot("ai_hidden")
	print("rival moved %.1f m while you hid" % e.global_position.distance_to(e_start))
	wall.crumble()

	# ---------------- Phase 2: strafe in the open.
	_phase = "open"
	_hits = 0
	pc.set_physics_process(false)   # we drive move_input directly
	var open_t := 0.0
	var dir := 1.0
	while open_t < 10.0:
		p.hp = 100.0
		if fmod(open_t, 1.4) < get_physics_process_delta_time():
			dir = -dir
		var to := e.global_position - p.global_position
		to.y = 0
		var side := to.normalized().cross(Vector3.UP)
		p.move_input = side * dir
		pc.yaw = rad_to_deg(atan2(-to.x, -to.z))
		await get_tree().physics_frame
		open_t += get_physics_process_delta_time()
		if absf(open_t - 4.0) < 0.01:
			_shot("ai_open")

	var hidden_proj := 0
	var hidden_total := 0
	var open_total := 0
	for c in _casts:
		if c[0] == "hidden":
			hidden_total += 1
			if (c[2] == "projectile" or c[2] == "beam" or c[2] == "cone") and not c[3]:
				hidden_proj += 1
		else:
			open_total += 1
		print("cast  %-6s  %-24s %-10s  los=%s" % c)
	print("HIDDEN: %d casts, %d wasted direct shots into the wall" % [hidden_total, hidden_proj])
	print("OPEN: %d casts, %d hits on a strafing player in 10 s" % [open_total, _hits])
	get_tree().quit()

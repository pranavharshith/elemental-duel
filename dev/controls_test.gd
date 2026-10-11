extends Node
## Dev test: feeds real InputEvents (keyboard + mouse) into a live duel and
## checks every control does what the HUD says. Usage:
##   godot --path . res://dev/controls_test.tscn

var duel: Node
var _fails := 0

func _ready() -> void:
	duel = (load("res://scenes/duel.tscn") as PackedScene).instantiate()
	add_child(duel)
	_run()

func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _tap(code: Key) -> void:
	_key(code, true)
	await get_tree().physics_frame
	_key(code, false)

func _check(name: String, ok: bool, detail: String = "") -> void:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		_fails += 1

func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _blocker(pos: Vector3, size: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	duel.add_child(body)
	body.global_position = pos
	return body

func _run() -> void:
	await _wait(2.6)   # countdown
	var p: Wizard = duel.player
	var pc: PlayerController = duel.player_ctrl
	duel.ai.enabled = false   # keep the rival still so results are deterministic
	duel.enemy.move_input = Vector3.ZERO
	_check("controls enabled after countdown", p.controls_enabled)
	p.elements_changed.connect(func(w: Wizard) -> void: print("   [t=%d] elements=%s" % [Time.get_ticks_msec(), w.elements]))
	p.spell_cast.connect(func(_w: Wizard, k: String) -> void: print("   [t=%d] CAST %s" % [Time.get_ticks_msec(), k]))
	p.fizzled.connect(func(_w: Wizard, r: String) -> void: print("   [t=%d] FIZZLE %s" % [Time.get_ticks_msec(), r]))

	# --- WASD, camera-relative
	var start := p.global_position
	_key(KEY_W, true)
	await _wait(0.6)
	_key(KEY_W, false)
	var fwd := Vector3(-sin(deg_to_rad(pc.yaw)), 0, -cos(deg_to_rad(pc.yaw)))
	var moved := p.global_position - start
	_check("W moves forward (camera-relative)", moved.dot(fwd) > 1.5, "moved=%s" % moved)
	await _wait(0.3)
	start = p.global_position
	_key(KEY_D, true)
	await _wait(0.5)
	_key(KEY_D, false)
	var right := Vector3(cos(deg_to_rad(pc.yaw)), 0, -sin(deg_to_rad(pc.yaw)))
	moved = p.global_position - start
	_check("D strafes right", moved.dot(right) > 1.0, "moved=%s" % moved)
	await _wait(0.3)

	# --- Mouse look
	var yaw0 := pc.yaw
	var pitch0 := pc.pitch
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(120, 40)
	mm.screen_relative = Vector2(120, 40)
	if DisplayServer.get_name() == "headless":
		# The headless driver has no captured operating-system pointer, but this
		# calls the exact controller look path used by mouse events.
		pc.apply_look_delta(mm.screen_relative)
	else:
		Input.parse_input_event(mm)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("mouse X turns camera", absf(pc.yaw - yaw0) > 5.0, "yaw %.1f -> %.1f" % [yaw0, pc.yaw])
	_check("mouse Y pitches camera (clamped)", pc.pitch < pitch0 and pc.pitch >= PlayerController.PITCH_MIN, "pitch %.1f -> %.1f" % [pitch0, pc.pitch])
	# Face the rival again for the casting checks.
	var to: Vector3 = duel.enemy.global_position - p.global_position
	pc.yaw = rad_to_deg(atan2(-to.x, -to.z))
	pc.pitch = -8.0
	await _wait(0.3)
	var aim_dir := (p.aim_point - p.global_position)
	aim_dir.y = 0
	_check("crosshair aim points at rival", aim_dir.normalized().dot(to.normalized()) > 0.95, "aim=%s" % p.aim_point)

	# --- Single key cast (Q = Fireball) after the combo window
	_tap(KEY_Q)
	await _wait(Wizard.COMBO_WINDOW + 0.15)
	_check("Q casts Fireball", p.last_spell == "fire", "last=%s" % p.last_spell)
	await _wait(0.6)

	# --- Quick double press = combo (E + F = Ice Shards)
	p.mana = 100.0
	_tap(KEY_E)
	await _wait(0.08)
	_tap(KEY_F)
	await _wait(Wizard.COMBO_WINDOW + 0.15)
	_check("E+F quickly casts Ice Shards", p.last_spell == "water+wind", "last=%s" % p.last_spell)
	await _wait(0.6)

	# --- Triple combo fires immediately (Q Q Q = Sun Flare)
	p.mana = 100.0
	_tap(KEY_Q)
	await _wait(0.05)
	_tap(KEY_Q)
	await _wait(0.05)
	_tap(KEY_Q)
	await _wait(0.1)
	_check("Q Q Q casts Sun Flare", p.last_spell == "fire+fire+fire", "last=%s" % p.last_spell)
	await _wait(0.6)

	# --- R = Earth wall appears
	p.mana = 100.0
	_tap(KEY_R)
	await _wait(Wizard.COMBO_WINDOW + 0.15)
	_check("R raises an Earth Wall", get_tree().get_nodes_in_group("earth_walls").size() > 0, "last=%s" % p.last_spell)
	await _wait(0.4)

	# --- C = lightning strike (warning marker then bolt)
	p.mana = 100.0
	_tap(KEY_C)
	await _wait(Wizard.COMBO_WINDOW + 0.15)
	_check("C calls Lightning", p.last_spell == "lightning", "last=%s" % p.last_spell)

	# --- Left click fires the buffer immediately
	await _wait(1.0)
	p.mana = 100.0
	p.cooldowns.clear()
	_tap(KEY_E)
	await get_tree().physics_frame
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = get_viewport().get_visible_rect().get_center()
	mb.global_position = mb.position
	if DisplayServer.get_name() == "headless":
		pc.release_buffer()
	else:
		Input.parse_input_event(mb)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("Left click releases combo early", p.last_spell == "water" and p.elements.is_empty(), "last=%s" % p.last_spell)
	mb = mb.duplicate()
	mb.pressed = false
	Input.parse_input_event(mb)

	# --- Space = spatial jump (costs SP, moves you)
	await _wait(0.5)
	var sp0 := p.sp
	var pos0 := p.global_position
	await _tap(KEY_SPACE)
	await get_tree().process_frame
	await get_tree().physics_frame
	_check("Space teleports", p.global_position.distance_to(pos0) > 1.5, "dist=%.2f" % p.global_position.distance_to(pos0))
	_check("Jump costs 35 SP", absf((sp0 - p.sp) - Wizard.JUMP_COST) < 1.0, "sp %.0f -> %.0f" % [sp0, p.sp])
	_check("Still inside arena", Vector2(p.global_position.x, p.global_position.z).length() <= Arena.PLAYABLE_RADIUS + 0.01)

	# --- PvP camera integrity: gameplay blockers retract the camera instead of
	# allowing a wall-peek. The old controller intentionally ignored layer 8.
	p.global_position = Vector3.ZERO
	p.velocity = Vector3.ZERO
	pc.yaw = 0.0
	pc.pitch = PlayerController.DEFAULT_PITCH
	pc.snap_behind()
	var behind := _blocker(Vector3(0, 1.2, 1.55), Vector3(3.6, 2.4, 0.8), 8)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	var arm := pc.get_node("CameraYaw/CameraPitch/CameraCollisionArm") as SpringArm3D
	_check("wall behind you doesn't crush the camera", arm.get_hit_length() > PlayerController.ARM_LENGTH - 0.3, "length=%.2f" % arm.get_hit_length())
	_check("wall behind you doesn't capture the aim", p.aim_point.z < p.global_position.z, "aim=%s" % p.aim_point)
	behind.queue_free()

	# --- Camera at the arena edge: must not be shoved into the wizard's head.
	p.global_position = Vector3(0, 0, Arena.PLAYABLE_RADIUS)
	pc.yaw = 0.0
	pc.pitch = PlayerController.DEFAULT_PITCH
	for i in 3:
		await get_tree().physics_frame
	await get_tree().process_frame
	_check("camera keeps distance at the arena edge", arm.get_hit_length() > 3.0, "length=%.2f" % arm.get_hit_length())

	# --- AI line of sight: hide the rival's view behind a wall
	duel.ai.enabled = true
	await _wait(0.2)
	print("AI has LOS now: ", duel.ai.has_line_of_sight(p))

	print("controls test done, %d failure(s)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)

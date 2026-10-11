extends Node
## Dev test: holds each movement key and saves a screenshot from the game camera
## and from a side camera, to check legs, torso and camera framing.
##   godot --path . res://dev/move_test.tscn

var duel: Node

func _ready() -> void:
	duel = (load("res://scenes/duel.tscn") as PackedScene).instantiate()
	add_child(duel)
	_run()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://dev/shots/%s.png" % name)

func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	duel.ai.enabled = false
	var p: Wizard = duel.player
	var pc: PlayerController = duel.player_ctrl
	var side_cam := Camera3D.new()
	side_cam.fov = 50
	duel.add_child(side_cam)
	for step in [["fwd", KEY_W], ["back", KEY_S], ["left", KEY_A], ["right", KEY_D], ["fwd_right", [KEY_W, KEY_D]]]:
		p.global_position = Vector3(0, 0, 4)
		pc.yaw = 0.0
		pc.pitch = -12.0
		pc.snap_behind()
		pc.yaw = 0.0
		var keys: Array = step[1] if step[1] is Array else [step[1]]
		for k in keys:
			_key(k, true)
		await get_tree().create_timer(0.55).timeout
		_shot("move_%s_cam" % step[0])
		await get_tree().create_timer(0.05).timeout
		# Side view of the same pose.
		var vp := p.visual_position()
		side_cam.global_position = vp + Vector3(4.5, 1.3, 0)
		side_cam.look_at(vp + Vector3(0, 0.9, 0))
		side_cam.make_current()
		await get_tree().process_frame
		await get_tree().process_frame
		_shot("move_%s_side" % step[0])
		var body_fwd := -p.global_transform.basis.z
		var vel := Vector3(p.velocity.x, 0, p.velocity.z)
		var rate: float = p._anim.tree.get("parameters/loco_rate/scale")
		print("%s: speed=%.2f  facing-vs-travel=%.0f deg  anim_rate=%.2f (must be > 0)" % [step[0], vel.length(),
			rad_to_deg(Vector3(body_fwd.x, 0, body_fwd.z).angle_to(vel)), rate])
		pc.camera.current = true
		for k in keys:
			_key(k, false)
		await get_tree().create_timer(0.4).timeout
	get_tree().quit()

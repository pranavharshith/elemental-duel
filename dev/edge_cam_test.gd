extends Node
## Dev test: camera arm length with the player standing near the arena edge,
## looking toward the centre (camera behind, outside the rim).
##   godot --path . res://dev/edge_cam_test.tscn

func _ready() -> void:
	var duel: Node = (load("res://scenes/duel.tscn") as PackedScene).instantiate()
	add_child(duel)
	await get_tree().create_timer(2.6).timeout
	duel.ai.enabled = false
	var p: Wizard = duel.player
	var pc: PlayerController = duel.player_ctrl
	var arm := pc.get_node("CameraYaw/CameraPitch/CameraCollisionArm") as SpringArm3D
	for r in [6.0, 10.0, 11.5, 12.6]:
		p.global_position = Vector3(0, 0, r)
		p.velocity = Vector3.ZERO
		pc.yaw = 0.0   # looking toward -Z = arena centre
		pc.pitch = PlayerController.DEFAULT_PITCH
		for i in 4:
			await get_tree().physics_frame
		await get_tree().process_frame
		print("radius %.1f: arm length %.2f / %.2f" % [r, arm.get_hit_length(), PlayerController.ARM_LENGTH])
		get_viewport().get_texture().get_image().save_png("res://dev/shots/edge_%d.png" % int(r * 10))
	get_tree().quit()

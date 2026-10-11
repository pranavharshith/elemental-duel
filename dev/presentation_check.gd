extends Node

var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		print("FAIL ", message)

func _ready() -> void:
	var duel := (load("res://scenes/duel.tscn") as PackedScene).instantiate()
	add_child(duel)
	await get_tree().create_timer(2.5).timeout
	duel.ai.enabled = false
	duel.player_ctrl.input_enabled = false
	duel.player.invuln_time = 1000
	duel.enemy.controls_enabled = false
	check(SpellBook.SPELLS.size() == 28, "All 28 original spells remain")
	check(InputMap.has_action("cast"), "Left-click cast action exists")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	check(InputMap.action_has_event("cast", mouse), "Left click is mapped")
	check(is_equal_approx(Arena.PLAYABLE_RADIUS, 17.2), "Expanded playable radius")
	var space: PhysicsDirectSpaceState3D = duel.get_world_3d().direct_space_state
	for i in 96:
		var angle := TAU * i / 96.0
		var direction := Vector3(sin(angle), 0, cos(angle))
		var from := direction * 16.0 + Vector3.UP
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, direction * 21.0 + Vector3.UP, 16))
		check(not hit.is_empty(), "Boundary sealed at angle %d" % i)
		check(Arena.clamp_to_arena(direction * 40).length() <= 17.201, "Teleport clamp %d" % i)
	var original_quality: int = Game.graphics_quality
	var original_adaptive: bool = Game.adaptive_resolution
	var original_fov: float = Game.camera_fov
	for quality in 3:
		Game.graphics_quality = quality
		Game.camera_fov = 60 + quality * 15
		Game.apply_presentation()
		check(duel.arena._sun.shadow_enabled == (quality > 0), "Shadow preset %d" % quality)
		check(is_equal_approx(duel.player_ctrl.camera.fov, Game.camera_fov), "Live FOV %d" % quality)
		var lights: Array[OmniLight3D] = []
		for i in 6:
			var light := VFX.budget_light(Color.WHITE, 1, 2)
			if light:
				add_child(light)
				lights.append(light)
		check(lights.size() <= [0, 2, 4][quality], "Light budget %d" % quality)
		for light in lights:
			light.free()
	Game.adaptive_resolution = false
	Game.apply_presentation()
	check(is_equal_approx(Perf.current_scale(), 1.0), "Native resolution when adaptive disabled")
	Game.graphics_quality = original_quality
	Game.adaptive_resolution = original_adaptive
	Game.camera_fov = original_fov
	Game.apply_presentation()
	duel.ai._dodge_cooldown = 9
	duel.ai._blocked_time = 9
	duel.ai._los = false
	var generation: int = duel.ai._round_generation
	duel.ai.reset_round()
	check(duel.ai._round_generation == generation + 1, "Old delayed reactions invalidated")
	check(duel.ai._dodge_cooldown == 0 and duel.ai._blocked_time == 0 and duel.ai._los, "AI round state reset")
	var bodies: Array[Node] = duel.arena.find_children("*", "StaticBody3D", true, false)
	check(bodies.size() == 3, "Decorative architecture adds no combat colliders")
	duel.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var report := {"checks": checks, "failures": failures}
	var file := FileAccess.open("res://dev/presentation-result.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t"))
	print("PRESENTATION_CHECK ", JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)

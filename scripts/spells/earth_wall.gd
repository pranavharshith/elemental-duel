class_name EarthWall
extends StaticBody3D
## Temporary stone wall. Blocks movement, projectiles and beams; has HP and
## crumbles when broken or when its duration ends.

const SIZE := Vector3(3.6, 2.4, 0.8)

var caster: Wizard
var hp := 45.0
var duration := 6.0
var _t := 0.0
var _visual: Node3D
var _crumbling := false
var _mats: Array = []
var _alpha := 1.0

func setup(owner_wizard: Wizard, spell: Dictionary) -> void:
	caster = owner_wizard
	hp = float(spell.get("wall_hp", 45.0))
	duration = float(spell.get("duration", 6.0))

func _ready() -> void:
	add_to_group("earth_walls")
	collision_layer = 8
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = SIZE
	cs.shape = box
	cs.position.y = SIZE.y * 0.5
	add_child(cs)
	_visual = Node3D.new()
	add_child(_visual)
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.48, 0.38, 0.28)
	rock.roughness = 1.0
	var moss := StandardMaterial3D.new()
	moss.albedo_color = Color(0.36, 0.42, 0.24)
	moss.roughness = 1.0
	for m in [rock, moss]:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	_mats = [rock, moss]
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 6:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var w := rng.randf_range(0.8, 1.2)
		var h := rng.randf_range(1.9, 2.7)
		bm.size = Vector3(w, h, rng.randf_range(0.7, 1.0))
		mi.mesh = bm
		mi.material_override = rock if i % 3 != 1 else moss
		mi.position = Vector3(-SIZE.x * 0.5 + 0.35 + i * (SIZE.x - 0.7) / 5.0, h * 0.5, rng.randf_range(-0.1, 0.1))
		mi.rotation = Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.3, 0.3), rng.randf_range(-0.12, 0.12))
		_visual.add_child(mi)
	_visual.position.y = -SIZE.y
	var tw := create_tween()
	tw.tween_property(_visual, "position:y", 0.0, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	VFX.burst(get_parent(), global_position + Vector3(0, 0.2, 0), Color(0.55, 0.45, 0.35), 30, 5.0, 0.6, 0.8,
		{"additive": false, "energy": 1.0, "emit_radius": 1.5, "gravity": Vector3(0, -4, 0), "direction": Vector3.UP, "spread": 60.0})
	_shake(0.15)

func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		crumble()

## Fade when the wall sits between the camera and the local player.
func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var want := 1.0
	if cam:
		var pc := cam.get_parent()
		while pc and not (pc is PlayerController):
			pc = pc.get_parent()
		if pc and (pc as PlayerController).wizard:
			var target := (pc as PlayerController).wizard.global_position + Vector3(0, 1.2, 0)
			var local_from := to_local(cam.global_position)
			var local_to := to_local(target)
			var half := SIZE * 0.5 + Vector3(0.2, 0.2, 0.2)
			var aabb := AABB(Vector3(-half.x, 0.0, -half.z), Vector3(half.x * 2.0, SIZE.y + 0.2, half.z * 2.0))
			if aabb.intersects_segment(local_from, local_to) or aabb.has_point(local_from):
				want = 0.3
	_alpha = move_toward(_alpha, want, delta * 5.0)
	for m in _mats:
		(m as StandardMaterial3D).albedo_color.a = _alpha

func take_damage(amount: float) -> void:
	if _crumbling:
		return
	hp -= amount
	if _visual:
		var tw := create_tween()
		tw.tween_property(_visual, "position:x", 0.08, 0.04)
		tw.tween_property(_visual, "position:x", -0.08, 0.04)
		tw.tween_property(_visual, "position:x", 0.0, 0.04)
	Sfx.play_at("rock_hit", global_position + Vector3.UP, -6.0)
	if hp <= 0.0:
		crumble()

func crumble() -> void:
	if _crumbling:
		return
	_crumbling = true
	collision_layer = 0
	VFX.burst(get_parent(), global_position + Vector3(0, 1.0, 0), Color(0.5, 0.4, 0.3), 40, 6.0, 0.5, 1.0,
		{"additive": false, "energy": 1.0, "emit_radius": 1.4, "gravity": Vector3(0, -12, 0)})
	Sfx.play_at("wall_break", global_position + Vector3.UP, 0.0)
	var tw := create_tween()
	tw.tween_property(_visual, "position:y", -SIZE.y - 0.2, 0.5).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)

func _shake(amount: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and cam.has_method("add_shake"):
		cam.add_shake(amount)

class_name Strike
extends Node3D
## Delayed ground strike: shows a warning marker, then lands a bolt, a meteor or
## a crystal spike and damages the opponent if they are still inside the radius.

var caster: Wizard
var spell: Dictionary
var delay := 0.7
var _t := 0.0
var _done := false
var _meteor: MeshInstance3D

func setup(owner_wizard: Wizard, spell_data: Dictionary, wait: float) -> void:
	caster = owner_wizard
	spell = spell_data
	delay = wait

func _ready() -> void:
	var color: Color = spell["color"]
	VFX.warning_marker(get_parent(), global_position, float(spell["radius"]), color, delay)
	if spell.has("meteor"):
		_meteor = MeshInstance3D.new()
		var sm := SphereMesh.new()
		var r := float(spell["radius"]) * 0.35
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 8
		sm.rings = 5
		_meteor.mesh = sm
		_meteor.material_override = Arena.emissive(Color(1.0, 0.4, 0.1), 3.0)
		_meteor.visible = false
		add_child(_meteor)
		var fire := VFX.make_particles(Color(1.0, 0.5, 0.15), 40, 0.5, r * 2.2, {"emit_radius": r, "vel_min": 0.2, "vel_max": 1.0, "scale_end": 0.0})
		fire.emitting = true
		_meteor.add_child(fire)

func _physics_process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if _meteor:
		var fall := 0.55
		var k := (_t - (delay - fall)) / fall
		if k > 0.0:
			_meteor.visible = true
			_meteor.position = Vector3(-6.0, 18.0, -4.0).lerp(Vector3.ZERO, clampf(k, 0, 1))
	if _t >= delay:
		_land()

func _land() -> void:
	_done = true
	var world := get_parent()
	var color: Color = spell["color"]
	var radius := float(spell["radius"])
	var pos := global_position
	var t := caster.opponent if is_instance_valid(caster) else null
	if t and t.alive:
		var flat := Vector2(t.global_position.x - pos.x, t.global_position.z - pos.z)
		if flat.length() <= radius + 0.35 and t.global_position.y < pos.y + 2.5:
			var info := {}
			for k in ["burn", "stun", "slow", "slow_time"]:
				if spell.has(k):
					info[k] = spell[k]
			if spell.has("knockback"):
				var kb := Vector3(flat.x, 0, flat.y)
				info["knockback"] = (kb.normalized() if kb.length() > 0.1 else Vector3.FORWARD) * float(spell["knockback"])
			t.take_hit(float(spell["damage"]), info)
	if spell.has("meteor"):
		VFX.explosion(world, pos + Vector3(0, 0.3, 0), color, radius)
		VFX.burst(world, pos, Color(0.4, 0.3, 0.25), 20, 6.0, 0.35, 0.9, {"additive": false, "energy": 1.0, "gravity": Vector3(0, -12, 0), "direction": Vector3.UP, "spread": 50.0})
		Sfx.play_at("explosion", pos, 2.0, 0.8)
		_shake(0.5)
	elif spell.has("spike"):
		_spawn_spike(world, pos, color, radius)
		Sfx.play_at("rock_hit", pos, -3.0, 1.3)
	else:
		var top := pos + Vector3(randf_range(-1.5, 1.5), 22.0, randf_range(-1.5, 1.5))
		VFX.bolt(world, top, pos, color, 0.16 * radius, 0.35)
		VFX.bolt(world, top, pos, Color(1, 1, 1), 0.06 * radius, 0.25)
		VFX.burst(world, pos + Vector3(0, 0.2, 0), color, int(30 * radius), 6.0, 0.3, 0.5)
		VFX.shockwave(world, pos + Vector3(0, 0.1, 0), color, radius)
		VFX.flash_light(world, pos + Vector3(0, 2, 0), color, 8.0, radius * 5.0, 0.35)
		Sfx.play_at("thunder", pos, -1.0 + radius, 1.15 - radius * 0.08)
		_shake(0.2 + radius * 0.08)
	if _meteor:
		_meteor.visible = false
	get_tree().create_timer(0.8).timeout.connect(queue_free)

func _spawn_spike(world: Node, pos: Vector3, color: Color, radius: float) -> void:
	var mi := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(radius * 0.7, 2.2, radius * 0.7)
	mi.mesh = pm
	mi.material_override = Arena.emissive(color, 2.0)
	world.add_child(mi)
	mi.global_position = pos + Vector3(0, -1.2, 0)
	mi.rotation = Vector3(randf_range(-0.25, 0.25), randf() * TAU, randf_range(-0.25, 0.25))
	var tw := mi.create_tween()
	tw.tween_property(mi, "global_position:y", 1.0, 0.1).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.6)
	tw.tween_property(mi, "global_position:y", -1.3, 0.35).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)
	VFX.burst(world, pos + Vector3(0, 0.3, 0), color, 16, 4.0, 0.25, 0.4)

func _shake(amount: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and cam.has_method("add_shake"):
		var d := cam.global_position.distance_to(global_position)
		cam.add_shake(amount * clampf(1.4 - d / 25.0, 0.2, 1.0))

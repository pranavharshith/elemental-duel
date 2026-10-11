class_name AreaEffect
extends Node3D
## Lingering ground zone (steam, mud, tempest, maelstrom). Damages in ticks,
## slows every frame and can pull the opponent toward its centre.

const TICK := 0.5

var caster: Wizard
var spell: Dictionary
var radius := 3.0
var duration := 5.0
var _t := 0.0
var _tick := 0.0
var _disc_mat: StandardMaterial3D
var _particles: GPUParticles3D
var _ending := false

func setup(owner_wizard: Wizard, spell_data: Dictionary) -> void:
	caster = owner_wizard
	spell = spell_data
	radius = float(spell["radius"])
	duration = float(spell["duration"])

func _ready() -> void:
	var color: Color = spell["color"]
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.03
	cyl.radial_segments = 48
	disc.mesh = cyl
	disc.position.y = 0.05
	_disc_mat = StandardMaterial3D.new()
	_disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_disc_mat.albedo_color = Color(color, 0.0)
	_disc_mat.emission_enabled = true
	_disc_mat.emission = color
	_disc_mat.emission_energy_multiplier = 0.6
	_disc_mat.roughness = 0.2
	disc.material_override = _disc_mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	var tw := create_tween()
	tw.tween_property(_disc_mat, "albedo_color:a", 0.55 if spell["name"] == "Mud Bog" else 0.3, 0.3)

	var opts := {"emit_radius": radius * 0.85, "vel_min": 0.3, "vel_max": 1.2, "gravity": Vector3(0, 1.2, 0),
		"scale_start": 0.6, "scale_end": 1.4, "additive": false, "energy": 1.0}
	var amount := int(radius * 22)
	var size := 1.4
	var life := 1.6
	if spell.has("pull"):
		opts = {"emit_ring": radius * 0.9, "orbit": 0.6, "radial": -radius * 0.8, "vel_min": 0.0, "vel_max": 0.2,
			"scale_start": 1.0, "scale_end": 0.2, "energy": 1.8}
		size = 0.6
		amount = int(radius * 30)
	elif spell.has("zap"):
		opts = {"emit_radius": radius * 0.8, "vel_min": 0.2, "vel_max": 0.8, "gravity": Vector3(0, 0.6, 0),
			"scale_start": 0.8, "scale_end": 1.6, "additive": false, "energy": 1.0}
		color = Color(0.25, 0.27, 0.38)
	elif spell["name"] == "Mud Bog":
		opts["gravity"] = Vector3(0, 0.3, 0)
		size = 0.5
		amount = int(radius * 10)
	_particles = VFX.make_particles(color, amount, life, size, opts)
	_particles.position.y = 0.4 if not spell.has("zap") else 2.5
	_particles.emitting = true
	add_child(_particles)

func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		_finish()
		return
	var t := caster.opponent if is_instance_valid(caster) else null
	if t == null or not t.alive:
		return
	var flat := Vector3(t.global_position.x - global_position.x, 0, t.global_position.z - global_position.z)
	var inside := flat.length() <= radius
	if inside:
		t.apply_area_slow(float(spell.get("slow", 1.0)))
		if spell.has("pull") and flat.length() > 0.6:
			t.global_position -= flat.normalized() * float(spell["pull"]) * delta
	_tick -= delta
	if _tick <= 0.0:
		_tick = TICK
		if spell.has("zap"):
			var p := global_position + Vector3(randf_range(-radius, radius) * 0.7, 0, randf_range(-radius, radius) * 0.7)
			if inside and randf() < 0.6:
				p = t.global_position
			VFX.bolt(get_parent(), p + Vector3(0, 3.0, 0), p, Color(0.7, 0.85, 1.0), 0.07, 0.18)
			Sfx.play_at("zap", p, -10.0, 1.3)
		if inside:
			t.take_hit(float(spell["dps"]) * TICK, {})

func _finish() -> void:
	if _ending:
		return
	_ending = true
	set_physics_process(false)
	_particles.emitting = false
	var tw := create_tween()
	tw.tween_property(_disc_mat, "albedo_color:a", 0.0, 0.6)
	tw.parallel().tween_property(_disc_mat, "emission_energy_multiplier", 0.0, 0.6)
	tw.tween_interval(1.0)
	tw.tween_callback(queue_free)

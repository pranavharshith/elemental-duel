class_name Projectile
extends Node3D
## Swept projectile: each physics step ray-casts the travelled segment against
## the world / earth walls and tests the opponent's capsule, so fast spells
## never tunnel through targets.

var caster: Wizard
var spell: Dictionary
var velocity := Vector3.ZERO
var speed := 20.0
var size := 0.25
var lifetime := 3.0
var _age := 0.0
var _dead := false
var _trail: GPUParticles3D
var _core: MeshInstance3D
var _light: OmniLight3D
# Render-time interpolation. Flight is simulated at the physics rate (60 Hz);
# drawing the raw position stuttered on 120/144 Hz screens. The visuals live
# under a top-level node placed between the last two physics positions.
var _visual: Node3D
var _prev_pos := Vector3.ZERO
var _curr_pos := Vector3.ZERO
var _has_state := false

func setup(owner_wizard: Wizard, spell_data: Dictionary, dir: Vector3) -> void:
	caster = owner_wizard
	spell = spell_data
	speed = float(spell.get("speed", 20.0))
	size = float(spell.get("size", 0.25))
	lifetime = float(spell.get("lifetime", 2.5))
	velocity = dir.normalized() * speed

func _ready() -> void:
	add_to_group("projectiles")
	var color: Color = spell["color"]
	_visual = Node3D.new()
	_visual.name = "Visual"
	_visual.top_level = true
	add_child(_visual)
	_core = MeshInstance3D.new()
	if spell.has("rock"):
		var sm := SphereMesh.new()
		sm.radius = size
		sm.height = size * 2.0
		sm.radial_segments = 7
		sm.rings = 4
		_core.mesh = sm
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(0.45, 0.36, 0.28)
		rm.roughness = 1.0
		_core.material_override = rm
	elif spell.has("shard"):
		var pm := PrismMesh.new()
		pm.size = Vector3(size * 0.8, size * 3.2, size * 0.8)
		_core.mesh = pm
		_core.rotation_degrees.x = -90
		_core.material_override = Arena.emissive_shared(color, 2.5)
	elif spell.has("stretch"):
		var cm := CapsuleMesh.new()
		cm.radius = size
		cm.height = size * float(spell["stretch"])
		_core.mesh = cm
		_core.rotation_degrees.x = 90
		_core.material_override = Arena.emissive_shared(color, 6.0, true)
	elif spell.has("tornado"):
		var cyl := CylinderMesh.new()
		cyl.top_radius = size * 1.3
		cyl.bottom_radius = size * 0.3
		cyl.height = size * 4.0
		_core.mesh = cyl
		var tm := Arena.emissive(color, 3.0, true)
		tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tm.albedo_color.a = 0.55
		_core.material_override = tm
	else:
		var sm := SphereMesh.new()
		sm.radius = size
		sm.height = size * 2.0
		_core.mesh = sm
		_core.material_override = Arena.emissive_shared(color.lightened(0.35), 5.0, true)
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(_core)
	if spell.has("shard") or spell.has("stretch"):
		_core.look_at_from_position(Vector3.ZERO, velocity.normalized(), Vector3.UP if absf(velocity.normalized().y) < 0.95 else Vector3.RIGHT)
		_core.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
	var trail_opts := {"vel_min": 0.1, "vel_max": 0.6, "emit_radius": size * 0.6, "scale_end": 0.0}
	if spell.has("tornado"):
		trail_opts = {"local": true, "emit_ring": size * 1.2, "orbit": 2.5, "vel_min": 0.5, "vel_max": 2.0,
			"direction": Vector3.UP, "spread": 10.0, "scale_end": 0.0}
	if spell.has("rock"):
		trail_opts["additive"] = false
		trail_opts["energy"] = 1.0
	var trail_color := color if not spell.has("rock") else Color(0.5, 0.42, 0.35)
	_trail = VFX.make_particles(trail_color, int(30 + size * 40), 0.4 if not spell.has("tornado") else 0.6, size * 2.2, trail_opts)
	_trail.emitting = true
	_visual.add_child(_trail)
	if not spell.has("rock"):
		# Budgeted: multi-shot spells (Ice Shards, ...) no longer spawn a light
		# per shard.
		_light = VFX.budget_light(color, 1.6, 2.5 + size * 4.0)
		if _light:
			_visual.add_child(_light)
	_visual.global_position = global_position

	set_notify_transform(true)

func _notification(what: int) -> void:
	# The spawner sets global_position right after add_child: snap the visuals
	# there so the first rendered frame isn't drawn at the world origin.
	if what == NOTIFICATION_TRANSFORM_CHANGED and not _has_state and _visual:
		_visual.global_position = global_position

func _process(_delta: float) -> void:
	if not _has_state:
		_visual.global_position = global_position
		return
	_visual.global_position = _prev_pos.lerp(_curr_pos, Engine.get_physics_interpolation_fraction())

func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not _has_state:
		_has_state = true
		_curr_pos = global_position
		set_notify_transform(false)
	_prev_pos = _curr_pos
	_age += delta
	if _age > lifetime:
		_explode(global_position, null)
		return
	# Homing (Flame Tornado): steer toward the opponent's chest.
	var target := caster.opponent if is_instance_valid(caster) else null
	if spell.has("homing") and target and target.alive:
		var want := (target.global_position + Vector3(0, 1.0, 0) - global_position).normalized() * speed
		velocity = velocity.lerp(want, clampf(float(spell["homing"]) * delta, 0.0, 1.0))
		velocity.y = clampf(velocity.y, -2.0, 2.0)
	if spell.has("gravity"):
		velocity.y -= float(spell["gravity"]) * delta
	if spell.has("tornado"):
		_core.rotate_y(delta * 14.0)
		var hv := Vector3(velocity.x, 0, velocity.z)
		velocity = hv.normalized() * speed
		global_position.y = lerpf(global_position.y, 1.0, delta * 3.0)
	var from := global_position
	var to := from + velocity * delta
	# 1) Opponent capsule (generous radius for readability).
	if target and target.alive and target.invuln_time <= 0.0:
		var base := target.global_position
		var seg_closest := Geometry3D.get_closest_points_between_segments(from, to, base + Vector3(0, 0.3, 0), base + Vector3(0, 1.6, 0))
		if seg_closest[0].distance_to(seg_closest[1]) < size + 0.45:
			_hit_wizard(target)
			_explode(seg_closest[0], target)
			return
	# 2) World and earth walls.
	var space := get_world_3d().direct_space_state
	var excl: Array[RID] = []
	if is_instance_valid(caster):
		excl.append(caster.get_rid())
	var q := PhysicsRayQueryParameters3D.create(from, to + velocity.normalized() * size, 1 | 8 | 16, excl)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		var col: Object = hit["collider"]
		if col is EarthWall:
			(col as EarthWall).take_damage(float(spell.get("damage", 10.0)) * float(spell.get("count", 1)) * 0.6 + 4.0)
		_explode(hit["position"] - velocity.normalized() * 0.1, null)
		return
	global_position = to
	_curr_pos = to

func _hit_wizard(w: Wizard) -> void:
	w.take_hit(float(spell.get("damage", 10.0)), _effects(w))

func _effects(w: Wizard) -> Dictionary:
	var info := {}
	if spell.has("knockback"):
		var kb := velocity.normalized()
		kb.y = 0
		if spell.has("explode"):
			kb = (w.global_position - global_position)
			kb.y = 0
		info["knockback"] = kb.normalized() * float(spell["knockback"])
	for k in ["burn", "slow", "slow_time", "stun"]:
		if spell.has(k):
			info[k] = spell[k]
	return info

func _explode(pos: Vector3, direct: Wizard) -> void:
	_dead = true
	var world := get_parent()
	var color: Color = spell["color"]
	var radius := float(spell.get("explode", 0.0))
	if radius > 0.0:
		var t := caster.opponent if is_instance_valid(caster) else null
		if t and t != direct and t.alive:
			var d := t.global_position + Vector3(0, 0.9, 0)
			if d.distance_to(pos) <= radius + 0.4:
				var fall := clampf(1.0 - d.distance_to(pos) / (radius + 0.4), 0.35, 1.0)
				t.take_hit(float(spell.get("damage", 10.0)) * fall, _effects(t))
		VFX.explosion(world, pos, color, radius)
		Sfx.play_at("explosion", pos, -2.0 + radius, 1.2 - radius * 0.08)
	elif spell.has("rock"):
		VFX.burst(world, pos, Color(0.5, 0.4, 0.3), 18, 4.0, 0.3, 0.6, {"additive": false, "energy": 1.0, "gravity": Vector3(0, -9, 0)})
		Sfx.play_at("rock_hit", pos, -2.0)
	else:
		VFX.burst(world, pos, color, 24, 4.0, 0.3, 0.45)
		VFX.flash_light(world, pos, color, 3.0, 4.0, 0.25)
		Sfx.play_at("splash" if color.b > 0.8 else "explosion", pos, -8.0, 1.5)
	# Let the trail fade instead of popping.
	_core.visible = false
	if _light:
		# Free now (not with the node 0.6 s later) to return the light slot.
		_light.queue_free()
		_light = null
	_trail.emitting = false
	remove_from_group("projectiles")
	get_tree().create_timer(0.6).timeout.connect(queue_free)

## Wind spells reflect enemy projectiles back at their caster.
func deflect(new_owner: Wizard) -> void:
	if _dead:
		return
	var old := caster
	caster = new_owner
	var target_pos := old.global_position + Vector3(0, 1.0, 0) if is_instance_valid(old) else global_position - velocity
	velocity = (target_pos - global_position).normalized() * speed * 1.15
	_age = 0.0
	VFX.burst(get_parent(), global_position, Color(0.8, 1.0, 0.9), 16, 4.0, 0.3, 0.4)

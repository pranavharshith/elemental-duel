class_name SpellRuntime
extends RefCounted
## Executes a resolved spell. Each spell "type" has one generic implementation
## that is fully parameterised by its SpellBook entry.

const MAX_GROUND_RANGE := 22.0

static func cast(caster: Wizard, key: String, aim: Vector3) -> void:
	var spell := SpellBook.get_spell(key)
	if spell.is_empty():
		return
	var world := caster.get_parent()
	var color: Color = spell["color"]
	match String(spell["type"]):
		"projectile":
			_cast_projectile(world, caster, spell, aim)
		"strike":
			_cast_strike(world, caster, spell, aim)
		"area":
			_cast_area(world, caster, spell, aim)
		"wall":
			_cast_wall(world, caster, spell, aim)
		"cone":
			_cast_cone(world, caster, spell, aim)
		"beam":
			_cast_beam(world, caster, spell, aim)
		"self":
			caster.apply_self_buff(spell)
			VFX.burst(world, caster.global_position + Vector3.UP, color, 40, 4.0, 0.35, 0.8, {"emit_radius": 0.6, "gravity": Vector3(0, 3, 0)})
			VFX.shockwave(world, caster.global_position + Vector3(0, 0.1, 0), color, 2.2)
			Sfx.play_at("buff", caster.global_position)
	VFX.burst(world, caster.cast_origin(), color, 14, 3.0, 0.22, 0.35)
	VFX.flash_light(world, caster.cast_origin(), color, 3.0, 4.0, 0.25)

## Ground target under the crosshair, limited to range and the arena disk.
static func ground_point(caster: Wizard, aim: Vector3) -> Vector3:
	var p := Vector3(aim.x, 0.0, aim.z)
	var from := Vector3(caster.global_position.x, 0.0, caster.global_position.z)
	if from.distance_to(p) > MAX_GROUND_RANGE:
		p = from + (p - from).normalized() * MAX_GROUND_RANGE
	return Arena.clamp_to_arena(p, 0.3)

## Aiming at the floor means "send it along the ground toward there": lift the
## target to chest height so projectiles and bolts fly level instead of diving.
static func air_target(aim: Vector3) -> Vector3:
	return Vector3(aim.x, maxf(aim.y, 1.0), aim.z)

static func _cast_projectile(world: Node, caster: Wizard, spell: Dictionary, aim: Vector3) -> void:
	var origin := caster.cast_origin()
	var dir := (air_target(aim) - origin).normalized()
	if spell.has("gravity"):
		# Lob arc: add lift proportional to distance so boulders land near the aim.
		var flat := Vector3(aim.x - origin.x, 0, aim.z - origin.z).length()
		var t := flat / float(spell["speed"])
		dir = ((air_target(aim) - origin) / maxf(t, 0.05) + Vector3.UP * 0.5 * float(spell["gravity"]) * t).normalized()
	if dir.length() < 0.5:
		dir = -caster.global_transform.basis.z
	var count := int(spell.get("count", 1))
	var spread := deg_to_rad(float(spell.get("spread", 0.0)))
	for i in count:
		var offset := 0.0
		if count > 1:
			offset = lerpf(-spread, spread, float(i) / (count - 1))
		var d := dir.rotated(Vector3.UP, offset)
		var proj := Projectile.new()
		proj.setup(caster, spell, d)
		world.add_child(proj)
		proj.global_position = origin
	if spell.has("rock"):
		Sfx.play_at("earth_cast", origin, -4.0, 1.3)
	elif spell.has("shard"):
		Sfx.play_at("water_cast", origin, -2.0, 1.4)
	else:
		var c: Color = spell["color"]
		var snd := "fire_cast"
		if c.b > 0.8 and c.r < 0.6:
			snd = "water_cast"
		if spell.has("stretch"):
			snd = "zap"
		Sfx.play_at(snd, origin, -2.0)

static func _cast_strike(world: Node, caster: Wizard, spell: Dictionary, aim: Vector3) -> void:
	var target := ground_point(caster, aim)
	var points: Array[Vector3] = []
	if spell.has("line"):
		var from := Vector3(caster.global_position.x, 0, caster.global_position.z)
		var dir := target - from
		dir.y = 0
		if dir.length() < 1.0:
			dir = -caster.global_transform.basis.z
		dir = dir.normalized()
		var n := int(spell["line"])
		for i in n:
			points.append(Arena.clamp_to_arena(from + dir * (1.8 + i * 1.6), 0.2))
	elif spell.has("count"):
		var n := int(spell["count"])
		points.append(target)
		var scatter := float(spell.get("scatter", 3.0))
		for i in n - 1:
			var a := randf() * TAU
			var r := randf_range(scatter * 0.35, scatter)
			points.append(Arena.clamp_to_arena(target + Vector3(cos(a), 0, sin(a)) * r, 0.2))
	else:
		points.append(target)
	var stagger := float(spell.get("stagger", 0.0))
	for i in points.size():
		var s := Strike.new()
		s.setup(caster, spell, float(spell.get("delay", 0.6)) + stagger * i)
		world.add_child(s)
		s.global_position = points[i]
	Sfx.play_at("charge", target, -6.0)

static func _cast_area(world: Node, caster: Wizard, spell: Dictionary, aim: Vector3) -> void:
	var a := AreaEffect.new()
	a.setup(caster, spell)
	world.add_child(a)
	a.global_position = ground_point(caster, aim)
	Sfx.play_at("water_cast" if not spell.has("zap") else "thunder", a.global_position, -2.0, 0.7)

static func _cast_wall(world: Node, caster: Wizard, spell: Dictionary, aim: Vector3) -> void:
	var dir := aim - caster.global_position
	dir.y = 0
	if dir.length() < 0.5:
		dir = -caster.global_transform.basis.z
	dir = dir.normalized()
	var segments := int(spell.get("segments", 1))
	var yaw_center := atan2(dir.x, dir.z)
	var angles := [0.0] if segments == 1 else [-0.85, 0.0, 0.85]
	for ang in angles:
		var d := dir.rotated(Vector3.UP, ang)
		var w := EarthWall.new()
		w.setup(caster, spell)
		world.add_child(w)
		var p := caster.global_position + d * (2.6 if segments == 1 else 2.4)
		p = Arena.clamp_to_arena(p, 0.5)
		p.y = 0.0
		w.global_position = p
		w.rotation.y = yaw_center + ang
	Sfx.play_at("earth_cast", caster.global_position + dir * 2.5)

static func _cast_cone(world: Node, caster: Wizard, spell: Dictionary, aim: Vector3) -> void:
	var origin := caster.global_position + Vector3(0, 1.0, 0)
	var dir := aim - caster.global_position
	dir.y = 0
	if dir.length() < 0.5:
		dir = -caster.global_transform.basis.z
	dir = dir.normalized()
	var rng := float(spell["range"])
	var half := deg_to_rad(float(spell["angle"]) * 0.5)
	var color: Color = spell["color"]
	var opp := caster.opponent
	if opp and opp.alive:
		var to := opp.global_position - caster.global_position
		to.y = 0
		if to.length() <= rng and (to.length() < 0.8 or dir.angle_to(to.normalized()) <= half) and _clear_line(caster, origin, opp.global_position + Vector3.UP):
			var falloff := clampf(1.2 - to.length() / rng, 0.45, 1.0)
			opp.take_hit(float(spell["damage"]), {"knockback": to.normalized() * float(spell["knockback"]) * falloff})
	if spell.get("deflect", false):
		for p in caster.get_tree().get_nodes_in_group("projectiles"):
			var proj := p as Projectile
			if proj.caster == caster:
				continue
			var to := proj.global_position - caster.global_position
			to.y = 0
			if to.length() <= rng and dir.angle_to(to.normalized()) <= half + 0.3:
				proj.deflect(caster)
	# Visual: a fan of fast particles.
	var p := VFX.make_particles(color, int(60 + rng * 6), 0.55, 0.6, {"one_shot": true, "explosive": 0.9,
		"direction": dir, "spread": rad_to_deg(half), "vel_min": rng * 1.2, "vel_max": rng * 2.0,
		"damping": rng * 1.5, "scale_start": 0.4, "scale_end": 1.6, "energy": 1.6})
	world.add_child(p)
	p.global_position = origin
	p.emitting = true
	p.finished.connect(p.queue_free)
	if color.b > 0.9 and color.r < 0.3:
		Sfx.play_at("splash", origin, 0.0)
	else:
		Sfx.play_at("wind_cast", origin, 0.0)

static func _cast_beam(world: Node, caster: Wizard, spell: Dictionary, aim: Vector3) -> void:
	var origin := caster.cast_origin()
	var dir := (air_target(aim) - origin).normalized()
	var end := origin + dir * float(spell["range"])
	var space := caster.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, end, 1 | 2 | 8 | 16, [caster.get_rid()])
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		end = hit["position"]
		var col: Object = hit["collider"]
		if col is Wizard:
			(col as Wizard).take_hit(float(spell["damage"]), {"stun": float(spell.get("stun", 0.0))})
		elif col is EarthWall:
			(col as EarthWall).take_damage(float(spell["damage"]))
	# Aim assist: a near miss right next to the opponent still connects.
	elif caster.opponent and caster.opponent.alive:
		var chest := caster.opponent.global_position + Vector3.UP
		var closest := Geometry3D.get_closest_point_to_segment(chest, origin, end)
		if closest.distance_to(chest) < 0.7:
			caster.opponent.take_hit(float(spell["damage"]), {"stun": float(spell.get("stun", 0.0))})
			end = chest
	var c: Color = spell["color"]
	VFX.bolt(world, origin, end, c, 0.09, 0.3)
	VFX.bolt(world, origin, end, Color(1, 1, 1), 0.04, 0.2)
	VFX.burst(world, end, c, 25, 5.0, 0.25, 0.4)
	VFX.flash_light(world, end, c, 5.0, 6.0, 0.3)
	Sfx.play_at("zap", origin, 0.0)

static func _clear_line(caster: Wizard, from: Vector3, to: Vector3) -> bool:
	var space := caster.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, 8, [caster.get_rid()])
	return space.intersect_ray(q).is_empty()

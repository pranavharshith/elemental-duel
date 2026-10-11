class_name VFX
extends RefCounted
## Procedural visual effects built from GPUParticles3D, meshes and lights.

## Dynamic omni lights are the most expensive thing in this renderer: every
## light re-draws every mesh it touches (including the whole floor) in an
## extra pass. Flashes and projectile glows share this budget; when it is
## full, effects simply skip their light (the emissive core + glow still read).
const MAX_DYNAMIC_LIGHTS := 4
## Unbounded caches would grow forever with per-spell colours/sizes.
const MAX_CACHE := 256

static var _soft_tex: GradientTexture2D
static var _mat_cache: Dictionary = {}
static var _pm_cache: Dictionary = {}
static var _quad_cache: Dictionary = {}
static var _mesh_cache: Dictionary = {}
static var _active_lights := 0
## While > 0 no effect lights are created (shader warm-up).
static var lights_suspended := 0

## Returns a budgeted OmniLight3D (not yet in the tree) or null when the
## budget is used up. Add it to the tree right away; it frees its slot when it
## leaves the tree.
static func budget_light(color: Color, energy: float, rng: float) -> OmniLight3D:
	var game := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Game")
	var quality: int = game.graphics_quality if game else 1
	var budget: int = [0, 2, MAX_DYNAMIC_LIGHTS][quality]
	if _active_lights >= budget or lights_suspended > 0:
		return null
	_active_lights += 1
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.tree_exiting.connect(func() -> void: _active_lights = maxi(0, _active_lights - 1), CONNECT_ONE_SHOT)
	return l

static func _cached_mesh(key: String, build: Callable) -> Mesh:
	var m: Mesh = _mesh_cache.get(key)
	if m == null:
		if _mesh_cache.size() > MAX_CACHE:
			_mesh_cache.clear()
		m = build.call()
		_mesh_cache[key] = m
	return m

static func _torus(inner: float, outer: float, rings: int = 48) -> Mesh:
	return _cached_mesh("torus_%s_%s_%d" % [inner, outer, rings], func() -> Mesh:
		var tm := TorusMesh.new()
		tm.inner_radius = inner
		tm.outer_radius = outer
		tm.rings = rings
		return tm)

static func _disc(radius: float) -> Mesh:
	return _cached_mesh("disc_%s" % radius, func() -> Mesh:
		var cyl := CylinderMesh.new()
		cyl.top_radius = radius
		cyl.bottom_radius = radius
		cyl.height = 0.02
		cyl.radial_segments = 48
		cyl.rings = 1
		return cyl)

static func _unit_box() -> Mesh:
	return _cached_mesh("unit_box", func() -> Mesh: return BoxMesh.new())

static func soft_texture() -> GradientTexture2D:
	if _soft_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.75))
		_soft_tex = GradientTexture2D.new()
		_soft_tex.gradient = g
		_soft_tex.fill = GradientTexture2D.FILL_RADIAL
		_soft_tex.fill_from = Vector2(0.5, 0.5)
		_soft_tex.fill_to = Vector2(1.0, 0.5)
		_soft_tex.width = 64
		_soft_tex.height = 64
	return _soft_tex

## Billboarded, vertex-coloured particle material. The arena is white, so
## additive blending would vanish against it: "glowing" particles use normal
## alpha blending with an HDR tint instead, which stays saturated on white and
## still feeds the glow pass.
static func particle_material(energy: float = 3.0, glowing: bool = true) -> StandardMaterial3D:
	var key := "%s_%s" % [energy, glowing]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_texture()
	var e := lerpf(1.0, energy, 0.5) if glowing else 1.0
	m.albedo_color = Color(e, e, e, 1.0)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_cache[key] = m
	return m

## Unshaded, alpha-blended material for rings, bolts and markers.
static func flat_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

static var _ramp_cache: Dictionary = {}
static var _curve_cache: Dictionary = {}

static func _ramp(color: Color, alpha: float = 1.0) -> GradientTexture1D:
	var key := "%s_%s" % [color.to_html(), alpha]
	if _ramp_cache.has(key):
		return _ramp_cache[key]
	var g := Gradient.new()
	g.set_color(0, Color(color.lightened(0.3), alpha))
	g.set_color(1, Color(color.darkened(0.2), 0.0))
	g.add_point(0.4, Color(color, 0.9 * alpha))
	var t := GradientTexture1D.new()
	t.gradient = g
	_ramp_cache[key] = t
	return t

static func _scale_curve(start: float, end: float) -> CurveTexture:
	var key := Vector2(start, end)
	if _curve_cache.has(key):
		return _curve_cache[key]
	var c := Curve.new()
	c.max_value = maxf(1.0, maxf(start, end))
	c.add_point(Vector2(0, start))
	c.add_point(Vector2(1, end))
	var t := CurveTexture.new()
	t.curve = c
	_curve_cache[key] = t
	return t

static func make_particles(color: Color, amount: int, lifetime: float, size: float, opts: Dictionary = {}) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = opts.get("local", false)
	p.one_shot = opts.get("one_shot", false)
	p.explosiveness = opts.get("explosive", 0.0)
	p.fixed_fps = 60
	p.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	p.process_material = _process_material(color, opts)
	p.draw_pass_1 = _particle_quad(size, opts.get("energy", 3.0), opts.get("additive", true))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

## Process materials are shared between identical effects: building one
## generates shader code and GPU resources, which caused hitches when every
## burst/trail made its own.
static func _process_material(color: Color, opts: Dictionary) -> ParticleProcessMaterial:
	var key := "%s|%s" % [color.to_html(), str(_pm_opts(opts))]
	var cached: ParticleProcessMaterial = _pm_cache.get(key)
	if cached:
		return cached
	if _pm_cache.size() > MAX_CACHE:
		_pm_cache.clear()
	var pm := ParticleProcessMaterial.new()
	pm.direction = opts.get("direction", Vector3.UP)
	pm.spread = opts.get("spread", 180.0)
	pm.initial_velocity_min = opts.get("vel_min", 0.5)
	pm.initial_velocity_max = opts.get("vel_max", 2.0)
	pm.gravity = opts.get("gravity", Vector3.ZERO)
	pm.damping_min = opts.get("damping", 0.0)
	pm.damping_max = opts.get("damping", 0.0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.scale_curve = _scale_curve(opts.get("scale_start", 1.0), opts.get("scale_end", 0.1))
	# Smoke-style (non-additive) particles stay translucent so they never wall off the view.
	pm.color_ramp = _ramp(color, 0.85 if opts.get("additive", true) else float(opts.get("alpha", 0.3)))
	if opts.has("emit_radius"):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = opts["emit_radius"]
	if opts.has("emit_ring"):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3.UP
		pm.emission_ring_radius = opts["emit_ring"]
		pm.emission_ring_inner_radius = opts["emit_ring"] * 0.8
		pm.emission_ring_height = 0.1
	if opts.has("orbit"):
		pm.orbit_velocity_min = opts["orbit"]
		pm.orbit_velocity_max = opts["orbit"]
	if opts.has("tangential"):
		pm.tangential_accel_min = opts["tangential"]
		pm.tangential_accel_max = opts["tangential"]
	if opts.has("radial"):
		pm.radial_accel_min = opts["radial"]
		pm.radial_accel_max = opts["radial"]
	if opts.has("emit_box"):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = opts["emit_box"]
	_pm_cache[key] = pm
	return pm

## Options that don't affect the process material (emitter-only settings).
static func _pm_opts(opts: Dictionary) -> Dictionary:
	var o := opts.duplicate()
	for k in ["local", "one_shot", "explosive", "energy"]:
		o.erase(k)
	return o

static func _particle_quad(size: float, energy: float, glowing: bool) -> QuadMesh:
	var key := "%s_%s_%s" % [snappedf(size, 0.01), energy, glowing]
	var quad: QuadMesh = _quad_cache.get(key)
	if quad == null:
		if _quad_cache.size() > MAX_CACHE:
			_quad_cache.clear()
		quad = QuadMesh.new()
		quad.size = Vector2(size, size)
		quad.material = particle_material(energy, glowing)
		_quad_cache[key] = quad
	return quad

## Spawns a one-shot effect that frees itself.
static func burst(parent: Node, pos: Vector3, color: Color, amount: int, speed: float, size: float, lifetime: float = 0.6, opts: Dictionary = {}) -> void:
	if parent == null:
		return
	var o := opts.duplicate()
	o["one_shot"] = true
	o["explosive"] = o.get("explosive", 0.95)
	o["vel_min"] = speed * 0.4
	o["vel_max"] = speed
	o["damping"] = o.get("damping", speed * 1.2)
	var p := make_particles(color, amount, lifetime, size, o)
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)

static func flash_light(parent: Node, pos: Vector3, color: Color, energy: float, rng: float, duration: float) -> void:
	if parent == null:
		return
	var l := budget_light(color, energy, rng)
	if l == null:
		return
	parent.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, duration)
	tw.tween_callback(l.queue_free)

static func shockwave(parent: Node, pos: Vector3, color: Color, radius: float, duration: float = 0.45) -> void:
	if parent == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _torus(0.85, 1.0)
	var m := flat_material(Color(color.r * 1.3, color.g * 1.3, color.b * 1.3, 0.9))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3(0.2, 0.3, 0.2)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 0.3, radius), duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(m, "albedo_color:a", 0.0, duration)
	tw.chain().tween_callback(mi.queue_free)

static func explosion(parent: Node, pos: Vector3, color: Color, radius: float) -> void:
	# Kept light: with normal blending, dense bursts would hide the wizards.
	burst(parent, pos, color, int(18 + radius * 10), radius * 5.0, 0.45 + radius * 0.1, 0.6)
	burst(parent, pos, color.lightened(0.4), 6, radius * 3.0, 0.35, 0.25)
	burst(parent, pos, Color(0.25, 0.22, 0.22), int(10 + radius * 6), radius * 2.0, 0.9 + radius * 0.2, 1.2,
		{"additive": false, "energy": 1.0, "gravity": Vector3(0, 1.5, 0)})
	shockwave(parent, Vector3(pos.x, 0.1, pos.z), color, radius)
	flash_light(parent, pos + Vector3.UP * 0.5, color, 6.0, radius * 3.5, 0.4)

static func status_particles(owner: Node3D, color: Color, size: float, rise: float, orbit: float = 0.0) -> GPUParticles3D:
	var opts := {"local": false, "emit_radius": 0.45, "vel_min": 0.2, "vel_max": 0.6,
		"gravity": Vector3(0, rise, 0), "scale_end": 0.0}
	if orbit != 0.0:
		opts = {"local": true, "emit_ring": 0.5, "orbit": orbit, "vel_min": 0.0, "vel_max": 0.1, "scale_end": 0.2}
	opts["energy"] = 1.4
	var p := make_particles(color, 18, 0.7, size * 0.4, opts)
	p.position = Vector3(0, 2.1 if orbit != 0.0 else 1.0, 0)
	p.emitting = false
	owner.add_child(p)
	return p

static func portal(parent: Node, pos: Vector3, color: Color) -> void:
	shockwave(parent, pos + Vector3(0, 0.1, 0), color, 1.6, 0.5)
	burst(parent, pos + Vector3(0, 1.0, 0), color, 40, 3.0, 0.3, 0.6, {"emit_radius": 0.5, "gravity": Vector3(0, 3, 0)})
	var ring := MeshInstance3D.new()
	ring.mesh = _torus(0.75, 0.9, 64)
	var m := flat_material(Color(color.r * 1.5, color.g * 1.5, color.b * 1.5, 1))
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ring)
	ring.global_position = pos + Vector3(0, 0.05, 0)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "position:y", ring.position.y + 2.0, 0.45)
	tw.tween_property(ring, "scale", Vector3(0.2, 1, 0.2), 0.45)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.45)
	tw.chain().tween_callback(ring.queue_free)
	flash_light(parent, pos + Vector3.UP, color, 4.0, 4.0, 0.35)

## One emitter whose box spans the jump line (previously ten separate
## particle systems per teleport).
static func jump_trail(parent: Node, from: Vector3, to: Vector3, color: Color) -> void:
	if parent == null:
		return
	var length := from.distance_to(to)
	var o := {"one_shot": true, "explosive": 1.0, "vel_min": 0.24, "vel_max": 0.6, "damping": 0.72,
		"emit_box": Vector3(0.06, 0.06, maxf(length * 0.5, 0.05))}
	var p := make_particles(color, 40, 0.45, 0.25, o)
	parent.add_child(p)
	var mid := (from + to) * 0.5
	if length > 0.01:
		var dir := (to - from) / length
		var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
		p.global_transform = Transform3D(Basis.looking_at(dir, up), mid)
	else:
		p.global_position = mid
	p.emitting = true
	p.finished.connect(p.queue_free)

## Jagged lightning bolt made from thin stretched boxes.
static func bolt(parent: Node, from: Vector3, to: Vector3, color: Color, width: float = 0.08, duration: float = 0.25) -> void:
	if parent == null:
		return
	var root := Node3D.new()
	parent.add_child(root)
	var m := flat_material(Color(color.r * 1.6, color.g * 1.6, color.b * 1.6, 1))
	var points: Array[Vector3] = [from]
	var segs := maxi(4, int(from.distance_to(to) / 1.2))
	var side := (to - from).cross(Vector3.UP).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	var side2 := (to - from).cross(side).normalized()
	for i in range(1, segs):
		var p := from.lerp(to, float(i) / segs)
		var jitter := 0.35 * from.distance_to(to) / segs
		p += side * randf_range(-jitter, jitter) + side2 * randf_range(-jitter, jitter)
		points.append(p)
	points.append(to)
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var seg_len := a.distance_to(b)
		if seg_len < 0.001:
			continue
		var mi := MeshInstance3D.new()
		# One shared unit cube, stretched by the transform (no mesh per segment).
		mi.mesh = _unit_box()
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		var dir := (b - a) / seg_len
		var basis := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
		basis.x *= width
		basis.y *= width
		basis.z *= seg_len + width
		mi.global_transform = Transform3D(basis, (a + b) * 0.5)
	var tw := root.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, duration)
	tw.tween_callback(root.queue_free)

static func damage_number(parent: Node, pos: Vector3, amount: float, color: Color) -> void:
	if parent == null or amount < 0.5:
		return
	var l := Label3D.new()
	l.text = str(int(round(amount)))
	l.font_size = 64 if amount < 15 else 88
	l.outline_size = 14
	l.modulate = color if amount < 15 else Color(1.0, 0.75, 0.3)
	l.outline_modulate = Color(0.1, 0.05, 0.1)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.pixel_size = 0.006
	parent.add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "global_position:y", pos.y + 1.2, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)

## Ground decal-like ring that warns where a strike will land.
static func warning_marker(parent: Node, pos: Vector3, radius: float, color: Color, duration: float) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = Vector3(pos.x, 0.06, pos.z)
	var disc := MeshInstance3D.new()
	var cyl := _disc(radius)
	disc.mesh = cyl
	# Warm, darker tint so the warning reads clearly on the white floor.
	var warn := color.lerp(Color(0.9, 0.2, 0.1), 0.35)
	var dm := flat_material(Color(warn, 0.22))
	dm.render_priority = 1
	disc.material_override = dm
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(disc)
	var edge := MeshInstance3D.new()
	edge.mesh = _torus(radius - 0.08, radius)
	edge.scale = Vector3(1, 0.2, 1)
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var em := flat_material(Color(warn.darkened(0.15), 0.95))
	em.render_priority = 2
	edge.material_override = em
	root.add_child(edge)
	var fill := MeshInstance3D.new()
	fill.mesh = cyl
	fill.material_override = dm
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fill.scale = Vector3(0.01, 1.5, 0.01)
	root.add_child(fill)
	var tw := root.create_tween()
	tw.tween_property(fill, "scale", Vector3(1, 1.5, 1), duration)
	tw.tween_callback(root.queue_free)
	return root

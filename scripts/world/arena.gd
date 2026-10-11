class_name Arena
extends Node3D
## Open duelling floor with a batched ornamental colonnade outside the boundary.
const PLAYABLE_RADIUS := 17.2
const WALL_INNER := 18.0          # inner face of the rim wall and boundary ring
const WALL_THICKNESS := 0.6
const WALL_HEIGHT := 0.85
const SPAWNS := [Vector3(0, 0, 9.0), Vector3(0, 0, -9.0)]

const FLOOR_COLOR := Color(0.6, 0.61, 0.64)
const LINE_COLOR := Color(0.36, 0.37, 0.41)
const BORDER_COLOR := Color(0.05, 0.05, 0.06)
const WALL_COLOR := Color(0.12, 0.19, 0.23)
const GROUND_COLOR := Color(0.10, 0.16, 0.20)
const SKY_COLOR := Color(0.37, 0.49, 0.57)

var _env: Environment
var _sun: DirectionalLight3D

func _ready() -> void:
	_build_environment()
	_build_floor()
	_build_wall()
	_build_markings()
	_build_colosseum()
	Game.presentation_changed.connect(_apply_quality)
	_apply_quality()
	# Compile spell/VFX shaders now (menu / round countdown), not mid-fight.
	ShaderWarmup.run(self, _env, _sun)

static var _emissive_cache: Dictionary = {}

## Shared, read-only emissive material. Use for materials that are never
## modified after creation (orbs, staff tips) so re-tinting doesn't allocate a
## new material every cast.
static func emissive_shared(color: Color, energy: float = 2.0, unshaded: bool = false) -> StandardMaterial3D:
	var key := "%s_%s_%s" % [color.to_html(), energy, unshaded]
	var m: StandardMaterial3D = _emissive_cache.get(key)
	if m == null:
		m = emissive(color, energy, unshaded)
		_emissive_cache[key] = m
	return m

static func emissive(color: Color, energy: float = 2.0, unshaded: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

static func matte(color: Color, roughness: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m

# ------------------------------------------------------------------ environment
func _build_environment() -> void:
	var env := Environment.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#122d48")
	sky_material.sky_horizon_color = Color("#91b0b8")
	sky_material.ground_bottom_color = Color("#152a36")
	sky_material.ground_horizon_color = Color("#7d9b9f")
	sky_material.sky_curve = 0.2
	sky_material.sun_angle_max = 12.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.83, 1.0)
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	# Compatibility rendering uses emissive spell cores without a bloom pass.
	env.glow_enabled = false
	env.glow_intensity = 0.6
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.5
	# No SSAO: the Compatibility renderer (desktop GL + web) ignores it anyway.
	# Light fog melts the far ground into the background.
	env.fog_enabled = true
	env.fog_light_color = SKY_COLOR
	env.fog_density = 0.0025
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_env = env

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.84, 0.64)
	sun.light_energy = 1.25
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	sun.shadow_blur = 2.0
	sun.shadow_opacity = 0.55
	# Two cascades over 48 m keep shadows crisp across the expanded arena
	# near the camera while rendering the shadow casters twice per frame
	# instead of four times (the default 4-split PSSM).
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 48.0
	sun.directional_shadow_split_1 = 0.3
	add_child(sun)
	_sun = sun

# ------------------------------------------------------------------ floor
func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "Floor"
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	body.add_child(shape)
	add_child(body)

	var disk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = WALL_INNER + WALL_THICKNESS
	cyl.bottom_radius = WALL_INNER + WALL_THICKNESS
	cyl.height = 0.1
	cyl.radial_segments = 96
	disk.mesh = cyl
	disk.position.y = -0.05
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = load("res://assets/shaders/arena_stone.gdshader")
	disk.material_override = floor_mat
	# Flat receivers never need to cast: keeps them out of the shadow passes.
	disk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disk)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(160, 160)
	ground.mesh = plane
	ground.position.y = -0.12
	ground.material_override = matte(GROUND_COLOR, 1.0)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)

# ------------------------------------------------------------------ boundary
func _build_wall() -> void:
	# Visible rim: one continuous tube mesh (no seams, no gaps).
	var wall := MeshInstance3D.new()
	wall.name = "RimWall"
	wall.mesh = _ring_mesh(WALL_INNER, WALL_INNER + WALL_THICKNESS, WALL_HEIGHT, 128)
	wall.material_override = matte(WALL_COLOR, 0.5)
	add_child(wall)

	# Camera-only collider matching the visible rim (layer 32 "camera_block"),
	# so the spring arm slides over it instead of looking through it.
	var cam_block := StaticBody3D.new()
	cam_block.name = "RimCameraBlock"
	cam_block.collision_layer = 32
	cam_block.collision_mask = 0
	for i in 64:
		var a := TAU * float(i) / 64
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(TAU * (WALL_INNER + WALL_THICKNESS) / 64.0 + 0.08, WALL_HEIGHT, WALL_THICKNESS)
		cs.shape = box
		cs.position = Vector3(sin(a), 0, cos(a)) * (WALL_INNER + WALL_THICKNESS * 0.5) + Vector3(0, WALL_HEIGHT * 0.5, 0)
		cs.rotation.y = a
		cam_block.add_child(cs)
	add_child(cam_block)

	# Invisible collision ring, much taller than the art: overlapping boxes whose
	# inner faces sit exactly on WALL_INNER. Layer 16 blocks wizards and spells
	# but not the camera, so the view never gets trapped against the rim.
	var ring := StaticBody3D.new()
	ring.name = "BoundaryRing"
	ring.collision_layer = 16
	var segments := 48
	var depth := 1.2
	for i in segments:
		var a := TAU * float(i) / segments
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(TAU * (WALL_INNER + depth) / segments + 0.1, 12.0, depth)
		cs.shape = box
		cs.position = Vector3(sin(a), 0, cos(a)) * (WALL_INNER + depth * 0.5) + Vector3(0, 6.0, 0)
		cs.rotation.y = a
		ring.add_child(cs)
	add_child(ring)

## Hollow cylinder (inner wall, outer wall, top cap) with smooth normals.
static func _ring_mesh(r_in: float, r_out: float, h: float, seg: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in seg:
		var a0 := TAU * float(i) / seg
		var a1 := TAU * float(i + 1) / seg
		var d0 := Vector3(sin(a0), 0, cos(a0))
		var d1 := Vector3(sin(a1), 0, cos(a1))
		var up := Vector3.UP * h
		# Outer face (normal outward).
		_quad(st, d0 * r_out, d1 * r_out, d1 * r_out + up, d0 * r_out + up, d0, d1, d1, d0)
		# Inner face (normal inward).
		_quad(st, d1 * r_in, d0 * r_in, d0 * r_in + up, d1 * r_in + up, -d1, -d0, -d0, -d1)
		# Top cap.
		_quad(st, d0 * r_in + up, d0 * r_out + up, d1 * r_out + up, d1 * r_in + up, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP)
	return st.commit()

## Flat annulus lying on the floor (normal up).
static func _band_mesh(r_in: float, r_out: float, seg: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in seg:
		var a0 := TAU * float(i) / seg
		var a1 := TAU * float(i + 1) / seg
		var d0 := Vector3(sin(a0), 0, cos(a0))
		var d1 := Vector3(sin(a1), 0, cos(a1))
		var n := Vector3.UP
		_quad(st, d0 * r_in, d0 * r_out, d1 * r_out, d1 * r_in, n, n, n, n)
	return st.commit()

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3) -> void:
	# Godot uses clockwise winding for front faces.
	for v in [[a, na], [c, nc], [b, nb], [a, na], [d, nd], [c, nc]]:
		st.set_normal(v[1])
		st.add_vertex(v[0])

# ------------------------------------------------------------------ markings
func _build_markings() -> void:
	var line := matte(Color(0.65, 0.48, 0.23), 0.45)
	for r in [2.0, 2.15]:
		_flat_ring(r, 0.035, line)
	# Solid black band along the edge: the "out of bounds" line, readable from
	# any camera angle. Its outer edge meets the black rim wall.
	var band := MeshInstance3D.new()
	band.mesh = _band_mesh(WALL_INNER - 0.9, WALL_INNER + 0.01, 128)
	band.position.y = 0.004
	var band_mat := matte(BORDER_COLOR, 0.6)
	band_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	band.material_override = band_mat
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(band)
	# Thin dark line just inside the band as a warning edge.
	_flat_ring(WALL_INNER - 1.45, 0.03, matte(BORDER_COLOR, 0.6))
	# Spawn marks: soft rings in a neutral grey.
	for s in SPAWNS:
		var m := _flat_ring(1.1, 0.04, line)
		m.position = Vector3(s.x, m.position.y, s.z)

func _flat_ring(radius: float, half_width: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius - half_width
	tm.outer_radius = radius + half_width
	tm.rings = 96
	tm.ring_segments = 6
	mi.mesh = tm
	mi.scale = Vector3(1, 0.05, 1)
	mi.position.y = 0.006
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

## Clamp a point onto the playable disk (used by teleport/AI).
static func clamp_to_arena(p: Vector3, margin: float = 0.0) -> Vector3:
	var flat := Vector3(p.x, 0, p.z)
	var r := PLAYABLE_RADIUS - margin
	if flat.length() > r:
		flat = flat.normalized() * r
	return Vector3(flat.x, p.y, flat.z)

func _apply_quality() -> void:
	_sun.shadow_enabled = Game.graphics_quality > 0

func _build_colosseum() -> void:
	var bronze := matte(Color("#98764a"), 0.4)
	bronze.metallic = 0.65
	for radius in [WALL_INNER + 0.12, WALL_INNER + 0.48]:
		var crown := MeshInstance3D.new()
		crown.mesh = _ring_mesh(radius, radius + 0.08, 0.06, 128)
		crown.position.y = WALL_HEIGHT
		crown.material_override = bronze
		crown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(crown)
	var deck := MeshInstance3D.new()
	deck.mesh = _ring_mesh(18.6, 23.0, 0.5, 96)
	deck.position.y = -0.5
	deck.material_override = matte(Color("#243944"))
	deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(deck)
	var placements: Array[Transform3D] = []
	for i in 20:
		var a := TAU * i / 20.0
		var basis := Basis(Vector3.UP, a).scaled(Vector3(1.4, 1.65, 1.4))
		placements.append(Transform3D(basis, Vector3(sin(a) * 22.0, 0, cos(a) * 22.0)))
	_batch_asset("res://assets/models/arena/pillar_decorated.gltf", placements)
	placements.clear()
	for i in 20:
		var a := TAU * (i + 0.5) / 20.0
		var basis := Basis(Vector3.UP, a).scaled(Vector3(1.4, 1.1, 1.0))
		placements.append(Transform3D(basis, Vector3(sin(a) * 22.0, 0, cos(a) * 22.0)))
	_batch_asset("res://assets/models/arena/wall_arched.gltf", placements)
	var colors := [Color("#eb8449"), Color("#59baff"), Color("#d4ad6b"), Color("#71d5b5"), Color("#c6a9fa")]
	for i in 5:
		var a := TAU * i / 5.0 + PI / 5.0
		var pos := Vector3(sin(a), 0, cos(a)) * 20.0
		var pedestal := MeshInstance3D.new()
		var base := CylinderMesh.new()
		base.top_radius = 0.65
		base.bottom_radius = 0.95
		base.height = 1.4
		base.radial_segments = 6
		pedestal.mesh = base
		pedestal.position = pos + Vector3.UP * 0.7
		pedestal.material_override = bronze
		add_child(pedestal)
		var crystal := MeshInstance3D.new()
		var gem := PrismMesh.new()
		gem.size = Vector3(0.8, 2.0, 0.8)
		crystal.mesh = gem
		crystal.position = pos + Vector3.UP * 2.5
		crystal.rotation.y = a
		crystal.material_override = emissive_shared(colors[i], 0.65)
		add_child(crystal)
		var sigil := _flat_ring(0.9, 0.04, emissive_shared(colors[i], 0.5, true))
		sigil.position = pos + Vector3.UP * 0.02
	# Skyline silhouettes are a single draw call and have no physics bodies.
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 7.0
	mesh.height = 20.0
	mesh.radial_segments = 5
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 28
	for i in 28:
		var a := TAU * i / 28.0
		var h := 0.6 + float((i * 7) % 11) / 10.0
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(1.8, h, 1.8)), Vector3(sin(a) * 90, h * 4.0 - 6, cos(a) * 90)))
	var mountains := MultiMeshInstance3D.new()
	mountains.multimesh = mm
	mountains.material_override = matte(Color("#334f61"))
	mountains.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mountains)

func _batch_asset(path: String, placements: Array[Transform3D]) -> void:
	var scene := load(path) as PackedScene
	if scene == null:
		return
	var source := scene.instantiate() as Node3D
	_batch_meshes(source, Transform3D.IDENTITY, placements)
	source.free()

func _batch_meshes(node: Node3D, parent_transform: Transform3D, placements: Array[Transform3D]) -> void:
	var local := parent_transform * node.transform
	if node is MeshInstance3D:
		var source := node as MeshInstance3D
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = source.mesh
		mm.instance_count = placements.size()
		for i in placements.size():
			mm.set_instance_transform(i, placements[i] * local)
		var batch := MultiMeshInstance3D.new()
		batch.multimesh = mm
		batch.material_override = source.material_override
		# Surrounding architecture is outside combat; skip its shadow passes.
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(batch)
	for child in node.get_children():
		if child is Node3D:
			_batch_meshes(child, local, placements)

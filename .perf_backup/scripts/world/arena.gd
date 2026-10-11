class_name Arena
extends Node3D
## Clean light-grey circular arena built entirely from primitives: a flat floor
## disk, a black edge band and black rim wall marking the boundary, an invisible
## (taller) collision ring, two spawn marks and soft studio lighting.
## No external models are loaded.

const PLAYABLE_RADIUS := 12.6     # wizards / teleports must stay inside this
const WALL_INNER := 13.4          # inner face of the rim wall and boundary ring
const WALL_THICKNESS := 0.6
const WALL_HEIGHT := 1.1
const SPAWNS := [Vector3(0, 0, 9.0), Vector3(0, 0, -9.0)]

const FLOOR_COLOR := Color(0.6, 0.61, 0.64)
const LINE_COLOR := Color(0.36, 0.37, 0.41)
const BORDER_COLOR := Color(0.05, 0.05, 0.06)
const WALL_COLOR := Color(0.08, 0.08, 0.09)
const GROUND_COLOR := Color(0.32, 0.33, 0.36)
const SKY_COLOR := Color(0.62, 0.65, 0.7)

func _ready() -> void:
	_build_environment()
	_build_floor()
	_build_wall()
	_build_markings()

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
	env.background_mode = Environment.BG_COLOR
	env.background_color = SKY_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	# Only bright spell cores bloom; the white floor stays crisp.
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.5
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.ssao_intensity = 1.2
	# Light fog melts the far ground into the background.
	env.fog_enabled = true
	env.fog_light_color = SKY_COLOR
	env.fog_density = 0.006
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.99, 0.97)
	sun.light_energy = 0.9
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	sun.shadow_blur = 2.0
	sun.shadow_opacity = 0.55
	sun.directional_shadow_max_distance = 50.0
	add_child(sun)

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
	disk.material_override = matte(FLOOR_COLOR, 0.75)
	add_child(disk)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(160, 160)
	ground.mesh = plane
	ground.position.y = -0.12
	ground.material_override = matte(GROUND_COLOR, 1.0)
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
		box.size = Vector3(1.5, WALL_HEIGHT, WALL_THICKNESS)
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
		box.size = Vector3(2.4, 12.0, depth)
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
	var line := matte(LINE_COLOR, 0.8)
	for r in [2.0, 6.0]:
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

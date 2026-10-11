class_name ShaderWarmup
extends SubViewport
## Compiles every material / particle shader the duel uses up front, in a tiny
## off-screen viewport, instead of the first time a spell is cast.
##
## The Compatibility renderer (desktop GL and especially WebGL) compiles
## shaders lazily on first draw, and each lit material has separate variants
## for "touched by an omni light" and "not touched". Without this, the first
## Meteor, Tornado, explosion flash on a wizard, damage number, etc. of every
## session froze the game for tens to hundreds of milliseconds mid-fight.
##
## It spawns the real spell nodes, VFX and character models (positional sound
## muted) twice in a private World3D lit like the arena: one group inside an
## omni light's range and one outside it. After a moment it frees itself.

const LIFETIME := 1.0
## Character models the duel can show (see Duel.RIVALS / HOST_LOOK).
const MODELS := [
	"res://assets/models/characters/player_blue.glb",
	"res://assets/models/characters/bot_red.glb",
	"res://assets/models/characters/bot_purple.glb",
	"res://assets/models/characters/bot_green.glb",
]
const LIT_CENTER := Vector3(-12, 0, -2)
const UNLIT_CENTER := Vector3(12, 0, -2)

static var _done := false

var _env: Environment
var _sun_template: DirectionalLight3D
var _t := 0.0

## Runs once per session. `env` and `sun` are the arena's, so the warm-up
## scene compiles the same light/shadow/fog shader variants.
static func run(host: Node, env: Environment, sun: DirectionalLight3D) -> void:
	# `-- --no-warmup` (dev): skip it, to measure first-use hitches.
	if _done or DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().has("--no-warmup"):
		return
	_done = true
	var w := ShaderWarmup.new()
	w._env = env
	w._sun_template = sun
	host.add_child(w)

func _ready() -> void:
	size = Vector2i(64, 64)
	own_world_3d = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	msaa_3d = get_tree().root.msaa_3d
	var root := Node3D.new()
	add_child(root)

	var we := WorldEnvironment.new()
	we.environment = _env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = _sun_template.light_color
	sun.light_energy = _sun_template.light_energy
	sun.rotation = _sun_template.rotation
	sun.shadow_enabled = _sun_template.shadow_enabled
	sun.shadow_blur = _sun_template.shadow_blur
	sun.directional_shadow_mode = _sun_template.directional_shadow_mode
	sun.directional_shadow_max_distance = _sun_template.directional_shadow_max_distance
	sun.directional_shadow_split_1 = _sun_template.directional_shadow_split_1
	root.add_child(sun)
	# Omni light over the "lit" group only (range stops well short of the other).
	var omni := OmniLight3D.new()
	omni.omni_range = 9.0
	omni.position = LIT_CENTER + Vector3(0, 2, 0)
	root.add_child(omni)
	# Wide camera that sees both groups (inside the shadow distance).
	var cam := Camera3D.new()
	cam.fov = 100.0
	cam.current = true
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 8, 22), Vector3(0, 0, -2))

	# Positional (spell) sounds stay silent while warm-up spells land/explode.
	Sfx.muted += 1
	# Effect flashes would light the "unlit" group; the omni above covers the
	# lit variants already.
	VFX.lights_suspended += 1
	for center in [LIT_CENTER, UNLIT_CENTER]:
		_spawn_group(root, center)

func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFETIME:
		set_process(false)
		queue_free()

func _exit_tree() -> void:
	Sfx.muted = maxi(0, Sfx.muted - 1)
	VFX.lights_suspended = maxi(0, VFX.lights_suspended - 1)

func _spawn_group(root: Node3D, center: Vector3) -> void:
	var group := Node3D.new()
	root.add_child(group)
	group.position = center
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 8)
	floor_mi.mesh = pm
	floor_mi.material_override = Arena.matte(Arena.FLOOR_COLOR, 0.75)
	group.add_child(floor_mi)
	_spawn_models(group)
	_spawn_spells(group)
	_spawn_vfx(group)

func _spawn_models(group: Node3D) -> void:
	var x := -3.0
	for path in MODELS:
		var ps := load(path) as PackedScene
		if ps == null:
			continue
		var model := ps.instantiate() as Node3D
		group.add_child(model)
		model.position = Vector3(x, 0, 2.0)
		x += 2.0
	# Procedural wizard parts (robe / hat / staff use the same matte features).
	var robe := MeshInstance3D.new()
	robe.mesh = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.45, 1.0)
	mat.roughness = 0.8
	robe.material_override = mat
	group.add_child(robe)
	robe.position = Vector3(3.0, 0.5, 2.0)

func _spawn_spells(group: Node3D) -> void:
	var x := -5.0
	for key in SpellBook.SPELLS:
		var spell: Dictionary = SpellBook.SPELLS[key]
		var pos := group.global_position + Vector3(x, 0.0, -1.0)
		x += 0.4
		match String(spell["type"]):
			"projectile":
				var proj := Projectile.new()
				proj.setup(null, spell, Vector3(0, 0, 1))
				group.add_child(proj)
				proj.remove_from_group("projectiles")
				proj.global_position = pos + Vector3.UP
			"strike":
				var s := Strike.new()
				s.setup(null, spell, 0.05)
				group.add_child(s)
				s.global_position = pos
			"area":
				var a := AreaEffect.new()
				a.setup(null, spell)
				group.add_child(a)
				a.global_position = pos
			"wall":
				var wall := EarthWall.new()
				wall.setup(null, spell)
				group.add_child(wall)
				wall.remove_from_group("earth_walls")
				wall.global_position = pos
			"cone":
				var p := VFX.make_particles(spell["color"], 20, 0.55, 0.6, {"one_shot": true, "explosive": 0.9,
					"direction": Vector3.FORWARD, "spread": 27.0, "vel_min": 9.0, "vel_max": 15.0,
					"damping": 11.0, "scale_start": 0.4, "scale_end": 1.6, "energy": 1.6})
				group.add_child(p)
				p.global_position = pos + Vector3.UP
				p.emitting = true
			"beam":
				VFX.bolt(group, pos + Vector3.UP * 2.0, pos, spell["color"], 0.09, 0.5)
			"self":
				VFX.burst(group, pos + Vector3.UP, spell["color"], 10, 4.0, 0.35, 0.8, {"emit_radius": 0.6, "gravity": Vector3(0, 3, 0)})
				VFX.shockwave(group, pos + Vector3(0, 0.1, 0), spell["color"], 2.2)

func _spawn_vfx(group: Node3D) -> void:
	var c := group.global_position + Vector3(0, 1, 1)
	var col := Color(0.3, 0.6, 1.0)
	VFX.explosion(group, c, col, 1.4)
	VFX.portal(group, c, col)
	VFX.jump_trail(group, c, c + Vector3(2, 0, 0), col)
	VFX.bolt(group, c + Vector3.UP * 2.0, c, col)
	VFX.warning_marker(group, c, 1.8, col, 0.6)
	# Both damage-number sizes, every digit, so glyphs are rasterised now.
	VFX.damage_number(group, c, 8.0, Color.WHITE)
	VFX.damage_number(group, c, 20.0, Color.WHITE)
	for size_px in [64, 88]:
		var l := Label3D.new()
		l.text = "0123456789"
		l.font_size = size_px
		l.outline_size = 14
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.pixel_size = 0.006
		group.add_child(l)
		l.global_position = c
	# Wizard status effects (sphere + orbiting ring emitters) and materials.
	var holder := Node3D.new()
	group.add_child(holder)
	holder.global_position = c
	for p in [VFX.status_particles(holder, col, 0.6, 2.0), VFX.status_particles(holder, col, 0.4, 0.5, 2.0)]:
		(p as GPUParticles3D).emitting = true
	# Area pull (ring + orbit + radial) emitter.
	var pull := VFX.make_particles(col, 20, 1.6, 0.6, {"emit_ring": 2.0, "orbit": 0.6, "radial": -2.0,
		"vel_min": 0.0, "vel_max": 0.2, "scale_start": 1.0, "scale_end": 0.2, "energy": 1.8})
	pull.emitting = true
	holder.add_child(pull)
	for mat in [Wizard.shield_material(), Wizard.flash_material(), Arena.emissive_shared(col, 4.0, true)]:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radial_segments = 8
		sm.rings = 4
		mi.mesh = sm
		mi.material_override = mat
		holder.add_child(mi)

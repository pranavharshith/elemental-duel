class_name Wizard
extends CharacterBody3D
## A duelling wizard. Owns stats (HP / Mana / SP), status effects, the element
## queue, movement and animation. Input comes from a controller node (player or
## AI) that sets `move_input`, `aim_point` and calls the action methods.

signal died(wizard: Wizard)
signal damaged(wizard: Wizard, amount: float)
signal spell_cast(wizard: Wizard, key: String)
signal elements_changed(wizard: Wizard)
signal fizzled(wizard: Wizard, reason: String)
# Online replication hooks (emitted on the authoritative side).
signal hit_fx(wizard: Wizard, dealt: float, absorbed: float, anim: int)
signal knockback_added(wizard: Wizard, kb: Vector3)
signal jumped(wizard: Wizard, from: Vector3, to: Vector3)

enum HitAnim { NONE, LIGHT, STUN }

const MODEL_YAW_OFFSET := PI
## Rapid element presses inside this window merge into one combo (plan: "buffer
## rapid inputs; longest valid combo takes priority"). Each press restarts it.
const COMBO_WINDOW := 0.28
## Body turn speed toward the travel direction (exponential rate, 1/s).
const TURN_RATE := 12.0
## Faster turn used to face the crosshair when casting.
const AIM_TURN_RATE := 30.0
## How long the body keeps facing the crosshair after a cast.
const AIM_HOLD := 0.45
## Movement speed while aim-holding (casting commits you a little).
const CAST_MOVE_MULT := 0.7
## Seconds of stun immunity after a stun ends.
const STUN_IMMUNITY := 1.5
## Incoming damage scale for the human player per difficulty.
const PLAYER_DAMAGE_TAKEN := [0.55, 0.75, 0.95]

const MAX_HP := 100.0
const MAX_MANA := 100.0
const MAX_SP := 100.0
const MANA_REGEN := 13.0
const SP_REGEN := 16.0
const SP_REGEN_DELAY := 1.0
const JUMP_COST := 35.0
const JUMP_RANGE := 8.5
const MOVE_SPEED := 4.8
const ACCEL := 40.0          # 90% top speed in ~120 ms: responsive, not twitchy
const DECEL := 52.0          # a positive, readable stop without ice-skating
const TURN_ACCEL := 64.0     # reversing direction remains deliberate and quick
const GRAVITY := 22.0
const GLOBAL_CAST_DELAY := 0.28

@export var display_name := "Wizard"
@export var robe_color := Color(0.3, 0.45, 1.0)
@export var model_path := "res://assets/models/characters/player_blue.glb"

var opponent: Wizard
var move_input := Vector3.ZERO      # world-space desired direction (y ignored)
var aim_point := Vector3.ZERO       # world-space target point
var face_aim := true                # turn to the aim point when casting
# Reticle state is authored by PlayerController from the final camera
# projection. HUD feedback must never guess from a world-space approximation.
var reticle_target: Object = null
var aim_blocked := false

var hp := MAX_HP
var mana := MAX_MANA
var sp := MAX_SP
var shield := 0.0
var alive := true
var controls_enabled := false

var elements: Array = []
var cooldowns: Dictionary = {}
var last_spell := ""

# Status effects
var burn_time := 0.0
var burn_dps := 3.0
var slow_time := 0.0
var slow_mult := 1.0
var stun_time := 0.0
var haste_time := 0.0
var haste_mult := 1.0
var heal_time := 0.0
var heal_rate := 0.0
var shield_time := 0.0
var invuln_time := 0.0
var area_slow := 1.0               # set every frame by area effects
var _area_slow_next := 1.0

var _knockback := Vector3.ZERO
var _sp_delay := 0.0
var _cast_lock := 0.0
var _hurt_flash := 0.0
var _model_root: Node3D
var _skeleton: Skeleton3D
var _anim: WizardAnimation
var _staff: Node3D
var _hand_bone := -1
var _staff_orb: MeshInstance3D
var _staff_light: OmniLight3D
var _orbs: Array[MeshInstance3D] = []
var _status_fx: Dictionary = {}
var _body_meshes: Array[MeshInstance3D] = []
var _flash_mat: StandardMaterial3D
var _step_timer := 0.0
var _buffer_time := 0.0
var _aim_hold := 0.0
var _stun_immune := 0.0
var _knockback_applied := Vector3.ZERO
## Multiplies all damage this wizard takes (difficulty for the player).
var damage_taken_mult := 1.0
## Plays non-positional UI sounds (fizzles). Only the local human's wizard.
var ui_sounds := false

# ---- Online roles ----
## Position/facing come from the network (interpolated), not local physics.
var net_move_remote := false
## HP/mana/SP/cooldowns/statuses come from the host; no local damage/casting.
var net_stats_remote := false
## Bumped on every teleport/respawn so the other side snaps instead of sliding.
var teleport_count := 0
var last_cast_seed := 0
var _net_buf := NetBuffer.new()
var _net_aim := Vector3.ZERO
# Visual interpolation: physics runs at 60 Hz, the model is drawn between the
# last two physics states so movement and camera stay smooth at any frame rate.
var _holder: Node3D
var _prev_pos := Vector3.ZERO
var _curr_pos := Vector3.ZERO
var _prev_yaw := 0.0
var _curr_yaw := 0.0
var _snap_visual := true

func _ready() -> void:
	add_to_group("wizards")
	collision_layer = 2
	collision_mask = 1 | 2 | 8 | 16
	floor_snap_length = 0.4
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	_load_model()
	_build_orbs()
	_build_status_fx()
	aim_point = global_position + Vector3(0, 1, -5)

# ======================================================================== model
func _load_model() -> void:
	var holder := Node3D.new()
	holder.name = "ModelHolder"
	holder.top_level = true
	add_child(holder)
	_holder = holder
	var ps: PackedScene = load(model_path)
	if ps == null:
		return
	_model_root = ps.instantiate() as Node3D
	_model_root.rotation.y = MODEL_YAW_OFFSET
	holder.add_child(_model_root)
	_skeleton = _model_root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.albedo_color = Color(1, 1, 1, 0.0)
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for mi in _model_root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var lname := String(m.name).to_lower()
		if lname.begins_with("hat_") or lname.begins_with("hairstyle"):
			m.visible = false
			continue
		if lname.begins_with("t_shirt") or lname.begins_with("pants"):
			var robe := StandardMaterial3D.new()
			robe.albedo_color = robe_color if lname.begins_with("t_shirt") else robe_color.darkened(0.55)
			robe.roughness = 0.8
			m.material_override = robe
		m.material_overlay = _flash_mat
		_body_meshes.append(m)
	var players := _model_root.find_children("*", "AnimationPlayer", true, false)
	if players.size() > 0:
		_anim = WizardAnimation.new(players[0] as AnimationPlayer, _model_root)
	_attach_hat()
	_attach_staff()

func _bone_socket(bone_name: String) -> BoneAttachment3D:
	if _skeleton == null or _skeleton.find_bone(bone_name) < 0:
		return null
	var att := BoneAttachment3D.new()
	att.name = "Socket_" + bone_name
	_skeleton.add_child(att)
	att.bone_name = bone_name
	return att

## Classic pointed wizard hat built from primitives, riding the head bone.
func _attach_hat() -> void:
	var socket := _bone_socket("Head")
	if socket == null:
		return
	var hat := Node3D.new()
	hat.name = "WizardHat"
	socket.add_child(hat)
	# Head bone sits at the base of the skull; the crown is ~0.3 m above it.
	hat.position = Vector3(0, 0.27, -0.02)
	hat.rotation_degrees = Vector3(-8, 0, 0)
	var felt := StandardMaterial3D.new()
	felt.albedo_color = robe_color.darkened(0.35)
	felt.roughness = 0.85
	var band := StandardMaterial3D.new()
	band.albedo_color = Color(1.0, 0.8, 0.35)
	band.metallic = 0.6
	band.roughness = 0.35
	var brim := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.3
	bm.bottom_radius = 0.32
	bm.height = 0.03
	brim.mesh = bm
	brim.material_override = felt
	hat.add_child(brim)
	var ring := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.175
	rm.bottom_radius = 0.18
	rm.height = 0.05
	ring.mesh = rm
	ring.position.y = 0.04
	ring.material_override = band
	hat.add_child(ring)
	# Two stacked cones give the tip a slight backward droop.
	var lower := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.09
	lm.bottom_radius = 0.17
	lm.height = 0.26
	lower.mesh = lm
	lower.position.y = 0.15
	lower.material_override = felt
	hat.add_child(lower)
	var tip := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.0
	tm.bottom_radius = 0.09
	tm.height = 0.26
	tip.mesh = tm
	tip.position = Vector3(0, 0.38, 0.04)
	tip.rotation_degrees.x = 18
	tip.material_override = felt
	hat.add_child(tip)
	var star := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	star.mesh = sm
	star.position = Vector3(0, 0.12, -0.165)
	star.material_override = Arena.emissive(Color(1.0, 0.9, 0.5), 3.0, true)
	hat.add_child(star)
	for mi in [brim, ring, lower, tip]:
		(mi as MeshInstance3D).material_overlay = _flash_mat

func _attach_staff() -> void:
	var parent: Node3D = _holder if _skeleton else self
	var socket: Node3D = _skeleton
	var staff := Node3D.new()
	staff.name = "Staff"
	parent.add_child(staff)
	if socket == null:
		staff.position = Vector3(0.35, 1.0, -0.2)
	# The staff follows the hand's POSITION but keeps an upright orientation
	# (see _update_staff). Aligning it to the forearm made it swing like a
	# dragged spear and stab the floor on every arm swing.
	_staff = staff
	if _skeleton:
		_hand_bone = _skeleton.find_bone("RightHand")
		staff.top_level = true
		_skeleton.skeleton_updated.connect(_update_staff)
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.025
	cyl.bottom_radius = 0.035
	cyl.height = 1.5
	shaft.mesh = cyl
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.22, 0.12)
	wood.roughness = 0.9
	shaft.material_override = wood
	# Hand grips about a third of the way up: 0.45 m below the grip, 1.05 m above.
	shaft.position = Vector3(0, 0.3, 0)
	staff.add_child(shaft)
	_staff_orb = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	_staff_orb.mesh = sm
	_staff_orb.position = Vector3(0, 1.1, 0)
	_staff_orb.material_override = Arena.emissive(robe_color.lightened(0.3), 4.0, true)
	staff.add_child(_staff_orb)
	_staff_light = OmniLight3D.new()
	_staff_light.light_color = robe_color
	_staff_light.light_energy = 0.8
	_staff_light.omni_range = 2.5
	_staff_orb.add_child(_staff_light)

## Small orbs that circle the wizard's head, one per queued element.
func _build_orbs() -> void:
	for i in SpellBook.MAX_QUEUE:
		var orb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.12
		sm.height = 0.24
		orb.mesh = sm
		orb.visible = false
		orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_holder.add_child(orb)
		_orbs.append(orb)

func _build_status_fx() -> void:
	_status_fx["burn"] = VFX.status_particles(_holder, Color(1.0, 0.45, 0.1), 0.7, 3.0)
	_status_fx["slow"] = VFX.status_particles(_holder, Color(0.45, 0.75, 1.0), 0.5, -0.5)
	_status_fx["stun"] = VFX.status_particles(_holder, Color(1.0, 0.85, 0.2), 0.4, 0.5, 2.0)
	_status_fx["haste"] = VFX.status_particles(_holder, Color(0.4, 0.95, 0.7), 0.6, 1.0)
	_status_fx["heal"] = VFX.status_particles(_holder, Color(0.3, 0.95, 0.45), 0.6, 2.0)
	var bubble := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.05
	sm.height = 2.1
	bubble.mesh = sm
	bubble.position.y = 0.95
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.85, 0.65, 0.35, 0.22)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.emission_enabled = true
	bm.emission = Color(0.9, 0.6, 0.3)
	bm.emission_energy_multiplier = 0.8
	bm.rim_enabled = true
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bubble.material_override = bm
	bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bubble.visible = false
	_holder.add_child(bubble)
	_status_fx["shield"] = bubble

# ======================================================================== loop
## Area effects call this every physics frame while the wizard stands inside.
func apply_area_slow(mult: float) -> void:
	_area_slow_next = minf(_area_slow_next, mult)

func _physics_process(delta: float) -> void:
	area_slow = _area_slow_next
	_area_slow_next = 1.0
	_tick_stats(delta)
	if net_move_remote:
		_puppet_step(delta)
		return
	var can_move := alive and controls_enabled and stun_time <= 0.0
	var wish := Vector3(move_input.x, 0, move_input.z)
	if wish.length() > 1.0:
		wish = wish.normalized()
	if not can_move:
		wish = Vector3.ZERO
	# Ground movement: camera-relative input arrives as a direction with the
	# selected forward/strafe/back speed already encoded by PlayerController.
	# Physics owns the resulting velocity; animation never affects gameplay.
	var target := wish * MOVE_SPEED * speed_multiplier() * (CAST_MOVE_MULT if _aim_hold > 0.0 else 1.0)
	var horiz := Vector3(velocity.x, 0, velocity.z) - _knockback_applied
	var rate := ACCEL
	if wish.length() < 0.1:
		rate = DECEL
	elif horiz.length() > 0.5 and horiz.normalized().dot(target.normalized()) < 0.0:
		rate = TURN_ACCEL
	horiz = horiz.move_toward(target, rate * delta)
	_knockback = _knockback.move_toward(Vector3.ZERO, 26.0 * delta)
	_knockback_applied = Vector3(_knockback.x, 0, _knockback.z)
	velocity.x = horiz.x + _knockback_applied.x
	velocity.z = horiz.z + _knockback_applied.z
	if is_on_floor():
		velocity.y = maxf(velocity.y, -1.0)
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	# Hard safety net: never leave the playable disk or fall through the floor.
	var clamped := Arena.clamp_to_arena(global_position)
	if clamped != global_position:
		global_position = clamped
		_knockback = Vector3.ZERO
	if global_position.y < -2.0:
		global_position.y = 0.5
		velocity = Vector3.ZERO
	_update_facing(delta)
	_update_animation(delta, wish)
	_update_footsteps(delta, Vector3(velocity.x, 0, velocity.z))
	_update_buffer(delta)
	_record_visual_state()

## Remote-controlled body: follow the interpolated network state. The host
## still runs this wizard's combo buffer (it owns the stats).
func _puppet_step(delta: float) -> void:
	var s := _net_buf.sample()
	if not s.is_empty():
		global_position = Arena.clamp_to_arena(s["pos"])
		rotation.y = float(s["yaw"])
		velocity = s["vel"]
	_knockback = Vector3.ZERO
	_knockback_applied = Vector3.ZERO
	if _tp_check >= 0.0:
		_tp_check -= delta
		if _tp_check < 0.0:
			needs_correction.emit(self, _pre_tp_pos, "Teleport not allowed")
	_update_animation(delta, Vector3.ZERO)
	_update_footsteps(delta, Vector3(velocity.x, 0, velocity.z))
	_update_buffer(delta)
	_record_visual_state()

func _record_visual_state() -> void:
	_prev_pos = _curr_pos
	_prev_yaw = _curr_yaw
	_curr_pos = global_position
	_curr_yaw = rotation.y
	if _snap_visual:
		_snap_visual = false
		_prev_pos = _curr_pos
		_prev_yaw = _curr_yaw

## Smoothed (render-time) position. The camera follows this, not the raw body.
func visual_position() -> Vector3:
	if not is_physics_processing() or _snap_visual:
		return global_position
	var f := Engine.get_physics_interpolation_fraction()
	return _prev_pos.lerp(_curr_pos, f)

func _update_visual(_delta: float) -> void:
	if _holder == null:
		return
	if not is_physics_processing() or _snap_visual:
		# Display-only wizards (menu) and fresh spawns are posed directly.
		_holder.global_transform = Transform3D(Basis(Vector3.UP, rotation.y), global_position)
	else:
		var f := Engine.get_physics_interpolation_fraction()
		var yaw := lerp_angle(_prev_yaw, _curr_yaw, f)
		_holder.global_transform = Transform3D(Basis(Vector3.UP, yaw), _prev_pos.lerp(_curr_pos, f))

## Keep the staff upright in the hand: it follows the hand bone's position
## but only leans slightly forward and outward. Runs on skeleton_updated so it
## uses this frame's final pose (no lag, no jitter).
func _update_staff() -> void:
	# skeleton_updated can fire while the scene is being built or torn down
	# (menu -> duel scene change); global transforms are invalid then.
	if _staff == null or _holder == null or _skeleton == null or _hand_bone < 0:
		return
	if not is_inside_tree() or not _skeleton.is_inside_tree() or not _staff.is_inside_tree():
		return
	var hand := _skeleton.global_transform * _skeleton.get_bone_global_pose(_hand_bone).origin
	var b := _holder.global_basis.orthonormalized()
	b = b * Basis(Vector3.RIGHT, deg_to_rad(-8.0)) * Basis(Vector3.BACK, deg_to_rad(-6.0))
	_staff.global_transform = Transform3D(b, hand)

func _process(delta: float) -> void:
	_update_visual(delta)
	_update_orbs()
	_update_status_visuals()
	if _hurt_flash > 0.0:
		_hurt_flash = maxf(0.0, _hurt_flash - delta * 4.0)
		_flash_mat.albedo_color = Color(1, 0.3, 0.25, _hurt_flash * 0.65)

func _tick_stats(delta: float) -> void:
	if net_stats_remote:
		# Stats arrive from the host; only local presentation timers tick.
		_aim_hold = maxf(0.0, _aim_hold - delta)
		invuln_time = maxf(0.0, invuln_time - delta)
		return
	if not alive:
		return
	mana = minf(MAX_MANA, mana + MANA_REGEN * delta)
	if _sp_delay > 0.0:
		_sp_delay -= delta
	else:
		sp = minf(MAX_SP, sp + SP_REGEN * delta)
	for k in cooldowns.keys():
		cooldowns[k] = maxf(0.0, cooldowns[k] - delta)
	_cast_lock = maxf(0.0, _cast_lock - delta)
	_aim_hold = maxf(0.0, _aim_hold - delta)
	_stun_immune = maxf(0.0, _stun_immune - delta)
	invuln_time = maxf(0.0, invuln_time - delta)
	stun_time = maxf(0.0, stun_time - delta)
	if slow_time > 0.0:
		slow_time -= delta
		if slow_time <= 0.0:
			slow_mult = 1.0
	if haste_time > 0.0:
		haste_time -= delta
		if haste_time <= 0.0:
			haste_mult = 1.0
	if shield_time > 0.0:
		shield_time -= delta
		if shield_time <= 0.0:
			shield = 0.0
	if heal_time > 0.0:
		heal_time -= delta
		hp = minf(MAX_HP, hp + heal_rate * delta)
	if burn_time > 0.0:
		burn_time -= delta
		_apply_raw_damage(burn_dps * delta, false)

func speed_multiplier() -> float:
	return slow_mult * area_slow * haste_mult

## Facing ("orient to movement", like Zelda / Genshin / Fortnite build mode):
## the character only has forward Walk/Run clips, so it always runs FACING the
## direction it travels: W, A, S and D all look like a natural straight-line
## run. When a spell is cast, the body snaps to the crosshair for a short
## AIM_HOLD and then turns back toward travel.
func _update_facing(delta: float) -> void:
	if not alive:
		return
	var dir := Vector3.ZERO
	var rate := TURN_RATE
	if _aim_hold > 0.0 and face_aim:
		dir = aim_point - global_position
		rate = AIM_TURN_RATE
	else:
		var flat := Vector3(velocity.x, 0, velocity.z) - _knockback_applied
		if flat.length() > 0.6 and move_input.length() > 0.1:
			dir = flat
	dir.y = 0
	if dir.length() < 0.1:
		return
	var target_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-rate * delta))

## Speed drives a synced Idle/Walk/Run blend with playback matched to stride.
## Always played forward: no reversed or twisted legs.
func _update_animation(delta: float, _wish: Vector3) -> void:
	if _anim == null or not alive:
		return
	var flat := Vector3(velocity.x, 0, velocity.z) - _knockback_applied
	var spd := flat.length()
	# While aim-holding and moving away from the facing direction, show a
	# slower walk instead of a moonwalking run.
	if _aim_hold > 0.0 and spd > 0.3:
		var fwd := -global_transform.basis.z
		if Vector3(fwd.x, 0, fwd.z).normalized().dot(flat.normalized()) < 0.3:
			spd = minf(spd, WizardAnimation.WALK_SPEED)
	_anim.set_locomotion(spd, 1.0, delta)

func _update_footsteps(delta: float, horiz: Vector3) -> void:
	if not is_on_floor() or horiz.length() < 2.0:
		return
	_step_timer -= delta * horiz.length() / 5.0
	if _step_timer <= 0.0:
		_step_timer = 0.36
		Sfx.play_at("step", global_position, -14.0)

func _update_orbs() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for i in _orbs.size():
		var orb := _orbs[i]
		if i < elements.size() and alive:
			orb.visible = true
			var a := t * 3.0 + TAU * i / maxf(1.0, elements.size())
			orb.position = Vector3(cos(a) * 0.55, 2.25 + sin(t * 4.0 + i) * 0.05, sin(a) * 0.55)
			if orb.get_meta("elem", "") != elements[i]:
				orb.set_meta("elem", elements[i])
				orb.material_override = Arena.emissive(SpellBook.ELEMENT_INFO[elements[i]]["color"], 4.0, true)
		else:
			orb.visible = false

func _update_status_visuals() -> void:
	(_status_fx["burn"] as GPUParticles3D).emitting = burn_time > 0.0 and alive
	(_status_fx["slow"] as GPUParticles3D).emitting = (slow_time > 0.0 or area_slow < 0.99) and alive
	(_status_fx["stun"] as GPUParticles3D).emitting = stun_time > 0.0 and alive
	(_status_fx["haste"] as GPUParticles3D).emitting = haste_time > 0.0 and alive
	(_status_fx["heal"] as GPUParticles3D).emitting = heal_time > 0.0 and alive
	(_status_fx["shield"] as MeshInstance3D).visible = shield > 0.0 and alive

# ======================================================================== actions
## Ability key pressed (Q/E/R/F/C). The element joins the combo buffer; the
## buffer fires automatically once COMBO_WINDOW passes without another press,
## or immediately when it holds three elements.
func queue_element(element: String) -> void:
	if net_stats_remote:
		return
	if not alive or not controls_enabled or stun_time > 0.0 or elements.size() >= SpellBook.MAX_QUEUE:
		return
	elements.append(element)
	_buffer_time = COMBO_WINDOW
	_tint_staff(SpellBook.ELEMENT_INFO[element]["color"])
	Sfx.play_at("elem_" + element, global_position, -6.0)
	elements_changed.emit(self)
	if elements.size() >= SpellBook.MAX_QUEUE:
		release_buffer()

## Cast whatever is buffered right now (also bound to left click).
func release_buffer() -> void:
	if net_stats_remote or elements.is_empty():
		return
	if _cast_lock > 0.0:
		# Still recovering from the previous cast: fire as soon as it ends.
		_buffer_time = _cast_lock
		return
	try_cast()

func _update_buffer(delta: float) -> void:
	if net_stats_remote or elements.is_empty():
		return
	_buffer_time -= delta
	if _buffer_time <= 0.0:
		release_buffer()

## 0..1 progress of the combo window (HUD feedback).
func buffer_progress() -> float:
	if elements.is_empty():
		return 0.0
	return clampf(1.0 - _buffer_time / COMBO_WINDOW, 0.0, 1.0)

func clear_elements() -> void:
	_buffer_time = 0.0
	if elements.is_empty():
		return
	elements.clear()
	_tint_staff(robe_color.lightened(0.3))
	elements_changed.emit(self)

## The spell the current buffer resolves to.
func pending_spell() -> String:
	return SpellBook.resolve(elements)

func cooldown_left(key: String) -> float:
	return float(cooldowns.get(key, 0.0))

func can_cast(key: String) -> bool:
	if key.is_empty() or not alive or not controls_enabled or stun_time > 0.0 or _cast_lock > 0.0:
		return false
	var spell := SpellBook.get_spell(key)
	return not spell.is_empty() and cooldown_left(key) <= 0.0 and mana >= float(spell["mana"])

func _fizzle(reason: String) -> void:
	fizzled.emit(self, reason)
	if ui_sounds:
		Sfx.play("fizzle", -8.0)

func try_cast() -> bool:
	if net_stats_remote:
		return false
	if not alive or not controls_enabled or stun_time > 0.0:
		clear_elements()
		return false
	if _cast_lock > 0.0:
		return false
	var key := pending_spell()
	if key.is_empty():
		return false
	var spell := SpellBook.get_spell(key)
	if cooldown_left(key) > 0.0 or mana < float(spell["mana"]):
		var reason := "%s recharging" % spell["name"] if cooldown_left(key) > 0.0 else "Not enough mana"
		clear_elements()
		_fizzle(reason)
		return false
	mana -= float(spell["mana"])
	cooldowns[key] = float(spell["cooldown"])
	_cast_lock = GLOBAL_CAST_DELAY
	last_spell = key
	elements.clear()
	_tint_staff(spell["color"])
	elements_changed.emit(self)
	if _anim:
		_anim.play_cast(1.6)
	# Face the target instantly so the spell visibly leaves toward the
	# crosshair, then keep facing it briefly (AIM_HOLD) before turning back
	# toward the direction of travel.
	var d := aim_point - global_position
	d.y = 0
	if d.length() > 0.1:
		rotation.y = atan2(-d.x, -d.z)
	_aim_hold = AIM_HOLD
	# Shared seed: online, the other machine replays this cast with the same
	# random scatter (meteor showers, thunderstorms, ...).
	last_cast_seed = randi()
	seed(last_cast_seed)
	SpellRuntime.cast(self, key, aim_point)
	randomize()
	spell_cast.emit(self, key)
	return true

## Spatial jump: teleport toward `direction` (world, flat). The landing spot is
## validated: inside the arena, not inside walls or the opponent. SP is only
## spent when a valid destination exists.
func try_spatial_jump(direction: Vector3) -> bool:
	var dest := _plan_jump(direction)
	if dest == Vector3.INF:
		return false
	sp -= JUMP_COST
	_sp_delay = SP_REGEN_DELAY
	invuln_time = 0.25
	var from := global_position
	_do_teleport(from, dest)
	jumped.emit(self, from, dest)
	return true

## Checks the jump rules and finds a landing spot (Vector3.INF = can't jump).
func _plan_jump(direction: Vector3) -> Vector3:
	if not alive or not controls_enabled or stun_time > 0.0:
		return Vector3.INF
	if sp < JUMP_COST:
		_fizzle("Not enough SP")
		return Vector3.INF
	var dir := Vector3(direction.x, 0, direction.z)
	if dir.length() < 0.1:
		dir = -global_transform.basis.z
	dir = dir.normalized()
	var dest := _find_jump_destination(dir)
	if dest == Vector3.INF:
		_fizzle("No room to jump")
	return dest

## Moves the body and plays the portal effects (no rule checks).
func _do_teleport(from: Vector3, dest: Vector3) -> void:
	VFX.portal(get_parent(), from, robe_color)
	global_position = dest
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	teleport_count += 1
	_net_buf.clear()
	# Teleport is a cut, not a slide: skip interpolation for the body. The
	# camera still glides after it (see PlayerController).
	_curr_pos = dest
	_snap_visual = true
	if _anim:
		_anim.play_dodge(2.2)
	VFX.portal(get_parent(), dest, robe_color)
	VFX.jump_trail(get_parent(), from + Vector3.UP, dest + Vector3.UP, robe_color)
	Sfx.play_at("teleport", dest, -2.0)

func _find_jump_destination(dir: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 1.7
	query.shape = cap
	query.collision_mask = 1 | 2 | 8 | 16
	query.exclude = [get_rid()]
	var dist := JUMP_RANGE
	while dist >= 2.0:
		var p := global_position + dir * dist
		p = Arena.clamp_to_arena(p, 0.6)
		p.y = global_position.y
		if (p - global_position).length() >= 1.5:
			query.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 0.95, 0))
			if space.intersect_shape(query, 1).is_empty():
				if opponent == null or opponent.global_position.distance_to(p) > 1.4:
					return p
		dist -= 0.75
	return Vector3.INF

func _tint_staff(c: Color) -> void:
	if _staff_orb:
		_staff_orb.material_override = Arena.emissive(c, 4.0, true)
	if _staff_light:
		_staff_light.light_color = c

## Position spells are launched from in front of the chest. Gameplay uses a
## stable cast origin rather than the visual staff tip, which keeps projectile
## collision honest while the hand is mid-animation.
func cast_origin_toward(direction: Vector3) -> Vector3:
	var flat := Vector3(direction.x, 0, direction.z)
	if flat.length_squared() < 0.01:
		flat = -global_transform.basis.z
	flat = flat.normalized()
	var right := Vector3(-flat.z, 0, flat.x)
	return global_position + Vector3(0, 1.28, 0) + flat * 0.58 + right * 0.18

func cast_origin() -> Vector3:
	return cast_origin_toward(aim_point - global_position)

# ======================================================================== damage
## info keys: knockback (Vector3), burn, slow, slow_time, stun
func take_hit(amount: float, info: Dictionary = {}) -> void:
	if net_stats_remote or not alive or invuln_time > 0.0:
		return
	var r := _apply_raw_damage(amount, true)
	if not alive:
		hit_fx.emit(self, r.x, r.y, HitAnim.NONE)
		return
	if info.has("knockback"):
		var kb: Vector3 = info["knockback"]
		kb.y = 0
		_knockback += kb
		knockback_added.emit(self, kb)
	var anim := HitAnim.NONE
	if info.get("burn", 0.0) > 0.0:
		burn_time = maxf(burn_time, float(info["burn"]))
	if info.get("slow", 1.0) < 1.0:
		slow_mult = minf(slow_mult, float(info["slow"])) if slow_time > 0.0 else float(info["slow"])
		slow_time = maxf(slow_time, float(info.get("slow_time", 2.0)))
	if info.get("stun", 0.0) > 0.0 and _stun_immune <= 0.0:
		stun_time = maxf(stun_time, float(info["stun"]))
		# No stun-locks: after a stun you get a short window of stun immunity.
		_stun_immune = stun_time + STUN_IMMUNITY
		anim = HitAnim.STUN
	elif amount >= 8.0:
		anim = HitAnim.LIGHT
	_play_hit_anim(anim)
	hit_fx.emit(self, r.x, r.y, anim)

func _play_hit_anim(anim: int) -> void:
	if _anim == null:
		return
	if anim == HitAnim.STUN:
		_anim.play_hit(1.0)
	elif anim == HitAnim.LIGHT:
		_anim.play_hit(1.4)

## Returns Vector2(dealt, absorbed).
func _apply_raw_damage(amount: float, feedback: bool) -> Vector2:
	if net_stats_remote or amount <= 0.0 or not alive:
		return Vector2.ZERO
	var dealt := amount * damage_taken_mult
	var absorbed := 0.0
	if shield > 0.0:
		absorbed = minf(shield, dealt)
		shield -= absorbed
		dealt -= absorbed
	hp = maxf(0.0, hp - maxf(dealt, 0.0))
	if feedback:
		_hit_feedback(maxf(dealt, 0.0), absorbed)
	if hp <= 0.0:
		_die()
	return Vector2(maxf(dealt, 0.0), absorbed)

## Damage numbers, flash and sound (also replayed on the other machine).
func _hit_feedback(dealt: float, absorbed: float) -> void:
	if absorbed > 0.0:
		Sfx.play_at("shield_hit", global_position, -6.0)
		VFX.damage_number(get_parent(), global_position + Vector3(0, 2.3, 0), absorbed, Color(0.9, 0.7, 0.4))
	if dealt > 0.0:
		_hurt_flash = 1.0
		Sfx.play_at("hit", global_position, -3.0)
		VFX.damage_number(get_parent(), global_position + Vector3(0, 2.3, 0), dealt, Color(1, 0.9, 0.85))
		damaged.emit(self, dealt)

func _die() -> void:
	alive = false
	elements.clear()
	_buffer_time = 0.0
	_aim_hold = 0.0
	burn_time = 0.0
	stun_time = 0.0
	if _anim:
		_anim.play_ko()
	died.emit(self)

func apply_self_buff(spell: Dictionary) -> void:
	if net_stats_remote:
		return
	var dur := float(spell.get("duration", 4.0))
	if spell.has("shield"):
		shield = float(spell["shield"])
		shield_time = dur
	if spell.has("haste"):
		haste_mult = float(spell["haste"])
		haste_time = dur
	if spell.get("cleanse", false):
		slow_time = 0.0
		slow_mult = 1.0
		burn_time = 0.0
	if spell.has("sp_restore"):
		sp = minf(MAX_SP, sp + float(spell["sp_restore"]))
	if spell.has("heal"):
		heal_rate = float(spell["heal"]) / dur
		heal_time = dur

func reset_for_round(pos: Vector3, face: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	hp = MAX_HP
	mana = MAX_MANA
	sp = MAX_SP
	shield = 0.0
	alive = true
	elements.clear()
	cooldowns.clear()
	last_spell = ""
	burn_time = 0.0
	slow_time = 0.0
	slow_mult = 1.0
	stun_time = 0.0
	haste_time = 0.0
	haste_mult = 1.0
	heal_time = 0.0
	shield_time = 0.0
	invuln_time = 0.0
	aim_point = face
	reticle_target = null
	aim_blocked = false
	_buffer_time = 0.0
	_cast_lock = 0.0
	_sp_delay = 0.0
	_aim_hold = 0.0
	_stun_immune = 0.0
	teleport_count += 1
	_net_buf.clear()
	_tp_check = -1.0
	_net_last_t = 0.0
	var d := face - pos
	rotation.y = atan2(-d.x, -d.z)
	_curr_pos = pos
	_curr_yaw = rotation.y
	_snap_visual = true
	_record_visual_state()
	_tint_staff(robe_color.lightened(0.3))
	if _anim:
		_anim.reset()
	elements_changed.emit(self)

func play_victory() -> void:
	if _anim:
		_anim.play_cast(0.8)

# ======================================================================== online
## Fastest legitimate movement between two network states (m/s): sprint with
## haste plus the strongest knockback. Anything faster is rejected by the host.
const NET_MAX_SPEED := 42.0

## Authoritative stats (host -> client).
func net_stats() -> Dictionary:
	return {"hp": hp, "mp": mana, "sp": sp, "sh": shield, "st": stun_time,
		"slt": slow_time, "slm": slow_mult, "hat": haste_time, "ham": haste_mult,
		"bu": burn_time, "he": heal_time, "iv": invuln_time,
		"el": elements.duplicate(), "cd": cooldowns.duplicate(), "ls": last_spell}

## Movement state of a locally simulated body.
func net_motion() -> Dictionary:
	return {"p": global_position, "y": rotation.y, "v": Vector3(velocity.x, 0, velocity.z),
		"tp": teleport_count, "a": aim_point}

func net_apply_stats(d: Dictionary) -> void:
	hp = float(d.get("hp", hp))
	mana = float(d.get("mp", mana))
	sp = float(d.get("sp", sp))
	shield = float(d.get("sh", shield))
	stun_time = float(d.get("st", 0.0))
	slow_time = float(d.get("slt", 0.0))
	slow_mult = float(d.get("slm", 1.0))
	haste_time = float(d.get("hat", 0.0))
	haste_mult = float(d.get("ham", 1.0))
	burn_time = float(d.get("bu", 0.0))
	heal_time = float(d.get("he", 0.0))
	invuln_time = float(d.get("iv", 0.0))
	cooldowns = d.get("cd", {})
	last_spell = String(d.get("ls", last_spell))
	var el: Array = d.get("el", [])
	if el != elements:
		if el.size() > elements.size():
			var e := String(el[-1])
			if SpellBook.ELEMENT_INFO.has(e):
				_tint_staff(SpellBook.ELEMENT_INFO[e]["color"])
				# Our own presses already played their sound instantly.
				if net_move_remote:
					Sfx.play_at("elem_" + e, global_position, -6.0)
		elements = el.duplicate()
		elements_changed.emit(self)

## Remote body state. `validate` (host side) rejects impossible movement.
## Returns false when the state was rejected.
func net_push_motion(d: Dictionary, remote_t: float, validate: bool) -> bool:
	var pos: Vector3 = d.get("p", global_position)
	var tp := int(d.get("tp", 0))
	pos = Arena.clamp_to_arena(pos)
	if validate and tp == _net_buf.tp and _net_last_t > 0.0:
		var dt := remote_t - _net_last_t
		if dt > 0.0 and Vector2(pos.x - _net_last_pos.x, pos.z - _net_last_pos.z).length() > NET_MAX_SPEED * dt + 0.5:
			return false
	_net_last_t = remote_t
	_net_last_pos = pos
	if d.has("a"):
		aim_point = d["a"]
	if tp != _net_buf.tp:
		# A teleport (or respawn) on the owner's side. Remember where we were;
		# a long move must be confirmed by a validated jump within 1 s.
		_pre_tp_pos = global_position
		if validate and Vector2(pos.x - global_position.x, pos.z - global_position.z).length() > 3.0 and _tp_check < 0.0:
			_tp_check = 1.0
	if _net_buf.push(remote_t, pos, float(d.get("y", rotation.y)), d.get("v", Vector3.ZERO), tp):
		global_position = pos
		rotation.y = float(d.get("y", rotation.y))
		_curr_pos = pos
		_snap_visual = true
	return true

var _net_last_t := 0.0
var _net_last_pos := Vector3.ZERO
var _pre_tp_pos := Vector3.ZERO
var _tp_check := -1.0

signal needs_correction(wizard: Wizard, pos: Vector3, reason: String)

## Replays a cast the host resolved (client side).
func net_play_cast(key: String, aim: Vector3, cast_seed: int) -> void:
	var spell := SpellBook.get_spell(key)
	if spell.is_empty():
		return
	aim_point = aim
	last_spell = key
	elements.clear()
	elements_changed.emit(self)
	_tint_staff(spell["color"])
	if _anim:
		_anim.play_cast(1.6)
	if not net_move_remote:
		var d := aim - global_position
		d.y = 0
		if d.length() > 0.1:
			rotation.y = atan2(-d.x, -d.z)
		_aim_hold = AIM_HOLD
	seed(cast_seed)
	SpellRuntime.cast(self, key, aim)
	randomize()
	spell_cast.emit(self, key)

func net_play_hit_fx(dealt: float, absorbed: float, anim: int) -> void:
	_hit_feedback(dealt, absorbed)
	_play_hit_anim(anim)

func net_add_knockback(kb: Vector3) -> void:
	_knockback += Vector3(kb.x, 0, kb.z)

func net_kill() -> void:
	if not alive:
		return
	alive = false
	elements.clear()
	_aim_hold = 0.0
	if _anim:
		_anim.play_ko()

## Joiner: teleport immediately on this screen, then ask the host to confirm.
func net_predict_jump(direction: Vector3) -> bool:
	var dest := _plan_jump(direction)
	if dest == Vector3.INF:
		return false
	var from := global_position
	_do_teleport(from, dest)
	Net.send_jump(from, dest)
	return true

## Host: check a joiner's teleport against the rules and the host's world.
func net_validate_jump(from: Vector3, dest: Vector3) -> bool:
	if not alive or not controls_enabled or stun_time > 0.0 or sp < JUMP_COST:
		return false
	var flat_dest := Vector3(dest.x, 0, dest.z)
	if flat_dest.length() > Arena.PLAYABLE_RADIUS - 0.5:
		return false
	if Vector2(dest.x - from.x, dest.z - from.z).length() > JUMP_RANGE + 0.5:
		return false
	# The claimed start must roughly match where the host sees us (lag slack).
	# The teleported position update may arrive before this request, so the
	# pre-teleport position counts too.
	var d_now := Vector2(global_position.x - from.x, global_position.z - from.z).length()
	var d_pre := Vector2(_pre_tp_pos.x - from.x, _pre_tp_pos.z - from.z).length()
	if minf(d_now, d_pre) > 4.5:
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.6
	query.shape = cap
	query.collision_mask = 8 | 16
	query.transform = Transform3D(Basis.IDENTITY, Vector3(dest.x, 0.95, dest.z))
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return false
	sp -= JUMP_COST
	_sp_delay = SP_REGEN_DELAY
	invuln_time = 0.25
	_tp_check = -1.0
	# Visual effect only: the body keeps following the owner's own states.
	var keep_tp := _net_buf.tp
	_do_teleport(from, Vector3(dest.x, global_position.y, dest.z))
	_net_buf.tp = keep_tp
	return true

## Joiner: the host rejected our position; snap to its version.
func net_correct(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	teleport_count += 1
	_curr_pos = pos
	_snap_visual = true

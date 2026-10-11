class_name AIController
extends Node
## Rival wizard brain. Plays by the same rules as the player: it presses element
## keys inside the combo window (orbs visible above its head), spends SP on
## spatial jumps and reacts to incoming spells with a difficulty-based delay.
##
## Aim: projectiles are aimed with a proper intercept solution (where you WILL
## be when the spell arrives), strikes lead by their warning delay.
## Line of sight: if you hide behind an earth wall the rival stops wasting
## projectiles, switches to spells that ignore walls (lightning, meteors,
## ground zones), flanks around the wall and may teleport past it.

## think: seconds between spells. aim_error: metres of sideways miss at 10 m.
## lead: how well it predicts your movement (0 = aims where you are).
const PROFILES := [
	# Apprentice: slow, sloppy, rarely combos. Should be beatable on a first try.
	{"think": 2.4, "queue_gap": 0.18, "aim_error": 2.2, "lead": 0.25, "dodge_chance": 0.12, "react": 0.5,
		"combo_bias": 0.15, "strafe": 0.55, "flank_jump": 0.0},
	# Adept: steady pressure, fair aim.
	{"think": 1.6, "queue_gap": 0.14, "aim_error": 1.3, "lead": 0.55, "dodge_chance": 0.35, "react": 0.32,
		"combo_bias": 0.4, "strafe": 0.75, "flank_jump": 0.3},
	# Archmage: the real challenge.
	{"think": 1.05, "queue_gap": 0.1, "aim_error": 0.7, "lead": 0.8, "dodge_chance": 0.6, "react": 0.2,
		"combo_bias": 0.65, "strafe": 0.9, "flank_jump": 0.6},
]

const LOS_INTERVAL := 0.12

var wizard: Wizard
var profile: Dictionary
var enabled := false

var _think := 1.0
var _plan: Array = []          # elements still to press for the planned spell
var _plan_key := ""
var _queue_timer := 0.0
var _strafe_dir := 1.0
var _strafe_timer := 0.0
var _dodge_cooldown := 0.0
var _evade_dir := Vector3.ZERO
var _evade_time := 0.0
var _seen_threats: Dictionary = {}
var _aim_noise := Vector3.ZERO
var _move := Vector3.ZERO
# Line of sight
var _los := true
var _los_timer := 0.0
var _blocked_time := 0.0
var _flank_dir := 1.0
var _flank_jump_cd := 0.0

func setup(w: Wizard, difficulty: int) -> void:
	wizard = w
	profile = PROFILES[clampi(difficulty, 0, 2)]
	reset_round()

## Fresh state each round; the first spell comes after a short grace period.
func reset_round() -> void:
	_think = float(profile["think"]) * 1.2
	_plan.clear()
	_plan_key = ""
	_move = Vector3.ZERO
	_evade_time = 0.0
	_seen_threats.clear()

func _physics_process(delta: float) -> void:
	if wizard == null or not enabled or not wizard.alive or not wizard.controls_enabled:
		if wizard:
			wizard.move_input = Vector3.ZERO
		_move = Vector3.ZERO
		return
	var opp := wizard.opponent
	if opp == null or not opp.alive:
		wizard.move_input = Vector3.ZERO
		return
	_dodge_cooldown -= delta
	_flank_jump_cd -= delta
	_update_los(delta, opp)
	_update_aim(opp)
	_update_movement(delta, opp)
	_react_to_threats(opp)
	_update_casting(delta, opp)

# --------------------------------------------------------------------- sight
func _update_los(delta: float, opp: Wizard) -> void:
	_los_timer -= delta
	if _los_timer <= 0.0:
		_los_timer = LOS_INTERVAL
		_los = has_line_of_sight(opp)
	_blocked_time = 0.0 if _los else _blocked_time + delta

## True when no earth wall sits between the two wizards' chests.
func has_line_of_sight(opp: Wizard) -> bool:
	var space := wizard.get_world_3d().direct_space_state
	var from := wizard.global_position + Vector3(0, 1.3, 0)
	var to := opp.global_position + Vector3(0, 1.1, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, 8, [wizard.get_rid(), opp.get_rid()])
	return space.intersect_ray(q).is_empty()

func _blocking_wall(opp: Wizard) -> EarthWall:
	var space := wizard.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(wizard.global_position + Vector3(0, 1.3, 0), opp.global_position + Vector3(0, 1.1, 0), 8, [wizard.get_rid()])
	var hit := space.intersect_ray(q)
	return hit["collider"] as EarthWall if not hit.is_empty() and hit["collider"] is EarthWall else null

# --------------------------------------------------------------------- movement
func _update_movement(delta: float, opp: Wizard) -> void:
	var me := wizard.global_position
	var to := opp.global_position - me
	to.y = 0
	var dist := to.length()
	var fwd := to.normalized() if dist > 0.1 else Vector3.FORWARD
	var side := fwd.cross(Vector3.UP).normalized()
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = randf_range(0.9, 2.2)
		if randf() < 0.65:
			_strafe_dir = -_strafe_dir
	var want := side * _strafe_dir * float(profile["strafe"])
	# Keep a comfortable duelling range.
	var low := wizard.hp < 35.0
	var want_min := 6.5 if not low else 8.5
	var want_max := 11.0
	if dist < want_min:
		want -= fwd * 0.9
	elif dist > want_max:
		want += fwd * 0.9
	# Hidden target: walk around the wall toward the open side.
	if not _los and _blocked_time > 0.25:
		var wall := _blocking_wall(opp)
		if wall and _blocked_time < 0.4:
			var rel := wall.global_position - me
			_flank_dir = -1.0 if side.dot(rel) > 0.0 else 1.0
		want = side * _flank_dir * 1.0 + fwd * 0.35
		if _blocked_time > 1.6 and _flank_jump_cd <= 0.0 and wizard.sp >= Wizard.JUMP_COST + 10.0 \
				and randf() < float(profile["flank_jump"]):
			_flank_jump_cd = 3.0
			wizard.try_spatial_jump(side * _flank_dir + fwd * 0.4)
	# Stay off the boundary.
	var flat := Vector3(me.x, 0, me.z)
	var edge := flat.length() - (Arena.PLAYABLE_RADIUS - 2.5)
	if edge > 0.0:
		want -= flat.normalized() * clampf(edge, 0.0, 1.5)
		if edge > 1.0 and side.dot(flat) * _strafe_dir > 0.0:
			_strafe_dir = -_strafe_dir
	# Step out of enemy ground effects.
	for node in wizard.get_parent().get_children():
		if (node is Strike or node is AreaEffect) and node.caster != wizard:
			var r := float(node.spell.get("radius", 2.0)) + 0.8
			var away: Vector3 = me - (node as Node3D).global_position
			away.y = 0
			if away.length() < r and _evade_time <= 0.0 and randf() < float(profile["dodge_chance"]) * 0.25 + 0.05:
				_evade_dir = (away.normalized() if away.length() > 0.2 else side)
				_evade_time = 0.6
	if _evade_time > 0.0:
		_evade_time -= delta
		want = _evade_dir * 1.4
	# Smooth steering: no single-frame direction flips.
	_move = _move.lerp(want.limit_length(1.0), 1.0 - exp(-7.0 * delta))
	wizard.move_input = _move

# --------------------------------------------------------------------- aiming
func _update_aim(opp: Wizard) -> void:
	var key := _plan_key if not _plan_key.is_empty() else wizard.pending_spell()
	var spell := SpellBook.get_spell(key)
	var chest := opp.global_position + Vector3(0, 1.0, 0)
	var vel := Vector3(opp.velocity.x, 0, opp.velocity.z) * float(profile["lead"])
	var target := chest
	if not spell.is_empty():
		match String(spell["type"]):
			"projectile":
				if spell.has("gravity"):
					var t := wizard.global_position.distance_to(chest) / float(spell["speed"])
					target = opp.global_position + vel * t
				elif not spell.has("homing"):
					target = _intercept(wizard.cast_origin(), chest, vel, float(spell.get("speed", 20.0)))
			"strike":
				target = opp.global_position + vel * float(spell.get("delay", 0.7)) * 0.85
				target.y = 0.0
			"area":
				target = opp.global_position + vel * 0.4
				target.y = 0.0
			"wall":
				target = opp.global_position
	wizard.aim_point = target + _aim_noise

## Where to aim so a projectile of `speed` meets a target moving at `vel`.
static func _intercept(origin: Vector3, target: Vector3, vel: Vector3, speed: float) -> Vector3:
	var t := origin.distance_to(target) / maxf(speed, 0.1)
	for i in 3:
		var p := target + vel * t
		t = origin.distance_to(p) / maxf(speed, 0.1)
	return Arena.clamp_to_arena(target + vel * t, 0.0)

func _reroll_noise(opp: Wizard) -> void:
	# Error grows with distance and is mostly sideways (like a human miss).
	var dist := wizard.global_position.distance_to(opp.global_position)
	var e := float(profile["aim_error"]) * clampf(dist / 10.0, 0.4, 1.4)
	var to := opp.global_position - wizard.global_position
	to.y = 0
	var side := to.normalized().cross(Vector3.UP) if to.length() > 0.1 else Vector3.RIGHT
	_aim_noise = side * randf_range(-e, e) + Vector3(0, randf_range(-e, e) * 0.2, 0)

# --------------------------------------------------------------------- threats
func _react_to_threats(opp: Wizard) -> void:
	if _dodge_cooldown > 0.0:
		return
	var me := wizard.global_position + Vector3(0, 1.0, 0)
	for p in wizard.get_tree().get_nodes_in_group("projectiles"):
		var proj := p as Projectile
		if proj.caster == wizard:
			continue
		var rel := me - proj.global_position
		var closing := proj.velocity.dot(rel.normalized())
		if closing <= 0.0:
			continue
		var tti := rel.length() / maxf(closing, 0.1)
		var miss := rel.cross(proj.velocity.normalized()).length()
		if tti > 0.9 or miss > 1.6:
			continue
		var id := proj.get_instance_id()
		if _seen_threats.has(id):
			continue
		_seen_threats[id] = true
		if randf() > float(profile["dodge_chance"]):
			continue
		_dodge_cooldown = float(profile["react"]) + 0.4
		await wizard.get_tree().create_timer(float(profile["react"]) * 0.5).timeout
		if not is_instance_valid(wizard) or not wizard.alive or not is_instance_valid(proj):
			return
		_evade(proj.velocity, opp)
		return

func _evade(threat_vel: Vector3, opp: Wizard) -> void:
	var side := threat_vel.cross(Vector3.UP).normalized()
	if randf() < 0.5:
		side = -side
	var roll := randf()
	var busy := not _plan.is_empty() or not wizard.elements.is_empty()
	# Wind deflect / earth wall when ready, otherwise teleport or sidestep.
	if roll < 0.25 and wizard.can_cast("wind") and not busy:
		wizard.aim_point = opp.global_position + Vector3(0, 1, 0)
		wizard.queue_element("wind")
		wizard.release_buffer()
		return
	if roll < 0.45 and wizard.can_cast("earth") and not busy:
		wizard.aim_point = opp.global_position
		wizard.queue_element("earth")
		wizard.release_buffer()
		return
	if wizard.sp >= Wizard.JUMP_COST:
		wizard.try_spatial_jump(side)
	else:
		_evade_dir = side
		_evade_time = 0.5

# --------------------------------------------------------------------- casting
func _update_casting(delta: float, opp: Wizard) -> void:
	# Same rules as the player: press element keys inside the combo window and
	# let the wizard's buffer resolve and fire the spell.
	if not _plan_key.is_empty() and not _los and _needs_sight(_plan_key):
		# Target ducked behind a wall mid-combo: abort instead of hitting stone.
		wizard.clear_elements()
		_plan.clear()
		_plan_key = ""
		_think = 0.1
		return
	if not _plan.is_empty():
		_queue_timer -= delta
		if _queue_timer <= 0.0:
			wizard.queue_element(_plan.pop_front())
			_queue_timer = minf(float(profile["queue_gap"]) * randf_range(0.8, 1.2), Wizard.COMBO_WINDOW * 0.8)
		return
	if not _plan_key.is_empty():
		if not wizard.elements.is_empty():
			return   # waiting for the buffer to fire
		_plan_key = ""
		_think = float(profile["think"]) * randf_range(0.7, 1.3)
		return
	_think -= delta
	if _think > 0.0:
		return
	_plan_key = _choose_spell(opp)
	if _plan_key.is_empty():
		_think = 0.25
		return
	_reroll_noise(opp)
	wizard.clear_elements()
	_plan = SpellBook.elements_of(_plan_key)
	_plan.shuffle()
	_queue_timer = 0.05

static func _needs_sight(key: String) -> bool:
	var spell := SpellBook.get_spell(key)
	match String(spell.get("type", "")):
		"projectile":
			return not spell.has("homing")
		"beam", "cone":
			return true
	return false

func _choose_spell(opp: Wizard) -> String:
	var dist := wizard.global_position.distance_to(opp.global_position)
	var options: Array = []   # [key, weight]
	var bias := float(profile["combo_bias"])
	for key in SpellBook.SPELLS:
		var spell: Dictionary = SpellBook.SPELLS[key]
		if wizard.cooldown_left(key) > 0.0 or wizard.mana < float(spell["mana"]) + 2.0:
			continue
		var n := SpellBook.elements_of(key).size()
		var w := 1.0 if n == 1 else (bias * 1.4 if n == 2 else bias * bias * 1.6)
		match String(spell["type"]):
			"projectile":
				if not _los:
					w *= 0.0 if not spell.has("homing") else 0.6
				else:
					w *= 1.6 if dist > 4.0 else 0.8
			"strike":
				if not _los:
					w *= 3.5
				else:
					w *= 1.4 if (opp.stun_time > 0.0 or opp.speed_multiplier() < 0.8) else 0.8
			"area":
				w *= 2.2 if not _los else 0.9
			"cone":
				w *= 2.6 if _los and dist < float(spell["range"]) * 0.8 else 0.0
			"beam":
				w *= 1.2 if _los else 0.0
			"wall":
				w *= 0.0 if not _los else (0.15 if wizard.hp > 50.0 else 0.35)
			"self":
				if spell.has("heal"):
					w *= 2.5 if wizard.hp < 45.0 else 0.0
				elif spell.has("shield"):
					w *= 1.4 if wizard.hp < 70.0 and wizard.shield <= 0.0 else 0.1
				else:
					w *= 0.6 if wizard.speed_multiplier() < 0.9 else 0.1
		if w > 0.0:
			options.append([key, w])
	if options.is_empty():
		return ""
	var total := 0.0
	for o in options:
		total += o[1]
	var r := randf() * total
	for o in options:
		r -= o[1]
		if r <= 0.0:
			return o[0]
	return options[0][0]

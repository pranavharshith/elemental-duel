extends Node3D
## Duel scene: builds arena + wizards, runs best-of-3 rounds, pause and results.
##
## Offline: you vs the AI rival.
## Online (Net.connected): host = wizard 0 (blue), joiner = wizard 1 (red).
##  - The host runs all rules (damage, stats, casts, rounds) for both wizards
##    and streams snapshots + events to the joiner.
##  - Each player moves their own wizard locally; the other wizard is an
##    interpolated "puppet".

enum Phase { WAITING, COUNTDOWN, LIVE, ROUND_END, MATCH_END }

const RIVALS := [
	{"name": "Ember the Apprentice", "color": Color(0.95, 0.35, 0.25), "model": "res://assets/models/characters/bot_red.glb"},
	{"name": "Sable the Adept", "color": Color(0.62, 0.35, 0.95), "model": "res://assets/models/characters/bot_purple.glb"},
	{"name": "Verdant the Archmage", "color": Color(0.3, 0.85, 0.45), "model": "res://assets/models/characters/bot_green.glb"},
]
const HOST_LOOK := {"color": Color(0.25, 0.5, 1.0), "model": "res://assets/models/characters/player_blue.glb"}
const JOIN_LOOK := {"color": Color(0.95, 0.35, 0.25), "model": "res://assets/models/characters/bot_red.glb"}
## Network send rate: every N physics frames. Direct (WebRTC/UDP) links send
## every frame (60 Hz: fresher states, ~8 ms less average delay); the relay
## stays at 30 Hz to keep room-server traffic down.
const NET_SEND_EVERY_DIRECT := 1
const NET_SEND_EVERY_RELAY := 2
const READY_TIMEOUT := 20.0

var arena: Arena
var player: Wizard        # the wizard this machine controls
var enemy: Wizard
var player_ctrl: PlayerController
var ai: AIController
var hud: DuelHUD
var pause_menu: PauseMenu
var phase := Phase.COUNTDOWN
var round_num := 0
var my_wins := 0
var opp_wins := 0

var online := false
var is_host := false
var host_w: Wizard        # wizard 0
var client_w: Wizard      # wizard 1
var _net_frame := 0
var _correction_cd := 0.0
var _ping_t := 0.0

func _ready() -> void:
	online = Net.online and Net.connected
	is_host = online and Net.is_host
	arena = Arena.new()
	add_child(arena)

	player = Wizard.new()
	enemy = Wizard.new()
	player.display_name = "You"
	player.ui_sounds = true
	if online:
		var mine: Dictionary = HOST_LOOK if is_host else JOIN_LOOK
		var theirs: Dictionary = JOIN_LOOK if is_host else HOST_LOOK
		player.robe_color = mine["color"]
		player.model_path = mine["model"]
		enemy.robe_color = theirs["color"]
		enemy.model_path = theirs["model"]
		enemy.display_name = Net.opp_name
		# Roles: see header. The puppet is always the other player's wizard.
		enemy.net_move_remote = true
		if not is_host:
			player.net_stats_remote = true
			enemy.net_stats_remote = true
		host_w = player if is_host else enemy
		client_w = enemy if is_host else player
	else:
		var rival: Dictionary = RIVALS[clampi(Game.difficulty, 0, 2)]
		player.robe_color = HOST_LOOK["color"]
		player.model_path = HOST_LOOK["model"]
		enemy.display_name = rival["name"]
		enemy.robe_color = rival["color"]
		enemy.model_path = rival["model"]
		player.damage_taken_mult = Wizard.PLAYER_DAMAGE_TAKEN[clampi(Game.difficulty, 0, 2)]
		host_w = player
		client_w = enemy
	add_child(player)
	add_child(enemy)

	player.opponent = enemy
	enemy.opponent = player
	if not online or is_host:
		player.died.connect(_on_wizard_died)
		enemy.died.connect(_on_wizard_died)

	player_ctrl = PlayerController.new()
	add_child(player_ctrl)
	player_ctrl.setup(player)

	if not online:
		ai = AIController.new()
		add_child(ai)
		ai.setup(enemy, Game.difficulty)

	hud = DuelHUD.new()
	add_child(hud)
	hud.bind(player, enemy)
	hud.set_names("You", enemy.display_name)

	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	pause_menu.resume_requested.connect(_resume)
	pause_menu.restart_requested.connect(_restart)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if online:
		_setup_online()
	else:
		Game.player_wins = 0
		Game.ai_wins = 0
		_start_round()

# ================================================================ rounds
func _start_round() -> void:
	round_num += 1
	_reset_round()
	if is_host:
		Net.send_round_start(round_num, _host_wins(), _client_wins())
	await _countdown()

func _host_wins() -> int:
	return my_wins if is_host else opp_wins

func _client_wins() -> int:
	return opp_wins if is_host else my_wins

func _reset_round() -> void:
	phase = Phase.COUNTDOWN
	_clear_spells()
	host_w.reset_for_round(Arena.SPAWNS[0], Arena.SPAWNS[1])
	client_w.reset_for_round(Arena.SPAWNS[1], Arena.SPAWNS[0])
	player.controls_enabled = false
	enemy.controls_enabled = false
	if ai:
		ai.enabled = false
	player_ctrl.snap_behind()
	hud.set_score(my_wins, opp_wins, Game.rounds_to_win)

func _countdown() -> void:
	var sub := "vs %s" % enemy.display_name
	for n in [3, 2, 1]:
		hud.banner(str(n), "ROUND %d  ·  %s" % [round_num, sub])
		Sfx.play("countdown", -4.0)
		await get_tree().create_timer(0.55).timeout
		if not is_inside_tree() or phase != Phase.COUNTDOWN:
			return
	hud.banner("DUEL!", "", Color(1.0, 0.85, 0.4))
	Sfx.play("fight", -2.0)
	phase = Phase.LIVE
	player.controls_enabled = true
	enemy.controls_enabled = true
	if ai:
		ai.reset_round()
		ai.enabled = true
	await get_tree().create_timer(0.6).timeout
	if is_inside_tree() and phase == Phase.LIVE:
		hud.clear_banner()

## Host / offline only: a wizard's HP reached zero.
func _on_wizard_died(w: Wizard) -> void:
	if phase != Phase.LIVE:
		return
	var player_won := w == enemy
	if player_won:
		my_wins += 1
	else:
		opp_wins += 1
	Game.player_wins = my_wins
	Game.ai_wins = opp_wins
	var match_over := my_wins >= Game.rounds_to_win or opp_wins >= Game.rounds_to_win
	if is_host:
		Net.send_round_end(1 if w == host_w else 0, _host_wins(), _client_wins(), match_over)
	await _round_end(player_won, match_over)

func _round_end(player_won: bool, match_over: bool) -> void:
	phase = Phase.ROUND_END
	player.controls_enabled = false
	enemy.controls_enabled = false
	if ai:
		ai.enabled = false
	hud.set_score(my_wins, opp_wins, Game.rounds_to_win)
	var cam := player_ctrl.camera
	if cam:
		cam.add_shake(0.6)
	if not online:
		# Slow-motion finish (offline only: it would desync two machines).
		Engine.time_scale = 0.35
		await get_tree().create_timer(0.5, true, false, true).timeout
		Engine.time_scale = 1.0
	else:
		await get_tree().create_timer(0.4).timeout
	if not is_inside_tree():
		return
	var score := "%d - %d" % [my_wins, opp_wins]
	if player_won:
		Sfx.play("victory", -3.0)
		player.play_victory()
		hud.banner("ROUND WON" if not match_over else "VICTORY", score, Color(1.0, 0.85, 0.35))
	else:
		Sfx.play("defeat", -3.0)
		enemy.play_victory()
		hud.banner("ROUND LOST" if not match_over else "DEFEAT", score, Color(1.0, 0.45, 0.45))
	await get_tree().create_timer(2.0).timeout
	if not is_inside_tree() or phase == Phase.MATCH_END:
		return
	if match_over:
		phase = Phase.MATCH_END
		hud.clear_banner()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		pause_menu.show_result(player_won, score, online, is_host)
	elif not online or is_host:
		_start_round()
	# Joiner: the host's next round_start message starts the next round.

func _clear_spells() -> void:
	for c in get_children():
		if c is Projectile or c is Strike or c is AreaEffect or c is EarthWall:
			c.queue_free()

# ================================================================ pause
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and phase != Phase.MATCH_END:
		if pause_menu.visible:
			_resume()
		else:
			_pause()
		get_viewport().set_input_as_handled()

func _pause() -> void:
	# Online games can't freeze time: the menu opens, the match keeps going.
	if not online:
		get_tree().paused = true
	player_ctrl.input_enabled = false
	player.move_input = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_menu.show_pause(online)

func _resume() -> void:
	pause_menu.visible = false
	get_tree().paused = false
	player_ctrl.input_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _restart() -> void:
	if online:
		Net.start_match()   # host only; reloads the duel on both machines
	else:
		Game.start_match()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and phase == Phase.LIVE and not pause_menu.visible:
		_pause()

# ================================================================ online
func _setup_online() -> void:
	Net.session_ended.connect(_on_session_ended)
	Net.register_duel(self)
	player_ctrl.net_client = not is_host
	if is_host:
		for w in [host_w, client_w]:
			(w as Wizard).spell_cast.connect(_host_on_cast)
			(w as Wizard).hit_fx.connect(_host_on_hit_fx)
			(w as Wizard).jumped.connect(_host_on_jump)
		client_w.knockback_added.connect(func(_w: Wizard, kb: Vector3) -> void: Net.send_knockback(kb))
		client_w.fizzled.connect(func(_w: Wizard, reason: String) -> void: Net.send_fizzle(reason))
		client_w.needs_correction.connect(func(_w: Wizard, pos: Vector3, reason: String) -> void: _send_correction(pos, reason))
		_reset_round()
		phase = Phase.WAITING
		hud.banner("", "Waiting for %s…" % Net.opp_name)
		var ok: bool = await Net.wait_remote_ready(READY_TIMEOUT)
		if not is_inside_tree():
			return
		if not ok:
			if Net.online:
				Net.leave()
			_on_session_ended("%s didn't load the match in time." % enemy.display_name)
			return
		_start_round()
	else:
		_reset_round()
		phase = Phase.WAITING
		hud.banner("", "Waiting for the host…")

func _physics_process(delta: float) -> void:
	if not online:
		return
	_correction_cd = maxf(0.0, _correction_cd - delta)
	_net_frame += 1
	var every := NET_SEND_EVERY_DIRECT if Net.is_direct() else NET_SEND_EVERY_RELAY
	if _net_frame % every != 0:
		return
	if is_host:
		var motion := host_w.net_motion()
		Net.send_snapshot({"t": NetBuffer.now(), "r": Net.my_rtt(), "m": motion, "h": host_w.net_stats(), "c": client_w.net_stats()})
	else:
		var state := client_w.net_motion()
		state["t"] = NetBuffer.now()
		state["r"] = Net.my_rtt()
		Net.send_input(state)

func _process(delta: float) -> void:
	if not online:
		return
	_ping_t -= delta
	if _ping_t <= 0.0:
		_ping_t = 0.5
		hud.set_ping(Net.ping_ms(), Net.link_kind())

func _send_correction(pos: Vector3, reason: String) -> void:
	if _correction_cd > 0.0:
		return
	_correction_cd = 0.5
	Net.send_correction(pos, reason)

func _on_session_ended(reason: String) -> void:
	if not is_inside_tree():
		return
	online = false
	phase = Phase.MATCH_END
	player.controls_enabled = false
	enemy.controls_enabled = false
	player.move_input = Vector3.ZERO
	get_tree().paused = false
	hud.clear_banner()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_menu.show_message("DISCONNECTED", reason)

# ---- host: authoritative events -> joiner
func _index_of(w: Wizard) -> int:
	return 0 if w == host_w else 1

func _host_on_cast(w: Wizard, key: String) -> void:
	Net.send_cast(_index_of(w), key, w.aim_point, w.last_cast_seed)

func _host_on_hit_fx(w: Wizard, dealt: float, absorbed: float, anim: int) -> void:
	Net.send_hit_fx(_index_of(w), dealt, absorbed, anim)

func _host_on_jump(w: Wizard, from: Vector3, to: Vector3) -> void:
	if w == host_w:
		Net.send_jump_fx(0, from, to)

# ---- host: joiner's requests (called by Net after sender validation)
func net_client_input(state: Dictionary) -> void:
	Net.remote_rtt = int(state.get("r", -1))
	if not client_w.net_push_motion(state, float(state.get("t", 0.0)), true):
		_send_correction(client_w.global_position, "Movement rejected")

func net_client_element(element: String, aim: Vector3) -> void:
	client_w.aim_point = aim
	client_w.queue_element(element)

func net_client_release(aim: Vector3) -> void:
	client_w.aim_point = aim
	client_w.release_buffer()

func net_client_jump(from: Vector3, dest: Vector3) -> void:
	if not client_w.net_validate_jump(from, dest):
		_send_correction(client_w._pre_tp_pos if client_w._tp_check >= 0.0 else client_w.global_position, "Jump blocked")

# ---- joiner: host's messages
func net_snapshot(snap: Dictionary) -> void:
	var t := float(snap.get("t", 0.0))
	Net.remote_rtt = int(snap.get("r", -1))
	host_w.net_push_motion(snap.get("m", {}), t, false)
	host_w.net_apply_stats(snap.get("h", {}))
	client_w.net_apply_stats(snap.get("c", {}))

func _wizard_at(index: int) -> Wizard:
	return host_w if index == 0 else client_w

func net_cast(index: int, key: String, aim: Vector3, cast_seed: int) -> void:
	_wizard_at(index).net_play_cast(key, aim, cast_seed)

func net_hit_fx(index: int, dealt: float, absorbed: float, anim: int) -> void:
	_wizard_at(index).net_play_hit_fx(dealt, absorbed, anim)

func net_knockback(kb: Vector3) -> void:
	client_w.net_add_knockback(kb)

func net_fizzle(reason: String) -> void:
	client_w.fizzled.emit(client_w, reason)
	Sfx.play("fizzle", -8.0)

func net_jump_fx(index: int, from: Vector3, to: Vector3) -> void:
	var w := _wizard_at(index)
	VFX.portal(self, from, w.robe_color)
	VFX.portal(self, to, w.robe_color)
	VFX.jump_trail(self, from + Vector3.UP, to + Vector3.UP, w.robe_color)
	Sfx.play_at("teleport", to, -2.0)

func net_correction(pos: Vector3, reason: String) -> void:
	client_w.net_correct(pos)
	client_w.fizzled.emit(client_w, reason)

func net_round_start(num: int, host_wins: int, client_wins: int) -> void:
	round_num = num
	my_wins = client_wins
	opp_wins = host_wins
	_reset_round()
	_countdown()

func net_round_end(winner: int, host_wins: int, client_wins: int, match_over: bool) -> void:
	if phase == Phase.ROUND_END or phase == Phase.MATCH_END:
		return
	my_wins = client_wins
	opp_wins = host_wins
	var loser := client_w if winner == 0 else host_w
	loser.net_kill()
	_round_end(winner == 1, match_over)

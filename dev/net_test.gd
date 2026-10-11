extends Node
## Two-process online test. Run one host and one joiner on this PC:
##   godot --headless --path . res://dev/net_test.tscn -- --role=host
##   godot --headless --path . res://dev/net_test.tscn -- --role=join
## Each side prints PASS/FAIL lines for what it can observe.

var role := "host"
var duel: Node
var _fails := 0
var _damaged := 0
var _corrections := 0
var _ended := ""
var _move := Vector3.ZERO

var persistent := false
const CODE_FILE := "user://net_test_code.txt"

func _ready() -> void:
	# The match changes scene, which would free this node: re-host the test on
	# the root (outside current_scene) so it survives.
	if not persistent:
		var keeper: Node = (get_script() as GDScript).new()
		keeper.persistent = true
		keeper.name = "NetTestKeeper"
		get_tree().root.add_child.call_deferred(keeper)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.substr(7)
	Net.session_ended.connect(func(r: String) -> void:
		_ended = r
		print("[%s] session ended: %s" % [role, r]))
	_run()

func _check(name: String, ok: bool, detail: String = "") -> void:
	print("[%s] %s  %s  %s" % [role, "PASS" if ok else "FAIL", name, detail])
	if not ok:
		_fails += 1

func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _physics_process(_d: float) -> void:
	if duel == null or not is_instance_valid(duel) or duel.player == null:
		return
	var p: Wizard = duel.player
	p.move_input = _move
	if duel.enemy:
		p.aim_point = duel.enemy.global_position + Vector3(0, 1.1, 0)

func _finish() -> void:
	print("[%s] done, %d failure(s)" % [role, _fails])
	get_tree().quit(1 if _fails > 0 else 0)

func _run() -> void:
	# ---------------- connect
	if role == "host":
		print("[host] server: %s" % Net.server_url())
		_check("host room requested", Net.host_room("HostWiz"))
		var tc := 0.0
		while Net.room_code.is_empty() and Net.online and tc < 10.0:
			await _wait(0.05)
			tc += 0.05
		_check("server gave a room code", Net.room_code.length() == 5, "code=%s %s" % [Net.room_code, Net.last_status()[0]])
		if Net.room_code.is_empty():
			return _finish()
		var f := FileAccess.open(CODE_FILE, FileAccess.WRITE)
		f.store_string(Net.room_code)
		f.close()
		var t := 0.0
		while not Net.connected and t < 20.0:
			await _wait(0.1)
			t += 0.1
		_check("joiner connected + handshake", Net.connected, "opp=%s" % Net.opp_name)
		if not Net.connected:
			return _finish()
		await _wait(0.5)
		Net.start_match()
	else:
		# A wrong code must fail with a clear message.
		Net.join_room("ZZZZZ", "JoinWiz")
		var tw := 0.0
		while Net.online and tw < 10.0:
			await _wait(0.05)
			tw += 0.05
		_check("wrong code is rejected", not Net.online and String(Net.last_status()[0]).contains("not found"), String(Net.last_status()[0]))
		# Wait for the host's code (written by the host process), type it lower-case.
		var code := ""
		var tf := 0.0
		while code.is_empty() and tf < 15.0:
			if FileAccess.file_exists(CODE_FILE):
				code = FileAccess.get_file_as_string(CODE_FILE).strip_edges()
			await _wait(0.1)
			tf += 0.1
		print("[join] joining room %s" % code)
		Net.join_room(code.to_lower(), "JoinWiz")
		var t := 0.0
		while not Net.connected and t < 15.0:
			await _wait(0.1)
			t += 0.1
		_check("connected to host", Net.connected, "host=%s" % Net.opp_name)
		if not Net.connected:
			return _finish()
	# ---------------- direct (WebRTC) link, when this build supports it
	if RelayPeer.rtc_supported():
		var tr := 0.0
		while Net.link_kind() != "direct" and Net.connected and tr < 10.0:
			await _wait(0.1)
			tr += 0.1
		_check("direct WebRTC link established", Net.link_kind() == "direct", "after %.1fs, link=%s" % [tr, Net.link_kind()])
	else:
		print("[%s] WebRTC not available in this build: testing the relay path" % role)
	await _wait(1.2)
	print("[%s] link=%s ping=%d ms" % [role, Net.link_kind(), Net.ping_ms()])
	# ---------------- wait for the duel scene + round 1 LIVE
	var t2 := 0.0
	while t2 < 25.0:
		var cs := get_tree().current_scene
		if cs and cs.has_method("net_snapshot") and cs.phase == 2:   # Phase.LIVE
			duel = cs
			break
		await _wait(0.05)
		t2 += 0.05
	_check("round 1 is live", duel != null)
	if duel == null:
		return _finish()
	duel.player_ctrl.set_physics_process(false)   # the test drives input
	duel.player_ctrl.set_process_unhandled_input(false)
	var p: Wizard = duel.player
	var e: Wizard = duel.enemy
	p.damaged.connect(func(_w: Wizard, _a: float) -> void: _damaged += 1)
	p.fizzled.connect(func(_w: Wizard, r: String) -> void:
		print("[%s] fizzle: %s" % [role, r])
		if r.contains("rejected") or r.contains("blocked") or r.contains("not allowed"):
			_corrections += 1)
	var e_spawn := e.global_position
	var p_spawn := p.global_position

	# ---------------- 1. movement replicates both ways
	await _wait(0.5)
	_move = Vector3(1, 0, 0)
	await _wait(1.0)
	_move = Vector3.ZERO
	await _wait(0.6)
	var my_moved := p.global_position.distance_to(p_spawn)
	var they_moved := e.global_position.distance_to(e_spawn)
	_check("my wizard moved locally", my_moved > 2.0, "%.2f m" % my_moved)
	_check("opponent's movement replicated here", they_moved > 2.0, "%.2f m" % they_moved)
	print("[%s] me=%s  opponent(as seen here)=%s" % [role, p.global_position.snapped(Vector3.ONE * 0.01), e.global_position.snapped(Vector3.ONE * 0.01)])

	# ---------------- 2. host casts at joiner
	if role == "host":
		p.queue_element("fire")
		await _wait(2.0)
		_check("host: joiner took fireball damage (authoritative)", e.hp < 100.0, "joiner hp=%.1f" % e.hp)
	else:
		await _wait(2.0)
		_check("joiner: my HP dropped (from host snapshot)", p.hp < 100.0, "hp=%.1f" % p.hp)
		_check("joiner: hit feedback replayed here", _damaged > 0, "damaged signals=%d" % _damaged)

	# ---------------- 3. joiner casts at host
	await _wait(0.5)
	if role == "join":
		Net.send_element("water", p.aim_point)
		# Combo window + a full round trip (slow relays can take ~0.5 s).
		var tm := 0.0
		while p.mana >= 99.0 and tm < 1.5:
			await _wait(0.05)
			tm += 0.05
		_check("joiner: my mana was spent (host-side rules)", p.mana < 99.0, "mana=%.1f after %.2fs" % [p.mana, tm])
		await _wait(maxf(0.1, 2.0 - tm))
		_check("joiner: host's HP drop visible here", e.hp < 100.0, "host hp=%.1f" % e.hp)
	else:
		await _wait(2.0)
		_check("host: joiner's spell damaged me", p.hp < 100.0, "hp=%.1f" % p.hp)

	# ---------------- 4. joiner teleports, host validates
	await _wait(0.5)
	if role == "join":
		var before := p.global_position
		var ok := p.net_predict_jump(Vector3(0, 0, 1))
		await _wait(1.0)
		_check("joiner: jump accepted (no correction)", ok and _corrections == 0 and p.global_position.distance_to(before) > 1.5, "moved %.2f, corrections=%d" % [p.global_position.distance_to(before), _corrections])
		_check("joiner: SP spent per host", p.sp < 90.0, "sp=%.1f" % p.sp)
	else:
		await _wait(1.0)
		_check("host: joiner's SP charged for jump", e.sp < 90.0, "joiner sp=%.1f" % e.sp)

	# ---------------- 5. host ends the round, joiner follows
	await _wait(0.5)
	if role == "host":
		e.take_hit(500.0)
		await _wait(0.6)
		_check("host: round ended", duel.phase == 3, "phase=%d" % duel.phase)
		await _wait(3.5)
		_check("host: round 2 started", duel.round_num == 2, "round=%d" % duel.round_num)
		await _wait(1.5)
		_check("host: my score is 1", duel.my_wins == 1)
	else:
		await _wait(0.6)
		_check("joiner: round end received", duel.phase == 3 and not p.alive, "phase=%d alive=%s" % [duel.phase, p.alive])
		await _wait(3.5)
		_check("joiner: round 2 started", duel.round_num == 2 and p.alive, "round=%d" % duel.round_num)
		await _wait(1.5)
		_check("joiner: opponent score is 1", duel.opp_wins == 1)

	print("[%s] after the duel: link=%s ping=%d ms remote delay=%.0f ms" % [role, Net.link_kind(), Net.ping_ms(), e._net_buf.delay() * 1000.0])
	# ---------------- 6. disconnect handling
	if role == "join":
		await _wait(0.5)
		print("[join] quitting to simulate a player leaving")
		Net.leave()
		await _wait(0.3)
		_finish()
	else:
		var t3 := 0.0
		while _ended.is_empty() and t3 < 10.0:
			await _wait(0.1)
			t3 += 0.1
		_check("host: noticed the joiner leaving", not _ended.is_empty(), "after %.1fs: %s" % [t3, _ended])
		_check("host: duel shows disconnect screen", duel.pause_menu.visible)
		_finish()

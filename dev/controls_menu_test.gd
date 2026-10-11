extends Node
## Dev test: open the Controls popup, rebind Fire Q -> G with real key events,
## check swap + Esc cancel + persistence, screenshot, then restore defaults.

var persistent := false

func _ready() -> void:
	if not persistent:
		var keeper: Node = (get_script() as GDScript).new()
		keeper.persistent = true
		get_tree().root.add_child.call_deferred(keeper)
		get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")
		return
	await get_tree().create_timer(0.8).timeout
	var fails := 0
	Game.reset_bindings()
	var menu := get_tree().current_scene
	var panel := ControlsPanel.new()
	menu._show_overlay(panel)
	await get_tree().create_timer(0.3).timeout
	# Rebind Fire to G.
	(panel._buttons["elem_fire"] as Button).pressed.emit()
	await _key(KEY_G)
	fails += _check("Fire rebound to G", Game.bindings["elem_fire"] == KEY_G)
	fails += _check("InputMap uses G for fire", _has_key("elem_fire", KEY_G) and not _has_key("elem_fire", KEY_Q))
	fails += _check("popup still open after capture", menu._overlay != null)
	# Rebind Water to G -> swap: Fire gets E.
	(panel._buttons["elem_water"] as Button).pressed.emit()
	await _key(KEY_G)
	fails += _check("conflict swaps keys", Game.bindings["elem_water"] == KEY_G and Game.bindings["elem_fire"] == KEY_E)
	# Esc cancels without closing.
	(panel._buttons["spatial_jump"] as Button).pressed.emit()
	await _key(KEY_ESCAPE)
	fails += _check("Esc cancels rebind", Game.bindings["spatial_jump"] == KEY_SPACE and menu._overlay != null)
	# Persistence.
	var cfg := ConfigFile.new()
	cfg.load(Game.SETTINGS_PATH)
	fails += _check("saved to settings", int(cfg.get_value("keys", "elem_water", 0)) == KEY_G)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://dev/shots/controls_menu.png")
	Game.reset_bindings()
	fails += _check("reset restores Q", Game.bindings["elem_fire"] == KEY_Q and _has_key("elem_fire", KEY_Q))
	print("controls menu test: %d failure(s)" % fails)
	get_tree().quit()

func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	ev = ev.duplicate()
	ev.pressed = false
	Input.parse_input_event(ev)
	await get_tree().process_frame

func _has_key(action: String, code: int) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey and (e as InputEventKey).physical_keycode == code:
			return true
	return false

func _check(n: String, ok: bool) -> int:
	print("%s  %s" % ["PASS" if ok else "FAIL", n])
	return 0 if ok else 1

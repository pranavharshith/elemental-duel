class_name DuelHUD
extends CanvasLayer
## In-match HUD: HP bars, mana/SP, element queue, spell preview, ability keys,
## cooldowns, crosshair, banners and toasts.

var player: Wizard
var enemy: Wizard

var _p_hp: ProgressBar
var _p_hp_ghost: ProgressBar
var _e_hp: ProgressBar
var _e_hp_ghost: ProgressBar
var _p_hp_text: Label
var _e_hp_text: Label
var _mana: ProgressBar
var _sp: ProgressBar
var _mana_text: Label
var _sp_text: Label
var _shield_label: Label
var _slots: Array[PanelContainer] = []
var _spell_name: Label
var _spell_info: Label
var _elem_tiles: Dictionary = {}
var _jump_tile: PanelContainer
var _cooldown_box: VBoxContainer
var _banner: Label
var _sub_banner: Label
var _toast: Label
var _toast_t := 0.0
var _pips_p: HBoxContainer
var _pips_e: HBoxContainer
var _crosshair: Control
var _e_queue: HBoxContainer
var _vignette: ColorRect
var _vignette_t := 0.0
var spellbook: SpellbookPanel
var _book_holder: CenterContainer
var _status_p: Label
var _status_e: Label
# Change tracking so per-frame updates don't rebuild styles / theme overrides.
var _jump_on_style := UIKit.panel_style(Color(0.55, 0.95, 0.75), 23, Color(1, 1, 1, 0.5), 2)
var _jump_off_style := UIKit.panel_style(Color(0.25, 0.3, 0.3), 23, Color(1, 1, 1, 0.1), 2)
var _jump_ready := false
var _jump_init := false
var _slot_styles: Dictionary = {}
var _slot_state: Array[String] = []
var _spell_name_color := Color(-1, -1, -1)
var _vignette_amount := -1.0
var _frames := 0

func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.theme()
	add_child(root)

	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = "shader_type canvas_item; uniform float amount = 0.0; void fragment(){ vec2 d = UV - 0.5; float v = smoothstep(0.25, 0.75, length(d)); COLOR = vec4(0.8, 0.05, 0.05, v * amount); }"
	var sm := ShaderMaterial.new()
	sm.shader = sh
	_vignette.material = sm
	root.add_child(_vignette)

	_build_top(root)
	_build_bottom(root)
	_build_center(root)
	_build_cooldowns(root)

	_book_holder = CenterContainer.new()
	_book_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_book_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_book_holder.visible = false
	root.add_child(_book_holder)
	spellbook = SpellbookPanel.new()
	_book_holder.add_child(spellbook)

func bind(p: Wizard, e: Wizard) -> void:
	player = p
	enemy = e
	p.fizzled.connect(func(_w: Wizard, reason: String) -> void: toast(reason, Color(1, 0.6, 0.5)))
	p.damaged.connect(func(_w: Wizard, amount: float) -> void: _vignette_t = clampf(_vignette_t + amount / 25.0, 0.0, 1.0))
	p.spell_cast.connect(func(_w: Wizard, key: String) -> void:
		var s := SpellBook.get_spell(key)
		if SpellBook.elements_of(key).size() >= 2:
			toast(String(s["name"]) + "!", (s["color"] as Color).lightened(0.3)))

# ------------------------------------------------------------------ layout
func _side_panel(root: Control, left: bool) -> Dictionary:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.06, 0.05, 0.1, 0.7), 12, Color(1, 1, 1, 0.08), 1))
	panel.custom_minimum_size = Vector2(470, 0)
	root.add_child(panel)
	if left:
		panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		panel.position = Vector2(24, 20)
	else:
		panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		panel.position = Vector2(-24 - 470, 20)
		panel.offset_left = -24 - 470
		panel.offset_right = -24
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var name := UIKit.label("", 20, UIKit.TEXT, 700)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 6)
	var hp_text := UIKit.label("100", 18, UIKit.TEXT, 700)
	if left:
		head.add_child(name)
		head.add_child(pips)
	else:
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		head.add_child(pips)
		head.add_child(name)
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(0, 26)
	vb.add_child(stack)
	var ghost := UIKit.bar(Color(1.0, 0.9, 0.7, 0.9), 26, 8)
	ghost.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(ghost)
	var hp := UIKit.bar(Color(0.25, 0.85, 0.4) if left else Color(0.95, 0.3, 0.3), 26, 8)
	hp.set_anchors_preset(Control.PRESET_FULL_RECT)
	(hp.get_theme_stylebox("background") as StyleBoxFlat).bg_color = Color(0, 0, 0, 0)
	if not left:
		hp.fill_mode = ProgressBar.FILL_END_TO_BEGIN
		ghost.fill_mode = ProgressBar.FILL_END_TO_BEGIN
	stack.add_child(hp)
	hp_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stack.add_child(hp_text)
	var status := UIKit.label("", 14, UIKit.MUTED)
	if not left:
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(status)
	return {"name": name, "hp": hp, "ghost": ghost, "text": hp_text, "pips": pips, "status": status, "vb": vb}

func _build_top(root: Control) -> void:
	var l := _side_panel(root, true)
	_p_hp = l["hp"]
	_p_hp_ghost = l["ghost"]
	_p_hp_text = l["text"]
	_pips_p = l["pips"]
	_status_p = l["status"]
	(l["name"] as Label).text = "You"
	var r := _side_panel(root, false)
	_e_hp = r["hp"]
	_e_hp_ghost = r["ghost"]
	_e_hp_text = r["text"]
	_pips_e = r["pips"]
	_status_e = r["status"]
	(r["name"] as Label).set_meta("enemy_name", true)
	r["name"].name = "EnemyName"
	_e_queue = HBoxContainer.new()
	_e_queue.alignment = BoxContainer.ALIGNMENT_END
	_e_queue.add_theme_constant_override("separation", 4)
	_e_queue.custom_minimum_size = Vector2(0, 22)
	(r["vb"] as VBoxContainer).add_child(_e_queue)
	_enemy_name_label = r["name"]

var _enemy_name_label: Label

func set_names(p: String, e: String) -> void:
	_enemy_name_label.text = e

func set_score(pw: int, ew: int, needed: int) -> void:
	for box in [_pips_p, _pips_e]:
		for c in box.get_children():
			c.queue_free()
	for i in needed:
		_pips_p.add_child(_pip(i < pw))
		_pips_e.add_child(_pip(i < ew))

func _pip(on: bool) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(16, 16)
	p.add_theme_stylebox_override("panel", UIKit.panel_style(Color(1.0, 0.8, 0.3) if on else Color(0.2, 0.18, 0.28), 8, Color(1, 1, 1, 0.3), 1))
	return p

func _build_bottom(root: Control) -> void:
	# Resource bars (bottom-left).
	var res := PanelContainer.new()
	res.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.06, 0.05, 0.1, 0.7), 12, Color(1, 1, 1, 0.08), 1))
	res.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	res.grow_vertical = Control.GROW_DIRECTION_BEGIN
	res.offset_left = 24
	res.offset_bottom = -24
	res.offset_top = -24
	res.custom_minimum_size = Vector2(340, 0)
	root.add_child(res)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	res.add_child(vb)
	var mrow := HBoxContainer.new()
	mrow.add_child(UIKit.label("MANA", 14, Color(0.6, 0.75, 1.0), 700))
	_mana_text = UIKit.label("100", 14, UIKit.TEXT, 700)
	_mana_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mana_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mrow.add_child(_mana_text)
	vb.add_child(mrow)
	_mana = UIKit.bar(Color(0.3, 0.5, 1.0), 14, 5)
	vb.add_child(_mana)
	var srow := HBoxContainer.new()
	srow.add_child(UIKit.label("SP  ·  Spatial Jump (35)", 14, Color(0.75, 1.0, 0.85), 700))
	_sp_text = UIKit.label("100", 14, UIKit.TEXT, 700)
	_sp_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	srow.add_child(_sp_text)
	vb.add_child(srow)
	_sp = UIKit.bar(Color(0.4, 0.95, 0.65), 14, 5)
	vb.add_child(_sp)
	_shield_label = UIKit.label("", 14, Color(0.95, 0.75, 0.45), 700)
	vb.add_child(_shield_label)

	# Spell composer (bottom-centre).
	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BEGIN
	center.offset_bottom = -22
	center.alignment = BoxContainer.ALIGNMENT_END
	center.add_theme_constant_override("separation", 8)
	root.add_child(center)
	_spell_name = UIKit.label("", 26, UIKit.TEXT, 800)
	_spell_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spell_name.add_theme_constant_override("outline_size", 10)
	_spell_name.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.12, 0.85))
	center.add_child(_spell_name)
	_spell_info = UIKit.label("", 14, Color(0.22, 0.22, 0.3))
	_spell_info.add_theme_constant_override("outline_size", 0)
	_spell_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_spell_info)
	var slots := HBoxContainer.new()
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	slots.add_theme_constant_override("separation", 10)
	center.add_child(slots)
	for i in SpellBook.MAX_QUEUE:
		var s := PanelContainer.new()
		s.custom_minimum_size = Vector2(52, 52)
		slots.add_child(s)
		_slots.append(s)
		_slot_state.append("-")   # sentinel: style applied on the first update
	var keys_panel := PanelContainer.new()
	keys_panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.06, 0.05, 0.1, 0.7), 14, Color(1, 1, 1, 0.08), 1))
	keys_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(keys_panel)
	var keys := HBoxContainer.new()
	keys.alignment = BoxContainer.ALIGNMENT_CENTER
	keys.add_theme_constant_override("separation", 10)
	keys_panel.add_child(keys)
	for e in SpellBook.ELEMENTS:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		var chip := UIKit.element_chip(e, 46)
		col.add_child(chip)
		var n := UIKit.label(String(SpellBook.ELEMENT_INFO[e]["name"]), 12, UIKit.TEXT)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(n)
		keys.add_child(col)
		_elem_tiles[e] = chip
	var jcol := VBoxContainer.new()
	jcol.add_theme_constant_override("separation", 2)
	_jump_tile = PanelContainer.new()
	_jump_tile.custom_minimum_size = Vector2(96, 46)
	var jl := UIKit.label(Game.key_name("spatial_jump").to_upper(), 14, Color(0.08, 0.05, 0.1), 800)
	jl.add_theme_constant_override("outline_size", 0)
	jl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	jl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_jump_tile.add_child(jl)
	jcol.add_child(_jump_tile)
	var jn := UIKit.label("Spatial Jump", 12, UIKit.MUTED)
	jn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	jcol.add_child(jn)
	keys.add_child(jcol)

	var help := UIKit.label("%s spellbook  ·  ESC pause" % Game.key_name("spellbook").to_upper(), 13, Color(0.2, 0.2, 0.26, 0.7))
	help.add_theme_constant_override("outline_size", 0)
	help.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	help.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help.offset_right = -24
	help.offset_bottom = -20
	root.add_child(help)

func _build_center(root: Control) -> void:
	_crosshair = Crosshair.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_crosshair)
	_banner = UIKit.label("", 96, Color.WHITE, 900)
	_banner.add_theme_constant_override("outline_size", 18)
	_banner.add_theme_color_override("font_outline_color", Color(0.15, 0.05, 0.25, 0.9))
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = -170
	_banner.offset_bottom = -50
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.pivot_offset = Vector2(400, 60)
	root.add_child(_banner)
	_sub_banner = UIKit.label("", 26, UIKit.TEXT, 600)
	_sub_banner.add_theme_constant_override("outline_size", 10)
	_sub_banner.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.12, 0.85))
	_sub_banner.set_anchors_preset(Control.PRESET_CENTER)
	_sub_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_sub_banner.offset_top = -40
	_sub_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_sub_banner)
	_toast = UIKit.label("", 22, UIKit.TEXT, 700)
	_toast.add_theme_constant_override("outline_size", 10)
	_toast.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.12, 0.85))
	_toast.set_anchors_preset(Control.PRESET_CENTER)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = 70
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_toast)

func _build_cooldowns(root: Control) -> void:
	_cooldown_box = VBoxContainer.new()
	_cooldown_box.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_cooldown_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_cooldown_box.offset_right = -24
	_cooldown_box.add_theme_constant_override("separation", 4)
	root.add_child(_cooldown_box)

# ------------------------------------------------------------------ runtime
func banner(text: String, sub: String = "", color: Color = Color.WHITE) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_sub_banner.text = sub
	_banner.scale = Vector2(1.4, 1.4)
	_banner.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_banner, "modulate:a", 1.0, 0.15)

func clear_banner() -> void:
	var tw := create_tween()
	tw.tween_property(_banner, "modulate:a", 0.0, 0.3)
	_sub_banner.text = ""

func toast(text: String, color: Color = UIKit.TEXT) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast.modulate.a = 1.0
	_toast_t = 1.2

func set_crosshair_visible(v: bool) -> void:
	_crosshair.visible = v

var _ping: Label

## Online only: connection quality, top centre. Green < 60 ms, amber < 120.
## `link`: "direct" (peer-to-peer), "connecting" or "relay" (via the server).
func set_ping(ms: int, link: String = "relay") -> void:
	if _ping == null:
		_ping = UIKit.label("", 15, UIKit.TEXT, 700)
		_ping.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_ping.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_ping.offset_top = 24
		_ping.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_ping.add_theme_constant_override("outline_size", 8)
		_ping.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.85))
		get_child(0).add_child(_ping)
	var link_text: String = {"direct": "DIRECT", "connecting": "CONNECTING"}.get(link, "RELAY")
	if ms < 0:
		_ping.text = "ONLINE  ·  %s  ·  ping —" % link_text
		_ping.add_theme_color_override("font_color", UIKit.MUTED)
		return
	_ping.text = "ONLINE  ·  %s  ·  ping %d ms" % [link_text, ms]
	var c := Color(0.45, 1.0, 0.55) if ms < 60 else (Color(1.0, 0.8, 0.3) if ms < 120 else Color(1.0, 0.4, 0.35))
	_ping.add_theme_color_override("font_color", c)

func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t < 0.4:
			_toast.modulate.a = _toast_t / 0.4
	_vignette_t = maxf(0.0, _vignette_t - delta * 1.5)
	var low := 0.0
	if player and player.alive and player.hp < 30.0:
		low = 0.25 + 0.15 * sin(Time.get_ticks_msec() / 200.0)
	var amount := maxf(_vignette_t, low)
	if amount != _vignette_amount:
		_vignette_amount = amount
		(_vignette.material as ShaderMaterial).set_shader_parameter("amount", amount)
	# A full-screen blended quad costs fill-rate every frame even when fully
	# transparent: hide it when idle (kept for the first frames so its shader
	# compiles during loading, not on the first hit).
	_frames += 1
	_vignette.visible = amount > 0.001 or _frames < 5
	if player == null or enemy == null:
		return
	_update_bars(delta)
	_update_composer()
	_update_cooldowns()
	_update_enemy_queue()
	var reticle := _crosshair as Crosshair
	if player.aim_blocked:
		reticle.state = Crosshair.State.BLOCKED
	elif player.reticle_target == enemy:
		reticle.state = Crosshair.State.TARGET
	else:
		reticle.state = Crosshair.State.NEUTRAL
	_book_holder.visible = Input.is_action_pressed("spellbook")

func _update_bars(delta: float) -> void:
	_p_hp.value = player.hp
	_e_hp.value = enemy.hp
	_p_hp_ghost.value = maxf(player.hp, move_toward(_p_hp_ghost.value, player.hp, 30.0 * delta))
	_e_hp_ghost.value = maxf(enemy.hp, move_toward(_e_hp_ghost.value, enemy.hp, 30.0 * delta))
	_p_hp_text.text = "%d" % ceili(player.hp)
	_e_hp_text.text = "%d" % ceili(enemy.hp)
	_mana.value = player.mana
	_sp.value = player.sp
	_mana_text.text = "%d" % int(player.mana)
	_sp_text.text = "%d" % int(player.sp)
	_shield_label.text = ("Stone Skin  %d" % int(player.shield)) if player.shield > 0.0 else ""
	_status_p.text = _status_text(player)
	_status_e.text = _status_text(enemy)
	# Theme overrides invalidate layout: only swap the style when it changes.
	var can_jump := player.sp >= Wizard.JUMP_COST
	if can_jump != _jump_ready or not _jump_init:
		_jump_init = true
		_jump_ready = can_jump
		_jump_tile.add_theme_stylebox_override("panel", _jump_on_style if can_jump else _jump_off_style)

func _status_text(w: Wizard) -> String:
	var parts: PackedStringArray = []
	if w.burn_time > 0.0:
		parts.append("Burning")
	if w.slow_time > 0.0 or w.area_slow < 0.99:
		parts.append("Slowed")
	if w.stun_time > 0.0:
		parts.append("Stunned")
	if w.haste_time > 0.0:
		parts.append("Hasted")
	if w.shield > 0.0:
		parts.append("Shielded")
	if w.heal_time > 0.0:
		parts.append("Regenerating")
	return "  ·  ".join(parts)

func _slot_style(element: String) -> StyleBoxFlat:
	if _slot_styles.has(element):
		return _slot_styles[element]
	var style: StyleBoxFlat
	if element.is_empty():
		style = UIKit.panel_style(Color(0.1, 0.08, 0.16, 0.6), 26, Color(1, 1, 1, 0.18), 2)
	else:
		var c: Color = SpellBook.ELEMENT_INFO[element]["color"]
		style = UIKit.panel_style(c, 26, c.lightened(0.5), 3)
		style.shadow_color = Color(c, 0.6)
		style.shadow_size = 10
	_slot_styles[element] = style
	return style

func _update_composer() -> void:
	# Styles are cached and only re-applied when a slot's element changes;
	# rebuilding StyleBoxes and theme overrides every frame forced the whole
	# HUD to re-layout constantly.
	for i in _slots.size():
		var element: String = player.elements[i] if i < player.elements.size() else ""
		if _slot_state[i] != element:
			_slot_state[i] = element
			_slots[i].add_theme_stylebox_override("panel", _slot_style(element))
	var key := player.pending_spell()
	if key.is_empty():
		_spell_name.text = ""
		_spell_info.text = "%s cast  ·  press keys together for combos" % " ".join(SpellBook.ELEMENTS.map(func(e: String) -> String: return Game.element_key(e)))
		return
	var spell := SpellBook.get_spell(key)
	var cd := player.cooldown_left(key)
	var ok := player.mana >= float(spell["mana"]) and cd <= 0.0
	_spell_name.text = String(spell["name"])
	var name_color: Color = (spell["color"] as Color).lightened(0.3) if ok else Color(0.6, 0.55, 0.6)
	if name_color != _spell_name_color:
		_spell_name_color = name_color
		_spell_name.add_theme_color_override("font_color", name_color)
	var info := "%d mana" % int(spell["mana"])
	if cd > 0.0:
		info += "  ·  ready in %.1fs" % cd
	elif player.mana < float(spell["mana"]):
		info += "  ·  not enough mana"
	_spell_info.text = info

func _update_cooldowns() -> void:
	var active: Array = []
	for k in player.cooldowns:
		if player.cooldowns[k] > 0.05:
			active.append(k)
	active.sort_custom(func(a, b) -> bool: return player.cooldowns[a] < player.cooldowns[b])
	while _cooldown_box.get_child_count() < active.size():
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_END
		row.add_theme_constant_override("separation", 8)
		_cooldown_box.add_child(row)
	for i in _cooldown_box.get_child_count():
		var row := _cooldown_box.get_child(i) as HBoxContainer
		if i >= active.size():
			row.visible = false
			continue
		row.visible = true
		var k: String = active[i]
		if row.get_meta("key", "") != k:
			row.set_meta("key", k)
			for c in row.get_children():
				c.queue_free()
			var l := UIKit.label("", 15, Color(0.18, 0.18, 0.25), 700)
			l.add_theme_constant_override("outline_size", 0)
			l.name = "L"
			row.add_child(l)
			row.add_child(UIKit.combo_row(k, 16))
		var lbl := row.get_node_or_null("L") as Label
		if lbl:
			lbl.text = "%s  %.1f" % [SpellBook.get_spell(k)["name"], player.cooldowns[k]]

func _update_enemy_queue() -> void:
	var sig := ",".join(enemy.elements)
	if _e_queue.get_meta("sig", "-") == sig:
		return
	_e_queue.set_meta("sig", sig)
	for c in _e_queue.get_children():
		c.queue_free()
	for e in enemy.elements:
		_e_queue.add_child(UIKit.element_chip(e, 20, false))

extends Node3D

var _cam: Camera3D
var _ui: Control
var _main_box: VBoxContainer
var _overlay: Control
var _diff_buttons: Array[Button] = []
var _diff_desc: Label
var _hero: Wizard
var _time := 0.0

const DIFF_DESC := [
	"A forgiving rival. Learn the elements and find your rhythm.",
	"A tactical rival. Expect combinations, cover and counterplay.",
	"A relentless rival. Precise aim and powerful combinations.",
]

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	add_child(Arena.new())
	_hero = Wizard.new()
	_hero.robe_color = Game.robe_tint()
	add_child(_hero)
	_hero.global_position = Vector3(3.4, 0, 1.0)
	_hero.rotation.y = PI + 0.25
	_hero.face_aim = false
	_hero.set_physics_process(false)
	_cam = Camera3D.new()
	_cam.fov = 48
	add_child(_cam)
	_cam.current = true
	_build_ui()
	Game.presentation_changed.connect(_refresh_hero)

func _refresh_hero() -> void:
	if _hero.robe_color == Game.robe_tint():
		return
	var old_position := _hero.global_position
	_hero.queue_free()
	_hero = Wizard.new()
	_hero.robe_color = Game.robe_tint()
	add_child(_hero)
	_hero.global_position = old_position
	_hero.rotation.y = PI + 0.25
	_hero.face_aim = false
	_hero.set_physics_process(false)

func _process(delta: float) -> void:
	_time += delta
	_cam.position = Vector3(1.0 + sin(_time * 0.09) * 0.25, 2.9, 8.5)
	_cam.look_at(Vector3(1.2, 1.5, 0.0))

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.theme = UIKit.theme()
	layer.add_child(_ui)
	var gradient := Gradient.new()
	gradient.set_color(0, Color("#08141f"))
	gradient.set_color(1, Color(0.02, 0.04, 0.07, 0))
	gradient.add_point(0.42, Color(0.025, 0.055, 0.08, 0.94))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2(1, 0.1)
	var shade := TextureRect.new()
	shade.texture = texture
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 56)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	_ui.add_child(margin)
	var frame := VBoxContainer.new()
	frame.add_theme_constant_override("separation", 18)
	margin.add_child(frame)
	var header := HBoxContainer.new()
	header.add_child(UIKit.label("E / D", 20, UIKit.ACCENT, 800))
	var edition := UIKit.label("THE CONFLUENCE  /  ELEMENTAL ARENA", 13, UIKit.MUTED, 600)
	edition.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edition.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(edition)
	frame.add_child(header)
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(content)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 540
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	_main_box = VBoxContainer.new()
	_main_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_main_box.add_theme_constant_override("separation", 12)
	scroll.add_child(_main_box)
	_main_box.add_child(UIKit.label("FIVE ELEMENTS. ONE VICTOR.", 14, UIKit.ACCENT, 700))
	_main_box.add_child(UIKit.label("ELEMENTAL\nDUEL", 68, UIKit.TEXT, 800))
	var desc := UIKit.label("Read your rival. Weave your spell.\nCommand the arena.", 19, UIKit.MUTED)
	_main_box.add_child(desc)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 10)
	for element in SpellBook.ELEMENTS:
		chips.add_child(UIKit.element_chip(element, 30, false))
	_main_box.add_child(chips)
	_main_box.add_child(UIKit.label("CHOOSE YOUR RIVAL", 12, UIKit.ACCENT, 700))
	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 8)
	_main_box.add_child(diff_row)
	for i in 3:
		var b := UIKit.button(Game.difficulty_name(i), _select_difficulty.bind(i))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 16)
		diff_row.add_child(b)
		_diff_buttons.append(b)
	_diff_desc = UIKit.label("", 14, UIKit.MUTED)
	_diff_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_diff_desc.custom_minimum_size = Vector2(0, 40)
	_main_box.add_child(_diff_desc)
	_select_difficulty(Game.difficulty)
	_main_box.add_child(UIKit.primary_button("ENTER THE ARENA", func() -> void:
		Game.save_settings()
		Game.start_match()))
	_main_box.add_child(UIKit.button("Play online", func() -> void: _show_overlay(OnlinePanel.new())))
	var links := HBoxContainer.new()
	links.add_theme_constant_override("separation", 8)
	links.add_child(UIKit.button("Spellbook", func() -> void: _show_overlay(SpellbookPanel.new())))
	links.add_child(UIKit.button("Controls", func() -> void: _show_overlay(ControlsPanel.new())))
	links.add_child(UIKit.button("Guide", func() -> void: _show_overlay(_controls_panel())))
	for button in links.get_children():
		button.add_theme_font_size_override("font_size", 15)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_box.add_child(links)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	frame.add_child(footer)
	footer.add_child(UIKit.button("Customize", func() -> void: _show_overlay(load("res://scripts/ui/settings_panel.gd").new())))
	footer.add_child(UIKit.button("Exit", func() -> void: get_tree().quit()))
	var credit := UIKit.label("28 SPELLS   /   FIRST TO TWO\nKayKit environment · Kenney audio · Inter", 12, UIKit.MUTED)
	credit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(credit)

func _select_difficulty(i: int) -> void:
	Game.difficulty = i
	for j in _diff_buttons.size():
		_diff_buttons[j].button_pressed = j == i
	_diff_desc.text = DIFF_DESC[i]

func _show_overlay(content: Control) -> void:
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.03, 0.045, 0.94)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 32
	scroll.offset_right = -32
	scroll.offset_top = 24
	scroll.offset_bottom = -24
	_overlay.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	box.add_child(content)
	var close := UIKit.button("Back", _close_overlay)
	box.add_child(close)
	close.grab_focus()

func _close_overlay() -> void:
	if is_instance_valid(_overlay):
		_overlay.queue_free()
		_overlay = null
	Game.save_settings()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_close_overlay()

func _controls_panel() -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(760, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	p.add_child(vb)
	var t := UIKit.label("HOW TO PLAY", 30, UIKit.TEXT, 800)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var move := "  ".join([Game.key_name("move_forward"), Game.key_name("move_left"), Game.key_name("move_back"), Game.key_name("move_right")])
	var elems := "  ".join(SpellBook.ELEMENTS.map(func(e: String) -> String: return Game.element_key(e)))
	var rows := [
		[move, "Move (camera-relative)"],
		["Mouse", "Aim — spells fly to the crosshair"],
		[elems, "Cast Fire · Water · Earth · Wind · Lightning toward the crosshair"],
		["Quick 2-3 keys", "Combine elements into a combo spell (order doesn't matter)"],
		["Left Click", "Fire the combo immediately (optional)"],
		[Game.key_name("spatial_jump"), "Spatial Jump — teleport toward move/camera direction (35 SP)"],
		[Game.key_name("spellbook") + " (hold)", "Spellbook"],
		["Esc", "Pause / settings"],
	]
	for r in rows:
		var h := HBoxContainer.new()
		var k := UIKit.label(r[0], 18, Color(1.0, 0.85, 0.5), 700)
		k.custom_minimum_size = Vector2(220, 0)
		h.add_child(k)
		h.add_child(UIKit.label(r[1], 18))
		vb.add_child(h)
	var tips := UIKit.label("Tips: Earth walls block projectiles and bolts. Wind deflects incoming spells back at the caster. Watch the orbs over your rival's head to read their next combo. Lightning strikes show a warning ring — keep moving. Win 2 rounds to take the duel.", 15, UIKit.MUTED)
	tips.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(tips)
	return p

extends Node3D
## Title screen: slowly orbiting camera over the arena, difficulty select,
## spellbook, controls and settings.

var _cam: Camera3D
var _angle := 0.0
var _ui: Control
var _main_box: VBoxContainer
var _overlay: Control
var _diff_buttons: Array[Button] = []
var _diff_desc: Label

const DIFF_DESC := [
	"Slow reactions, mostly single elements. Great for learning combos.",
	"Leads its shots, dodges sometimes, weaves double combos.",
	"Fast weaving, sharp aim, frequent dodges and triple combos.",
]

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var arena := Arena.new()
	add_child(arena)
	_spawn_display_wizard(Vector3(-1.6, 0, 1.0), Color(0.25, 0.5, 1.0), "res://assets/models/characters/player_blue.glb", 0.5)
	_spawn_display_wizard(Vector3(1.6, 0, -1.0), Color(0.95, 0.35, 0.25), "res://assets/models/characters/bot_red.glb", PI + 0.5)
	_cam = Camera3D.new()
	_cam.fov = 60
	add_child(_cam)
	_cam.current = true
	_build_ui()

func _spawn_display_wizard(pos: Vector3, color: Color, model: String, yaw: float) -> void:
	var w := Wizard.new()
	w.robe_color = color
	w.model_path = model
	add_child(w)
	w.global_position = pos
	w.rotation.y = yaw
	w.face_aim = false
	w.set_physics_process(false)

func _process(delta: float) -> void:
	_angle += delta * 0.08
	_cam.position = Vector3(sin(_angle) * 9.0, 3.2, cos(_angle) * 9.0)
	_cam.look_at(Vector3(0, 1.3, 0))

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.theme = UIKit.theme()
	layer.add_child(_ui)
	var grad := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.03, 0.02, 0.08, 0.92))
	g.set_color(1, Color(0.03, 0.02, 0.08, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	grad.texture = gt
	grad.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	grad.offset_right = 760
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(grad)

	_main_box = VBoxContainer.new()
	_main_box.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_main_box.offset_left = 90
	_main_box.offset_top = -300
	_main_box.custom_minimum_size = Vector2(440, 0)
	_main_box.add_theme_constant_override("separation", 12)
	_ui.add_child(_main_box)
	var title := UIKit.label("ELEMENTAL", 76, Color(1.0, 0.85, 0.5), 900)
	title.add_theme_constant_override("outline_size", 12)
	title.add_theme_color_override("font_outline_color", Color(0.25, 0.08, 0.3))
	_main_box.add_child(title)
	var title2 := UIKit.label("DUEL", 76, Color(0.7, 0.6, 1.0), 900)
	title2.add_theme_constant_override("outline_size", 12)
	title2.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.3))
	_main_box.add_child(title2)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	for e in SpellBook.ELEMENTS:
		chips.add_child(UIKit.element_chip(e, 30, false))
	_main_box.add_child(chips)
	_main_box.add_child(UIKit.label("Weave five elements into %d spells. Outwit a rival wizard." % SpellBook.SPELLS.size(), 17, UIKit.MUTED))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	_main_box.add_child(spacer)

	_main_box.add_child(UIKit.label("RIVAL", 14, UIKit.MUTED, 700))
	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 8)
	_main_box.add_child(diff_row)
	for i in 3:
		var b := UIKit.button(Game.difficulty_name(i), _select_difficulty.bind(i))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		diff_row.add_child(b)
		_diff_buttons.append(b)
	_diff_desc = UIKit.label("", 15, UIKit.MUTED)
	_diff_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_diff_desc.custom_minimum_size = Vector2(440, 44)
	_main_box.add_child(_diff_desc)
	_select_difficulty(Game.difficulty, false)

	var play := UIKit.button("Start Duel", func() -> void:
		Game.save_settings()
		Game.start_match())
	play.add_theme_font_size_override("font_size", 26)
	play.custom_minimum_size = Vector2(0, 62)
	_main_box.add_child(play)
	var online := UIKit.button("Play Online", func() -> void: _show_overlay(OnlinePanel.new()))
	online.add_theme_font_size_override("font_size", 22)
	_main_box.add_child(online)
	_main_box.add_child(UIKit.button("Spellbook", func() -> void: _show_overlay(SpellbookPanel.new())))
	_main_box.add_child(UIKit.button("Controls", func() -> void: _show_overlay(ControlsPanel.new())))
	_main_box.add_child(UIKit.button("How to Play", func() -> void: _show_overlay(_controls_panel())))
	_main_box.add_child(UIKit.button("Quit", func() -> void: get_tree().quit()))

	var credit := UIKit.label("Characters: Creative Characters FREE · Sounds: Kenney (CC0) · Inter font (OFL)", 13, Color(0.2, 0.2, 0.26, 0.6))
	credit.add_theme_constant_override("outline_size", 0)
	credit.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	credit.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	credit.grow_vertical = Control.GROW_DIRECTION_BEGIN
	credit.offset_right = -20
	credit.offset_bottom = -14
	_ui.add_child(credit)

func _select_difficulty(i: int, click := true) -> void:
	Game.difficulty = i
	for j in _diff_buttons.size():
		_diff_buttons[j].button_pressed = j == i
	_diff_desc.text = DIFF_DESC[i]

func _show_overlay(content: Control) -> void:
	if _overlay:
		_overlay.queue_free()
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.05, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	center.add_child(vb)
	vb.add_child(content)
	var close := UIKit.button("Back", func() -> void:
		_overlay.queue_free()
		_overlay = null)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.custom_minimum_size = Vector2(200, 0)
	vb.add_child(close)
	_main_box.visible = false
	_overlay.tree_exited.connect(func() -> void: _main_box.visible = true)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and _overlay:
		_overlay.queue_free()
		_overlay = null

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

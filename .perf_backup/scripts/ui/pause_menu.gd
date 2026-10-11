class_name PauseMenu
extends CanvasLayer
## Pause overlay with settings; also the end-of-match and disconnect screen.
## Online, opening it does not freeze the match.

signal resume_requested
signal restart_requested

var _panel: PanelContainer
var _title: Label
var _subtitle: Label
var _note: Label
var _resume_btn: Button
var _restart_btn: Button
var _menu_btn: Button
var _settings: VBoxContainer

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UIKit.theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.06, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_panel.add_child(vb)
	_title = UIKit.label("PAUSED", 44, UIKit.TEXT, 900)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title)
	_subtitle = UIKit.label("", 18, UIKit.MUTED)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.custom_minimum_size = Vector2(420, 0)
	vb.add_child(_subtitle)
	_note = UIKit.label("", 15, Color(1.0, 0.8, 0.5))
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(420, 0)
	vb.add_child(_note)
	_resume_btn = UIKit.button("Resume", func() -> void: resume_requested.emit())
	vb.add_child(_resume_btn)
	_restart_btn = UIKit.button("Restart Match", func() -> void: restart_requested.emit())
	vb.add_child(_restart_btn)
	_settings = VBoxContainer.new()
	_settings.add_theme_constant_override("separation", 6)
	vb.add_child(_settings)
	_settings.add_child(UIKit.label("Mouse sensitivity", 15, UIKit.MUTED))
	var sens := HSlider.new()
	sens.min_value = 0.05
	sens.max_value = 0.8
	sens.step = 0.01
	sens.value = Game.mouse_sensitivity
	sens.custom_minimum_size = Vector2(0, 24)
	sens.value_changed.connect(func(v: float) -> void:
		Game.mouse_sensitivity = v
		Game.save_settings())
	_settings.add_child(sens)
	_settings.add_child(UIKit.label("Volume", 15, UIKit.MUTED))
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.01
	vol.value = Game.master_volume
	vol.custom_minimum_size = Vector2(0, 24)
	vol.value_changed.connect(func(v: float) -> void:
		Game.master_volume = v
		Game.apply_volume()
		Game.save_settings())
	_settings.add_child(vol)
	_menu_btn = UIKit.button("Main Menu", func() -> void: Game.go_to_menu())
	vb.add_child(_menu_btn)
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	# Offline the duel scene is paused while this is open, so Esc-to-resume
	# lives here.
	if visible and _resume_btn.visible and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		resume_requested.emit()

func show_pause(online: bool = false) -> void:
	_title.remove_theme_color_override("font_color")
	_title.text = "PAUSED" if not online else "MENU"
	_subtitle.text = ("Difficulty: " + Game.difficulty_name()) if not online else "Online match vs %s" % Net.opp_name
	_note.text = "" if not online else "The match keeps running while this menu is open."
	_resume_btn.visible = true
	_restart_btn.visible = not online
	_menu_btn.text = "Main Menu" if not online else "Leave Match"
	_settings.visible = true
	visible = true

func show_result(won: bool, score: String, online: bool = false, is_host: bool = false) -> void:
	_title.text = "VICTORY" if won else "DEFEAT"
	_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35) if won else Color(1.0, 0.45, 0.45))
	if online:
		_subtitle.text = score + "   ·   vs " + Net.opp_name
		_note.text = "" if is_host else "Waiting for the host to start a rematch…"
		_restart_btn.text = "Rematch"
		_restart_btn.visible = is_host
		_menu_btn.text = "Leave"
	else:
		_subtitle.text = score + "   ·   " + Game.difficulty_name()
		_note.text = ""
		_restart_btn.text = "Restart Match"
		_restart_btn.visible = true
		_menu_btn.text = "Main Menu"
	_resume_btn.visible = false
	_settings.visible = false
	visible = true

func show_message(title: String, text: String) -> void:
	_title.text = title
	_title.add_theme_color_override("font_color", Color(1.0, 0.6, 0.45))
	_subtitle.text = text
	_note.text = ""
	_resume_btn.visible = false
	_restart_btn.visible = false
	_settings.visible = false
	_menu_btn.text = "Main Menu"
	visible = true

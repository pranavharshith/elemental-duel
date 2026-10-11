class_name ControlsPanel
extends PanelContainer
## Key bindings screen (main menu "Controls"). Click a key, press the new key.
## Esc cancels. Binding a key that's already used swaps the two actions.

var _buttons: Dictionary = {}   # action -> Button
var _listening := ""
var _hint: Label

func _ready() -> void:
	theme = UIKit.theme()
	add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.06, 0.05, 0.11, 0.94), 16, Color(0.5, 0.4, 0.85, 0.7)))
	custom_minimum_size = Vector2(820, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	add_child(vb)
	var title := UIKit.label("CONTROLS", 30, UIKit.TEXT, 800)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	_hint = UIKit.label("", 15, UIKit.MUTED)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_hint)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 8)
	vb.add_child(grid)
	for entry in Game.BINDABLE:
		grid.add_child(_row(entry[0], entry[1]))
	# Fixed (not rebindable) inputs, shown for completeness.
	grid.add_child(_fixed_row("Aim", "Mouse"))
	grid.add_child(_fixed_row("Fire combo now", "Left Click"))
	grid.add_child(_fixed_row("Pause / menu", "Esc"))

	var tip := UIKit.label("Press 2 or 3 element keys quickly to combine them into a combo spell.", 14, UIKit.MUTED)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tip)
	var reset := UIKit.button("Reset to Defaults", func() -> void:
		_listening = ""
		Game.reset_bindings())
	reset.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(reset)

	Game.bindings_changed.connect(_refresh)
	_refresh()

func _row(action: String, label_text: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var element := action.trim_prefix("elem_")
	if action.begins_with("elem_") and SpellBook.ELEMENT_INFO.has(element):
		var chip := UIKit.element_chip(element, 22, false)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER   # stay round
		h.add_child(chip)
	var l := UIKit.label(label_text, 18, UIKit.TEXT, 600)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var b := Button.new()
	b.custom_minimum_size = Vector2(150, 40)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void:
		Sfx.play("click", -6.0)
		_listening = action
		_refresh())
	h.add_child(b)
	_buttons[action] = b
	h.custom_minimum_size = Vector2(380, 0)
	return h

func _fixed_row(label_text: String, key_text: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var l := UIKit.label(label_text, 18, UIKit.MUTED, 600)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var k := UIKit.label(key_text, 18, UIKit.MUTED, 700)
	k.custom_minimum_size = Vector2(150, 40)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(k)
	h.custom_minimum_size = Vector2(380, 0)
	return h

func _refresh() -> void:
	for action in _buttons:
		var b: Button = _buttons[action]
		b.text = "Press a key…" if action == _listening else Game.key_name(action)
		b.modulate = Color(1.0, 0.85, 0.45) if action == _listening else Color.WHITE
	_hint.text = "Press the new key, or Esc to cancel." if not _listening.is_empty() else "Click a key to change it."

## Runs before the menu's Esc-to-close handler, so capturing a key never
## closes the popup.
func _input(event: InputEvent) -> void:
	if _listening.is_empty() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	var k := event as InputEventKey
	var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	var action := _listening
	_listening = ""
	if code != KEY_ESCAPE:
		Game.rebind(action, code)
		Sfx.play("click", -6.0)
	_refresh()

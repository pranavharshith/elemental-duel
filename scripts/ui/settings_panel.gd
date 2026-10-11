extends PanelContainer

func _ready() -> void:
	custom_minimum_size = Vector2(650, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	box.add_child(UIKit.label("MAKE IT YOURS", 30, UIKit.TEXT, 800))
	box.add_child(UIKit.label("Display changes apply now. Robe color applies to your next duel.", 15, UIKit.MUTED))
	_choice(box, "Graphics", ["Performance", "Balanced", "High"], Game.graphics_quality, func(i: int) -> void: Game.graphics_quality = i)
	_check(box, "Adaptive 3D resolution", Game.adaptive_resolution, func(v: bool) -> void: Game.adaptive_resolution = v)
	_slider(box, "Field of view", 60, 95, 1, Game.camera_fov, func(v: float) -> void: Game.camera_fov = v)
	_slider(box, "Screen shake", 0, 1, 0.05, Game.screen_shake, func(v: float) -> void: Game.screen_shake = v)
	_slider(box, "Mouse sensitivity", 0.05, 0.8, 0.01, Game.mouse_sensitivity, func(v: float) -> void: Game.mouse_sensitivity = v)
	_slider(box, "Master volume", 0, 1, 0.05, Game.master_volume, func(v: float) -> void:
		Game.master_volume = v
		Game.apply_volume())
	_choice(box, "Crosshair", ["Cross", "Dot", "Ring"], Game.crosshair_style, func(i: int) -> void: Game.crosshair_style = i)
	_choice(box, "Robe color · solo play", ["Sapphire", "Jade", "Amethyst", "Amber"], Game.robe_index, func(i: int) -> void: Game.robe_index = i)
	_check(box, "Show frame rate", Game.show_fps, func(v: bool) -> void: Game.show_fps = v)
	var note := UIKit.label("Performance disables shadows and spell lights. Balanced uses 2× anti-aliasing; High uses 4×. The HUD always stays sharp.", 14, UIKit.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)

func _changed() -> void:
	Game.apply_presentation()
	Game.save_settings()

func _row(box: VBoxContainer, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var label := UIKit.label(title, 16)
	label.custom_minimum_size.x = 220
	row.add_child(label)
	box.add_child(row)
	return row

func _choice(box: VBoxContainer, title: String, options: Array, selected: int, cb: Callable) -> void:
	var row := _row(box, title)
	var menu := OptionButton.new()
	for option in options:
		menu.add_item(option)
	menu.selected = selected
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.item_selected.connect(func(i: int) -> void:
		cb.call(i)
		_changed())
	row.add_child(menu)

func _check(box: VBoxContainer, title: String, selected: bool, cb: Callable) -> void:
	var row := _row(box, title)
	var check := CheckButton.new()
	check.button_pressed = selected
	check.text = "On" if selected else "Off"
	check.toggled.connect(func(value: bool) -> void:
		check.text = "On" if value else "Off"
		cb.call(value)
		_changed())
	row.add_child(check)

func _slider(box: VBoxContainer, title: String, low: float, high: float, step: float, value: float, cb: Callable) -> void:
	var row := _row(box, title)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(200, 30)
	row.add_child(slider)
	var readout := UIKit.label("%.2f" % value, 15, UIKit.ACCENT)
	readout.custom_minimum_size.x = 52
	row.add_child(readout)
	slider.value_changed.connect(func(v: float) -> void:
		readout.text = "%.2f" % v
		cb.call(v)
		Game.apply_presentation())
	slider.drag_ended.connect(func(_changed_value: bool) -> void: Game.save_settings())
	slider.focus_exited.connect(Game.save_settings)

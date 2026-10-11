class_name UIKit
extends RefCounted
## Shared UI theme and widget helpers.

const FONT_PATH := "res://assets/fonts/Inter.woff2"
const BG := Color(0.025, 0.055, 0.078, 0.95)
const ACCENT := Color(0.83, 0.69, 0.43)
const TEXT := Color(0.91, 0.94, 0.95)
const MUTED := Color(0.58, 0.69, 0.74)

static var _theme: Theme
static var _fonts: Dictionary = {}

static func font(weight: int = 500) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var base: Font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else ThemeDB.fallback_font
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {"wght": weight}
	_fonts[weight] = fv
	return fv

static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font(500)
	t.default_font_size = 18
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.6))
	t.set_constant("outline_size", "Label", 0)
	# Buttons
	var normal := panel_style(Color(0.055, 0.105, 0.14, 0.96), 4, Color(0.25, 0.36, 0.40, 0.7))
	var hover := panel_style(Color(0.10, 0.18, 0.22, 1.0), 4, ACCENT)
	var pressed := panel_style(Color(0.23, 0.22, 0.16, 1.0), 4, ACCENT.lightened(0.3))
	for s in [normal, hover, pressed]:
		s.content_margin_left = 22
		s.content_margin_right = 22
		s.content_margin_top = 10
		s.content_margin_bottom = 10
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", hover)
	t.set_stylebox("disabled", "Button", normal)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_font_size("font_size", "Button", 20)
	t.set_stylebox("panel", "PanelContainer", panel_style(BG, 6, Color(0.29, 0.40, 0.44, 0.6), 1))
	# Sliders
	var grab := StyleBoxFlat.new()
	grab.bg_color = ACCENT
	t.set_stylebox("slider", "HSlider", panel_style(Color(0.1, 0.17, 0.20), 4, Color(0, 0, 0, 0), 0))
	t.set_stylebox("grabber_area", "HSlider", panel_style(ACCENT.darkened(0.2), 4, Color(0, 0, 0, 0), 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", panel_style(ACCENT, 4, Color(0, 0, 0, 0), 0))
	_theme = t
	return t

static func panel_style(bg: Color, radius: int = 12, border: Color = Color(0, 0, 0, 0), border_w: int = 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(border_w)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.anti_aliasing = true
	return s

static func label(text: String, size: int = 18, color: Color = TEXT, weight: int = 500) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if weight != 500:
		l.add_theme_font_override("font", font(weight))
	return l

static func bar(fill: Color, height: int = 18, radius: int = 6) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, height)
	b.max_value = 100
	b.value = 100
	b.add_theme_stylebox_override("background", panel_style(Color(0.05, 0.04, 0.08, 0.85), radius, Color(1, 1, 1, 0.12), 1))
	var f := panel_style(fill, radius, Color(0, 0, 0, 0), 0)
	f.content_margin_left = 0
	f.content_margin_right = 0
	b.add_theme_stylebox_override("fill", f)
	return b

static func button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func() -> void:
		Sfx.play("click", -6.0)
		cb.call())
	b.mouse_entered.connect(func() -> void: Sfx.play("hover", -16.0))
	return b

## Elements drawn as coloured round chips with their key letter.
static func element_chip(element: String, size: float = 44.0, show_key: bool = true) -> PanelContainer:
	var info: Dictionary = SpellBook.ELEMENT_INFO[element]
	var p := PanelContainer.new()
	var c: Color = info["color"]
	var s := panel_style(c.darkened(0.15), 6, c.lightened(0.45), 2)
	s.content_margin_left = 0
	s.content_margin_right = 0
	s.content_margin_top = 0
	s.content_margin_bottom = 0
	s.shadow_color = Color(c, 0.45)
	s.shadow_size = 0
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size = Vector2(size, size)
	if show_key:
		var key_text := Game.element_key(element)
		var fs := int(size * 0.42) if key_text.length() <= 2 else int(size * 0.26)
		var l := label(key_text, fs, Color(0.08, 0.05, 0.1), 800)
		l.add_theme_constant_override("outline_size", 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		p.add_child(l)
	else:
		var icon := TextureRect.new()
		icon.texture = load("res://assets/ui/" + element + ".svg")
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(size * 0.65, size * 0.65)
		icon.modulate = Color("#14232b")
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(icon)
	return p

static func combo_row(key: String, chip: float = 26.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for e in SpellBook.elements_of(key):
		row.add_child(element_chip(e, chip, false))
	return row

static func primary_button(text: String, cb: Callable) -> Button:
	var b := button(text, cb)
	b.add_theme_stylebox_override("normal", panel_style(ACCENT, 4, ACCENT.lightened(0.15), 1))
	b.add_theme_stylebox_override("hover", panel_style(ACCENT.lightened(0.15), 4, Color.WHITE, 1))
	b.add_theme_stylebox_override("pressed", panel_style(ACCENT.darkened(0.15), 4, ACCENT, 1))
	for slot in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(slot, Color("#15252d"))
	b.add_theme_font_override("font", font(800))
	b.custom_minimum_size.y = 58
	return b

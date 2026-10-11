class_name UIKit
extends RefCounted
## Shared UI theme and widget helpers.

const FONT_PATH := "res://assets/fonts/Inter.woff2"
const BG := Color(0.07, 0.06, 0.12, 0.82)
const ACCENT := Color(0.62, 0.48, 1.0)
const TEXT := Color(0.95, 0.93, 1.0)
const MUTED := Color(0.68, 0.65, 0.8)

static var _theme: Theme
static var _font: FontVariation

static func font(weight: int = 500) -> Font:
	var base: Font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else ThemeDB.fallback_font
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {"wght": weight}
	return fv

static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font(500)
	t.default_font_size = 18
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.6))
	t.set_constant("outline_size", "Label", 4)
	# Buttons
	var normal := panel_style(Color(0.16, 0.13, 0.27, 0.92), 10, Color(0.4, 0.33, 0.65, 0.8))
	var hover := panel_style(Color(0.26, 0.2, 0.44, 0.96), 10, ACCENT)
	var pressed := panel_style(Color(0.36, 0.28, 0.6, 1.0), 10, ACCENT.lightened(0.3))
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
	t.set_stylebox("panel", "PanelContainer", panel_style(BG, 14, Color(0.4, 0.33, 0.7, 0.6)))
	# Sliders
	var grab := StyleBoxFlat.new()
	grab.bg_color = ACCENT
	t.set_stylebox("slider", "HSlider", panel_style(Color(0.2, 0.18, 0.3), 4, Color(0, 0, 0, 0), 0))
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
	var s := panel_style(c.darkened(0.15), int(size * 0.5), c.lightened(0.45), 2)
	s.content_margin_left = 0
	s.content_margin_right = 0
	s.content_margin_top = 0
	s.content_margin_bottom = 0
	s.shadow_color = Color(c, 0.45)
	s.shadow_size = 6
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
	return p

static func combo_row(key: String, chip: float = 26.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for e in SpellBook.elements_of(key):
		row.add_child(element_chip(e, chip, false))
	return row

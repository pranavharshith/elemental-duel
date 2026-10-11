class_name SpellbookPanel
extends PanelContainer
## Lists every spell with its element recipe. Used in the menu and on Tab in-game.

func _ready() -> void:
	theme = UIKit.theme()
	add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.BG, 6, UIKit.ACCENT.darkened(0.45), 1))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	add_child(vb)
	var title := UIKit.label("SPELLBOOK", 30, UIKit.TEXT, 800)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var hint := UIKit.label("Each key casts its element. Press 2 or 3 keys in quick succession to combine them; the longest valid combo wins and order doesn't matter.", 15, UIKit.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1180, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	var sections := [[], [], []]
	for key in SpellBook.SPELLS:
		sections[SpellBook.elements_of(key).size() - 1].append(key)
	for keys in sections:
		for key in keys:
			grid.add_child(_card(key))

func _card(key: String) -> Control:
	var spell: Dictionary = SpellBook.SPELLS[key]
	var c: Color = spell["color"]
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(380, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UIKit.panel_style(Color("#132730"), 4, Color(c, 0.55), 1))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.add_child(UIKit.combo_row(key, 24))
	var name := UIKit.label(String(spell["name"]), 19, c.lightened(0.35), 700)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name)
	top.add_child(UIKit.label("%d MP  ·  %.1fs" % [int(spell["mana"]), float(spell["cooldown"])], 13, UIKit.MUTED))
	vb.add_child(top)
	var keys := ""
	for e in SpellBook.elements_of(key):
		keys += Game.element_key(e) + " "
	var d := UIKit.label("[%s]  %s" % [keys.strip_edges(), String(spell["desc"])], 14, UIKit.TEXT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(d)
	return card

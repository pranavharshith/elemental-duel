extends Node
## Global game state: settings, input map, and scene flow.

const SETTINGS_PATH := "user://settings.cfg"

enum Difficulty { EASY, NORMAL, HARD }

var difficulty: int = Difficulty.NORMAL
var mouse_sensitivity := 0.25
var master_volume := 0.8
var rounds_to_win := 2
var player_wins := 0
var ai_wins := 0

# Element keys. Physical keycodes keep the layout stable on non-QWERTY boards.
const INPUTS := {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"elem_fire": [KEY_Q],
	"elem_water": [KEY_E],
	"elem_earth": [KEY_R],
	"elem_wind": [KEY_F],
	"elem_lightning": [KEY_C],
	"spatial_jump": [KEY_SPACE],
	"spellbook": [KEY_TAB],
	"pause": [KEY_ESCAPE],
}

## Actions the player can rebind in the Controls screen, in display order.
## Esc (pause) stays fixed: it also cancels a rebind.
const BINDABLE := [
	["move_forward", "Move forward"],
	["move_back", "Move back"],
	["move_left", "Move left"],
	["move_right", "Move right"],
	["elem_fire", "Fire"],
	["elem_water", "Water"],
	["elem_earth", "Earth"],
	["elem_wind", "Wind"],
	["elem_lightning", "Lightning"],
	["spatial_jump", "Spatial Jump"],
	["spellbook", "Spellbook (hold)"],
]

signal bindings_changed

## action -> physical keycode currently bound.
var bindings: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Deliver every mouse motion event as it arrives (no per-frame merging):
	# recommended for precise mouse aim.
	Input.use_accumulated_input = false
	for action in INPUTS:
		bindings[action] = int(INPUTS[action][0])
	load_settings()
	_register_inputs()

func _register_inputs() -> void:
	for action in INPUTS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
	_apply_bindings()

func _apply_bindings() -> void:
	for action in bindings:
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				InputMap.action_erase_event(action, ev)
		var k := InputEventKey.new()
		k.physical_keycode = bindings[action]
		InputMap.action_add_event(action, k)

## Bind `action` to `keycode` (physical). If another action already uses that
## key, the two swap so nothing is ever left unbound or doubled.
func rebind(action: String, keycode: int) -> void:
	if not bindings.has(action) or action == "pause" or keycode == KEY_ESCAPE:
		return
	var old: int = bindings[action]
	for other in bindings:
		if other != action and int(bindings[other]) == keycode:
			bindings[other] = old
	bindings[action] = keycode
	_apply_bindings()
	save_settings()
	bindings_changed.emit()

func reset_bindings() -> void:
	for action in INPUTS:
		bindings[action] = int(INPUTS[action][0])
	_apply_bindings()
	save_settings()
	bindings_changed.emit()

## Label for the key bound to `action`, using the player's keyboard layout.
func key_name(action: String) -> String:
	if not bindings.has(action):
		return "?"
	var code: int = bindings[action]
	var shown := DisplayServer.keyboard_get_keycode_from_physical(code)
	var s := OS.get_keycode_string(shown if shown != KEY_NONE else code)
	return s if not s.is_empty() else OS.get_keycode_string(code)

## Key letter for an element ("fire" -> "Q").
func element_key(element: String) -> String:
	return key_name("elem_" + element)
	if not InputMap.has_action("cast"):
		InputMap.add_action("cast")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("cast", mb)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		difficulty = int(cfg.get_value("game", "difficulty", difficulty))
		mouse_sensitivity = float(cfg.get_value("input", "sensitivity", mouse_sensitivity))
		master_volume = float(cfg.get_value("audio", "volume", master_volume))
		for action in bindings:
			var code := int(cfg.get_value("keys", action, bindings[action]))
			if code > 0:
				bindings[action] = code
	apply_volume()

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)   # keep other sections (e.g. [online])
	for action in bindings:
		cfg.set_value("keys", action, bindings[action])
	cfg.set_value("game", "difficulty", difficulty)
	cfg.set_value("input", "sensitivity", mouse_sensitivity)
	cfg.set_value("audio", "volume", master_volume)
	cfg.save(SETTINGS_PATH)

func apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))

func difficulty_name(d: int = difficulty) -> String:
	return ["Apprentice", "Adept", "Archmage"][clampi(d, 0, 2)]

func start_match() -> void:
	player_wins = 0
	ai_wins = 0
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/duel.tscn")

func go_to_menu() -> void:
	Net.leave()   # leaving a match always ends the online session
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

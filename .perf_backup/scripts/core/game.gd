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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Deliver every mouse motion event as it arrives (no per-frame merging):
	# recommended for precise mouse aim.
	Input.use_accumulated_input = false
	_register_inputs()
	load_settings()

func _register_inputs() -> void:
	for action in INPUTS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for key in INPUTS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
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
	apply_volume()

func save_settings() -> void:
	var cfg := ConfigFile.new()
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

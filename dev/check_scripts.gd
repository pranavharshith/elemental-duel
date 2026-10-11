extends Node
## Loads every script so parse/compile errors surface in one headless run.
## Usage: godot --headless --path . res://dev/check.tscn

func _walk(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_walk(dir.path_join(sub), out)

func _ready() -> void:
	var files: Array = []
	_walk("res://scripts", files)
	var bad := 0
	for f in files:
		var s := load(f) as GDScript
		if s == null or not s.can_instantiate():
			print("FAILED: ", f)
			bad += 1
	print("checked %d scripts, %d failed" % [files.size(), bad])
	get_tree().quit(1 if bad > 0 else 0)

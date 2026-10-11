extends Node
## Dev probe: create a room on the configured server and print the result.
##   godot --headless --path . res://dev/probe.tscn [-- --server=ws://127.0.0.1:8787]

func _ready() -> void:
	print("server: ", Net.server_url())
	Net.host_room("Probe")
	var t := 0.0
	while Net.online and Net.room_code.is_empty() and t < 12.0:
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	print("after %.1fs  code='%s'  status=%s" % [t, Net.room_code, Net.last_status()])
	Net.leave()
	get_tree().quit()

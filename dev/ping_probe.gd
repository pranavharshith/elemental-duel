extends Node
## Dev probe: hosts a room on the configured server and prints the measured
## round-trip time to the relay for ~16 s.
##   godot --headless --path . res://dev/ping_probe.tscn [-- --server=ws://127.0.0.1:8787]
func _ready() -> void:
	print("server: ", Net.server_url())
	Net.host_room("Probe")
	var samples: Array[int] = []
	for i in 40:
		await get_tree().create_timer(0.4).timeout
		var r: int = Net.my_rtt()
		if r >= 0 and (samples.is_empty() or r != samples[-1]):
			samples.append(r)
	print("relay rtt samples (ms): ", samples)
	Net.leave()
	get_tree().quit()

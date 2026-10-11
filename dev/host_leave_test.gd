extends Node
## Dev: joiner in lobby, host closes the room -> joiner must get a clear message.
##   run with -- --role=host|join --server=ws://127.0.0.1:8787

const CODE_FILE := "user://host_leave_code.txt"

func _ready() -> void:
	var role := "host"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.substr(7)
	if role == "host":
		Net.host_room("H")
		while Net.room_code.is_empty():
			await get_tree().create_timer(0.05).timeout
		var f := FileAccess.open(CODE_FILE, FileAccess.WRITE)
		f.store_string(Net.room_code)
		f.close()
		while not Net.connected:
			await get_tree().create_timer(0.05).timeout
		await get_tree().create_timer(0.5).timeout
		print("[host] closing room")
		Net.leave()
		await get_tree().create_timer(0.5).timeout
	else:
		var code := ""
		while code.is_empty():
			await get_tree().create_timer(0.1).timeout
			if FileAccess.file_exists(CODE_FILE):
				code = FileAccess.get_file_as_string(CODE_FILE)
		var ended := [""]
		Net.session_ended.connect(func(r: String) -> void: ended[0] = r)
		Net.join_room(code, "J")
		var t := 0.0
		while ended[0].is_empty() and t < 15.0:
			await get_tree().create_timer(0.1).timeout
			t += 0.1
		print("[join] %s after %.1fs: %s" % ["PASS" if not ended[0].is_empty() else "FAIL", t, ended[0]])
	get_tree().quit()

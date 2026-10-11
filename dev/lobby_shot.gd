extends Node
## Dev: screenshot the Play Online lobby (join view, then hosting view).

var persistent := false

func _ready() -> void:
	if not persistent:
		var keeper: Node = (get_script() as GDScript).new()
		keeper.persistent = true
		get_tree().root.add_child.call_deferred(keeper)
		get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")
		return
	print("keeper ready")
	await get_tree().create_timer(1.0).timeout
	var menu := get_tree().current_scene
	print("menu: ", menu)
	menu._show_overlay(OnlinePanel.new())
	await get_tree().create_timer(0.8).timeout
	await _shot("lobby_join")
	Net.host_room("Pranav")
	await get_tree().create_timer(1.5).timeout
	await _shot("lobby_host")
	get_tree().quit()

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://dev/shots/%s.png" % n)

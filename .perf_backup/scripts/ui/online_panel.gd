class_name OnlinePanel
extends PanelContainer
## "Play Online" lobby, Smash Karts / skribbl style:
##   Create Room -> a 5-letter code appears -> send it to a friend.
##   Join Room   -> type the code -> you're in.

var _name_edit: LineEdit
var _code_edit: LineEdit
var _create_btn: Button
var _join_btn: Button
var _start_btn: Button
var _leave_btn: Button
var _status: Label
var _choose_box: VBoxContainer
var _room_box: VBoxContainer
var _code_label: Label
var _copy_btn: Button
var _players: Label

func _ready() -> void:
	theme = UIKit.theme()
	custom_minimum_size = Vector2(640, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	add_child(vb)
	var title := UIKit.label("PLAY ONLINE", 30, UIKit.TEXT, 800)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	var nl := UIKit.label("Your name", 16, UIKit.MUTED, 700)
	nl.custom_minimum_size = Vector2(110, 0)
	name_row.add_child(nl)
	_name_edit = LineEdit.new()
	_name_edit.text = Net.my_name
	_name_edit.max_length = 16
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_edit)
	vb.add_child(name_row)

	# ---- Not in a room: create or join
	_choose_box = VBoxContainer.new()
	_choose_box.add_theme_constant_override("separation", 12)
	vb.add_child(_choose_box)
	_create_btn = UIKit.button("Create Room", func() -> void:
		Net.host_room(_name_edit.text)
		_refresh())
	_create_btn.custom_minimum_size = Vector2(0, 56)
	_create_btn.add_theme_font_size_override("font_size", 24)
	_choose_box.add_child(_create_btn)
	var or_l := UIKit.label("— or join a friend's room —", 15, UIKit.MUTED)
	or_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_choose_box.add_child(or_l)
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 10)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "ROOM CODE"
	_code_edit.max_length = 7
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_edit.add_theme_font_size_override("font_size", 28)
	_code_edit.custom_minimum_size = Vector2(0, 56)
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_edit.text_changed.connect(func(t: String) -> void:
		var up := t.to_upper()
		if up != t:
			var caret := _code_edit.caret_column
			_code_edit.text = up
			_code_edit.caret_column = caret)
	_code_edit.text_submitted.connect(func(_t: String) -> void: _join())
	join_row.add_child(_code_edit)
	_join_btn = UIKit.button("Join", _join)
	_join_btn.custom_minimum_size = Vector2(140, 56)
	_join_btn.add_theme_font_size_override("font_size", 24)
	join_row.add_child(_join_btn)
	_choose_box.add_child(join_row)

	# ---- In a room
	_room_box = VBoxContainer.new()
	_room_box.add_theme_constant_override("separation", 8)
	vb.add_child(_room_box)
	var rl := UIKit.label("ROOM CODE", 15, UIKit.MUTED, 700)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_box.add_child(rl)
	_code_label = UIKit.label("·····", 72, Color(1.0, 0.85, 0.45), 900)
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_label.add_theme_constant_override("outline_size", 10)
	_code_label.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.25))
	_room_box.add_child(_code_label)
	_copy_btn = UIKit.button("Copy Code", func() -> void:
		DisplayServer.clipboard_set(Net.room_code)
		_on_status("Copied %s. Send it to your friend." % Net.room_code, Net.Kind.OK))
	_copy_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_copy_btn.custom_minimum_size = Vector2(220, 0)
	_room_box.add_child(_copy_btn)
	_players = UIKit.label("", 18, UIKit.TEXT, 600)
	_players.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_box.add_child(_players)

	# ---- Status + actions
	_status = UIKit.label("", 17, UIKit.TEXT, 600)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(600, 0)
	vb.add_child(_status)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_start_btn = UIKit.button("Start Duel", func() -> void: Net.start_match())
	_start_btn.custom_minimum_size = Vector2(240, 58)
	_start_btn.add_theme_font_size_override("font_size", 24)
	actions.add_child(_start_btn)
	_leave_btn = UIKit.button("Leave Room", func() -> void:
		Net.leave()
		_on_status("You left the room.", Net.Kind.INFO))
	actions.add_child(_leave_btn)
	vb.add_child(actions)

	Net.status.connect(_on_status)
	Net.peer_joined.connect(func(_n: String) -> void: _refresh())
	Net.session_ended.connect(func(_r: String) -> void: _refresh())
	Net.room_info_changed.connect(_refresh)
	var last := Net.last_status()
	if Net.online:
		_on_status(last[0], last[1])
	else:
		_on_status("Create a room and send the code to a friend, or type their code to join.", Net.Kind.INFO)

func _exit_tree() -> void:
	# Backing out of the lobby leaves the room, unless the duel is loading.
	if not Net.match_starting:
		Net.leave()

func _join() -> void:
	Net.join_room(_code_edit.text, _name_edit.text)
	_refresh()

func _on_status(text: String, kind: int) -> void:
	_status.text = text
	var c := UIKit.TEXT
	if kind == Net.Kind.OK:
		c = Color(0.5, 1.0, 0.6)
	elif kind == Net.Kind.ERROR:
		c = Color(1.0, 0.5, 0.45)
	_status.add_theme_color_override("font_color", c)
	_refresh()

func _refresh() -> void:
	if not is_inside_tree():
		return
	var in_room := Net.online and (Net.is_host or Net.connected)
	_choose_box.visible = not Net.online
	_name_edit.editable = not Net.online
	_join_btn.disabled = Net.online
	_create_btn.disabled = Net.online
	_room_box.visible = in_room
	_code_label.text = Net.room_code if not Net.room_code.is_empty() else "·····"
	_copy_btn.visible = Net.is_host and not Net.room_code.is_empty()
	if Net.is_host:
		_players.text = ("%s  vs  %s" % [Net.my_name, Net.opp_name]) if Net.connected else "Waiting for a friend to join…"
	else:
		_players.text = "%s  vs  %s" % [Net.opp_name, Net.my_name] if Net.connected else ""
	_start_btn.visible = Net.online and Net.is_host
	_start_btn.disabled = not Net.connected
	_leave_btn.visible = Net.online
	_leave_btn.text = "Close Room" if Net.is_host else ("Leave Room" if Net.connected else "Cancel")

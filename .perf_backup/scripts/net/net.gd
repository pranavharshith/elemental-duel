extends Node
## Online session manager (autoload "Net").
##
## Rooms work like Smash Karts / skribbl: the host presses "Create Room" and
## gets a 5-letter code; the friend types the code and joins. Both games
## connect OUT to the room server on the internet (relay/ folder, a Cloudflare
## Worker), so no port forwarding, LAN or VPN is needed.
##
## Model: the host is wizard 0 and is authoritative for HP, mana, SP,
## cooldowns, damage, statuses, teleport validation and round results. Each
## player simulates their own movement locally; the host clamps it. Spell
## casts are replicated as events with a shared random seed.
##
## Every RPC lives on this node (/root/Net exists on both machines at all
## times), so nothing breaks while one side is still loading the duel scene.

signal status(text: String, kind: int)
signal peer_joined(name: String)
signal session_ended(reason: String)
signal room_info_changed

enum Kind { INFO, OK, ERROR }

## Must match GAME_VERSION in relay/src/index.ts.
const VERSION := "elemental-duel-net-2"
## The deployed room server (relay/ folder, `npx wrangler deploy` prints the
## URL; use wss:// instead of https://). Both players' builds must use the
## same server. Override for testing with the command line
## (-- --server=ws://127.0.0.1:8787) or user://settings.cfg [online] server="...".
const DEFAULT_SERVER := "wss://elemental-duel-relay.qrpran.workers.dev"
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 5
const HELLO_TIMEOUT := 6.0

var online := false          # a session (hosting or joined) is open
var is_host := false
var connected := false       # opponent present and handshake complete
var match_starting := false  # scene change to the duel is in progress
var remote_ready := false    # opponent's duel scene has loaded
var my_name := ""
var opp_name := ""
var room_code := ""
var duel: Node = null        # the running online duel (registered by duel.gd)
## Opponent's latency to the room server, reported in their packets.
var remote_rtt := -1

var _peer: RelayPeer
var _client_id := 0
var _hello_t := -1.0
var _status_text := ""
var _status_kind := Kind.INFO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	my_name = "Wizard%d" % (randi() % 900 + 100)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		leave()

func last_status() -> Array:
	return [_status_text, _status_kind]

func _set_status(text: String, kind: int = Kind.INFO) -> void:
	_status_text = text
	_status_kind = kind
	status.emit(text, kind)

static func clean_name(n: String) -> String:
	var s := n.strip_edges().replace("\n", " ")
	if s.length() > 16:
		s = s.substr(0, 16)
	return s if not s.is_empty() else "Wizard"

## Normalises what the player typed ("abc 12", "ab-c12") to a room code, or "".
static func clean_code(text: String) -> String:
	var s := text.strip_edges().to_upper().replace(" ", "").replace("-", "")
	if s.length() != CODE_LENGTH:
		return ""
	for ch in s:
		if not CODE_ALPHABET.contains(ch):
			return ""
	return s

func server_url() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--server="):
			return a.substr(9).trim_suffix("/")
	var cfg := ConfigFile.new()
	if cfg.load(Game.SETTINGS_PATH) == OK:
		var s := String(cfg.get_value("online", "server", ""))
		if not s.is_empty():
			return s.trim_suffix("/")
	return DEFAULT_SERVER

# ============================================================== host / join
func _server_ready() -> bool:
	if server_url().contains("YOUR-SUBDOMAIN"):
		_set_status("The online server isn't set up yet: deploy relay/ and put its URL in DEFAULT_SERVER (scripts/net/net.gd).", Kind.ERROR)
		return false
	return true

func host_room(player_name: String) -> bool:
	if not _server_ready():
		return false
	leave()
	my_name = clean_name(player_name)
	_peer = RelayPeer.new()
	_peer.room_created.connect(_on_room_created)
	if _peer.host(server_url(), VERSION) != OK:
		_set_status(_peer.error_text, Kind.ERROR)
		_peer = null
		return false
	multiplayer.multiplayer_peer = _peer
	online = true
	is_host = true
	room_code = ""
	_set_status("Creating room…", Kind.INFO)
	room_info_changed.emit()
	return true

func join_room(code_text: String, player_name: String) -> bool:
	var code := clean_code(code_text)
	if code.is_empty():
		_set_status("Room codes are %d letters/numbers, like K7QXM." % CODE_LENGTH, Kind.ERROR)
		return false
	if not _server_ready():
		return false
	leave()
	my_name = clean_name(player_name)
	_peer = RelayPeer.new()
	if _peer.join(server_url(), code, VERSION) != OK:
		_set_status(_peer.error_text, Kind.ERROR)
		_peer = null
		return false
	multiplayer.multiplayer_peer = _peer
	online = true
	is_host = false
	room_code = code
	_set_status("Joining room %s…" % code, Kind.INFO)
	return true

## Close everything. Safe to call at any time.
func leave() -> void:
	var p := _peer
	_peer = null
	if multiplayer and multiplayer.multiplayer_peer == p and p != null:
		multiplayer.multiplayer_peer = null
	if p:
		p.close()
	online = false
	is_host = false
	connected = false
	match_starting = false
	remote_ready = false
	opp_name = ""
	room_code = ""
	remote_rtt = -1
	duel = null
	_client_id = 0
	_hello_t = -1.0

## Often called from inside multiplayer callbacks, where the peer must not be
## replaced synchronously, so the actual teardown is deferred.
func _end_session(reason: String) -> void:
	var was_online := online
	online = false
	connected = false
	_set_status(reason, Kind.ERROR)
	call_deferred("leave")
	if was_online:
		session_ended.emit(reason)

func _peer_error(fallback: String) -> String:
	if _peer and not _peer.error_text.is_empty():
		return _peer.error_text
	return fallback

## Round-trip time to the opponent in ms, through the server (-1 if unknown).
func ping_ms() -> int:
	if _peer == null or not connected or _peer.rtt_ms < 0:
		return -1
	return _peer.rtt_ms + maxi(remote_rtt, 0)

func my_rtt() -> int:
	return _peer.rtt_ms if _peer else -1

# ============================================================== events
func _on_room_created(code: String) -> void:
	room_code = code
	_set_status("Room ready! Send your friend the code.", Kind.OK)
	room_info_changed.emit()

func _on_peer_connected(id: int) -> void:
	if is_host:
		if connected:
			_peer.disconnect_peer(id)   # room is full
			return
		_client_id = id
		_hello_t = HELLO_TIMEOUT

func _on_peer_disconnected(id: int) -> void:
	if not is_host or id != _client_id:
		return
	var who := opp_name if not opp_name.is_empty() else "Your friend"
	var was_connected := connected
	connected = false
	remote_ready = false
	_client_id = 0
	opp_name = ""
	_hello_t = -1.0
	if duel != null or match_starting:
		_end_session("%s left the match." % who)
	elif was_connected:
		_set_status("%s left. Room %s is still open." % [who, room_code], Kind.ERROR)
		session_ended.emit("%s left." % who)
		room_info_changed.emit()

func _on_connected_to_server() -> void:
	_set_status("Found the room. Saying hello…", Kind.INFO)
	_s_hello.rpc_id(1, VERSION, my_name)

func _on_connection_failed() -> void:
	_end_session(_peer_error("Couldn't reach the game server. Check your internet connection."))

func _on_server_disconnected() -> void:
	_end_session(_peer_error("Lost connection to the game server." if is_host else "Lost connection to the host."))

func _process(delta: float) -> void:
	if _hello_t >= 0.0 and not connected:
		_hello_t -= delta
		if _hello_t < 0.0 and _client_id != 0 and _peer:
			_peer.disconnect_peer(_client_id)
			_client_id = 0

# ============================================================== handshake
@rpc("any_peer", "call_remote", "reliable")
func _s_hello(version: String, player_name: String) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if id != _client_id:
		return
	if version != VERSION:
		_c_rejected.rpc_id(id, "Version mismatch: the host runs a different build of the game.")
		_kick_later(id)
		return
	_hello_t = -1.0
	opp_name = clean_name(player_name)
	connected = true
	_c_welcome.rpc_id(id, my_name)
	_set_status("%s joined! Press Start Duel." % opp_name, Kind.OK)
	peer_joined.emit(opp_name)
	room_info_changed.emit()

@rpc("authority", "call_remote", "reliable")
func _c_welcome(host_name: String) -> void:
	opp_name = clean_name(host_name)
	connected = true
	_set_status("Joined %s's room. Waiting for the host to start…" % opp_name, Kind.OK)
	peer_joined.emit(opp_name)

@rpc("authority", "call_remote", "reliable")
func _c_rejected(reason: String) -> void:
	_end_session(reason)

func _kick_later(id: int) -> void:
	get_tree().create_timer(0.3).timeout.connect(func() -> void:
		if _peer:
			_peer.disconnect_peer(id))

# ============================================================== match flow
## Host: load the duel on both machines (also used for rematch).
func start_match() -> void:
	if not is_host or not connected:
		return
	_c_start_match.rpc()
	_load_duel()

@rpc("authority", "call_remote", "reliable")
func _c_start_match() -> void:
	_load_duel()

func _load_duel() -> void:
	match_starting = true
	remote_ready = false
	duel = null
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/duel.tscn")

func register_duel(d: Node) -> void:
	duel = d
	match_starting = false
	if not is_host:
		_s_duel_ready.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _s_duel_ready() -> void:
	if _from_client():
		remote_ready = true

## Host: wait until the joiner's duel scene is up (false on timeout/leave).
func wait_remote_ready(timeout: float) -> bool:
	var t := 0.0
	while not remote_ready and connected and t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()
	return remote_ready and connected

func _from_client() -> bool:
	return is_host and connected and multiplayer.get_remote_sender_id() == _client_id

func _duel_ok() -> bool:
	return duel != null and is_instance_valid(duel) and duel.is_inside_tree()

# ---- client -> host (validated by sender id) ----
func send_input(state: Dictionary) -> void:
	if connected and not is_host:
		_s_input.rpc_id(1, state)

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _s_input(state: Dictionary) -> void:
	if _from_client() and _duel_ok():
		duel.net_client_input(state)

func send_element(element: String, aim: Vector3) -> void:
	if connected and not is_host:
		_s_element.rpc_id(1, element, aim)

@rpc("any_peer", "call_remote", "reliable", 2)
func _s_element(element: String, aim: Vector3) -> void:
	if _from_client() and _duel_ok() and SpellBook.ELEMENTS.has(element):
		duel.net_client_element(element, aim)

func send_release(aim: Vector3) -> void:
	if connected and not is_host:
		_s_release.rpc_id(1, aim)

@rpc("any_peer", "call_remote", "reliable", 2)
func _s_release(aim: Vector3) -> void:
	if _from_client() and _duel_ok():
		duel.net_client_release(aim)

func send_jump(from: Vector3, dest: Vector3) -> void:
	if connected and not is_host:
		_s_jump.rpc_id(1, from, dest)

@rpc("any_peer", "call_remote", "reliable", 2)
func _s_jump(from: Vector3, dest: Vector3) -> void:
	if _from_client() and _duel_ok():
		duel.net_client_jump(from, dest)

# ---- host -> client ----
func _to_client() -> bool:
	return is_host and connected and _client_id != 0

func send_snapshot(snap: Dictionary) -> void:
	if _to_client():
		_c_snapshot.rpc_id(_client_id, snap)

@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _c_snapshot(snap: Dictionary) -> void:
	if _duel_ok():
		duel.net_snapshot(snap)

func send_cast(index: int, key: String, aim: Vector3, cast_seed: int) -> void:
	if _to_client():
		_c_cast.rpc_id(_client_id, index, key, aim, cast_seed)

@rpc("authority", "call_remote", "reliable", 2)
func _c_cast(index: int, key: String, aim: Vector3, cast_seed: int) -> void:
	if _duel_ok():
		duel.net_cast(index, key, aim, cast_seed)

func send_hit_fx(index: int, dealt: float, absorbed: float, anim: int) -> void:
	if _to_client():
		_c_hit_fx.rpc_id(_client_id, index, dealt, absorbed, anim)

@rpc("authority", "call_remote", "reliable", 2)
func _c_hit_fx(index: int, dealt: float, absorbed: float, anim: int) -> void:
	if _duel_ok():
		duel.net_hit_fx(index, dealt, absorbed, anim)

func send_knockback(kb: Vector3) -> void:
	if _to_client():
		_c_knockback.rpc_id(_client_id, kb)

@rpc("authority", "call_remote", "reliable", 2)
func _c_knockback(kb: Vector3) -> void:
	if _duel_ok():
		duel.net_knockback(kb)

func send_fizzle(reason: String) -> void:
	if _to_client():
		_c_fizzle.rpc_id(_client_id, reason)

@rpc("authority", "call_remote", "reliable", 2)
func _c_fizzle(reason: String) -> void:
	if _duel_ok():
		duel.net_fizzle(reason)

func send_jump_fx(index: int, from: Vector3, to: Vector3) -> void:
	if _to_client():
		_c_jump_fx.rpc_id(_client_id, index, from, to)

@rpc("authority", "call_remote", "reliable", 2)
func _c_jump_fx(index: int, from: Vector3, to: Vector3) -> void:
	if _duel_ok():
		duel.net_jump_fx(index, from, to)

func send_correction(pos: Vector3, reason: String) -> void:
	if _to_client():
		_c_correction.rpc_id(_client_id, pos, reason)

@rpc("authority", "call_remote", "reliable", 2)
func _c_correction(pos: Vector3, reason: String) -> void:
	if _duel_ok():
		duel.net_correction(pos, reason)

func send_round_start(round_num: int, host_wins: int, client_wins: int) -> void:
	if _to_client():
		_c_round_start.rpc_id(_client_id, round_num, host_wins, client_wins)

@rpc("authority", "call_remote", "reliable", 2)
func _c_round_start(round_num: int, host_wins: int, client_wins: int) -> void:
	if _duel_ok():
		duel.net_round_start(round_num, host_wins, client_wins)

func send_round_end(winner: int, host_wins: int, client_wins: int, match_over: bool) -> void:
	if _to_client():
		_c_round_end.rpc_id(_client_id, winner, host_wins, client_wins, match_over)

@rpc("authority", "call_remote", "reliable", 2)
func _c_round_end(winner: int, host_wins: int, client_wins: int, match_over: bool) -> void:
	if _duel_ok():
		duel.net_round_end(winner, host_wins, client_wins, match_over)

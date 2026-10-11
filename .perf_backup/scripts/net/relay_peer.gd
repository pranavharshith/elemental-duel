class_name RelayPeer
extends MultiplayerPeerExtension
## Godot multiplayer peer that talks to the room relay server over one
## WebSocket (wss://). Set it as multiplayer.multiplayer_peer and all normal
## @rpc calls work. Host = peer id 1 (server), joiner = peer id 2.
##
## Binary frames = game packets (forwarded to the other player by the relay).
## Text frames = control: welcome / peer_joined / peer_left / error, plus a
## "ping" -> "pong" keep-alive used to measure latency to the server.

signal room_created(code: String)

const HOST_ID := 1
const JOIN_ID := 2
const PING_EVERY := 2.0
const SILENCE_TIMEOUT := 10.0
const CONNECT_TIMEOUT := 10.0

var code := ""
## Last error from the server or the connection, shown to the player.
var error_text := ""
## Round-trip time to the relay server (ms), -1 until measured.
var rtt_ms := -1

var _ws := WebSocketPeer.new()
var _host := false
var _status := CONNECTION_DISCONNECTED
var _other := false            # the other player is in the room
var _in: Array[PackedByteArray] = []
var _target := 0
var _mode := TRANSFER_MODE_RELIABLE
var _channel := 0
var _refuse := false
var _ping_t := 0.0
var _ping_sent_ms := 0
var _last_rx := 0.0
var _start := 0.0

static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

## Host a new room on the relay (`base` like "wss://relay.example.workers.dev").
func host(base: String, version: String) -> Error:
	_host = true
	return _open("%s/host?v=%s" % [base, version.uri_encode()])

func join(base: String, room_code: String, version: String) -> Error:
	_host = false
	code = room_code
	return _open("%s/join/%s?v=%s" % [base, room_code.uri_encode(), version.uri_encode()])

func _open(url: String) -> Error:
	_ws.inbound_buffer_size = 1 << 20
	_ws.outbound_buffer_size = 1 << 20
	_ws.max_queued_packets = 8192
	var err := _ws.connect_to_url(url)
	if err != OK:
		error_text = "Couldn't start the connection (error %d)." % err
		return err
	_status = CONNECTION_CONNECTING
	_start = _now()
	_last_rx = _now()
	return OK

# ------------------------------------------------------------ polling
func _poll() -> void:
	if _status == CONNECTION_DISCONNECTED:
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN or st == WebSocketPeer.STATE_CLOSING:
		while _ws.get_available_packet_count() > 0:
			var pkt := _ws.get_packet()
			_last_rx = _now()
			if _ws.was_string_packet():
				_control(pkt.get_string_from_utf8())
			elif _other:
				_in.append(pkt)
	if st == WebSocketPeer.STATE_OPEN:
		if _now() >= _ping_t:
			_ping_t = _now() + PING_EVERY
			_ping_sent_ms = Time.get_ticks_msec()
			_ws.send_text("ping")
		if _now() - _last_rx > SILENCE_TIMEOUT:
			_fail("Lost connection to the game server.")
			return
	if _status == CONNECTION_CONNECTING and _now() - _start > CONNECT_TIMEOUT:
		_fail("Couldn't reach the game server. Check your internet connection.")
		return
	if st == WebSocketPeer.STATE_CLOSED:
		if error_text.is_empty():
			var reason := _ws.get_close_reason()
			if not reason.is_empty():
				error_text = reason
			elif _status == CONNECTION_CONNECTING:
				error_text = "Couldn't reach the game server. Check your internet connection."
			else:
				error_text = "Lost connection to the game server."
		_drop()

func _control(text: String) -> void:
	if text == "pong":
		if _ping_sent_ms > 0:
			rtt_ms = Time.get_ticks_msec() - _ping_sent_ms
		return
	var msg = JSON.parse_string(text)
	if typeof(msg) != TYPE_DICTIONARY:
		return
	match String(msg.get("t", "")):
		"welcome":
			code = String(msg.get("code", code))
			_status = CONNECTION_CONNECTED
			if _host:
				room_created.emit(code)
			else:
				_other = true
				peer_connected.emit(HOST_ID)
		"peer_joined":
			if _host and not _other:
				_other = true
				peer_connected.emit(JOIN_ID)
		"peer_left":
			if _host and _other:
				_other = false
				_in.clear()
				peer_disconnected.emit(JOIN_ID)
		"error":
			error_text = String(msg.get("msg", "Server error."))

func _fail(reason: String) -> void:
	if error_text.is_empty():
		error_text = reason
	_ws.close(1000, "")
	_drop()

func _drop() -> void:
	if _status == CONNECTION_DISCONNECTED:
		return
	if _host and _other:
		_other = false
		peer_disconnected.emit(JOIN_ID)
	_other = false
	_in.clear()
	_status = CONNECTION_DISCONNECTED

# ------------------------------------------------------------ MultiplayerPeer API
func _get_connection_status() -> ConnectionStatus:
	return _status

func _get_unique_id() -> int:
	return HOST_ID if _host else JOIN_ID

func _is_server() -> bool:
	return _host

func _is_server_relay_supported() -> bool:
	return false

func _get_available_packet_count() -> int:
	return _in.size()

func _get_packet_script() -> PackedByteArray:
	return _in.pop_front() if not _in.is_empty() else PackedByteArray()

func _get_packet_peer() -> int:
	return JOIN_ID if _host else HOST_ID

func _get_packet_channel() -> int:
	return 0

func _get_packet_mode() -> TransferMode:
	return TRANSFER_MODE_RELIABLE

func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _status != CONNECTION_CONNECTED or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNCONFIGURED
	if not _other or _target == _get_unique_id():
		return OK   # nobody to deliver to
	return _ws.put_packet(buffer)

func _get_max_packet_size() -> int:
	return 60000

func _set_target_peer(peer: int) -> void:
	_target = peer

func _set_transfer_mode(mode: TransferMode) -> void:
	_mode = mode

func _get_transfer_mode() -> TransferMode:
	return _mode

func _set_transfer_channel(channel: int) -> void:
	_channel = channel

func _get_transfer_channel() -> int:
	return _channel

func _set_refuse_new_connections(enable: bool) -> void:
	_refuse = enable

func _is_refusing_new_connections() -> bool:
	return _refuse

func _disconnect_peer(peer: int, _force: bool) -> void:
	if _host and peer == JOIN_ID and _other:
		_ws.send_text("kick")
	elif not _host and peer == HOST_ID:
		_close()

func _close() -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN or _ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		_ws.close(1000, "Left")
	_other = false
	_in.clear()
	_status = CONNECTION_DISCONNECTED

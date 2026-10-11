class_name RelayPeer
extends MultiplayerPeerExtension
## Godot multiplayer peer for online matches. Set it as
## multiplayer.multiplayer_peer and all normal @rpc calls work.
## Host = peer id 1 (server), joiner = peer id 2.
##
## Two transports:
##  1. Relay: one WebSocket (wss://) to the room server, which forwards every
##     binary frame to the other player. Always used to find each other.
##  2. Direct (WebRTC): once both players are in the room, the games try to
##     open a peer-to-peer WebRTC connection (signalled through the relay via
##     Net's RPCs). Game packets then go straight between the two players over
##     UDP instead of player -> server -> player over TCP: no detour through
##     the server's region and no TCP head-of-line stalls when a packet is
##     lost, which is what produced the 300-600 ms spikes. Snapshots use an
##     unreliable channel; events a reliable one. If the direct link can't be
##     made (strict NAT, no TURN, native build without WebRTC) or drops, the
##     relay keeps working.
##
## Switching is ordered: when a side starts sending directly it first sends a
## FENCE over the relay; the receiver holds direct packets until that fence
## arrives, so nothing sent before the switch is overtaken.
##
## Text frames on the relay = control: welcome / peer_joined / peer_left /
## error, plus "ping" -> "pong" (latency to the server + keep-alive).

signal room_created(code: String)
## Signalling data for the other player (Net forwards it with an RPC).
## kind: "sdp" (a=type, b=sdp) or "ice" (a=media, b=name, index).
signal rtc_signal(kind: String, a: String, b: String, index: int)
signal link_changed

const HOST_ID := 1
const JOIN_ID := 2
const PING_EVERY := 2.0
const PEER_PING_EVERY := 0.5
const SILENCE_TIMEOUT := 10.0
const CONNECT_TIMEOUT := 10.0
const RTC_TIMEOUT := 12.0

# Peer-level packets (never handed to SceneMultiplayer). The 0xFF 'E' 'D'
# prefix plus exact sizes can't collide with Godot's RPC packets here.
const _MAGIC_FENCE := 1
const _MAGIC_PING := 2
const _MAGIC_PONG := 3

var code := ""
## Last error from the server or the connection, shown to the player.
var error_text := ""
## Round-trip time to the relay server (ms), -1 until measured.
var rtt_ms := -1
## Measured player-to-player round trip (ms, smoothed), -1 until measured.
var peer_rtt_ms := -1
## Set by Net once the handshake is done (both sides run this build).
var peer_ready := false

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
var _peer_ping_t := 0.0
var _peer_rtt_f := -1.0
var _rtt_epoch_ms := 0.0
var _last_rx := 0.0
var _start := 0.0

# ---- WebRTC direct link
var _rtc: WebRTCPeerConnection
var _ch_reliable: WebRTCDataChannel
var _ch_fast: WebRTCDataChannel
var _rtc_started := 0.0
var _rtc_send := false         # our outgoing packets use the direct link
var _fence_seen := false       # the other side's fence arrived on the relay
var _rtc_pending: Array[PackedByteArray] = []
var _rtc_was_open := false

static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

## True when this build/platform can make WebRTC connections. Browsers have it
## built in; native builds need the webrtc-native GDExtension.
static func rtc_supported() -> bool:
	if OS.get_cmdline_user_args().has("--no-direct"):   # dev: force the relay
		return false
	return OS.has_feature("web") or ClassDB.class_exists("WebRTCLibPeerConnection")

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

## "direct", "connecting" (direct link being negotiated) or "relay".
func link_kind() -> String:
	if _rtc_send and _rtc_open():
		return "direct"
	if _rtc != null:
		return "connecting"
	return "relay"

func is_direct() -> bool:
	return _rtc_send and _rtc_open()

# ------------------------------------------------------------ WebRTC
## Starts negotiating the direct link. The host makes the offer.
func start_rtc(ice_servers: Array) -> bool:
	if _rtc != null or not rtc_supported() or _status != CONNECTION_CONNECTED:
		return false
	var pc := WebRTCPeerConnection.new()
	if pc.initialize({"iceServers": ice_servers}) != OK:
		return false
	_rtc = pc
	_rtc.session_description_created.connect(_on_sdp_created)
	_rtc.ice_candidate_created.connect(_on_ice_created)
	# Negotiated channels: same ids on both sides, nothing extra to signal.
	_ch_reliable = _rtc.create_data_channel("events", {"negotiated": true, "id": 1, "ordered": true})
	_ch_fast = _rtc.create_data_channel("state", {"negotiated": true, "id": 2, "ordered": true, "maxRetransmits": 0})
	if _ch_reliable == null or _ch_fast == null:
		_rtc_teardown()
		return false
	for ch in [_ch_reliable, _ch_fast]:
		(ch as WebRTCDataChannel).write_mode = WebRTCDataChannel.WRITE_MODE_BINARY
	_rtc_started = _now()
	if _host:
		_rtc.create_offer()
	link_changed.emit()
	return true

func rtc_active() -> bool:
	return _rtc != null

func _on_sdp_created(type: String, sdp: String) -> void:
	if _rtc == null:
		return
	_rtc.set_local_description(type, sdp)
	rtc_signal.emit("sdp", type, sdp, 0)

func _on_ice_created(media: String, index: int, name: String) -> void:
	rtc_signal.emit("ice", media, name, index)

## Signalling from the other player (via Net).
func rtc_remote_sdp(type: String, sdp: String) -> void:
	if _rtc:
		_rtc.set_remote_description(type, sdp)   # an offer auto-creates our answer

func rtc_remote_ice(media: String, index: int, name: String) -> void:
	if _rtc:
		_rtc.add_ice_candidate(media, index, name)

func _rtc_open() -> bool:
	return _ch_reliable != null and _ch_fast != null \
		and _ch_reliable.get_ready_state() == WebRTCDataChannel.STATE_OPEN \
		and _ch_fast.get_ready_state() == WebRTCDataChannel.STATE_OPEN

func _poll_rtc() -> void:
	if _rtc == null:
		return
	_rtc.poll()
	var open := _rtc_open()
	if open:
		_rtc_was_open = true
		for ch in [_ch_reliable, _ch_fast]:
			var c := ch as WebRTCDataChannel
			while c.get_available_packet_count() > 0:
				_receive(c.get_packet(), true)
		if not _rtc_send and _other:
			# Switch our outgoing traffic: fence on the old path first.
			_ws.put_packet(_magic(_MAGIC_FENCE))
			_rtc_send = true
			_reset_peer_rtt()   # new path: don't average with relay pings
			link_changed.emit()
		return
	var st := _rtc.get_connection_state()
	var failed := st == WebRTCPeerConnection.STATE_FAILED or st == WebRTCPeerConnection.STATE_CLOSED
	if _rtc_was_open or failed or _now() - _rtc_started > RTC_TIMEOUT:
		_rtc_teardown()

## Drops the direct link and falls back to the relay (both directions).
func _rtc_teardown() -> void:
	if _rtc:
		_rtc.close()
	_rtc = null
	_ch_reliable = null
	_ch_fast = null
	_rtc_send = false
	_rtc_was_open = false
	_fence_seen = false
	for pkt in _rtc_pending:
		_in.append(pkt)
	_rtc_pending.clear()
	_reset_peer_rtt()
	link_changed.emit()

func _reset_peer_rtt() -> void:
	_rtt_epoch_ms = Time.get_ticks_usec() / 1000.0
	_peer_rtt_f = -1.0
	peer_rtt_ms = -1
	_peer_ping_t = 0.0   # measure the new path right away

# ------------------------------------------------------------ peer packets
static func _magic(kind: int, payload: PackedByteArray = PackedByteArray()) -> PackedByteArray:
	var p := PackedByteArray([0xFF, 0x45, 0x44, kind])
	p.append_array(payload)
	return p

static func _magic_kind(pkt: PackedByteArray) -> int:
	if pkt.size() != 4 and pkt.size() != 12:
		return 0
	if pkt[0] != 0xFF or pkt[1] != 0x45 or pkt[2] != 0x44:
		return 0
	return pkt[3]

## Packet from the other player (relay or direct).
func _receive(pkt: PackedByteArray, direct: bool) -> void:
	match _magic_kind(pkt):
		_MAGIC_FENCE:
			_fence_seen = true
			for p in _rtc_pending:
				_in.append(p)
			_rtc_pending.clear()
			return
		_MAGIC_PING:
			_send_raw(_magic(_MAGIC_PONG, pkt.slice(4)), direct)
			return
		_MAGIC_PONG:
			var sent := pkt.decode_double(4)
			var rtt := Time.get_ticks_usec() / 1000.0 - sent
			# Pings sent before a link switch measured the old path.
			if sent >= _rtt_epoch_ms and rtt >= 0.0 and rtt < 10000.0:
				# Smoothed, but a rise shows up quickly.
				_peer_rtt_f = rtt if _peer_rtt_f < 0.0 else lerpf(_peer_rtt_f, rtt, 0.35 if rtt > _peer_rtt_f else 0.15)
				peer_rtt_ms = int(round(_peer_rtt_f))
			return
	if direct and not _fence_seen:
		_rtc_pending.append(pkt)
	else:
		_in.append(pkt)

func _send_raw(pkt: PackedByteArray, direct: bool) -> void:
	if direct and _ch_fast and _ch_fast.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
		_ch_fast.put_packet(pkt)
	elif _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.put_packet(pkt)
		_flush_ws()

func _send_peer_ping() -> void:
	var payload := PackedByteArray()
	payload.resize(8)
	payload.encode_double(0, Time.get_ticks_usec() / 1000.0)
	_send_raw(_magic(_MAGIC_PING, payload), is_direct())

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
				_receive(pkt, false)
	_poll_rtc()
	if st == WebSocketPeer.STATE_OPEN:
		if _now() >= _ping_t:
			_ping_t = _now() + PING_EVERY
			_ping_sent_ms = Time.get_ticks_msec()
			_ws.send_text("ping")
		if peer_ready and _other and _now() >= _peer_ping_t:
			_peer_ping_t = _now() + PEER_PING_EVERY
			_send_peer_ping()
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
				_reset_peer_state()
				peer_disconnected.emit(JOIN_ID)
		"error":
			error_text = String(msg.get("msg", "Server error."))

## Forget everything about the current opponent (they left).
func _reset_peer_state() -> void:
	_other = false
	_in.clear()
	_rtc_pending.clear()
	peer_ready = false
	peer_rtt_ms = -1
	_peer_rtt_f = -1.0
	if _rtc:
		_rtc_teardown()
		_in.clear()

func _fail(reason: String) -> void:
	if error_text.is_empty():
		error_text = reason
	_ws.close(1000, "")
	_drop()

func _drop() -> void:
	if _status == CONNECTION_DISCONNECTED:
		return
	var had_other := _other
	_reset_peer_state()
	if _host and had_other:
		peer_disconnected.emit(JOIN_ID)
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
	if _rtc_send and _rtc_open():
		# Snapshots/inputs (unreliable RPCs) may be dropped: a newer one is
		# always on the way. Events must arrive.
		var ch := _ch_reliable if _mode == TRANSFER_MODE_RELIABLE else _ch_fast
		return ch.put_packet(buffer)
	var err := _ws.put_packet(buffer)
	_flush_ws()
	return err

## Native WebSocketPeer only writes queued frames during poll(), which
## SceneMultiplayer runs once at the start of each frame: a snapshot sent
## from _physics_process waited up to a whole frame. Flush right away.
## (In browsers put_packet already sends immediately.) Incoming frames read
## by this poll stay queued in the socket until _poll() handles them.
func _flush_ws() -> void:
	if not OS.has_feature("web"):
		_ws.poll()

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
	_reset_peer_state()
	_status = CONNECTION_DISCONNECTED

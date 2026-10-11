extends Node
## Dev harness: plays a scripted, VFX-heavy duel against the AI and reports
## frame-time statistics (average, 1% low, worst frame, hitch count) plus
## render counters. Usage (real renderer, not headless):
##   godot --path . --resolution 2560x1440 res://dev/bench.tscn
## VSync is disabled so the numbers reflect actual frame cost.

const DURATION := 24.0
const WARMUP := 3.5          # skip the countdown / first frames
const COMBOS := [
	["fire"], ["lightning"], ["earth"], ["fire", "earth"], ["water", "wind"],
	["fire", "water"], ["lightning", "lightning"], ["water", "water"],
	["fire", "wind"], ["earth", "earth"], ["fire", "fire", "fire"],
	["lightning", "water"], ["wind", "wind"], ["fire", "lightning"],
]

var duel: Node
var _t := 0.0
var _cast_t := 0.0
var _i := 0
var _frames: PackedFloat32Array = []
var _draws := 0
var _prims := 0
var _samples := 0
var _last_us := 0
var _gpu := 0.0
var _cpu := 0.0

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	duel = (load("res://scenes/duel.tscn") as PackedScene).instantiate()
	add_child(duel)
	_last_us = Time.get_ticks_usec()

func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var dt_ms := (now - _last_us) / 1000.0
	_last_us = now
	_t += delta
	var pc: PlayerController = duel.player_ctrl
	var p: Wizard = duel.player
	var e: Wizard = duel.enemy
	if pc and e:
		var d := e.global_position - p.global_position
		pc.yaw = rad_to_deg(atan2(-d.x, -d.z))
		pc.pitch = -8.0
	# Strafe back and forth so the camera and wizard keep moving.
	p.move_input = Vector3(sin(_t * 1.3), 0, 0)
	p.hp = 100.0
	e.hp = 100.0
	_cast_t -= delta
	if _t > WARMUP and _cast_t <= 0.0:
		_cast_t = 0.45
		p.mana = 100.0
		p.cooldowns.clear()
		p.stun_time = 0.0
		p.clear_elements()
		for el in COMBOS[_i % COMBOS.size()]:
			p.queue_element(el)
		p.release_buffer()
		_i += 1
		if _i % 5 == 0:
			p.sp = 100.0
			p.try_spatial_jump(Vector3(1 if _i % 10 == 0 else -1, 0, 0))
	if _t > WARMUP:
		if dt_ms > 20.0:
			print("  hitch %.1fms at t=%.2f after combo #%d %s" % [dt_ms, _t, _i - 1, COMBOS[maxi(0, _i - 1) % COMBOS.size()]])
		_frames.append(dt_ms)
		_draws += int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		_prims += int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		_samples += 1
		var vp := get_viewport().get_viewport_rid()
		_gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		_cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
	if _t > WARMUP + DURATION:
		_report()
		get_tree().quit()

func _report() -> void:
	var sorted := _frames.duplicate()
	sorted.sort()
	var total := 0.0
	for f in _frames:
		total += f
	var avg := total / _frames.size()
	var n1 := maxi(1, _frames.size() / 100)
	var low := 0.0
	for i in n1:
		low += sorted[sorted.size() - 1 - i]
	low /= n1
	var hitches := 0
	for f in _frames:
		if f > 33.3:
			hitches += 1
	print("BENCH frames=%d avg=%.2fms (%.0f fps) 1%%low=%.2fms worst=%.2fms hitches>33ms=%d draws=%d prims=%d gpu=%.2fms render_cpu=%.2fms window=%s" % [
		_frames.size(), avg, 1000.0 / avg, low, sorted[sorted.size() - 1], hitches,
		_draws / maxi(1, _samples), _prims / maxi(1, _samples), _gpu / maxi(1, _samples), _cpu / maxi(1, _samples),
		str(DisplayServer.window_get_size())])

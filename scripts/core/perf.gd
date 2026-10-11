extends Node
## Adaptive 3D render resolution.
##
## The 3D scene is drawn at a reduced internal resolution when the screen has
## far more pixels than the GPU can comfortably fill (4K / high-DPI monitors,
## browser canvases at devicePixelRatio 1.5-2), and steps down further if the
## frame rate stays low. The HUD and menus always render at full resolution.
##
## Downscaling only helps when the GPU is the bottleneck. If a step down does
## not raise the frame rate, it is reverted and adaptation stops, so a
## CPU-bound machine never ends up blurry for nothing.

## Max 3D pixels per frame. Web (WebGL) gets a tighter budget than native GL.
const WEB_PIXEL_BUDGET := 1920.0 * 1080.0
const DESKTOP_PIXEL_BUDGET := 2560.0 * 1440.0
const MIN_SCALE := 0.6
const STEP := 0.1
const SAMPLE_SECONDS := 2.0
## Frames longer than this are loading stalls, not steady-state cost.
const STALL_MS := 120.0
## Must gain at least this much fps from a step down to keep it.
const MIN_GAIN := 1.06

var enabled := true
var _cap := 1.0          # from the pixel budget
var _dyn := 1.0          # adaptive factor on top of the cap
var _locked := false
var _last_us := 0
var _acc_ms := 0.0
var _frames := 0
var _good_samples := 0
var _fps_before_step := 0.0
var _pending_check := false
var _up_cooldown := 3

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.size_changed.connect(_update_cap)
	_update_cap()
	_last_us = Time.get_ticks_usec()

func current_scale() -> float:
	return get_viewport().scaling_3d_scale

func _update_cap() -> void:
	var size := get_window().size
	var px := float(size.x * size.y)
	var budget := WEB_PIXEL_BUDGET if OS.has_feature("web") else DESKTOP_PIXEL_BUDGET
	_cap = 1.0 if px <= 0.0 else clampf(sqrt(budget / px), MIN_SCALE, 1.0)
	_apply()

func _apply() -> void:
	get_viewport().scaling_3d_scale = clampf(_cap * _dyn, MIN_SCALE, 1.0) if enabled else 1.0

func _notification(what: int) -> void:
	# Background tabs / unfocused windows are throttled: don't learn from them.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_reset_sample()

func _reset_sample() -> void:
	_acc_ms = 0.0
	_frames = 0
	_last_us = Time.get_ticks_usec()

func _process(_delta: float) -> void:
	# Real time: `delta` is scaled by Engine.time_scale (round-end slow motion).
	var now := Time.get_ticks_usec()
	var ms := (now - _last_us) / 1000.0
	_last_us = now
	if not enabled or _locked or ms > STALL_MS:
		return
	_acc_ms += ms
	_frames += 1
	if _acc_ms < SAMPLE_SECONDS * 1000.0:
		return
	var fps := _frames * 1000.0 / _acc_ms
	_reset_sample()
	_evaluate(fps)

func _target_fps() -> float:
	var hz := DisplayServer.screen_get_refresh_rate()
	if hz <= 0.0:
		hz = 60.0
	return minf(hz, 60.0)

func _evaluate(fps: float) -> void:
	var target := _target_fps()
	if _pending_check:
		_pending_check = false
		if fps < _fps_before_step * MIN_GAIN and fps < target * 0.95:
			# Lower resolution didn't help: not GPU-bound. Undo and stop.
			_dyn = minf(1.0, _dyn + STEP)
			_locked = true
			_apply()
			return
	var scale := _cap * _dyn
	if fps < target * 0.85 and scale > MIN_SCALE + 0.001:
		_fps_before_step = fps
		_pending_check = true
		_good_samples = 0
		_dyn = maxf(MIN_SCALE / _cap, _dyn - STEP)
		_up_cooldown = mini(_up_cooldown * 2, 24)
		_apply()
	elif fps >= target * 0.97 and _dyn < 1.0:
		_good_samples += 1
		if _good_samples >= _up_cooldown:
			_good_samples = 0
			_dyn = minf(1.0, _dyn + STEP)
			_apply()
	else:
		_good_samples = 0

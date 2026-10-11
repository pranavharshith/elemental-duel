class_name NetBuffer
extends RefCounted
## Snapshot interpolation for a remotely controlled body. States are stamped
## with the sender's clock; we render a little in the past so there are
## almost always two states to blend between, which hides network jitter.
## A changed teleport counter clears the buffer so teleports snap instead of
## sliding across the arena.
##
## The render delay adapts to the connection: one send interval plus the
## recent worst-case lateness (jitter). A steady direct link at 60 Hz ends up
## around 25-40 ms; a jittery relay grows it (up to MAX_DELAY) so motion stays
## smooth instead of stuttering. (It used to be a fixed 100 ms.)

const MIN_DELAY := 0.025
const MAX_DELAY := 0.25
const MAX_EXTRAPOLATE := 0.15
const MAX_SNAPS := 32
## How fast the delay may shrink / grow (seconds of delay per second).
const SHRINK_RATE := 0.04
const GROW_RATE := 0.6

var tp := -1
var _snaps: Array = []        # [remote_time, pos, yaw, vel]
var _offset := 0.0            # local_time - remote_time of the fastest packet
var _have_offset := false
var _interval := 1.0 / 30.0   # smoothed sender interval
var _late_peak := 0.03        # decaying max lateness vs the fastest packet
var _delay := 0.1
var _last_remote_t := -1.0
var _last_sample_t := -1.0

static func now() -> float:
	return Time.get_ticks_usec() / 1000000.0

func clear() -> void:
	_snaps.clear()
	tp = -1

## Current interpolation delay in seconds (diagnostics / HUD).
func delay() -> float:
	return _delay

## Returns true when the body must snap (first state or a teleport).
func push(remote_t: float, pos: Vector3, yaw: float, vel: Vector3, tp_count: int) -> bool:
	var est := now() - remote_t
	if not _have_offset or est < _offset:
		_offset = est
		_have_offset = true
	else:
		_offset = lerpf(_offset, est, 0.002)   # follow slow clock drift
	var late := est - _offset
	_late_peak = maxf(late, _late_peak * 0.995)
	if _last_remote_t > 0.0 and remote_t > _last_remote_t:
		_interval = lerpf(_interval, clampf(remote_t - _last_remote_t, 0.005, 0.2), 0.1)
	_last_remote_t = maxf(_last_remote_t, remote_t)
	var snapped := false
	if tp_count != tp:
		_snaps.clear()
		tp = tp_count
		snapped = true
	if not _snaps.is_empty() and remote_t <= float(_snaps[-1][0]):
		return snapped   # stale / out of order
	_snaps.append([remote_t, pos, yaw, vel])
	while _snaps.size() > MAX_SNAPS:
		_snaps.pop_front()
	return snapped

func _update_delay() -> void:
	var t := now()
	var dt := 0.0 if _last_sample_t < 0.0 else clampf(t - _last_sample_t, 0.0, 0.1)
	_last_sample_t = t
	var target := clampf(_interval + _late_peak + 0.005, MIN_DELAY, MAX_DELAY)
	if target > _delay:
		_delay = minf(target, _delay + GROW_RATE * dt)
	else:
		_delay = maxf(target, _delay - SHRINK_RATE * dt)

## {"pos", "yaw", "vel"} at render time, or {} if nothing received yet.
func sample() -> Dictionary:
	if _snaps.is_empty():
		return {}
	_update_delay()
	var rt := now() - _offset - _delay
	var first: Array = _snaps[0]
	if rt <= float(first[0]) or _snaps.size() == 1:
		if _snaps.size() == 1:
			return _extrapolate(first, rt)
		return {"pos": first[1], "yaw": first[2], "vel": first[3]}
	var last: Array = _snaps[-1]
	if rt >= float(last[0]):
		return _extrapolate(last, rt)
	for i in range(_snaps.size() - 1, 0, -1):
		var a: Array = _snaps[i - 1]
		if float(a[0]) <= rt:
			var b: Array = _snaps[i]
			var f := clampf((rt - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001), 0.0, 1.0)
			# Drop states we will never need again.
			while i > 2:
				_snaps.pop_front()
				i -= 1
			return {"pos": (a[1] as Vector3).lerp(b[1], f), "yaw": lerp_angle(float(a[2]), float(b[2]), f),
				"vel": (a[3] as Vector3).lerp(b[3], f)}
	return {"pos": last[1], "yaw": last[2], "vel": last[3]}

func _extrapolate(s: Array, rt: float) -> Dictionary:
	var dt := clampf(rt - float(s[0]), 0.0, MAX_EXTRAPOLATE)
	var vel: Vector3 = s[3]
	return {"pos": (s[1] as Vector3) + Vector3(vel.x, 0, vel.z) * dt, "yaw": s[2], "vel": vel}

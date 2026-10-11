class_name NetBuffer
extends RefCounted
## Snapshot interpolation for a remotely controlled body. States are stamped
## with the sender's clock; we render DELAY seconds in the past so there are
## almost always two states to blend between, which hides network jitter.
## A changed teleport counter clears the buffer so teleports snap instead of
## sliding across the arena.

const DELAY := 0.1
const MAX_EXTRAPOLATE := 0.15
const MAX_SNAPS := 32

var tp := -1
var _snaps: Array = []        # [remote_time, pos, yaw, vel]
var _offset := 0.0            # local_time - remote_time (smoothed)
var _have_offset := false

static func now() -> float:
	return Time.get_ticks_usec() / 1000000.0

func clear() -> void:
	_snaps.clear()
	tp = -1

## Returns true when the body must snap (first state or a teleport).
func push(remote_t: float, pos: Vector3, yaw: float, vel: Vector3, tp_count: int) -> bool:
	var est := now() - remote_t
	if not _have_offset or est < _offset:
		_offset = est
		_have_offset = true
	else:
		_offset = lerpf(_offset, est, 0.01)   # follow slow clock drift
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

## {"pos", "yaw", "vel"} at render time, or {} if nothing received yet.
func sample() -> Dictionary:
	if _snaps.is_empty():
		return {}
	var rt := now() - _offset - DELAY
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

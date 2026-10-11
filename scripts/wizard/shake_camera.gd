class_name ShakeCamera
extends Camera3D
## Camera3D with trauma-based screen shake. Kept subtle: big shakes make the
## crosshair unreliable.

const MAX_OFFSET := 0.12

var _trauma := 0.0
var _t := 0.0

func add_shake(amount: float) -> void:
	_trauma = clampf(_trauma + amount * 0.6, 0.0, 0.8)

func _process(delta: float) -> void:
	_t += delta
	_trauma = maxf(0.0, _trauma - delta * 2.2)
	var s := _trauma * _trauma * Game.screen_shake
	h_offset = s * MAX_OFFSET * sin(_t * 47.0)
	v_offset = s * MAX_OFFSET * cos(_t * 39.0)

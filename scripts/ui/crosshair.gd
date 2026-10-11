class_name Crosshair
extends Control
## Minimal centred crosshair. It reflects the real two-stage aim result rather
## than guessing from distance to an enemy: red means a valid target, amber
## means the cast origin is blocked by cover, and white is a clear world aim.

enum State { NEUTRAL, TARGET, BLOCKED }

var state := State.NEUTRAL
var _previous_state := -1

func _process(_delta: float) -> void:
	if state != _previous_state:
		_previous_state = state
		queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	var col := Color(1, 1, 1, 0.95)
	if state == State.TARGET:
		col = Color(1.0, 0.3, 0.25, 1.0)
	elif state == State.BLOCKED:
		col = Color(1.0, 0.72, 0.2, 1.0)
	var outline := Color(0.05, 0.05, 0.1, 0.75)
	var gap := 6.0 if state == State.TARGET else 8.0
	var len := 9.0
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(c + d * (gap - 1.0), c + d * (gap + len + 1.0), outline, 4.0)
	draw_circle(c, 3.2, outline)
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(c + d * gap, c + d * (gap + len), col, 2.0)
	draw_circle(c, 1.8, col)
	if state == State.BLOCKED:
		draw_arc(c, 15.0, 0.0, TAU, 24, col, 1.5)

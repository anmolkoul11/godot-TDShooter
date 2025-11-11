extends Node2D
class_name Tracer

@export var width: float = 3.0
@export var lifetime: float = 0.08

@onready var _line: Line2D = $Line2D
var _t: float = 0.0

# Draw a line from start → end (in global space)
func fire(start: Vector2, end_: Vector2) -> void:
	global_position = start
	_line.clear_points()
	_line.add_point(Vector2.ZERO)
	_line.add_point(end_ - start)

func _process(delta: float) -> void:
	_t += delta
	var a: float = clampf(1.0 - _t / maxf(lifetime, 0.0001), 0.0, 1.0)

	# Fade alpha: copy color, change .a, reassign
	var col: Color = _line.modulate
	col.a = a
	_line.modulate = col

	# Thin the line as it fades
	_line.width = maxf(0.5, width * a)

	if _t >= lifetime:
		queue_free()

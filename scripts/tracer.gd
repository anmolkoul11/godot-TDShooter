extends Node2D
class_name Tracer

@export var width: float = 3.0
@export var lifetime: float = 0.08

@onready var _line: Line2D = $Line2D
var _t: float = 0.0

# Default fire: keeps whatever color is set in the scene (your original player color)
func fire(start: Vector2, end_: Vector2) -> void:
	_fire_internal(start, end_, _line.modulate)

# Enemy (or special) fire: explicitly set a color
func fire_colored(start: Vector2, end_: Vector2, color: Color) -> void:
	_fire_internal(start, end_, color)

func _fire_internal(start: Vector2, end_: Vector2, color: Color) -> void:
	global_position = start
	_line.clear_points()
	_line.add_point(Vector2.ZERO)
	_line.add_point(end_ - start)

	_line.modulate = color
	_t = 0.0

func _process(delta: float) -> void:
	_t += delta
	var a: float = clampf(1.0 - _t / maxf(lifetime, 0.0001), 0.0, 1.0)

	# Fade alpha over time
	var col: Color = _line.modulate
	col.a = a
	_line.modulate = col

	# Thin line as it fades
	_line.width = maxf(0.5, width * a)

	if _t >= lifetime:
		queue_free()

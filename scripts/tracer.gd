extends Node2D
class_name Tracer

@export var width: float = 3.0
@export var lifetime: float = 0.08  # kept for compatibility (unused when speed_px_per_sec > 0)
@export var bullet_radius: float = 5.0
@export var speed_px_per_sec: float = 9000.0  # visual travel speed; if <= 0, fall back to lifetime
@export var fade_time: float = 0.06          # fade after reaching the end

@onready var _line: Line2D = $Line2D
var _t: float = 0.0
var _local_end: Vector2 = Vector2.ZERO
var _bullet_pos: Vector2 = Vector2.ZERO
var _travel_time: float = 0.08
var _total_time: float = 0.14

# Default fire: keeps whatever color is set in the scene (your original player color)
func fire(start: Vector2, end_: Vector2) -> void:
	_fire_internal(start, end_, _line.modulate)

# Enemy (or special) fire: explicitly set a color
func fire_colored(start: Vector2, end_: Vector2, color: Color) -> void:
	_fire_internal(start, end_, color)

func _fire_internal(start: Vector2, end_: Vector2, color: Color) -> void:
	global_position = start
	_local_end = end_ - start
	_line.clear_points()
	# Start with zero-length line; we'll extend it over lifetime
	_line.add_point(Vector2.ZERO)
	_line.add_point(Vector2.ZERO)

	_line.modulate = color
	_t = 0.0
	_bullet_pos = Vector2.ZERO

	# Compute travel time from distance if speed is set; otherwise use provided lifetime
	var dist := _local_end.length()
	if speed_px_per_sec > 0.0:
		_travel_time = maxf(0.001, dist / speed_px_per_sec)
		_total_time = _travel_time + maxf(0.0, fade_time)
	else:
		_travel_time = maxf(0.001, lifetime)
		_total_time = _travel_time
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	if _t <= _travel_time:
		# Travel phase: grow line, full alpha
		var progress: float = clampf(_t / _travel_time, 0.0, 1.0)
		_bullet_pos = _local_end * progress
		_line.set_point_position(1, _bullet_pos)
		# Full alpha during travel
		var col: Color = _line.modulate
		col.a = 1.0
		_line.modulate = col
		_line.width = width
		queue_redraw()
	elif _t < _total_time:
		# Fade phase: line is full length, fade and thin out
		_line.set_point_position(1, _local_end)
		var fade_progress := (_t - _travel_time) / maxf(fade_time, 0.0001)
		fade_progress = clampf(fade_progress, 0.0, 1.0)
		var col: Color = _line.modulate
		col.a = 1.0 - fade_progress
		_line.modulate = col
		_line.width = maxf(0.5, width * (1.0 - fade_progress))
		queue_redraw()
	else:
		queue_free()

func _draw() -> void:
	# Draw a small bullet dot at the tip for better visual feedback
	if bullet_radius > 0.0 and _t <= _travel_time:
		var col: Color = _line.modulate
		col.a = 1.0
		draw_circle(_bullet_pos, bullet_radius, col)

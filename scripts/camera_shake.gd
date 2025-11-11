extends Camera2D
class_name CameraShake

var _amplitude := 0.0
var _time_left := 0.0
var _orig_offset := Vector2.ZERO

func _ready() -> void:
	add_to_group("main_camera")
	_orig_offset = offset

func shake(amplitude: float = 6.0, duration: float = 0.08) -> void:
	_amplitude = amplitude
	_time_left = duration

func _process(delta: float) -> void:
	if _time_left > 0.0:
		_time_left -= delta
		offset = _orig_offset + Vector2(
			randf_range(-_amplitude, _amplitude),
			randf_range(-_amplitude, _amplitude)
		)
	else:
		offset = _orig_offset

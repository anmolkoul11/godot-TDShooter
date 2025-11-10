extends Node2D
class_name MuzzleFlash

@export var lifetime: float = 0.10
@onready var _particles: CPUParticles2D = $CPUParticles2D
@onready var _light: PointLight2D = $PointLight2D
var _time := 0.0

func fire_at(pos: Vector2, angle: float) -> void:
	global_position = pos
	rotation = angle
	# kick
	_particles.emitting = false
	_particles.emitting = true
	_light.visible = true
	_time = 0.0

func _process(delta: float) -> void:
	_time += delta
	# fade light quickly
	_light.energy = lerp(4.0, 0.0, _time / lifetime)
	if _time >= lifetime:
		queue_free()

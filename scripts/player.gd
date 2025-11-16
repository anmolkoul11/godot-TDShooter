extends CharacterBody2D
class_name Player

signal died

var speed: float = 300.0

const BULLET_SCENE  := preload("res://scenes/bullet.tscn")
const MUZZLE_SCENE  := preload("res://scenes/muzzle_flash.tscn") # ok if missing
const TRACER_SCENE  := preload("res://scenes/tracer.tscn")       # NEW

@export var shoot_cooldown: float = 0.12
var _cooldown_left: float = 0.0

@onready var camera_remote_transform: RemoteTransform2D = $CamRemoteTransform
@onready var shoot_raycast: RayCast2D = $ShootRayCast
@onready var shoot_sound: AudioStreamPlayer2D = $ShootSFX

@export var dash_speed: float = 900.0
@export var dash_duration: float = 0.18
@export var dash_cooldown: float = 0.60
@export var dash_action: StringName = &"Dash"   # Change if you used a different action name

var is_dashing: bool = false
var _dash_time_left: float = 0.0
var _dash_cooldown_left: float = 0.0
var _dash_dir: Vector2 = Vector2.ZERO

func _process(delta: float) -> void:
	look_at(get_global_mouse_position())

	if Input.is_action_just_pressed("quit_game"):
		get_tree().quit()

	_cooldown_left = max(0.0, _cooldown_left - delta)
	if Input.is_action_just_pressed("shoot") and _cooldown_left <= 0.0:
	# For rapid fire rate use --> Input.is_action_pressed("shoot") 
		_fire_bullet()
		_cooldown_left = shoot_cooldown

func _physics_process(delta: float) -> void:
	# Dash cooldown
	if _dash_cooldown_left > 0.0:
		_dash_cooldown_left -= delta

	# Movement input
	var move_dir := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	var input_dir := move_dir.normalized()

	# Dash start
	if not is_dashing and _dash_cooldown_left <= 0.0 and Input.is_action_just_pressed(dash_action):
		var dir: Vector2 = input_dir
		if dir == Vector2.ZERO:
			dir = (get_global_mouse_position() - global_position).normalized()
			if dir == Vector2.ZERO:
				dir = velocity.normalized()
		if dir != Vector2.ZERO:
			is_dashing = true
			_dash_dir = dir
			_dash_time_left = dash_duration
			velocity = _dash_dir * dash_speed

	# Dash / normal movement
	if is_dashing:
		_dash_time_left -= delta
		velocity = _dash_dir * dash_speed
		if _dash_time_left <= 0.0:
			is_dashing = false
			_dash_cooldown_left = dash_cooldown
	else:
		if move_dir != Vector2.ZERO:
			velocity = input_dir * speed
		else:
			velocity.x = move_toward(velocity.x, 0, speed)
			velocity.y = move_toward(velocity.y, 0, speed)

	move_and_slide()

func _fire_bullet() -> void:
	var start := shoot_raycast.global_position
	var dir := (get_global_mouse_position() - start).normalized()

	shoot_raycast.force_raycast_update()
	var end_point := start + dir * 700.0
	if shoot_raycast.is_colliding():
		end_point = shoot_raycast.get_collision_point()

	if BULLET_SCENE:
		var bullet: Bullet = BULLET_SCENE.instantiate()
		get_tree().current_scene.add_child(bullet)
		bullet.setup(self, start, dir)

	if TRACER_SCENE:
		var tracer: Tracer = TRACER_SCENE.instantiate()
		get_tree().current_scene.add_child(tracer)
		tracer.fire(start, end_point)

	if MUZZLE_SCENE:
		var flash = MUZZLE_SCENE.instantiate()
		get_tree().current_scene.add_child(flash)
		flash.fire_at(start, dir.angle())

	var cam = get_tree().get_first_node_in_group("main_camera")
	if cam and cam.has_method("shake"):
		cam.shake(6.0, 0.08)

	if shoot_sound:
		shoot_sound.play()

func _on_hitbox_body_entered(body: Node2D) -> void:
	if body is Enemy:
		died.emit()
		queue_free()

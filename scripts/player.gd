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

func _process(delta: float) -> void:
	look_at(get_global_mouse_position())

	if Input.is_action_just_pressed("quit_game"):
		get_tree().quit()

	_cooldown_left = max(0.0, _cooldown_left - delta)
	if Input.is_action_pressed("shoot") and _cooldown_left <= 0.0:
		_fire_bullet()
		_cooldown_left = shoot_cooldown

func _physics_process(_delta: float) -> void:
	var move_dir := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	if move_dir != Vector2.ZERO:
		velocity = speed * move_dir.normalized()
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.y = move_toward(velocity.y, 0, speed)
	move_and_slide()

func _fire_bullet() -> void:
	var bullet: Bullet = BULLET_SCENE.instantiate()
	var scene_root := get_tree().get_current_scene()
	var bullets_node := scene_root.get_node_or_null("Bullets")
	if bullets_node:
		bullets_node.add_child(bullet)
	else:
		scene_root.add_child(bullet)

	var start := shoot_raycast.global_position
	var dir := (get_global_mouse_position() - start).normalized()
	bullet.setup(self, start, dir)

	# === INSTANT TRACER (Option A) ===
	if TRACER_SCENE:
		# use the existing ShootRayCast to find the hit point; fallback to fixed length
		shoot_raycast.force_raycast_update()
		var end_point := start + dir * 700.0
		if shoot_raycast.is_colliding():
			end_point = shoot_raycast.get_collision_point()

		var tracer: Tracer = TRACER_SCENE.instantiate()
		scene_root.add_child(tracer)
		tracer.fire(start, end_point)
	# === END TRACER ===

	# Optional muzzle flash (safe if scene exists)
	if MUZZLE_SCENE:
		var flash = MUZZLE_SCENE.instantiate()
		scene_root.add_child(flash)
		flash.fire_at(start, dir.angle())

	# Optional camera shake (if your Camera2D has the CameraShake script and is in group "main_camera")
	var cam = get_tree().get_first_node_in_group("main_camera")
	if cam and cam.has_method("shake"):
		cam.shake(6.0, 0.08)

	if shoot_sound:
		shoot_sound.play()

func _on_hitbox_body_entered(body: Node2D) -> void:
	if body is Enemy:
		died.emit()
		queue_free()

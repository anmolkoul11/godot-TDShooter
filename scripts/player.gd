extends CharacterBody2D
class_name Player

signal died
var speed = 300.0

@onready var camera_remote_transform = $CamRemoteTransform
@onready var shoot_raycast = $ShootRayCast
@onready var shoot_sound = $ShootSFX

func _process(delta: float) -> void:
	look_at(get_global_mouse_position())
	
	if Input.is_action_just_pressed("quit_game"):
		get_tree().quit()
		
		
	if Input.is_action_just_pressed("shoot"):
		if shoot_raycast.is_colliding():
			var collider = shoot_raycast.get_collider()
			shoot_sound.play()
			if collider is StaticBody2D:
				print("Shot a box")
			elif collider is Enemy:
				collider.take_damage(1,self)
		
func _physics_process(delta: float) -> void:
	var move_dir = Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_up", "move_down"))
	
	if move_dir != Vector2.ZERO:
		velocity = speed * move_dir.normalized()
	else:
		velocity.x= move_toward(velocity.x, 0 , speed)
		velocity.y= move_toward(velocity.y, 0 , speed)
		
	move_and_slide()

func _on_hitbox_body_entered(body: Node2D) -> void:
	print("player is touched")
	if body is Enemy:
		print("Enemy touched the player")
		died.emit()
		queue_free()

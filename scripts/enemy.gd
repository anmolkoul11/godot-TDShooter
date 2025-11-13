extends CharacterBody2D
class_name Enemy

const BULLET_SCENE  := preload("res://scenes/bullet.tscn")
const MUZZLE_SCENE  := preload("res://scenes/muzzle_flash.tscn")
const TRACER_SCENE  := preload("res://scenes/tracer.tscn")

@export var speed: float = 150.0
@export var stop_distance: float = 40.0
@export var show_path: bool = true
@export var hit_points: int = 3
@export var tracer_speed_px_per_sec: float = 7500.0  # enemy tracer slightly slower than player
@export var tracer_fade_time: float = 0.06           # fade after reaching target

# Shooting parameters
@export var shoot_distance: float = 900.0               # Max distance at which the enemy will shoot
@export var shoot_interval: float = 0.9                 # Seconds between shots
@export_range(0.0, 1.0) var min_accuracy: float = 0.4   # 40%
@export_range(0.0, 1.0) var max_accuracy: float = 0.8   # 80%

var direction: Vector2 = Vector2.ZERO
var player: Player = null

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var hurt_sound: AudioStreamPlayer2D = $HurtSound
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var _timer: Timer = $Timer
@onready var shoot_timer: Timer = $ShootTimer
@onready var shoot_sound: AudioStreamPlayer2D = $ShootSFX

func _ready() -> void:
	# Path update timer
	if not _timer.timeout.is_connected(_on_timer_timeout):
		_timer.timeout.connect(_on_timer_timeout)

	# Shooting timer
	if shoot_timer:
		shoot_timer.wait_time = shoot_interval
		if not shoot_timer.timeout.is_connected(_on_shoot_timer_timeout):
			shoot_timer.timeout.connect(_on_shoot_timer_timeout)
		shoot_timer.start()

	# Obstacle avoidance / nav tuning
	nav_agent.path_desired_distance = 30.0
	nav_agent.target_desired_distance = 30.0
	nav_agent.radius = 40.0
	nav_agent.max_speed = speed
	nav_agent.avoidance_enabled = true
	nav_agent.avoidance_layers = 1
	nav_agent.avoidance_mask = 1

	# Quieter than player’s gunshot
	if shoot_sound:
		shoot_sound.volume_db = -6.0  # ~half perceived loudness

func _process(_delta: float) -> void:
	if player != null:
		if is_instance_valid(player):
			look_at(player.global_position)
		else:
			player = null

func _physics_process(_delta: float) -> void:
	if player != null and not is_instance_valid(player):
		player = null

	if player != null:
		if nav_agent.is_navigation_finished():
			velocity = Vector2.ZERO
			move_and_slide()
			if show_path:
				queue_redraw()
			return

		var next_position: Vector2 = nav_agent.get_next_path_position()
		var dir: Vector2 = (next_position - global_position).normalized()
		var distance_to_player := global_position.distance_to(player.global_position)

		if distance_to_player > stop_distance:
			var desired_velocity := dir * speed
			nav_agent.set_velocity(desired_velocity)
			velocity = desired_velocity
		else:
			velocity = Vector2.ZERO
			nav_agent.set_velocity(Vector2.ZERO)

		move_and_slide()

	if show_path:
		queue_redraw()

func _draw() -> void:
	if not show_path or player == null:
		return

	var path: PackedVector2Array = nav_agent.get_current_navigation_path()

	if path.size() > 1:
		for i in range(path.size() - 1):
			var start := to_local(path[i])
			var end := to_local(path[i + 1])
			draw_line(start, end, Color.YELLOW, 3.0)

		for point in path:
			var local_point := to_local(point)
			draw_circle(local_point, 8, Color.ORANGE)

		if not nav_agent.is_navigation_finished():
			var next_pos := to_local(nav_agent.get_next_path_position())
			draw_circle(next_pos, 12, Color.RED)

		var target_local := to_local(nav_agent.target_position)
		draw_circle(target_local, 15, Color.GREEN)

func makepath() -> void:
	if player != null and is_instance_valid(player):
		nav_agent.target_position = player.global_position

func _on_player_detection_body_entered(body: Node2D) -> void:
	if body is Player and player == null:
		player = body
		print(name + " found the player")

func _on_player_detection_body_exited(body: Node2D) -> void:
	if body is Player and player != null:
		player = null
		print(name + " lost the player")

func take_damage(amount: int, attacker: Player) -> void:
	if amount <= 0:
		return

	player = attacker  # Aggro the shooter
	hit_points -= amount

	hurt_sound.play()
	animation_player.play("take_damage")

	if hit_points <= 0:
		print(name + " died")
		queue_free()

func _on_timer_timeout() -> void:
	makepath()

# ===== SHOOTING =====

func _on_shoot_timer_timeout() -> void:
	_shoot_at_player()

func _shoot_at_player() -> void:
	if player == null or not is_instance_valid(player):
		return

	var start := global_position
	var distance_to_player := start.distance_to(player.global_position)
	if distance_to_player > shoot_distance:
		return

	# Aim towards player
	var dir := (player.global_position - start).normalized()

	# Choose an accuracy in [min_accuracy, max_accuracy]
	var accuracy := randf_range(min_accuracy, max_accuracy)

	# With probability (1 - accuracy) we intentionally miss by rotating the aim
	if randf() > accuracy:
		var miss_angle_deg := randf_range(-25.0, 25.0)
		dir = dir.rotated(deg_to_rad(miss_angle_deg))

	var scene_root := get_tree().get_current_scene()

	# === BULLET (same pattern as player) ===
	var bullet: Bullet = BULLET_SCENE.instantiate()
	var bullets_node := scene_root.get_node_or_null("Bullets")
	if bullets_node:
		bullets_node.add_child(bullet)
	else:
		scene_root.add_child(bullet)

	bullet.setup(self, start, dir)

	# === TRACER (uses the same Tracer scene as player) ===
	if TRACER_SCENE:
		# Raycast to actual hit point so tracer length matches reality
		var max_range := 1200.0
		var to := start + dir * max_range
		var space_state := get_world_2d().direct_space_state
		var query := PhysicsRayQueryParameters2D.create(start, to)
		# Collide with world (layer 1) and player (layer 2)
		query.collision_mask = (1 << 0) | (1 << 1)
		var res := space_state.intersect_ray(query)
		var end_point: Vector2 = (res.get("position", to)) as Vector2

		var tracer: Tracer = TRACER_SCENE.instantiate()
		scene_root.add_child(tracer)
		tracer.speed_px_per_sec = tracer_speed_px_per_sec
		tracer.fade_time = tracer_fade_time
		tracer.fire_colored(start, end_point, Color(1, 0, 0, 1))  # bright red

	# === MUZZLE FLASH (same as player) ===
	if MUZZLE_SCENE:
		var flash: MuzzleFlash = MUZZLE_SCENE.instantiate()
		scene_root.add_child(flash)
		flash.fire_at(start, dir.angle())

	# Quieter firing sound
	if shoot_sound:
		shoot_sound.play()

	print("%s fired at player with accuracy %.2f" % [name, accuracy])

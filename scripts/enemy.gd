extends CharacterBody2D
class_name Enemy

@export var speed: float = 150.0
@export var stop_distance: float = 40.0
@export var show_path: bool = true
@export var hit_points: int = 3

var direction: Vector2 = Vector2.ZERO
var player: Player = null

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var hurt_sound: AudioStreamPlayer2D = $HurtSound
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var _timer: Timer = $Timer

func _ready() -> void:
	# Connect the timer signal
	_timer.timeout.connect(_on_timer_timeout)

	# Obstacle avoidance / nav tuning
	nav_agent.path_desired_distance = 30.0
	nav_agent.target_desired_distance = 30.0
	nav_agent.radius = 40.0
	nav_agent.max_speed = speed
	nav_agent.avoidance_enabled = true
	nav_agent.avoidance_layers = 1  # Which layers to avoid (binary mask)
	nav_agent.avoidance_mask = 1    # Which layers this agent is on

func _process(_delta: float) -> void:
	if player != null:
		look_at(player.global_position)

func _physics_process(_delta: float) -> void:
	if player != null:
		if nav_agent.is_navigation_finished():
			velocity = Vector2.ZERO
			move_and_slide()
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
	if player != null:
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

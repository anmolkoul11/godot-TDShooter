extends CharacterBody2D
class_name Enemy

var speed: float = 150.0
var direction:= Vector2.ZERO
var player: Player = null
var stop_distance := 40.0
var hit_points: int = 3
@export var show_path: bool = true
@onready var animation_player = $AnimationPlayer
@onready var hurt_sound = $HurtSound
@onready var nav_agent := $NavigationAgent2D as NavigationAgent2D

func _ready():
	# Connect the timer signal
	$Timer.timeout.connect(_on_timer_timeout)

	# obstacle avoidance
	nav_agent.path_desired_distance = 30.0
	nav_agent.target_desired_distance = 30.0
	nav_agent.radius = 40.0  # Agent collision radius
	nav_agent.max_speed = speed	
	nav_agent.avoidance_enabled = true
	nav_agent.avoidance_layers = 1  # Which layers to avoid (binary mask)
	nav_agent.avoidance_mask = 1    # Which layers this agent is on

func _process(delta: float) -> void:
	if player != null:
		look_at(player.global_position)
	
func _physics_process(delta: float) -> void:
	if player != null:
		if nav_agent.is_navigation_finished():
			velocity = Vector2.ZERO
			move_and_slide()
			return
		
		var next_position = nav_agent.get_next_path_position()
		var dir = (next_position - global_position).normalized()
		var distance_to_player = global_position.distance_to(player.global_position)
		
		if distance_to_player > stop_distance:
			var desired_velocity = dir * speed
			
			# This makes the agent adjust its path to avoid other agents
			nav_agent.set_velocity(desired_velocity)
			velocity = desired_velocity
		else:
			velocity = Vector2.ZERO
			nav_agent.set_velocity(Vector2.ZERO)
		
		move_and_slide()
		
	if show_path:
		queue_redraw()

func _draw():
	if not show_path or player == null:
		return
	
	var path = nav_agent.get_current_navigation_path()
	
	if path.size() > 1:
		for i in range(path.size() - 1):
			var start = to_local(path[i])
			var end = to_local(path[i + 1])
			draw_line(start, end, Color.YELLOW, 3.0)
		
		for point in path:
			var local_point = to_local(point)
			draw_circle(local_point, 8, Color.ORANGE)
		
		if not nav_agent.is_navigation_finished():
			var next_pos = to_local(nav_agent.get_next_path_position())
			draw_circle(next_pos, 12, Color.RED)
		
		var target_local = to_local(nav_agent.target_position)
		draw_circle(target_local, 15, Color.GREEN)
		
func makepath() -> void:
	if player != null:
		nav_agent.target_position = player.global_position
	
func _on_player_detection_body_entered(body: Node2D) -> void:
	if body is Player:
		if player == null:
			player = body
			print(name + " found the player")
	
func _on_player_detection_body_exited(body: Node2D) -> void:
	if body is Player:
		if player != null:
			player = null
			print(name + " lost the player")
		
func take_damage(amount: int, attacker: Player):
	if amount > 0:
		player = attacker
		hit_points -= 1
		hurt_sound.play()
		animation_player.play("take_damage")
		if hit_points <= 0:
			print(name + " died")
			queue_free()
			
func _on_timer_timeout():
	makepath()

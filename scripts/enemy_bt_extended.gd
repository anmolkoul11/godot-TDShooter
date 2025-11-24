extends CharacterBody2D
class_name ExtendedBTEnemy

@export var speed: float = 150.0
@export var stop_distance: float = 30.0
@export var flank_radius: float = 400.0
@export var hit_points: int = 3

# === Behaviour tuning ===
@export var wander_radius: float = 800.0           # how far from spawn we wander
@export var wander_interval: float = 3.5           # How often to pick new wander point

# Motion smoothing (from FSM/BT)
@export var rotation_speed: float = 8.0            # Radians per second for smooth rotation
@export var acceleration: float = 800.0            # Pixels per second squared
@export var deceleration: float = 1200.0           # Pixels per second squared (for stopping)

# Debug visualization
@export var debug_draw_enabled: bool = false       # Toggle debug visualization
@export var debug_draw_path: bool = true           # Draw navigation path
@export var debug_draw_target: bool = true         # Draw current target
@export var debug_draw_state: bool = true          # Draw state text
@export var debug_draw_flanking: bool = true       # Draw flanking radius circle

enum EnemyState { WANDER, ENGAGE }

var player: Player = null
var direction: Vector2 = Vector2.ZERO
var _state: EnemyState = EnemyState.WANDER
var _aggro: bool = false

var _wander_center: Vector2 = Vector2.ZERO
var _wander_target: Vector2 = Vector2.ZERO
var _has_wander_target: bool = false
var _wander_timer: float = 0.0

var _current_target: Vector2 = Vector2.ZERO
var _flank_reached: bool = false              # Has this enemy reached its flank position?
var _close_in_timer: float = 0.0              # Timer for slow close-in movement
var _squad_index: int = -1                    # Index in squad for determining role

const BULLET_SCENE := preload("res://scenes/bullet.tscn")
const MUZZLE_SCENE := preload("res://scenes/muzzle_flash.tscn")
const TRACER_SCENE := preload("res://scenes/tracer.tscn")
const ENEMY_SHOOTER_SCRIPT := preload("res://scripts/enemy_shooter.gd")

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var hurt_sound: AudioStreamPlayer2D = $HurtSound
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var _timer: Timer = $Timer
@onready var shooter: Node = $EnemyShooter

var squad: SquadCoordinator = null


func _ready() -> void:
	randomize()

	_wander_center = global_position

	if _timer and not _timer.timeout.is_connected(_on_timer_timeout):
		_timer.timeout.connect(_on_timer_timeout)

	if nav_agent:
		nav_agent.path_desired_distance = 30.0
		nav_agent.target_desired_distance = 30.0
		nav_agent.radius = 40.0
		nav_agent.max_speed = speed
		nav_agent.avoidance_enabled = true
		nav_agent.avoidance_layers = 1
		nav_agent.avoidance_mask = 1

	var root: Node = get_tree().get_current_scene()
	if root and root.has_node("SquadCoordinator"):
		squad = root.get_node("SquadCoordinator") as SquadCoordinator
		squad.register_enemy(self)
		_squad_index = squad.enemies.find(self)

	# IMPORTANT: we do NOT set `player` here.
	# `player` will be assigned only when:
	#  - PlayerDetection Area2D sees the player, OR
	#  - the player shoots us (take_damage).


func _exit_tree() -> void:
	if squad:
		squad.unregister_enemy(self)


func _process(_delta: float) -> void:
	if player and is_instance_valid(player):
		look_at(player.global_position)


func _physics_process(_delta: float) -> void:
	# === State selection ===
	# If we currently have a valid player target, engage; otherwise wander.
	if player != null and is_instance_valid(player):
		_state = EnemyState.ENGAGE
	elif not _aggro:
		_state = EnemyState.WANDER

	# === Behaviour per state ===
	match _state:
		EnemyState.WANDER:
			_state_wander()
		EnemyState.ENGAGE:
			_state_engage()

	_move_character()
	
	# Debug visualization
	if debug_draw_enabled:
		queue_redraw()


# ======================
#  States
# ======================

func _state_wander() -> void:
	# Update wander timer and pick new target if needed
	_wander_timer += get_physics_process_delta_time()
	var to_target = _wander_target - global_position
	
	# Add randomness to interval so enemies don't all pick new targets at once
	var interval_variance = wander_interval * randf_range(0.8, 1.2)
	
	if not _has_wander_target or to_target.length() < 10 or _wander_timer >= interval_variance:
		_pick_new_wander_target()
		_wander_timer = 0.0

	# Move directly toward wander target (simple direct approach like BT enemy)
	var dir: Vector2 = to_target.normalized()
	var target_velocity: Vector2 = dir * (speed * 0.5)
	velocity = velocity.move_toward(target_velocity, acceleration * get_physics_process_delta_time())
	
	# Smooth face direction (look toward movement)
	_face_direction_smooth(dir, get_physics_process_delta_time())

	# Play wander animation
	if animation_player.current_animation != "run":
		animation_player.play("run")

func _state_engage() -> void:
	if player == null or not is_instance_valid(player):
		return

	# Determine if this is the front enemy (slot 0)
	var is_front_enemy: bool = (_squad_index >= 0 and _squad_index % 4 == 0)

	# If front enemy, chase player directly
	if is_front_enemy:
		_current_target = player.global_position
	# Otherwise, use flanking position
	elif squad:
		var flank_pos = squad.get_flank_target_position(self, flank_radius)
		var dist_to_flank = global_position.distance_to(flank_pos)
		
		# Once close to flank position, start moving closer to player
		if dist_to_flank < stop_distance * 2.0:
			_flank_reached = true
		
		# If reached flank, slowly move closer to player
		if _flank_reached:
			_close_in_timer += get_physics_process_delta_time()
			var close_in_speed = speed * 0.15  # Very slow close-in
			_current_target = player.global_position.move_toward(flank_pos, close_in_speed * _close_in_timer)
		else:
			_current_target = flank_pos
	else:
		_current_target = player.global_position

	var dist_to_target: float = global_position.distance_to(_current_target)

	var dir: Vector2
	if nav_agent:
		if nav_agent.is_navigation_finished():
			nav_agent.target_position = _current_target
		var next_pos: Vector2 = nav_agent.get_next_path_position()
		dir = (next_pos - global_position).normalized()
	else:
		dir = (_current_target - global_position).normalized()

	if dist_to_target > stop_distance and dir != Vector2.ZERO:
		var desired_velocity: Vector2 = dir * speed
		velocity = desired_velocity
		if nav_agent:
			nav_agent.set_velocity(desired_velocity)
	else:
		velocity = Vector2.ZERO
		if nav_agent:
			nav_agent.set_velocity(Vector2.ZERO)

	_try_fire_at_player()


func _pick_new_wander_target() -> void:
	var angle: float = randf() * TAU
	_wander_target = _wander_center + Vector2(cos(angle), sin(angle)) * wander_radius
	_has_wander_target = true

# ======================
#  Shooting (with red tracers, faster than Stage 1)
# ======================

func _try_fire_at_player() -> void:
	if player == null or not is_instance_valid(player):
		return
	shooter.try_fire_at_target(self, player)


# ======================
#  Movement + damage
# ======================

func _move_character() -> void:
	if velocity.length() > 0.1:
		animation_player.play("run")
	else:
		if animation_player.current_animation != "idle":
			animation_player.play("idle")

	move_and_slide()


func take_damage(amount: int, attacker: Player) -> void:
	if amount <= 0:
		return

	player = attacker           # lock onto whoever shot us
	_aggro = true
	_state = EnemyState.ENGAGE

	hit_points -= amount

	hurt_sound.play()
	animation_player.play("take_damage")

	if hit_points <= 0:
		print(name + " (BT enemy) died")
		queue_free()


func _on_timer_timeout() -> void:
	# Keep the NavigationAgent goal refreshed
	if nav_agent:
		if _state == EnemyState.ENGAGE and _current_target != Vector2.ZERO:
			nav_agent.target_position = _current_target
		elif _state == EnemyState.WANDER and _has_wander_target:
			nav_agent.target_position = _wander_target


# ======================
#  Smooth Movement Helpers
# ======================

func _face_direction_smooth(dir: Vector2, delta: float) -> void:
	if dir.length() > 0.001:
		var target_angle = dir.angle()
		var angle_diff = angle_difference(rotation, target_angle)
		var max_rotation = rotation_speed * delta
		if abs(angle_diff) < max_rotation:
			rotation = target_angle
		else:
			rotation += sign(angle_diff) * max_rotation


# ======================
#  Detection Area (same idea as Stage 1)
# ======================

func _on_player_detection_body_entered(body: Node2D) -> void:
	if body is Player and player == null:
		player = body as Player
		print(name + " found the player")


func _on_player_detection_body_exited(body: Node2D) -> void:
	# If we haven't been shot yet (_aggro == false), losing sight of the
	# player should drop the target (similar to Stage 1 feel).
	if body is Player and not _aggro and player != null and body == player:
		player = null
		print(name + " lost the player")


func _on_hitbox_area_entered(area: Area2D) -> void:
	# If enemy touches player hitbox, player dies
	if area.is_in_group("player_hitbox") or area.name == "Hitbox":
		var player_node = area.get_parent()
		if player_node is Player:
			player_node.died.emit()
			player_node.queue_free()


# ======================
#  Debug Visualization
# ======================

func _draw() -> void:
	if not debug_draw_enabled:
		return

	var _local_pos = global_position
	
	# Draw current target point - just a line, no circle
	if debug_draw_target and _current_target != Vector2.ZERO:
		var target_local = to_local(_current_target)
		draw_line(Vector2.ZERO, target_local, Color.YELLOW, 2.0)
	
	# Draw wander target (when wandering) - just a line, no circle
	if debug_draw_target and _state == EnemyState.WANDER and _has_wander_target:
		var wander_local = to_local(_wander_target)
		draw_line(Vector2.ZERO, wander_local, Color.CYAN, 1.5)
	
	# Draw navigation path
	if debug_draw_path and nav_agent and not nav_agent.is_navigation_finished():
		var path = nav_agent.get_current_navigation_path()
		if path.size() > 0:
			for i in range(path.size() - 1):
				var p1_local = to_local(path[i])
				var p2_local = to_local(path[i + 1])
				var color = Color.GREEN if _state == EnemyState.WANDER else Color.RED
				draw_line(p1_local, p2_local, color, 2.0)
	
	# Draw state text and info
	if debug_draw_state:
		var state_text = "WANDER" if _state == EnemyState.WANDER else "ENGAGE"
		var aggro_text = " [AGGRO]" if _aggro else ""
		var info_text = "%s%s\nHP: %d\nVel: %.0f" % [state_text, aggro_text, hit_points, velocity.length()]
		draw_string(ThemeDB.fallback_font, Vector2(10, -20), info_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

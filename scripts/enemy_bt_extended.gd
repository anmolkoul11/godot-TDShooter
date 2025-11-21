extends CharacterBody2D
class_name ExtendedBTEnemy

@export var speed: float = 150.0
@export var stop_distance: float = 40.0
@export var flank_radius: float = 260.0
@export var hit_points: int = 3

# === Behaviour tuning ===
@export var wander_radius: float = 600.0           # how far from spawn we wander
@export var wander_interval: float = 2.5           # How often to pick new wander point

# Motion smoothing (from FSM/BT)
@export var rotation_speed: float = 8.0            # Radians per second for smooth rotation
@export var acceleration: float = 800.0            # Pixels per second squared
@export var deceleration: float = 1200.0           # Pixels per second squared (for stopping)

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


# ======================
#  States
# ======================

func _state_wander() -> void:
	# Update wander timer and pick new target if needed
	_wander_timer += get_physics_process_delta_time()
	var to_target = _wander_target - global_position
	if not _has_wander_target or to_target.length() < 30.0 or _wander_timer >= wander_interval:
		_pick_new_wander_target()
		_wander_timer = 0.0

	# Get direction from navigation or direct path
	var dir: Vector2
	if nav_agent:
		if nav_agent.is_navigation_finished():
			nav_agent.target_position = _wander_target
		var next_pos: Vector2 = nav_agent.get_next_path_position()
		dir = (next_pos - global_position).normalized()
	else:
		dir = (_wander_target - global_position).normalized()

	# Wander at reduced speed with smooth acceleration
	var target_velocity: Vector2 = dir * (speed * 0.5)
	velocity = velocity.move_toward(target_velocity, acceleration * get_physics_process_delta_time())
	
	# Smooth face direction (look toward movement)
	_face_direction_smooth(dir, get_physics_process_delta_time())
	
	# Update navigation agent
	if nav_agent:
		nav_agent.set_velocity(velocity)

	# Play wander animation
	if animation_player.current_animation != "run":
		animation_player.play("run")


func _state_engage() -> void:
	if player == null or not is_instance_valid(player):
		return

	# Use flanking from the SquadCoordinator if available; otherwise just chase
	if squad:
		_current_target = squad.get_flank_target_position(self, flank_radius)
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
	var radius: float = randf() * wander_radius
	var offset: Vector2 = Vector2(cos(angle), sin(angle)) * radius
	_wander_target = _wander_center + offset
	_has_wander_target = true
	if nav_agent:
		nav_agent.target_position = _wander_target


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

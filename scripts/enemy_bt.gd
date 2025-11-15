extends CharacterBody2D
class_name ExtendedBTEnemy

@export var speed: float = 150.0
@export var stop_distance: float = 40.0
@export var flank_radius: float = 260.0
@export var hit_points: int = 3

# === Behaviour tuning ===
@export var wander_radius: float = 600.0           # how far from spawn we wander
@export var fire_range: float = 900.0              # max range we try to shoot the player
@export var stage1_fire_interval: float = 0.8      # approximate Stage 1 interval
@export var fire_interval_factor: float = 0.7      # Stage 2 fires ~30% faster

enum EnemyState { WANDER, ENGAGE }

var player: Player = null
var direction: Vector2 = Vector2.ZERO
var _state: EnemyState = EnemyState.WANDER
var _aggro: bool = false

var _wander_center: Vector2 = Vector2.ZERO
var _wander_target: Vector2 = Vector2.ZERO
var _has_wander_target: bool = false

var _current_target: Vector2 = Vector2.ZERO

var _fire_interval: float = 0.6
var _fire_cooldown_left: float = 0.0

const BULLET_SCENE := preload("res://scenes/bullet.tscn")
const MUZZLE_SCENE := preload("res://scenes/muzzle_flash.tscn")
const TRACER_SCENE := preload("res://scenes/tracer.tscn")

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var hurt_sound: AudioStreamPlayer2D = $HurtSound
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var _timer: Timer = $Timer

var squad: SquadCoordinator = null


func _ready() -> void:
	randomize()

	_wander_center = global_position
	_fire_interval = stage1_fire_interval * fire_interval_factor

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


func _physics_process(delta: float) -> void:
	_fire_cooldown_left = max(0.0, _fire_cooldown_left - delta)

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
	if not _has_wander_target or global_position.distance_to(_wander_target) < 30.0:
		_pick_new_wander_target()

	if nav_agent:
		if nav_agent.is_navigation_finished():
			nav_agent.target_position = _wander_target
		var next_pos: Vector2 = nav_agent.get_next_path_position()
		direction = (next_pos - global_position).normalized()
	else:
		direction = (_wander_target - global_position).normalized()

	var desired_velocity: Vector2 = direction * (speed * 0.5) # wander slower
	velocity = desired_velocity
	if nav_agent:
		nav_agent.set_velocity(desired_velocity)

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
	if _fire_cooldown_left > 0.0:
		return
	if player == null or not is_instance_valid(player):
		return

	var to_player: Vector2 = player.global_position - global_position
	var distance: float = to_player.length()
	if distance > fire_range:
		return

	var dir: Vector2 = to_player.normalized()

	# Slight inaccuracy (for logs similar to Stage 1)
	var accuracy: float = randf_range(0.4, 0.9)
	var max_spread: float = (1.0 - accuracy) * 0.25
	var spread: float = randf_range(-max_spread, max_spread)
	dir = dir.rotated(spread)

	var start: Vector2 = global_position
	var scene_root: Node = get_tree().get_current_scene()

	# Bullet
	var bullet: Bullet = BULLET_SCENE.instantiate()
	var bullets_node: Node = scene_root.get_node_or_null("Bullets")
	if bullets_node:
		bullets_node.add_child(bullet)
	else:
		scene_root.add_child(bullet)

	bullet.setup(self, start, dir)

	# 🔴 Tracer – enemy shots are red
	if TRACER_SCENE:
		var tracer: Node2D = TRACER_SCENE.instantiate()
		scene_root.add_child(tracer)

		# tint tracer red
		tracer.modulate = Color(1.0, 0.0, 0.0)

		var end_point: Vector2 = start + dir * fire_range
		if tracer.has_method("fire"):
			tracer.call("fire", start, end_point)

	# Muzzle flash
	if MUZZLE_SCENE:
		var flash: Node = MUZZLE_SCENE.instantiate()
		scene_root.add_child(flash)
		if flash.has_method("fire_at"):
			flash.call("fire_at", start, dir.angle())

	print("%s fired at player with accuracy %.2f" % [name, accuracy])

	_fire_cooldown_left = _fire_interval


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

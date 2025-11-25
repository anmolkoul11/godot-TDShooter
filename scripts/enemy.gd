extends CharacterBody2D
class_name Enemy

const BULLET_SCENE  := preload("res://scenes/bullet.tscn")
const MUZZLE_SCENE  := preload("res://scenes/muzzle_flash.tscn")
const TRACER_SCENE  := preload("res://scenes/tracer.tscn")

@export var speed: float = 150.0
@export var stop_distance: float = 40.0
@export var hit_points: int = 3
@export var show_path: bool = true

# FSM params
@export var wander_radius: float = 400.0
@export var wander_interval: float = 2.5         # How often to pick a new wander point
@export var path_refresh_interval: float = 0.35   # How often to refresh chase path
@export var stop_duration: float = 2.0            # Stop state duration

# Motion smoothing
@export var rotation_speed: float = 8.0           # Radians per second for smooth rotation
@export var acceleration: float = 800.0            # Pixels per second squared
@export var deceleration: float = 1200.0          # Pixels per second squared (for stopping)

@export var debug_ai: bool = true

enum State { IDLE, CHASE, STOP, RETREAT, DEAD }
var state: State = State.IDLE

var player: Player = null
var home_position: Vector2
var wander_target: Vector2
var wander_timer: float = 0.0
var path_timer: float = 0.0
var stop_timer: float = 0.0

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var hurt_sound: AudioStreamPlayer2D = $HurtSound
@onready var shooter: Node = $EnemyShooter

func _ready() -> void:
	home_position = global_position
	nav_agent.path_desired_distance = 20
	nav_agent.target_desired_distance = 20
	nav_agent.radius = 30
	nav_agent.avoidance_enabled = false
	_pick_new_wander_target()
	_log("READY -> IDLE")

func _process(_delta: float) -> void:
	if show_path:
		queue_redraw()

func _physics_process(delta: float) -> void:
	match state:
		State.DEAD:
			velocity = Vector2.ZERO
		State.IDLE:
			_do_idle(delta)
		State.CHASE:
			_do_chase(delta)
		State.STOP:
			_do_stop(delta)
		State.RETREAT:
			_do_retreat(delta)
	move_and_slide()

# ---------------- STATES ----------------

func _do_idle(delta: float) -> void:
	wander_timer += delta
	var to_target = wander_target - global_position
	if to_target.length() < 10 or wander_timer >= wander_interval:
		_pick_new_wander_target()
		wander_timer = 0.0
	var dir = to_target.normalized()
	var target_velocity = dir * speed * 0.55
	velocity = velocity.move_toward(target_velocity, acceleration * delta)
	_face_direction_smooth(dir, delta)
	# Transition on detection
	if player:
		_change_state(State.CHASE)

func _do_chase(delta: float) -> void:
	if not player:
		_change_state(State.IDLE)
		return
	path_timer += delta
	# Refresh path
	if path_timer >= path_refresh_interval or nav_agent.is_navigation_finished():
		nav_agent.target_position = player.global_position
		path_timer = 0.0
	# Move along path
	if not nav_agent.is_navigation_finished():
		var next_pos = nav_agent.get_next_path_position()
		var dir = (next_pos - global_position).normalized()
		var target_velocity = dir * speed
		velocity = velocity.move_toward(target_velocity, acceleration * delta)
		_face_direction_smooth(dir, delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	# Try to fire at player if in range
	if player and is_instance_valid(player):
		shooter.try_fire_at_target(self, player)
	# Stop distance -> STOP state
	if global_position.distance_to(player.global_position) <= stop_distance:
		_change_state(State.STOP)

func _do_stop(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	stop_timer += delta
	# Face player if present, else face last wander target
	if player:
		var dir = (player.global_position - global_position).normalized()
		_face_direction_smooth(dir, delta)
	# Shoot at player during stop
	if player and is_instance_valid(player):
		shooter.try_fire_at_target(self, player)
	if stop_timer >= stop_duration:
		# After stop: if player still near, re-enter CHASE; else RETREAT back home
		if player and global_position.distance_to(player.global_position) > stop_distance:
			_change_state(State.CHASE)
		else:
			_change_state(State.RETREAT)

func _do_retreat(delta: float) -> void:
	var to_home = home_position - global_position
	if to_home.length() < 20:
		# Reached home, transition to IDLE
		_change_state(State.IDLE)
		return
	# Move toward home
	var dir = to_home.normalized()
	var target_velocity = dir * speed * 0.7
	velocity = velocity.move_toward(target_velocity, acceleration * delta)
	_face_direction_smooth(dir, delta)
	# If player re-enters detection, immediately chase again
	if player:
		_change_state(State.CHASE)

# ---------------- EVENTS ----------------

func take_damage(amount: int, attacker: Player) -> void:
	if state == State.DEAD or amount <= 0:
		return
	player = attacker
	hit_points -= amount
	hurt_sound.play()
	if animation_player.has_animation("take_damage"):
		animation_player.play("take_damage")
	_log("DAMAGE -> %d HP left" % hit_points)
	if hit_points <= 0:
		_die()
	else:
		_change_state(State.CHASE)

func _die() -> void:
	state = State.DEAD
	velocity = Vector2.ZERO
	if animation_player.has_animation("dead"):
		animation_player.play("dead")
	_log("DEAD")
	PerformanceMetrics.on_enemy_killed("FSM")
	queue_free()

# Connected to PlayerDetection Area2D signals
func _on_player_detection_body_entered(body: Node) -> void:
	if body is Player:
		player = body
		_log("DETECTION ENTER")
		if state != State.DEAD:
			_change_state(State.CHASE)

func _on_player_detection_body_exited(body: Node) -> void:
	if body is Player and body == player:
		player = null
		_log("DETECTION EXIT")
		if state == State.CHASE:
			_change_state(State.STOP)

# ---------------- HELPERS ----------------

func _pick_new_wander_target() -> void:
	var rand_dir = Vector2(randf() * 2 - 1, randf() * 2 - 1).normalized()
	var radius = randf() * wander_radius
	wander_target = home_position + rand_dir * radius
	_log("NEW WANDER TARGET %s" % wander_target)

func _change_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	match state:
		State.IDLE:
			wander_timer = 0.0
			_pick_new_wander_target()
		State.CHASE:
			path_timer = 0.0
			if player:
				nav_agent.target_position = player.global_position
		State.STOP:
			stop_timer = 0.0
		State.RETREAT:
			path_timer = 0.0
		State.DEAD:
			pass
	_log("STATE -> %s" % _state_name(state))

func _state_name(s: State) -> String:
	match s:
		State.IDLE: return "IDLE"
		State.CHASE: return "CHASE"
		State.STOP: return "STOP"
		State.RETREAT: return "RETREAT"
		State.DEAD: return "DEAD"
	return "?"

func _face_direction(dir: Vector2) -> void:
	if dir.length() > 0.001:
		rotation = dir.angle()

func _face_direction_smooth(dir: Vector2, delta: float) -> void:
	if dir.length() > 0.001:
		var target_angle = dir.angle()
		var angle_diff = angle_difference(rotation, target_angle)
		var max_rotation = rotation_speed * delta
		if abs(angle_diff) < max_rotation:
			rotation = target_angle
		else:
			rotation += sign(angle_diff) * max_rotation

func _draw() -> void:
	if not show_path:
		return
	var path = nav_agent.get_current_navigation_path()
	for i in range(path.size() - 1):
		draw_line(to_local(path[i]), to_local(path[i + 1]), Color.YELLOW, 2.0)

func _log(msg: String) -> void:
	if debug_ai:
		print("[Enemy %s] %s" % [name, msg])

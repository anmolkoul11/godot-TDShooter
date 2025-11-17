extends CharacterBody2D
class_name EnemyBT

@export var speed: float = 150.0
@export var stop_distance: float = 40.0
@export var hit_points: int = 3
@export var show_path: bool = true

# FSM params
@export var wander_radius: float = 400.0
@export var wander_interval: float = 2.5         # How often to pick a new wander point
@export var stop_duration: float = 2.0            # Stop state duration

# Motion smoothing
@export var rotation_speed: float = 8.0           # Radians per second for smooth rotation
@export var acceleration: float = 800.0           # Pixels per second squared
@export var deceleration: float = 1200.0          # Pixels per second squared (for stopping)

# BT path tracer
var trail_points: Array[Vector2] = []
@export var trail_interval: float = 0.1
var trail_timer: float = 0.0

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

	# --- Record BT movement path only while chasing ---
	if state == State.CHASE:
		trail_timer += delta
		if trail_timer >= trail_interval:
			trail_points.append(global_position)
			if trail_points.size() > 120:
				trail_points.pop_front()
			trail_timer = 0.0
	# --------------------------------------------------

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

# Pure BT-style seek: no A*, move directly toward player
func _do_chase(delta: float) -> void:
	if not player:
		_change_state(State.IDLE)
		return

	var to_player: Vector2 = player.global_position - global_position
	var distance: float = to_player.length()

	if distance > stop_distance:
		var dir := to_player.normalized()
		var target_velocity = dir * speed
		velocity = velocity.move_toward(target_velocity, acceleration * delta)
		_face_direction_smooth(dir, delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
		_change_state(State.STOP)

func _do_stop(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	stop_timer += delta
	# Face player if present, else face last wander target
	if player:
		var dir = (player.global_position - global_position).normalized()
		_face_direction_smooth(dir, delta)
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
	# Move toward home (BT-style steering)
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
			stop_timer = 0.0
			trail_points.clear()
			trail_timer = 0.0
			# no nav_agent path for movement (pure BT steering)
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
	if state != State.CHASE:
		return
	if trail_points.size() < 2:
		return

	for i in range(trail_points.size() - 1):
		var a = to_local(trail_points[i])
		var b = to_local(trail_points[i + 1])
		draw_line(a, b, Color.YELLOW, 2.0)

func _log(msg: String) -> void:
	if debug_ai:
		print("[Enemy %s] %s" % [name, msg])

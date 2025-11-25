extends CharacterBody2D
class_name EnemyBT

const BULLET_SCENE := preload("res://scenes/bullet.tscn")
const MUZZLE_SCENE := preload("res://scenes/muzzle_flash.tscn")
const TRACER_SCENE := preload("res://scenes/tracer.tscn")

@export var speed: float = 150.0
@export var stop_distance: float = 60.0
@export var hit_points: int = 3
@export var show_path: bool = true

@export var wander_radius: float = 400.0
@export var wander_interval: float = 2.5
@export var path_refresh_interval: float = 0.35
@export var stop_duration: float = 2.0

@export var rotation_speed: float = 8.0
@export var acceleration: float = 800.0
@export var deceleration: float = 1200.0

@export var detection_radius: float = 500.0
@export var fire_range: float = 800.0             # Max range to shoot player
@export var fire_interval: float = 0.9            # Interval between shots (seconds)
@export var debug_ai: bool = false

var player: Player = null
var home_position: Vector2
var wander_target: Vector2
var wander_timer := 0.0
var path_timer := 0.0
var stop_timer := 0.0
var is_aggro: bool = false   


@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var hurt_sound: AudioStreamPlayer2D = $HurtSound
@onready var shooter: Node = $EnemyShooter

# SIMPLE BEHAVIOR TREE NODES
func BT_Leaf(func_ref):
	return {
		"type": "leaf",
		"func": func_ref
	}

func BT_Selector(children):
	return {
		"type": "selector",
		"children": children
	}

func BT_Run(node: Dictionary, delta):
	match node["type"]:
		"leaf":
			return node["func"].call(delta)

		"selector":
			for c in node["children"]:
				if BT_Run(c, delta):
					return true
			return false

	return false


# BUILD BEHAVIOR TREE
var root: Dictionary

func _ready():
	home_position = global_position

	nav_agent.path_desired_distance = 20
	nav_agent.target_desired_distance = 20
	nav_agent.radius = 30
	nav_agent.avoidance_enabled = false

	_pick_new_wander_target()
	_ensure_player_ref()

	root = BT_Selector([
		BT_Leaf(_state_dead),
		BT_Leaf(_state_combat),
		BT_Leaf(_state_idle_or_retreat)
	])

func _physics_process(delta):
	BT_Run(root, delta)
	move_and_slide()
	queue_redraw()


# STATE LEAVES
func _state_dead(_delta) -> bool:
	if hit_points <= 0:
		_do_dead()
		return true
	return false


func _state_combat(delta) -> bool:
	if not _player_visible(delta):
		return false 

	if _player_in_stop_range(delta):
		_log("State: STOP (combat)")
		_do_stop(delta)
	else:
		_log("State: CHASE (combat)")
		_do_chase(delta)

	return true


func _state_idle_or_retreat(delta) -> bool:
	_log("State: IDLE/WANDER")
	_do_idle(delta)
	return true


# PLAYER LOOKUP HELPERS 
func _ensure_player_ref() -> void:
	if player != null:
		return

	var root_node := get_tree().root
	player = _find_player_in_subtree(root_node)

	if player != null:
		_log("Found Player node in tree: %s" % player.name)
	else:
		_log("WARNING: Player node not found in tree")


func _find_player_in_subtree(node: Node) -> Player:
	if node is Player:
		return node

	for child in node.get_children():
		var found := _find_player_in_subtree(child)
		if found != null:
			return found

	return null

func _player_visible(_delta) -> bool:
	if player == null:
		_ensure_player_ref()
		if player == null:
			return false

	var dist := global_position.distance_to(player.global_position)
	var player_visible := is_aggro or dist <= detection_radius

	return player_visible



func _player_in_stop_range(_delta) -> bool:
	if not player:
		return false
	return global_position.distance_to(player.global_position) <= stop_distance


# PATH LOGIC
func _do_dead() -> void:
	velocity = Vector2.ZERO
	_log("State: DEAD")


func _do_idle(delta):
	wander_timer += delta
	var to_target = wander_target - global_position

	if to_target.length() < 10 or wander_timer >= wander_interval:
		_pick_new_wander_target()
		wander_timer = 0.0
		_log("New wander target chosen")

	var dir = to_target.normalized()
	var target_velocity = dir * speed * 0.55
	velocity = velocity.move_toward(target_velocity, acceleration * delta)
	_face_direction_smooth(dir, delta)


func _do_chase(delta):
	if not player:
		return

	path_timer += delta

	if path_timer >= path_refresh_interval or nav_agent.is_navigation_finished():
		nav_agent.target_position = player.global_position
		path_timer = 0.0
		_log("Path updated toward player")

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


func _do_stop(delta):
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	stop_timer += delta

	if player:
		var dir = (player.global_position - global_position).normalized()
		_face_direction_smooth(dir, delta)

	# Shoot at player during stop
	if player and is_instance_valid(player):
		shooter.try_fire_at_target(self, player)

	if stop_timer >= stop_duration:
		stop_timer = 0.0
		_log("Stop expired")


#func _do_retreat(delta):
	#var to_home = home_position - global_position
	#if to_home.length() < 20:
		#return
#
	#var dir = to_home.normalized()
	#var target_velocity = dir * speed * 0.7
#
	#velocity = velocity.move_toward(target_velocity, acceleration * delta)
	#_face_direction_smooth(dir, delta)

func take_damage(amount: int, attacker: Player) -> void:
	if amount <= 0:
		return

	player = attacker 
	hit_points -= amount

	if hurt_sound:
		hurt_sound.play()

	if animation_player and animation_player.has_animation("take_damage"):
		animation_player.play("take_damage")

	_log("DAMAGE: -%d HP -> %d left" % [amount, hit_points])

	if hit_points <= 0:
		_die()
	else:
		is_aggro = true 

func _die() -> void:
	_log("DEAD")
	velocity = Vector2.ZERO

	if animation_player and animation_player.has_animation("death"):
		animation_player.play("death")

	await get_tree().create_timer(0.5).timeout
	PerformanceMetrics.on_enemy_killed("BT")

	queue_free()


# UTILITIES
func _pick_new_wander_target():
	var angle = randf() * TAU
	wander_target = home_position + Vector2(cos(angle), sin(angle)) * wander_radius
	_log("New wander target set")


func _face_direction_smooth(dir, delta):
	if dir == Vector2.ZERO:
		return
	var target_rot = dir.angle()
	rotation = lerp_angle(rotation, target_rot, rotation_speed * delta)

func _draw() -> void:
	if not show_path:
		return

	var path = nav_agent.get_current_navigation_path()
	if path.size() < 2:
		return

	for i in range(path.size() - 1):
		draw_line(
			to_local(path[i]),
			to_local(path[i + 1]),
			Color.YELLOW,
			2.0
		)
		
#LOGGING
func _log(msg: String) -> void:
	if debug_ai:
		print("[EnemyBT %s] %s" % [name, msg])

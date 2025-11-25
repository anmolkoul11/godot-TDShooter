extends CharacterBody2D
class_name ExtendedBTEnemy

@export var speed: float = 150.0
@export var stop_distance: float = 30.0
@export var flank_radius: float = 400.0
@export var hit_points: int = 3

# === Dash ability (now only for dashing TO COVER) ===
@export var dash_speed: float = 600.0           # Dash movement speed
@export var dash_duration: float = 0.25         # How long dash lasts
@export var dash_cooldown: float = 1.0          # How long before can dash again
@export var dodge_chance: float = 0.6           # Chance to dash to cover when shot/under fire
@export var danger_detection_range: float = 300.0  # Distance to detect incoming bullets

# === Cover System ===
@export var cover_search_range: float = 500.0      # How far to search for cover
@export var cover_health_threshold: float = 0.5    # Seek cover when health < 50%
@export var peek_fire_interval: float = 1.0        # Peek out and fire every X seconds
@export var retreat_health_threshold: float = 0.3  # Retreat when health < 30%

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

enum EnemyState { WANDER, ENGAGE, TAKING_COVER, RETREATING }

var player: Player = null
var direction: Vector2 = Vector2.ZERO
var _state: EnemyState = EnemyState.WANDER
var _aggro: bool = false

var _wander_center: Vector2 = Vector2.ZERO
var _wander_target: Vector2 = Vector2.ZERO
var _has_wander_target: bool = false
var _wander_timer: float = 0.0

var _current_target: Vector2 = Vector2.ZERO
var _flank_reached: bool = false
var _close_in_timer: float = 0.0
var _squad_index: int = -1

var is_dashing: bool = false
var _dash_time_left: float = 0.0
var _dash_cooldown_left: float = 0.0
var _dash_dir: Vector2 = Vector2.ZERO
var _actual_dodge_chance: float = 0.0

# === Cover System ===
var _cover_position: Vector2 = Vector2.ZERO   # Detected cover location
var _in_cover: bool = false                   # Currently in cover (logical flag, but textures now use LOS)
var _peek_fire_timer: float = 0.0             # Timer for peek-fire behavior
var _retreat_spawn_position: Vector2 = Vector2.ZERO  # Where to retreat to
var _wants_cover: bool = false                # Set when bullets/damage make us seek cover

# === Predictive bullets (used only to trigger dash-to-cover) ===
var _incoming_bullets: Array = []

const BULLET_SCENE := preload("res://scenes/bullet.tscn")
const MUZZLE_SCENE := preload("res://scenes/muzzle_flash.tscn")
const TRACER_SCENE := preload("res://scenes/tracer.tscn")
const ENEMY_SHOOTER_SCRIPT := preload("res://scripts/enemy_shooter.gd")

@onready var sprite: Sprite2D = $Sprite2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var hurt_sound: AudioStreamPlayer2D = $HurtSound
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var _timer: Timer = $Timer
@onready var shooter: Node = $EnemyShooter

var squad: SquadCoordinator = null

# === Textures for cover / normal ===
var _normal_texture: Texture2D
const COVER_TEXTURE: Texture2D = preload("res://assets/enemyEXTcover.png")


func _ready() -> void:
	randomize()

	# Store whatever texture the enemy had in the scene (enemyEXT.png)
	if sprite:
		_normal_texture = sprite.texture

	_wander_center = global_position
	_retreat_spawn_position = global_position
	
	_actual_dodge_chance = randf_range(0.4, 0.7)  # per-enemy cover-dash chance

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


func _exit_tree() -> void:
	if squad:
		squad.unregister_enemy(self)
	_incoming_bullets.clear()


func _process(_delta: float) -> void:
	if player and is_instance_valid(player):
		look_at(player.global_position)


func _physics_process(_delta: float) -> void:
	# Update dash cooldown
	if _dash_cooldown_left > 0.0:
		_dash_cooldown_left -= _delta

	# Check if bullets are coming toward us; may trigger dash-to-cover
	_check_for_incoming_bullets()

	# === State selection ===
	var health_ratio := float(hit_points) / 3.0  # assuming max hp = 3
	
	if player != null and is_instance_valid(player):
		if health_ratio <= retreat_health_threshold:
			_state = EnemyState.RETREATING
		# Either health is low OR we've "decided" we want cover due to bullets
		elif _wants_cover or (health_ratio <= cover_health_threshold and not _in_cover):
			_state = EnemyState.TAKING_COVER
		else:
			_state = EnemyState.ENGAGE
	elif not _aggro:
		_state = EnemyState.WANDER

	# === Handle dash movement ===
	if is_dashing:
		_dash_time_left -= _delta
		velocity = _dash_dir * dash_speed
		if _dash_time_left <= 0.0:
			is_dashing = false
			_dash_cooldown_left = dash_cooldown
	else:
		match _state:
			EnemyState.WANDER:
				_state_wander()
			EnemyState.ENGAGE:
				_state_engage()
			EnemyState.TAKING_COVER:
				_state_taking_cover()
			EnemyState.RETREATING:
				_state_retreating()

	# === Texture swap purely based on LOS (enemy behind box) ===
	_update_cover_texture()

	_move_character()

	if debug_draw_enabled:
		queue_redraw()


# ======================
#  States
# ======================

func _state_wander() -> void:
	_wander_timer += get_physics_process_delta_time()
	var to_target = _wander_target - global_position
	
	var interval_variance = wander_interval * randf_range(0.8, 1.2)
	
	if not _has_wander_target or to_target.length() < 10 or _wander_timer >= interval_variance:
		_pick_new_wander_target()
		_wander_timer = 0.0

	var dir: Vector2 = to_target.normalized()
	var target_velocity: Vector2 = dir * (speed * 0.5)
	velocity = velocity.move_toward(target_velocity, acceleration * get_physics_process_delta_time())
	
	_face_direction_smooth(dir, get_physics_process_delta_time())

	if animation_player.current_animation != "run":
		animation_player.play("run")


func _state_engage() -> void:
	if player == null or not is_instance_valid(player):
		return

	var is_front_enemy: bool = (_squad_index >= 0 and _squad_index % 4 == 0)

	if is_front_enemy:
		_current_target = player.global_position
	elif squad:
		var flank_pos = squad.get_flank_target_position(self, flank_radius)
		var dist_to_flank = global_position.distance_to(flank_pos)
		
		if dist_to_flank < stop_distance * 2.0:
			_flank_reached = true
		
		if _flank_reached:
			PerformanceMetrics.on_flank_attempt()
			_close_in_timer += get_physics_process_delta_time()
			var close_in_speed = speed * 0.15
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
#  TAKING COVER
# ======================

func _state_taking_cover() -> void:
	if player == null or not is_instance_valid(player):
		return

	# Ensure we have a cover target
	if _cover_position == Vector2.ZERO:
		_find_cover()
	
	if _cover_position != Vector2.ZERO:
		_current_target = _cover_position
		var dist_to_cover = global_position.distance_to(_cover_position)
		
		if dist_to_cover < stop_distance:
			_in_cover = true
			PerformanceMetrics.on_cover_entered()
			velocity = Vector2.ZERO
			if nav_agent:
				nav_agent.set_velocity(Vector2.ZERO)
			
			# In cover: keep wanting cover while player is around
			_wants_cover = true
			
			_peek_fire_timer += get_physics_process_delta_time()
			if _peek_fire_timer >= peek_fire_interval:
				_try_fire_at_player()
				_peek_fire_timer = 0.0
		else:
			_in_cover = false
			var dir: Vector2
			if nav_agent:
				if nav_agent.target_position != _cover_position or nav_agent.is_navigation_finished():
					nav_agent.target_position = _cover_position
				var next_pos: Vector2 = nav_agent.get_next_path_position()
				dir = (next_pos - global_position).normalized()
			else:
				dir = (_cover_position - global_position).normalized()
			
			if dir != Vector2.ZERO:
				var desired_velocity: Vector2 = dir * speed
				velocity = desired_velocity
				if nav_agent:
					nav_agent.set_velocity(desired_velocity)
				_face_direction_smooth(dir, get_physics_process_delta_time())
	else:
		# No cover found, give up on forced cover for now
		_state = EnemyState.ENGAGE
		_wants_cover = false
		_in_cover = false


func _state_retreating() -> void:
	PerformanceMetrics.on_retreat()

	if player == null or not is_instance_valid(player):
		return

	_in_cover = false
	_current_target = _retreat_spawn_position
	var dist_to_safety = global_position.distance_to(_retreat_spawn_position)
	
	if dist_to_safety < stop_distance * 2.0:
		velocity = Vector2.ZERO
		if animation_player.current_animation != "idle":
			animation_player.play("idle")
		
		hit_points = min(3, hit_points + 1 * get_physics_process_delta_time())
	else:
		var dir = (_retreat_spawn_position - global_position).normalized()
		velocity = velocity.move_toward(dir * (speed * 0.8), acceleration * get_physics_process_delta_time())
		_face_direction_smooth(dir, get_physics_process_delta_time())
		
		if animation_player.current_animation != "run":
			animation_player.play("run")
		
		if randf() < 0.3:
			_try_fire_at_player()


# ======================
#  Cover search
# ======================

func _find_cover() -> void:
	if player == null or not is_instance_valid(player):
		_cover_position = Vector2.ZERO
		return

	var space_state := get_world_2d().direct_space_state
	var best_cover: Vector2 = Vector2.ZERO
	var best_distance: float = INF
	
	for i in range(8):
		var angle = (TAU / 8.0) * i
		var check_direction = Vector2(cos(angle), sin(angle))
		var candidate = global_position + check_direction * (cover_search_range * 0.6)
		
		var query := PhysicsRayQueryParameters2D.create(candidate, player.global_position)
		query.collision_mask = 9  # walls / obstacles
		var result := space_state.intersect_ray(query)
		
		if result:
			var dist_to_player = candidate.distance_to(player.global_position)
			if dist_to_player < best_distance:
				best_distance = dist_to_player
				best_cover = candidate
	
	if best_cover != Vector2.ZERO:
		_cover_position = best_cover
	else:
		_cover_position = global_position


# ======================
#  Texture + cover LOS helpers
# ======================

func _update_cover_texture() -> void:
	# "In cover" for visuals = there is a wall/box between enemy and player
	var behind_cover := _is_behind_cover()

	if behind_cover:
		if sprite and sprite.texture != COVER_TEXTURE:
			sprite.texture = COVER_TEXTURE
	else:
		if sprite and _normal_texture and sprite.texture != _normal_texture:
			sprite.texture = _normal_texture


func _is_behind_cover() -> bool:
	if player == null or not is_instance_valid(player):
		return false

	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, player.global_position)
	query.collision_mask = 9  # same mask you used for walls/boxes in _find_cover()
	var result := space_state.intersect_ray(query)

	# If we hit something on wall layer 9 between enemy and player, we consider that "taking cover"
	return not result.is_empty()


# ======================
#  Dash TO COVER helper (core change)
# ======================

func _dash_to_cover() -> void:
	if _dash_cooldown_left > 0.0:
		return
	if player == null or not is_instance_valid(player):
		return
	if _in_cover:
		return
	if randf() > _actual_dodge_chance:
		return

	# Make sure we know where cover is
	if _cover_position == Vector2.ZERO:
		_find_cover()
	if _cover_position == Vector2.ZERO:
		return

	_wants_cover = true
	_state = EnemyState.TAKING_COVER

	var dir := (_cover_position - global_position).normalized()
	if dir == Vector2.ZERO:
		return

	is_dashing = true
	_dash_dir = dir
	_dash_time_left = dash_duration
	velocity = _dash_dir * dash_speed

	print(name + " is dashing to cover")


# ======================
#  Shooting
# ======================

func _try_fire_at_player() -> void:
	if player == null or not is_instance_valid(player):
		return

	# Do NOT fire if we are behind cover (box/wall blocks LOS to player)
	if _is_behind_cover():
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

	player = attacker
	_aggro = true

	hit_points -= amount

	hurt_sound.play()
	animation_player.play("take_damage")

	# NEW: instead of side-dodging, try dashing TO COVER on hit
	_dash_to_cover()

	if hit_points <= 0:
		PerformanceMetrics.on_enemy_killed("EXT")
		print(name + " (BT enemy) died")
		queue_free()


# ======================
#  Bullet checks – now also only dash-to-cover
# ======================

func _try_dodge() -> void:
	# Only dodge if cooldown is available and random chance succeeds
	if _dash_cooldown_left <= 0.0 and randf() < _actual_dodge_chance:
		# Pick a random perpendicular direction to move away from player
		var to_player = (player.global_position - global_position).normalized()
		var dodge_dir = to_player.rotated(randf_range(-PI / 2.0, PI / 2.0)).normalized()
		
		# Start dash
		is_dashing = true
		_dash_dir = dodge_dir
		_dash_time_left = dash_duration
		velocity = _dash_dir * dash_speed
		
		print(name + " dodged!")
		PerformanceMetrics.on_dodge()

func _check_for_incoming_bullets() -> void:
	var bullets = get_tree().get_nodes_in_group("bullets")
	
	for bullet in bullets:
		if not is_instance_valid(bullet):
			continue
		
		var distance = global_position.distance_to(bullet.global_position)
		if distance >= danger_detection_range:
			continue
		
		var bullet_velocity = bullet.velocity if bullet.has_meta("velocity") else bullet.direction * 1500.0
		var to_bullet = (bullet.global_position - global_position).normalized()
		
		# Bullet roughly heading our way
		if bullet_velocity.normalized().dot(to_bullet) > 0.5:
			_dash_to_cover()
			return   # only try once per frame
		print(name + " predicted dodge!")
		PerformanceMetrics.on_dodge()



func _on_timer_timeout() -> void:
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
#  Detection Area
# ======================

func _on_player_detection_body_entered(body: Node2D) -> void:
	if body is Player and player == null:
		player = body as Player
		print(name + " found the player")


func _on_player_detection_body_exited(body: Node2D) -> void:
	if body is Player and not _aggro and player != null and body == player:
		player = null
		print(name + " lost the player")


func _on_hitbox_area_entered(area: Area2D) -> void:
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
	
	if debug_draw_target and _current_target != Vector2.ZERO:
		var target_local = to_local(_current_target)
		draw_line(Vector2.ZERO, target_local, Color.YELLOW, 2.0)
	
	if debug_draw_target and _state == EnemyState.WANDER and _has_wander_target:
		var wander_local = to_local(_wander_target)
		draw_line(Vector2.ZERO, wander_local, Color.CYAN, 1.5)
	
	if debug_draw_path and nav_agent and not nav_agent.is_navigation_finished():
		var path = nav_agent.get_current_navigation_path()
		if path.size() > 0:
			for i in range(path.size() - 1):
				var p1_local = to_local(path[i])
				var p2_local = to_local(path[i + 1])
				var color = Color.GREEN if _state == EnemyState.WANDER else Color.RED
				draw_line(p1_local, p2_local, color, 2.0)
	
	if debug_draw_state:
		var state_text: String
		match _state:
			EnemyState.WANDER:
				state_text = "WANDER"
			EnemyState.ENGAGE:
				state_text = "ENGAGE"
			EnemyState.TAKING_COVER:
				state_text = "COVER"
			EnemyState.RETREATING:
				state_text = "RETREAT"
			_:
				state_text = "UNKNOWN"
		
		var aggro_text = " [AGGRO]" if _aggro else ""
		var info_text = "%s%s\nHP: %d\nVel: %.0f" % [state_text, aggro_text, hit_points, velocity.length()]
		draw_string(ThemeDB.fallback_font, Vector2(10, -20), info_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

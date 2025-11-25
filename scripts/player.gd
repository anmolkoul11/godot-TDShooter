extends CharacterBody2D
class_name Player

signal died

var speed: float = 300.0
var has_key: bool = false  # Track if player has acquired the key

@export var max_health: int = 4

# Health regen settings
@export var regen_delay: float = 5.0        # wait 5 seconds after damage
@export var regen_per_second: float = 1.0   # heal 1 HP per second

var health: int
var _time_since_damage: float = 0.0
var _regen_accum: float = 0.0

var infinite_health: bool = false  # Toggle with H key
var _h_key_pressed: bool = false   # Track H key state

const BULLET_SCENE  := preload("res://scenes/bullet.tscn")
const MUZZLE_SCENE  := preload("res://scenes/muzzle_flash.tscn") # ok if missing
const TRACER_SCENE  := preload("res://scenes/tracer.tscn")

@export var shoot_cooldown: float = 0.12
@export var tracer_speed_px_per_sec: float = 9000.0  # visual tracer speed
@export var tracer_fade_time: float = 0.06           # fade after reaching target
var _cooldown_left: float = 0.0

@onready var camera_remote_transform: RemoteTransform2D = $CamRemoteTransform
@onready var shoot_raycast: RayCast2D = $ShootRayCast
@onready var shoot_sound: AudioStreamPlayer2D = $ShootSFX
@onready var health_bar: ProgressBar = $HealthBarContainer/HealthBar
@onready var stamina_bar: ProgressBar = $HealthBarContainer/StaminaBar

@export var dash_speed: float = 900.0
@export var dash_duration: float = 0.18
@export var dash_cooldown: float = 0.60
@export var dash_action: StringName = &"Dash"   # Change if you used a different action name

var is_dashing: bool = false
var _dash_time_left: float = 0.0
var _dash_cooldown_left: float = 0.0
var _dash_dir: Vector2 = Vector2.ZERO

func _ready() -> void:
	health = max_health
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = health

func _process(delta: float) -> void:
	look_at(get_global_mouse_position())
	
	if health <= 1:
		PerformanceMetrics.on_player_low_health(delta)

	if Input.is_action_just_pressed("quit_game"):
		get_tree().quit()

	# Toggle infinite health with U key
	if Input.is_key_pressed(KEY_U) and not _h_key_pressed:
		infinite_health = !infinite_health
		_h_key_pressed = true
		print("Infinite health: %s" % ("ON" if infinite_health else "OFF"))
	elif not Input.is_key_pressed(KEY_U):
		_h_key_pressed = false

	_cooldown_left = max(0.0, _cooldown_left - delta)
	if Input.is_action_just_pressed("shoot") and _cooldown_left <= 0.0:
	# For rapid fire rate use --> Input.is_action_pressed("shoot") 
		_fire_bullet()
		_cooldown_left = shoot_cooldown

	# Handle health regeneration
	_handle_regen(delta)

func _physics_process(delta: float) -> void:

	# Dash cooldown
	if _dash_cooldown_left > 0.0:
		_dash_cooldown_left -= delta

	# Movement input
	var move_dir := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	var input_dir := move_dir.normalized()

	# Dash start
	if not is_dashing and _dash_cooldown_left <= 0.0 and Input.is_action_just_pressed(dash_action):
		var dir: Vector2 = input_dir
		if dir == Vector2.ZERO:
			dir = (get_global_mouse_position() - global_position).normalized()
			if dir == Vector2.ZERO:
				dir = velocity.normalized()
		if dir != Vector2.ZERO:
			is_dashing = true
			_dash_dir = dir
			_dash_time_left = dash_duration
			velocity = _dash_dir * dash_speed
			PerformanceMetrics.on_dash_used()

	# Dash / normal movement
	if is_dashing:
		_dash_time_left -= delta
		velocity = _dash_dir * dash_speed
		if _dash_time_left <= 0.0:
			is_dashing = false
			_dash_cooldown_left = dash_cooldown
	else:
		if move_dir != Vector2.ZERO:
			velocity = input_dir * speed
		else:
			velocity.x = move_toward(velocity.x, 0, speed)
			velocity.y = move_toward(velocity.y, 0, speed)

	move_and_slide()
	
	# Update stamina bar based on dash cooldown
	if stamina_bar:
		var stamina_ratio = 1.0 - (_dash_cooldown_left / dash_cooldown)
		stamina_bar.value = stamina_ratio


func _fire_bullet() -> void:
	PerformanceMetrics.on_player_fired()
	var bullet: Bullet = BULLET_SCENE.instantiate()
	var scene_root: Node = get_tree().get_current_scene()
	var bullets_node: Node = scene_root.get_node_or_null("Bullets")
	if bullets_node:
		bullets_node.add_child(bullet)
	else:
		scene_root.add_child(bullet)

	var start: Vector2 = shoot_raycast.global_position
	var dir: Vector2 = (get_global_mouse_position() - start).normalized()
	bullet.setup(self, start, dir)

	# === INSTANT TRACER ===
	if TRACER_SCENE:
		# use the existing ShootRayCast to find the hit point; fallback to fixed length
		shoot_raycast.force_raycast_update()
		var end_point: Vector2 = start + dir * 700.0
		if shoot_raycast.is_colliding():
			end_point = shoot_raycast.get_collision_point()

		var tracer: Tracer = TRACER_SCENE.instantiate()
		scene_root.add_child(tracer)
		# Configure tracer to travel at a consistent speed and then fade
		tracer.speed_px_per_sec = tracer_speed_px_per_sec
		tracer.fade_time = tracer_fade_time
		tracer.fire(start, end_point)

	if MUZZLE_SCENE:
		var flash: Node = MUZZLE_SCENE.instantiate()
		scene_root.add_child(flash)
		flash.fire_at(start, dir.angle())

	# Optional camera shake (if your Camera2D has the CameraShake script and is in group "main_camera")
	var cam: Node = get_tree().get_first_node_in_group("main_camera")
	if cam and cam.has_method("shake"):
		cam.shake(6.0, 0.08)

	if shoot_sound:
		shoot_sound.play()


func _on_hitbox_body_entered(body: Node2D) -> void:
	# If any enemy body touches the player's hitbox, the player dies immediately
	if body is Enemy or body is EnemyBT or body is ExtendedBTEnemy:
		died.emit()
		queue_free()


func _handle_regen(delta: float) -> void:
	# Already full, nothing to do
	if health >= max_health:
		_time_since_damage = 0.0
		_regen_accum = 0.0
		return

	# Time since last damage
	_time_since_damage += delta

	# Wait until regen_delay has passed
	if _time_since_damage < regen_delay:
		return

	# Accumulate fractional healing
	_regen_accum += delta * regen_per_second

	# Heal in whole HP steps
	while _regen_accum >= 1.0 and health < max_health:
		health += 1
		_regen_accum -= 1.0
		print("Player regenerated to health = %d" % health)
		_update_health_bar()

	# Stop when full
	if health >= max_health:
		_time_since_damage = 0.0
		_regen_accum = 0.0


func take_damage(amount: int, attacker: CharacterBody2D = null) -> void:
	if amount <= 0:
		return

	# If infinite health is enabled, take no damage
	if infinite_health:
		return

	health -= amount
	PerformanceMetrics.on_player_damaged(amount)

	var attacker_name: String = "Unknown"
	if attacker != null:
		attacker_name = attacker.name
	print("Player hit by %s, health = %d" % [attacker_name, health])

	# Update health bar
	_update_health_bar()

	# Reset regen timer and accumulator on hit
	_time_since_damage = 0.0
	_regen_accum = 0.0

	if health <= 0:
		died.emit()
		queue_free()


func _update_health_bar() -> void:
	if health_bar:
		health_bar.value = max(0, health)
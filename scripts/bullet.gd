extends Area2D
class_name Bullet

@export var speed: float = 1400.0
@export var damage: int = 1
@export var max_distance: float = 2200.0
@export var debug_logs: bool = false

var _dir: Vector2 = Vector2.RIGHT
var _traveled: float = 0.0
var _shooter: CharacterBody2D   # can be Player OR Enemy

@onready var _ray: RayCast2D = $RayCast2D

func setup(shooter: CharacterBody2D, start_pos: Vector2, direction: Vector2) -> void:
	_shooter = shooter
	global_position = start_pos
	_dir = direction.normalized()
	rotation = _dir.angle()

	if debug_logs:
		print("[Bullet] Spawned by %s at %s dir=%s" % [shooter.name, start_pos, _dir])

func _ready() -> void:
	# Make sure we get collision signals
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

	# Ensure raycast is active
	_ray.enabled = true
	_ray.collide_with_areas = true
	_ray.collide_with_bodies = true

	# VERY IMPORTANT: make sure bullets can hit player + enemies + walls.
	# In your project:
	#   Layer 1 → world/obstacles
	#   Layer 2 → Player  (collision_layer = 2)
	#   Layer 3 → Enemy   (collision_layer = 4)
	set_collision_mask_value(1, true)  # world / crates
	set_collision_mask_value(2, true)  # player
	set_collision_mask_value(3, true)  # enemies

func _physics_process(delta: float) -> void:
	var step := speed * delta

	# Raycast one step ahead to get instant hits
	_ray.target_position = _dir * step
	_ray.force_raycast_update()
	if _ray.is_colliding():
		var collider := _ray.get_collider()
		_hit(collider)
		return

	# Move the bullet
	global_position += _dir * step
	_traveled += step

	if _traveled >= max_distance:
		queue_free()

func _on_body_entered(body: Node) -> void:
	_hit(body)

func _on_area_entered(area: Area2D) -> void:
	_hit(area)

func _hit(target: Object) -> void:
	if _shooter == null:
		return

	# Don't hit our own shooter
	if target == _shooter:
		return

	# === Player shooting enemies ===
	if target is Enemy and _shooter is Player:
		if debug_logs:
			print("[Bullet] Damaging enemy: ", target.name)
		(target as Enemy).take_damage(damage, _shooter as Player)
		queue_free()
		return

	# === Enemy shooting player ===
	if target is Player and _shooter is Enemy:
		if debug_logs:
			print("[Bullet] Damaging player: ", target.name)
		(target as Player).take_damage(damage, _shooter as Enemy)
		queue_free()
		return

	# Hit walls / obstacles / anything else solid
	if target is CollisionObject2D:
		if debug_logs:
			print("[Bullet] Hit obstacle: ", target.name)
		queue_free()

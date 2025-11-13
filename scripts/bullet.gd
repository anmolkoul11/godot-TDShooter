extends Area2D
class_name Bullet

@export var speed: float = 1400.0
@export var damage: int = 1
@export var max_distance: float = 2200.0
@export var debug_logs: bool = false

var _dir: Vector2 = Vector2.RIGHT
var _traveled: float = 0.0
var _shooter: CharacterBody2D   # can be Player OR Enemy
var _consumed: bool = false     # prevent double-processing within the same frame

@onready var _ray: RayCast2D = $RayCast2D

func setup(shooter: CharacterBody2D, start_pos: Vector2, direction: Vector2) -> void:
	_shooter = shooter
	global_position = start_pos
	_dir = direction.normalized()
	rotation = _dir.angle()

	# Configure a broad collision mask so both ray and area detect all relevant targets
	# Layers (from your project):
	# 1 = world/boxes, 2 = player, 3 = player_hitbox, 4 = enemy, 5 = enemy_hitbox
	var broad_mask := (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4)
	collision_mask = broad_mask
	if _ray:
		_ray.collision_mask = broad_mask

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
	_ray.hit_from_inside = true
    # Collision mask is set in setup() based on shooter type

func _physics_process(delta: float) -> void:
	var step := speed * delta

	# Raycast one step ahead to get instant hits
	# RayCast2D target_position is LOCAL; the bullet node is already rotated to _dir
	# so cast forward along local +X to avoid double-rotating the direction
	_ray.target_position = Vector2.RIGHT * step
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
	if _consumed:
		return
	if _shooter == null:
		return

	# Resolve to owning actor (handles hitbox Areas)
	var actor := _find_actor(target)

	# Don't hit our own shooter
	if actor == _shooter or target == _shooter:
		return

	# === Player shooting enemies ===
	if (actor is Enemy or target is Enemy) and _shooter is Player:
		if debug_logs:
			var enemy_name := ((actor as Enemy).name) if actor is Enemy else ((target as Enemy).name)
			print("[Bullet] Damaging enemy: ", enemy_name)
		var enemy := (actor as Enemy) if actor is Enemy else (target as Enemy)
		enemy.take_damage(damage, _shooter as Player)
		_consumed = true
		queue_free()
		return

	# === Enemy shooting player ===
	if (actor is Player or target is Player) and _shooter is Enemy:
		if debug_logs:
			var player_name := ((actor as Player).name) if actor is Player else ((target as Player).name)
			print("[Bullet] Damaging player: ", player_name)
		var player := (actor as Player) if actor is Player else (target as Player)
		player.take_damage(damage, _shooter as Enemy)
		_consumed = true
		queue_free()
		return

	# Hit walls / obstacles / anything else solid
	if target is CollisionObject2D:
		if debug_logs:
			print("[Bullet] Hit obstacle: ", target.name)
		_consumed = true
		queue_free()

func _find_actor(target: Object) -> Node:
	# If it's directly an actor type
	if target is Enemy or target is Player:
		return target as Node
	# If it's a node (e.g., Area2D hitbox), climb to find the actor
	if target is Node:
		var n: Node = target
		while n:
			if n is Enemy or n is Player:
				return n
			n = n.get_parent()
	return null


extends Area2D
class_name Bullet

@export var speed: float = 1400.0
@export var damage: int = 1
@export var max_distance: float = 2200.0
@export var debug_logs: bool = false

var _dir: Vector2 = Vector2.RIGHT
var _traveled: float = 0.0
var _shooter: CharacterBody2D = null  # Player, Enemy, EnemyBT, or ExtendedBTEnemy
var _consumed: bool = false           # prevent double-processing in the same frame

@onready var _ray: RayCast2D = $RayCast2D


func setup(shooter: CharacterBody2D, start_pos: Vector2, direction: Vector2) -> void:
	_shooter = shooter
	global_position = start_pos
	_dir = direction.normalized()
	rotation = _dir.angle()

	# 1 = world/boxes, 2 = player, 3 = player_hitbox, 4 = enemy, 5 = enemy_hitbox
	var broad_mask: int = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4)
	collision_mask = broad_mask
	if _ray:
		_ray.collision_mask = broad_mask

	if debug_logs:
		var shooter_name: String = "Unknown"
		if shooter != null:
			shooter_name = shooter.name
		print("[Bullet] Spawned by %s at %s dir=%s" % [shooter_name, start_pos, _dir])


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

	if _ray:
		_ray.enabled = true
		_ray.collide_with_areas = true
		_ray.collide_with_bodies = true
		_ray.hit_from_inside = true


func _physics_process(delta: float) -> void:
	if _consumed:
		return

	var step: float = speed * delta

	if _ray:
		_ray.target_position = Vector2.RIGHT * step
		_ray.force_raycast_update()
		if _ray.is_colliding():
			var collider: Object = _ray.get_collider()
			_hit(collider)
			return

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

	var actor: Node = _find_actor(target)

	# Don't hit our own shooter
	if actor != null and actor == _shooter:
		return
	if target == _shooter:
		return

	var shooter_is_player: bool = _shooter is Player
	var shooter_is_enemy_side: bool = (_shooter is Enemy) or (_shooter is EnemyBT) or (_shooter is ExtendedBTEnemy)

	# === Player bullets hitting enemies (Enemy, EnemyBT, or ExtendedBTEnemy) ===
	if shooter_is_player and (
		(actor is Enemy) or (actor is EnemyBT) or (actor is ExtendedBTEnemy) or
		(target is Enemy) or (target is EnemyBT) or (target is ExtendedBTEnemy)
	):
		var enemy: CharacterBody2D = null
		if actor is Enemy or actor is EnemyBT or actor is ExtendedBTEnemy:
			enemy = actor as CharacterBody2D
		elif target is Enemy or target is EnemyBT or target is ExtendedBTEnemy:
			enemy = target as CharacterBody2D

		if enemy != null:
			if debug_logs:
				var enemy_name: String = enemy.name
				print("[Bullet] Damaging enemy: ", enemy_name)
			enemy.take_damage(damage, _shooter as Player)
			_consumed = true
			
			var shooter_type := "FSM"
			if _shooter is EnemyBT: shooter_type = "BT"
			elif _shooter is ExtendedBTEnemy: shooter_type = "EXT"
			PerformanceMetrics.on_enemy_bullet_hit_player(shooter_type)

			queue_free()
			PerformanceMetrics.on_player_bullet_hit_enemy()
			return

	# === Enemy / EnemyBT / ExtendedBTEnemy bullets hitting player ===
	if shooter_is_enemy_side and ((actor is Player) or (target is Player)):
		var player: Player = null
		if actor is Player:
			player = actor as Player
		elif target is Player:
			player = target as Player

		if player != null:
			if debug_logs:
				var player_name: String = player.name
				print("[Bullet] Damaging player: ", player_name)
			
			var shooter_type := "FSM"
			if _shooter is EnemyBT: shooter_type = "BT"
			elif _shooter is ExtendedBTEnemy: shooter_type = "EXT"

			PerformanceMetrics.on_enemy_bullet_hit_player(shooter_type)


			# Player.take_damage expects CharacterBody2D as 2nd arg
			if _shooter is Enemy:
				player.take_damage(damage, _shooter as Enemy)
			elif _shooter is EnemyBT:
				player.take_damage(damage, _shooter as EnemyBT)
			elif _shooter is ExtendedBTEnemy:
				player.take_damage(damage, _shooter as ExtendedBTEnemy)

			_consumed = true
			queue_free()
			return

	# Hit walls / obstacles / anything else solid
	if target is CollisionObject2D:
		if debug_logs:
			var col: CollisionObject2D = target as CollisionObject2D
			var col_name: String = col.name
			print("[Bullet] Hit obstacle: ", col_name)
		_consumed = true
		queue_free()


func _find_actor(target: Object) -> Node:
	# Direct actors
	if target is Enemy or target is EnemyBT or target is Player or target is ExtendedBTEnemy:
		return target as Node

	# Hitbox Areas etc: climb up the parent chain
	if target is Node:
		var n: Node = target
		while n:
			if n is Enemy or n is EnemyBT or n is Player or n is ExtendedBTEnemy:
				return n
			n = n.get_parent()

	return null

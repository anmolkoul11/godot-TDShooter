extends Node
class_name EnemyShooter

# Preload scenes
const BULLET_SCENE := preload("res://scenes/bullet.tscn")
const MUZZLE_SCENE := preload("res://scenes/muzzle_flash.tscn")
const TRACER_SCENE := preload("res://scenes/tracer.tscn")

# Reference to the enemy using this shooter
var enemy: CharacterBody2D = null

# Export parameters
@export var fire_range: float = 800.0
@export var fire_interval: float = 0.9

# Internal state
var fire_cooldown_left: float = 0.0


func _ready() -> void:
	# Get parent enemy reference
	if get_parent() is CharacterBody2D:
		enemy = get_parent() as CharacterBody2D


func _process(delta: float) -> void:
	# Decrement cooldown
	fire_cooldown_left = max(0.0, fire_cooldown_left - delta)


func try_fire_at_target(shooter: CharacterBody2D, target: Node2D) -> bool:
	"""
	Attempt to fire at a target.
	Returns true if shot fired, false otherwise.
	"""
	if fire_cooldown_left > 0.0:
		return false
	if target == null or not is_instance_valid(target):
		return false

	var to_target: Vector2 = target.global_position - shooter.global_position
	var distance: float = to_target.length()
	if distance > fire_range:
		return false

	var dir: Vector2 = to_target.normalized()

	# Slight inaccuracy for balance (40-90% accuracy)
	var accuracy: float = randf_range(0.4, 0.9)
	var max_spread: float = (1.0 - accuracy) * 0.25
	var spread: float = randf_range(-max_spread, max_spread)
	dir = dir.rotated(spread)

	var start: Vector2 = shooter.global_position
	var scene_root: Node = get_tree().get_current_scene()

	# Spawn bullet
	var bullet: Bullet = BULLET_SCENE.instantiate()
	var bullets_node: Node = scene_root.get_node_or_null("Bullets")
	if bullets_node:
		bullets_node.add_child(bullet)
	else:
		scene_root.add_child(bullet)
	
	var type := "FSM"
	if enemy is EnemyBT: type = "BT"
	elif enemy is ExtendedBTEnemy: type = "EXT"

	PerformanceMetrics.on_enemy_bullet_fired(type)

	bullet.setup(shooter, start, dir)

	# Spawn red tracer (enemy shots are red)
	if TRACER_SCENE:
		var tracer: Node2D = TRACER_SCENE.instantiate()
		scene_root.add_child(tracer)
		tracer.modulate = Color(1.0, 0.0, 0.0)
		var end_point: Vector2 = start + dir * fire_range
		if tracer.has_method("fire"):
			tracer.call("fire", start, end_point)

	# Spawn muzzle flash
	if MUZZLE_SCENE:
		var flash: Node = MUZZLE_SCENE.instantiate()
		scene_root.add_child(flash)
		if flash.has_method("fire_at"):
			flash.call("fire_at", start, dir.angle())

	# Reset cooldown
	fire_cooldown_left = fire_interval
	
	if enemy:
		print("%s fired at target with accuracy %.2f" % [enemy.name, accuracy])

	return true


func can_fire() -> bool:
	"""Check if shooter is ready to fire"""
	return fire_cooldown_left <= 0.0


func get_cooldown_remaining() -> float:
	"""Get remaining cooldown in seconds"""
	return fire_cooldown_left

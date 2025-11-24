extends Node2D
class_name TurtleBox

@export var pickup_margin: float = 270.0   # 10px all around

@onready var turtle: Turtle = $Turtle
@onready var _box_shape: CollisionShape2D = $CollisionShape2D
@onready var _pickup_zone: Area2D = $TurtlePickupZone
@onready var _pickup_shape: CollisionShape2D = $TurtlePickupZone/CollisionShape2D

func _ready() -> void:
	# Make the pickup zone centered on the box and slightly larger
	_configure_pickup_zone()

	if _pickup_zone and not _pickup_zone.body_entered.is_connected(_on_pickup_zone_body_entered):
		_pickup_zone.body_entered.connect(_on_pickup_zone_body_entered)


func _configure_pickup_zone() -> void:
	if _box_shape == null or _pickup_shape == null:
		return

	# Align pickup zone position with box collider (same origin)
	_pickup_zone.position = _box_shape.position

	var src_shape := _box_shape.shape
	if src_shape is RectangleShape2D:
		var rect := src_shape as RectangleShape2D
		var new_rect := RectangleShape2D.new()
		new_rect.extents = rect.extents + Vector2(pickup_margin, pickup_margin)
		_pickup_shape.shape = new_rect
	elif src_shape is CircleShape2D:
		var circ := src_shape as CircleShape2D
		var new_circ := CircleShape2D.new()
		new_circ.radius = circ.radius + pickup_margin
		_pickup_shape.shape = new_circ
	else:
		# Fallback: if it’s some other shape, just reuse it (no expand)
		_pickup_shape.shape = src_shape.duplicate()

	# Make sure the pickup zone only sees the player
	_pickup_zone.collision_layer = 0
	# Assuming player is on physics layer 2 → (1 << 1)
	_pickup_zone.collision_mask = 1 << 1


func _on_pickup_zone_body_entered(body: Node2D) -> void:
	if not (body is Player):
		return
	if turtle == null or turtle.is_carried:
		return

	turtle.call_deferred("pick_up", body)

extends Area2D
class_name Bullet

@export var speed: float = 1400.0
@export var damage: int = 1
@export var max_distance: float = 2200.0
@export var debug_logs: bool = false

var _dir: Vector2 = Vector2.RIGHT
var _traveled := 0.0
var _shooter: Player

@onready var _ray: RayCast2D = $RayCast2D

func setup(shooter: Player, start_pos: Vector2, direction: Vector2) -> void:
	_shooter = shooter
	global_position = start_pos
	_dir = direction.normalized()
	rotation = _dir.angle()

func _ready() -> void:
	if not is_connected("body_entered", Callable(self, "_on_body_entered")):
		body_entered.connect(_on_body_entered)
	if not is_connected("area_entered", Callable(self, "_on_area_entered")):
		area_entered.connect(_on_area_entered)
	_ray.enabled = true
	_ray.collide_with_areas = true
	_ray.collide_with_bodies = true

func _physics_process(delta: float) -> void:
	var step := speed * delta
	_ray.target_position = _dir * step
	_ray.force_raycast_update()
	if _ray.is_colliding():
		_hit(_ray.get_collider())
		return
	global_position += _dir * step
	_traveled += step
	if _traveled >= max_distance:
		queue_free()

func _on_body_entered(body: Node) -> void: _hit(body)
func _on_area_entered(area: Area2D) -> void: _hit(area)

func _hit(target: Object) -> void:
	if target == _shooter:
		return
	if target is Enemy or target is EnemyBT:
		if debug_logs: print("[Bullet] Damaging enemy: ", target.name)
		target.take_damage(damage, _shooter)
		queue_free()
		return
	if target is CollisionObject2D:
		queue_free()

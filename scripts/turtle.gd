extends Area2D
class_name Turtle

signal picked_up

var is_carried: bool = false
var carrier: Player = null

@export var backpack_offset: Vector2 = Vector2(0, -32)

func _ready() -> void:
	# pickup is triggered by TurtleBox or world, not here
	pass


func pick_up(p: Player) -> void:
	if is_carried:
		return

	carrier = p
	is_carried = true

	var old_parent := get_parent()
	if old_parent:
		old_parent.remove_child(self)
	carrier.add_child(self)

	# Put turtle on backpack
	position = backpack_offset

	# You can change this to (0.5, 0.5) if you want it smaller
	scale = Vector2(1, 1)

	print("[Turtle] Picked up by %s" % carrier.name)
	picked_up.emit()


func drop_to(new_parent: Node2D, local_pos: Vector2 = Vector2.ZERO) -> void:
	if not is_carried:
		return

	is_carried = false
	carrier = null

	var old_parent := get_parent()
	if old_parent:
		old_parent.remove_child(self)
	new_parent.add_child(self)
	position = local_pos

	print("[Turtle] Dropped at: %s" % new_parent.name)


func _process(_delta: float) -> void:
	if is_carried and carrier:
		var t := Time.get_ticks_msec() / 1000.0
		var bob := sin(t * 6.0) * 3.0
		position = backpack_offset + Vector2(0, bob)

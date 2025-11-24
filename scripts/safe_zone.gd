extends Area2D
class_name SafeZone

signal turtle_delivered

func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	# Only the player can deliver the turtle
	if not (body is Player):
		return

	# Look for carried turtle as a child of the player
	for child in body.get_children():
		if child is Turtle and child.is_carried:
			print("[SafeZone] Turtle delivered by player")
			turtle_delivered.emit()
			return

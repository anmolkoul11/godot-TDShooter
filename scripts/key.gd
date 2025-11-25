extends Area2D
class_name Key

signal picked_up

var is_picked_up: bool = false

func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not (body is Player):
		return
	if is_picked_up:
		return
	
	# Mark as picked up
	is_picked_up = true
	body.has_key = true
	
	print("[Key] Picked up by %s" % body.name)
	picked_up.emit()
	
	# Dissapear the key
	queue_free()

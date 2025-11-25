extends Node2D
class_name Cage

signal cage_opened

@export var gate_slide_duration: float = 0.6
@export var gate_dissapear_delay: float = 0.3  # Time after slide before dissapear

var _gate: Node2D = null
var _gate_collision: CollisionShape2D = null
var _gate_blocker: StaticBody2D = null
var _is_open: bool = false

func _ready() -> void:
	print("[Cage] _ready() called")
	# Get references to gate components
	_gate = get_node_or_null("Gate")
	if _gate:
		print("[Cage] Found gate node")
		_gate_collision = _gate.get_node_or_null("CollisionShape2D")
		_gate_blocker = _gate.get_node_or_null("GateBlocker")
		print("[Cage] Gate collision: ", _gate_collision, " Gate blocker: ", _gate_blocker)
	else:
		print("[Cage] ERROR: Gate node not found!")
	
	# Listen for player touching gate area
	var gate_area = get_node_or_null("Gate")
	if gate_area and gate_area is Area2D:
		print("[Cage] Gate is Area2D, connecting signal")
		if not gate_area.body_entered.is_connected(_on_gate_body_entered):
			gate_area.body_entered.connect(_on_gate_body_entered)
			print("[Cage] Signal connected successfully")
	else:
		print("[Cage] ERROR: Gate is not Area2D or not found")


func _on_gate_body_entered(body: Node2D) -> void:
	print("[Cage] Gate area touched by: ", body.name)
	if not (body is Player):
		print("[Cage] Not a player, ignoring")
		return
	if _is_open:
		print("[Cage] Gate already open")
		return
	
	# Check if player has key
	print("[Cage] Player has_key: ", body.has_key)
	if not body.has_key:
		print("[Cage] Player tried to open gate but has no key!")
		return
	
	# Open the gate
	_open_gate()


func _open_gate() -> void:
	_is_open = true
	print("[Cage] Gate opening!")
	
	if not _gate:
		return
	
	# Disable ALL blocking - use call_deferred to avoid physics flush error
	if _gate_blocker:
		_gate_blocker.call_deferred("queue_free")
	if _gate_collision:
		_gate_collision.set_deferred("disabled", true)
	
	# Slide gate to the right (X translation)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	
	# Slide the gate 100 pixels to the right over gate_slide_duration
	tween.tween_property(_gate, "position:x", _gate.position.x + 100.0, gate_slide_duration)
	
	# Dissapear after delay
	tween.tween_callback(func():
		_dissapear_gate()
	)
	
	cage_opened.emit()


func _dissapear_gate() -> void:
	if not _gate:
		return
	
	# Tween gate alpha to 0 (fade out)
	var fade_tween := create_tween()
	fade_tween.set_trans(Tween.TRANS_SINE)
	fade_tween.set_ease(Tween.EASE_IN)
	fade_tween.tween_property(_gate, "modulate:a", 0.0, 0.3)
	
	# After fade, free the gate
	fade_tween.tween_callback(_gate.queue_free)

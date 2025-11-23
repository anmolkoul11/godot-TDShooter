extends Node
class_name DebugManager

# Global debug toggle
var debug_mode_enabled: bool = false

# References to all enemies
var all_enemies: Array = []

func _ready() -> void:
	# Listen for input to toggle debug mode
	pass


func _input(event: InputEvent) -> void:
	# Press 'I' to toggle debug visualization
	if event is InputEventKey and event.pressed and event.keycode == KEY_I:
		toggle_debug_mode()


func toggle_debug_mode() -> void:
	debug_mode_enabled = !debug_mode_enabled
	
	# Find all enemy instances in the scene
	_update_enemies_list()
	
	# Toggle debug for each enemy based on its type
	for enemy in all_enemies:
		if is_instance_valid(enemy):
			if enemy is ExtendedBTEnemy:
				enemy.debug_draw_enabled = debug_mode_enabled
			else:
				# FSM (Enemy) and BT (EnemyBT) use show_path
				enemy.show_path = debug_mode_enabled
	
	var status = "ON" if debug_mode_enabled else "OFF"
	print("[DebugManager] Debug visualization turned %s (%d enemies)" % [status, all_enemies.size()])


func _update_enemies_list() -> void:
	all_enemies.clear()
	var root = get_tree().get_current_scene()
	_find_enemies_recursive(root)


func _find_enemies_recursive(node: Node) -> void:
	# Find all three enemy types
	if node is Enemy or node is EnemyBT or node is ExtendedBTEnemy:
		all_enemies.append(node)
	
	for child in node.get_children():
		_find_enemies_recursive(child)


func enable_debug() -> void:
	if not debug_mode_enabled:
		toggle_debug_mode()


func disable_debug() -> void:
	if debug_mode_enabled:
		toggle_debug_mode()

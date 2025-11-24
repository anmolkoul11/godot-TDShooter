extends Node
class_name SquadCoordinator

var player: Player = null
var enemies: Array = []


func register_enemy(enemy: Node) -> void:
	if not enemies.has(enemy):
		enemies.append(enemy)


func unregister_enemy(enemy: Node) -> void:
	enemies.erase(enemy)


func get_group_center() -> Vector2:
	if enemies.is_empty():
		return Vector2.ZERO

	var sum := Vector2.ZERO
	var count := 0
	for e in enemies:
		if is_instance_valid(e):
			sum += e.global_position
			count += 1

	if count == 0:
		return Vector2.ZERO

	return sum / float(count)


func get_flank_target_position(enemy: Node, flank_radius: float) -> Vector2:
	if player == null or not is_instance_valid(player):
		return enemy.global_position

	var center := get_group_center()
	var dir := (player.global_position - center).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT

	var index := enemies.find(enemy)
	if index == -1:
		index = 0

	# Base 4 cardinal directions
	var base_offsets: Array[Vector2] = [
		dir,                          # Front
		dir.rotated(-PI / 2.0),       # Left
		dir.rotated(PI / 2.0),        # Right
		-dir,                         # Back
	]

	# Determine which slot and layer this enemy should occupy
	var slot_index := index % 4                    # Which cardinal direction (0-3)
	var layer := int(index / 4.0)                  # Which layer (0=closest, 1=next ring, etc)
	
	# First 4 enemies: inner ring at base flank_radius
	# Next 4 enemies: outer ring at 1.5x flank_radius
	# Next 4 enemies: outer ring at 2x flank_radius, etc
	var distance_multiplier: float = 1.0 + (float(layer) * 0.5)
	var adjusted_radius: float = flank_radius * distance_multiplier
	
	var slot := base_offsets[slot_index]
	return player.global_position - slot * adjusted_radius

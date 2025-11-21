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

	var offsets: Array[Vector2] = [
		dir,
		dir.rotated(-PI / 2.0),
		dir.rotated(PI / 2.0),
		-dir,
	]

	var slot := offsets[index % offsets.size()]
	return player.global_position - slot * flank_radius

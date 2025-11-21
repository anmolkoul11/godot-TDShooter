extends Node2D

const STAGE1_ENEMY_NAMES := ["Enemy", "Enemy1", "Enemy2", "Enemy4(BT)", "Enemy5(BT)"]
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const BT_ENEMY_SCENE := preload("res://scenes/enemy_bt_extended.tscn")

# Stage-2 spawn offsets relative to player
const BT_SPAWN_OFFSETS := [
	Vector2(-700, -400),
	Vector2(700, -400),
	Vector2(-700, 400),
	Vector2(700, 400),
]

@onready var player: Player = $Player
@onready var main_camera: Camera2D = $MainCamera

var squad_coordinator: SquadCoordinator

var _in_stage2: bool = false
var _stage2_transition_started: bool = false

# We copy this from any Stage-1 enemy so Stage-2 enemies look identical in size
var _bt_enemy_scale: Vector2 = Vector2.ONE


func _ready() -> void:
	player.died.connect(_on_player_died)
	player.camera_remote_transform.remote_path = main_camera.get_path()

	# Shared coordinator for Stage-2 BT enemies
	squad_coordinator = SquadCoordinator.new()
	squad_coordinator.name = "SquadCoordinator"
	add_child(squad_coordinator)
	squad_coordinator.player = player

	# Capture visual scale from one of the Stage-1 enemies
	for enemy_name in STAGE1_ENEMY_NAMES:
		if has_node(enemy_name):
			var e := get_node(enemy_name) as Node2D
			_bt_enemy_scale = e.scale
			break


func _process(_delta: float) -> void:
	if _in_stage2 or _stage2_transition_started:
		return

	if _are_stage1_enemies_cleared():
		_stage2_transition_started = true
		_start_stage2_transition()


func _are_stage1_enemies_cleared() -> bool:
	for enemy_name in STAGE1_ENEMY_NAMES:
		if has_node(enemy_name):
			return false
	return true


func _start_stage2_transition() -> void:
	print("Stage 1 cleared → transitioning to Stage 2")

	# CanvasLayer so fade is guaranteed on top of everything
	var layer := CanvasLayer.new()
	layer.name = "Stage2FadeLayer"
	add_child(layer)

	var fade := ColorRect.new()
	fade.name = "Stage2Fade"
	fade.color = Color(0, 0, 0, 0)
	fade.anchor_left = 0.0
	fade.anchor_top = 0.0
	fade.anchor_right = 1.0
	fade.anchor_bottom = 1.0
	fade.offset_left = 0.0
	fade.offset_top = 0.0
	fade.offset_right = 0.0
	fade.offset_bottom = 0.0

	layer.add_child(fade)

	# Fade to black over 1.2 seconds, THEN start Stage 2
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 1.0, 1.2)
	tween.tween_callback(Callable(self, "_enter_stage2"))


func _enter_stage2() -> void:
	_in_stage2 = true
	print("Stage 2 started: spawning BT enemies")

	# IMPORTANT: we do NOT move the player. They stay exactly where Stage 1 ended.
	for offset in BT_SPAWN_OFFSETS:
		var enemy := BT_ENEMY_SCENE.instantiate()
		get_tree().current_scene.add_child(enemy)

		# Same position logic as before – around the player
		enemy.global_position = player.global_position + offset

		# Match Stage-1 enemy size
		if enemy is Node2D:
			enemy.scale = _bt_enemy_scale

	# Fade back in and then remove fade layer
	var layer: CanvasLayer = get_node_or_null("Stage2FadeLayer")
	if layer:
		var fade: ColorRect = layer.get_node_or_null("Stage2Fade")
		if fade:
			var tween := create_tween()
			tween.tween_property(fade, "color:a", 0.0, 1.2)
			tween.tween_callback(layer.queue_free)


func _on_player_died() -> void:
	print("game over!")
	get_tree().create_timer(3.0).timeout.connect(get_tree().reload_current_scene)

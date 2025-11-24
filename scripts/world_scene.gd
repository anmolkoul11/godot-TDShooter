extends Node2D

const STAGE1_ENEMY_NAMES := ["Enemy", "Enemy1", "Enemy2", "Enemy4(BT)", "Enemy5(BT)"]
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const BT_ENEMY_SCENE := preload("res://scenes/enemy_bt_extended.tscn")
const DEBUG_MANAGER_SCRIPT := preload("res://scripts/debug_manager.gd")
const TURTLE_BOX_SCENE := preload("res://scenes/turtle_box.tscn")
const SAFE_ZONE_SCENE := preload("res://scenes/safe_zone.tscn")

# Stage-2 spawn offsets relative to player
const BT_SPAWN_OFFSETS := [
	Vector2(-700, -400),
	Vector2(700, -400),
	Vector2(-700, 400),
	Vector2(700, 400),
	Vector2(0, -600),
	Vector2(0, 600),
]

@onready var player: Player = $Player
@onready var main_camera: Camera2D = $MainCamera

var squad_coordinator: SquadCoordinator

var _in_stage2: bool = false
var _stage2_transition_started: bool = false

# We copy this from any Stage-1 enemy so Stage-2 enemies look identical in size
var _bt_enemy_scale: Vector2 = Vector2.ONE

var _turtle: Turtle = null
var _turtle_box: TurtleBox = null
var _safe_zone: SafeZone = null


func _ready() -> void:
	player.died.connect(_on_player_died)
	player.camera_remote_transform.remote_path = main_camera.get_path()

	# Shared coordinator for Stage-2 BT enemies
	squad_coordinator = SquadCoordinator.new()
	squad_coordinator.name = "SquadCoordinator"
	add_child(squad_coordinator)
	squad_coordinator.player = player
	
	# Create and add debug manager for visualization
	var debug_manager = Node.new()
	debug_manager.set_script(DEBUG_MANAGER_SCRIPT)
	debug_manager.name = "DebugManager"
	add_child(debug_manager)

	# Capture visual scale from one of the Stage-1 enemies
	for enemy_name in STAGE1_ENEMY_NAMES:
		if has_node(enemy_name):
			var e := get_node(enemy_name) as Node2D
			_bt_enemy_scale = e.scale
			break

	# Spawn special turtle box for Level 1
	_spawn_turtle_box()


func _spawn_turtle_box() -> void:
	_turtle_box = TURTLE_BOX_SCENE.instantiate()
	add_child(_turtle_box)

	# Place the crate somewhere in Level 1.
	_turtle_box.global_position = Vector2(2500, 1400)
	print("[World] TurtleBox spawned at ", _turtle_box.global_position)

	# Grab the turtle from inside the crate, and hook level-complete logic
	_turtle = _turtle_box.turtle
	if _turtle:
		_turtle.picked_up.connect(_on_turtle_picked_up)
	else:
		push_warning("TurtleBox has no Turtle child!")


func _on_turtle_picked_up() -> void:
	print("[World] LEVEL 1 COMPLETE – Turtle rescued!")

	# Don't double-trigger
	if _stage2_transition_started or _in_stage2:
		return

	_stage2_transition_started = true
	_start_stage2_transition()


func _process(_delta: float) -> void:
	# IMPORTANT:
	# We NO LONGER start Stage 2 when all Stage 1 enemies are cleared.
	# Stage 2 should ONLY be triggered by picking up the turtle.
	pass


# Kept for future, but unused now
func _are_stage1_enemies_cleared() -> bool:
	for enemy_name in STAGE1_ENEMY_NAMES:
		if has_node(enemy_name):
			return false
	return true


func _start_stage2_transition() -> void:
	print("Turtle picked up → transitioning to Stage 2")

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
	print("Stage 2 started: cleaning Stage 1 enemies, spawning BT enemies + safe zone")

	# Check if player is still valid (might have been killed by enemy contact)
	if not is_instance_valid(player):
		print("Player was killed during stage transition!")
		return

	# 1) REMOVE ANY REMAINING STAGE-1 ENEMIES
	for enemy_name in STAGE1_ENEMY_NAMES:
		if has_node(enemy_name):
			var e := get_node(enemy_name)
			if is_instance_valid(e):
				e.queue_free()
				print("[World] Removed Stage 1 enemy: ", enemy_name)

	# 2) SPAWN THE 4 EXTENDED BT ENEMIES AROUND THE PLAYER (original behavior)
	for offset in BT_SPAWN_OFFSETS:
		var enemy := BT_ENEMY_SCENE.instantiate()
		get_tree().current_scene.add_child(enemy)

		enemy.global_position = player.global_position + offset

		if enemy is Node2D:
			enemy.scale = _bt_enemy_scale

	# 3) SPAWN SAFE ZONE
	_spawn_safe_zone()

	# 4) Fade back in and then remove fade layer
	var layer: CanvasLayer = get_node_or_null("Stage2FadeLayer")
	if layer:
		var fade := layer.get_node_or_null("Stage2Fade")
		if fade:
			var tween := create_tween()
			tween.tween_property(fade, "color:a", 0.0, 1.2)
			tween.tween_callback(layer.queue_free)



func _spawn_safe_zone() -> void:
	_safe_zone = SAFE_ZONE_SCENE.instantiate()
	add_child(_safe_zone)

	# Set location for safe zone (tweak as needed)
	_safe_zone.global_position = Vector2(-500, -100)

	# Set scale
	_safe_zone.scale = Vector2(0.2, 0.2)

	_safe_zone.turtle_delivered.connect(_on_turtle_delivered)

	print("[World] SafeZone spawned at ", _safe_zone.global_position)


func _on_turtle_delivered() -> void:
	print("[World] LEVEL 2 COMPLETE – Turtle delivered to SafeZone")

	if _turtle and _turtle.is_carried:
		# Drop turtle at safe zone center
		_turtle.drop_to(_safe_zone, Vector2.ZERO)

		# Smooth scale up (celebration / rescue animation)
		var tween := create_tween()
		tween.tween_property(
			_turtle,
			"scale",
			Vector2(5, 5),
			0.4
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Delay, then restart or move to next scene
	get_tree().create_timer(2.0).timeout.connect(func():
		get_tree().reload_current_scene()
	)


func _on_player_died() -> void:
	print("game over!")
	get_tree().create_timer(3.0).timeout.connect(get_tree().reload_current_scene)

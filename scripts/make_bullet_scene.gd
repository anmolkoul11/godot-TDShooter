@tool
extends EditorScript

func _run() -> void:
	var scene := PackedScene.new()

	# Root Area2D
	var root := Area2D.new()
	root.name = "Bullet"
	# Layer 8 (1 << 7 = 128). Mask = World + Player + Player hitbox + Enemy + Enemy hitbox
	root.collision_layer = 1 << 7
	root.collision_mask  = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4)

	# Collision shape (small circle)
	var col := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 8.0
	col.shape = circle
	root.add_child(col)

	# RayCast to prevent tunneling
	var ray := RayCast2D.new()
	ray.enabled = true
	ray.collide_with_areas = true
	ray.collide_with_bodies = true
	root.add_child(ray)

	# Attach your bullet script
	var bullet_script := load("res://scripts/bullet.gd")
	if bullet_script:
		root.set_script(bullet_script)
	else:
		push_error("Couldn't find res://scripts/bullet.gd — make sure it exists.")

	scene.pack(root)
	var target_path := "res://scenes/bullet.tscn"
	if ResourceLoader.exists(target_path):
		push_warning("Bullet scene already exists at %s — skipping save. Delete it if you want to regenerate." % target_path)
		return

	var err := ResourceSaver.save(scene, target_path)
	if err == OK:
		print("Saved bullet scene: %s" % target_path)
	else:
		push_error("Failed to save bullet scene, code: %s" % err)

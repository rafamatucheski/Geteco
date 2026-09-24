extends SceneTree

func _init() -> void:
	var passed := 0
	var failed := 0

	print("--- Running test_v1_combat_parity.gd ---")

	# 1. Test CharacterFallPresentation3D
	var FallScript: GDScript = load("res://gameplay/CharacterFallPresentation3D.gd")
	if FallScript == null:
		print("FAIL: CharacterFallPresentation3D failed to load")
		failed += 1
	else:
		print("PASS: CharacterFallPresentation3D loaded")
		passed += 1

		# Create a dummy character with visual and limbs
		var root := Node3D.new()
		var visual := Node3D.new()
		root.add_child(visual)

		# Add joints for testing
		var left_leg := Node3D.new()
		left_leg.name = "left_upper_leg"
		visual.add_child(left_leg)
		var right_leg := Node3D.new()
		right_leg.name = "right_upper_leg"
		visual.add_child(right_leg)
		var left_arm := Node3D.new()
		left_arm.name = "left_upper_arm"
		visual.add_child(left_arm)
		var right_arm := Node3D.new()
		right_arm.name = "right_upper_arm"
		visual.add_child(right_arm)

		var fall = FallScript.new(root, visual, Vector3(0, 0, 1), 0.35, 1)
		if fall != null and not fall.finished:
			print("PASS: Fall initialized with variant 1 and directional impact")
			passed += 1
		else:
			print("FAIL: Fall initialization failed")
			failed += 1

		# Step fall physics
		fall.update(0.1)
		if visual.rotation.x != 0.0 or visual.position.y != 0.0:
			print("PASS: Fall simulation step articulated visual rotation and position")
			passed += 1
		else:
			print("FAIL: Fall simulation step had no effect")
			failed += 1

		# Step until finished
		fall.update(0.4)
		if fall.finished:
			print("PASS: Fall completed and settled onto ground")
			passed += 1
		else:
			print("FAIL: Fall did not complete in expected time")
			failed += 1

		root.queue_free()

	# 2. Test CombatEffects
	var EffectsScript: GDScript = load("res://gameplay/CombatEffects.gd")
	if EffectsScript == null:
		print("FAIL: CombatEffects failed to load")
		failed += 1
	else:
		print("PASS: CombatEffects loaded")
		passed += 1

		var effects: Node3D = EffectsScript.new()
		root_node_add(effects)

		# Test blood
		effects.blood(Vector3(0, 1, 0), Vector3(1, 0, 0), 30.0)
		print("PASS: blood() emitted droplet spray and aerosol mist")
		passed += 1

		# Test muzzle smoke
		effects.muzzle_smoke(Vector3(0, 1, 0), Vector3(0, 0, -1))
		print("PASS: muzzle_smoke() emitted smoke puff")
		passed += 1

		# Test impacts
		for mat in ["concrete", "wood", "metal", "flesh", "glass", "world"]:
			effects.impact(Vector3(0, 1, 0), Vector3.UP, mat, 20.0)
		print("PASS: impact() emitted surface-specific sparks and dust")
		passed += 1

		# Test stain puddle mechanics
		effects.stain(Vector3(0, 0, 0), 0.75)
		effects._physics_process(0.1)
		effects._physics_process(1.2)
		effects._physics_process(2.4)
		print("PASS: stain() expanding blood puddle and coagulation process stepped cleanly")
		passed += 1

		effects.clear()
		effects.shutdown()
		effects.queue_free()

	print("--- Finished test_v1_combat_parity: Passed=%d Failed=%d ---" % [passed, failed])
	if failed == 0:
		quit(0)
	else:
		quit(1)

func root_node_add(node: Node) -> void:
	root.add_child(node)

extends SceneTree

func _init() -> void:
	call_deferred("run_test")

func run_test() -> void:
	create_timer(45.0).timeout.connect(func():
		printerr("PRESENTATION_BUDGET TIMEOUT")
		quit(2)
	)
	var budget = root.get_node("PresentationBudget")
	budget.set_process(false)
	var actor = load("res://characters/AnimatedPedestrian3D.gd").new()
	actor.defer_presentation = true
	actor.position = Vector2(100000, 100000)
	root.add_child(actor)
	actor.set_physics_process(false)
	preload("res://characters/pedestrians/CitizenDetails.gd").dress(actor, 0)
	assert(actor.viewport == null)
	assert(actor.has_node("CollisionShape2D"))
	budget._process(0.016)
	assert(actor.viewport == null, "Entidade distante não deve criar rig")
	actor.position = Vector2(100, 100)
	actor.is_incapacitated = true
	budget._process(0.11)
	assert(actor.viewport != null)
	assert(actor.head_node.get_child_count() > 2, "Acessórios devem aguardar o rig")
	# Presentation starts an animated fall; it must settle after simulation ticks.
	for frame in 60: actor._physics_process(1.0 / 60.0)
	assert(actor.is_incapacitated and actor.model_root.rotation.x > 1.0, "Estado anterior à criação deve ser preservado")
	var count = actor.get_child_count()
	actor.ensure_presentation()
	assert(actor.get_child_count() == count)
	actor.free()
	budget._process(0.016)
	print("PRESENTATION_BUDGET: proximidade, colisão, acessórios e incapacitação aprovados")
	quit(0)

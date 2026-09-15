extends SceneTree
const FACTORY := preload("res://world/shared/emergency/ModernTrafficFactory.gd")
const CACHE := preload("res://VehicleGeometryCache.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var budget := root.get_node("PresentationBudget")
	budget.set_process(false)
	var fixture := Node2D.new()
	root.add_child(fixture)
	current_scene = fixture
	var actors := []
	var states := []
	var i := 0
	for id in ["bike_urban","cargo_flatbed_truck","route_city"]:
		var start_x := 100.0 if i == 0 else 15000.0
		var lane := FACTORY.create_lane(fixture,"Lane"+str(i),PackedVector2Array([Vector2(start_x,i*100),Vector2(start_x+500,i*100)]))
		var actor := FACTORY.spawn_moving_vehicle(lane,"Prepared"+str(i),id,.2,60,i)
		actors.append(actor)
		states.append([actor.global_transform,actor.collision_layer,actor.collision_mask,actor.collision.shape.size,actor.speed,actor.process_mode,actor.visible])
		i += 1
	paused = true
	var prepared: int = await CACHE.prepare_resident_presentations(self)
	assert(prepared == 1, "Startup prepares only the vehicle inside the entry view")
	for index in actors.size():
		var actor: Node2D = actors[index]
		assert(states[index] == [actor.global_transform,actor.collision_layer,actor.collision_mask,actor.collision.shape.size,actor.speed,actor.process_mode,actor.visible], "Preparation preserves traffic state and hull")
		if index == 0:
			assert(is_instance_valid(actor.body_model) and actor._pending_spec.is_empty())
			var model: Node3D = actor.body_model
			actor.ensure_presentation()
			assert(actor.body_model == model, "First encounter reuses the prepared presentation")
		else:
			assert(actor.body_model == null and not actor._pending_spec.is_empty(), "Offscreen presentation stays deferred")
	assert(budget.pending.has(actors[1]) and budget.pending.has(actors[2]), "Offscreen vehicles remain in the presentation queue")
	budget.pending.erase(actors[0])
	actors[1].global_position = Vector2(120, 120)
	budget._process(0.016)
	assert(is_instance_valid(actors[1].body_model) and actors[1]._pending_spec.is_empty(), "Presentation budget resolves a deferred vehicle when it approaches")
	paused = false
	fixture.free()
	budget.set_process(true)
	print("RESIDENT_PREPARATION PASS entry priority, deferred queue, state and reuse")
	quit(0)

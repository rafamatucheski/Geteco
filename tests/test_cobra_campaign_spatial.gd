extends SceneTree

## Production terrain, buildings, parked cars and ambient cast are present.
## Invoke real controller interactions to inspect the actual spawned opponents.
const CONTROLLER := preload("res://world/harbor/campaign/CobraCampaignController.gd")
const STATE := preload("res://world/harbor/campaign/CobraCampaignState.gd")
var failures := 0
var actor_count := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	var scene := load("res://world/harbor/HarborPreview.tscn").instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	for i in 8:
		await physics_frame
	var player := scene.get_node("Player") as CharacterBody2D
	player.set_physics_process(false)
	var territory := scene.get_node("CobraTerritory")
	territory.set_mission_access(true)
	for actor in territory.guards+territory.residents:
		actor.set_physics_process(false)
	var state := STATE.new()
	state.bind(null)
	var controller := CONTROLLER.new()
	scene.add_child(controller)
	controller.configure(player,state,territory)
	controller.set_physics_process(false)
	controller._neighbor.set_physics_process(false)
	await physics_frame
	check_clear(scene,controller._neighbor as CollisionObject2D,"Mission resident")
	for mission in ["cobra_collection","cobra_supply","cobra_finale"]:
		controller.active_id = mission
		controller.stage = 0
		controller.objective_position = {"cobra_collection":controller.RESIDENT,"cobra_supply":controller.SUPPLY,"cobra_finale":controller.WORKSHOP}[mission]
		player.global_position = controller.objective_position+Vector2(-70,0)
		check(controller.interact(),"Production interaction starts "+mission)
		var encounter: Node2D = controller._encounter
		check(is_instance_valid(encounter),"Actual finite encounter exists")
		if not is_instance_valid(encounter):
			continue
		encounter.set_physics_process(false)
		for actor in encounter.actors:
			actor.set_physics_process(false)
		await physics_frame
		for actor in encounter.actors:
			actor_count += 1
			check_clear(scene,actor,mission+"/"+actor.name)
		# Walkable approach to the interaction, using mask 1 for permanent solids.
		var query := PhysicsRayQueryParameters2D.create(player.global_position,controller.objective_position,1)
		query.exclude = [player.get_rid()]
		check(scene.get_world_2d().direct_space_state.intersect_ray(query).is_empty(),"Interaction approach unobstructed: "+mission)
		encounter.queue_free()
		controller._encounter = null
		await physics_frame
	print("COBRA CAMPAIGN SPATIAL: actors=%d failures=%d" % [actor_count,failures])
	scene.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)

func check_clear(scene: Node2D, actor: CollisionObject2D, label: String) -> void:
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.5
	query.shape = circle
	query.transform = Transform2D(0,actor.global_position)
	query.collision_mask = 7
	query.exclude = [actor.get_rid()]
	query.collide_with_areas = false
	var collisions := scene.get_world_2d().direct_space_state.intersect_shape(query,32)
	var blockers: Array[String] = []
	for collision in collisions:
		blockers.append(String(collision.collider.get_path()))
	check(collisions.is_empty(),"%s at %s overlaps %s" % [label,actor.global_position,blockers])

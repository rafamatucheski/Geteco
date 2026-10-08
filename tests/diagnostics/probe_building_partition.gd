extends SceneTree
const CATALOG = preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
const PLACE = preload("res://world/places/harbor_buildings/HarborBuildingPlace.gd")

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var place = PLACE.new()
	place.definition = CATALOG.for_source("FoundryTerraceWest").duplicate(true)
	place.floor_index = 1
	stage.add_child(place)
	var actor := CharacterBody3D.new()
	actor.collision_layer = 2
	actor.collision_mask = 7
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.7
	capsule.radius = .30
	collision.shape = capsule
	collision.position.y = .86
	actor.add_child(collision)
	stage.add_child(actor)
	await physics_frame
	await physics_frame
	var base: Vector3 = Vector3(-1.05,place.floor_height(1)+.04,-1.2)
	for offset in [0.0,.02,-.02,.1,-.1]:
		actor.position = base+Vector3.RIGHT*float(offset)
		var motion := Vector3(0,0,-2.50875)
		var hit := KinematicCollision3D.new()
		var blocked := actor.test_move(actor.global_transform,motion,hit)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = collision.global_transform
		query.motion = motion
		query.collision_mask = 1
		var shape_cast := stage.get_world_3d().direct_space_state.cast_motion(query)
		var actual := actor.move_and_collide(motion)
		print("PARTITION_PROBE offset=",offset," blocked=",blocked," collision=",hit.get_collider() if blocked else null," shape_cast=",shape_cast," moved=",actor.position-base-Vector3.RIGHT*float(offset)," actual=",actual.get_collider() if actual != null else null)
		actor.position = base+Vector3.RIGHT*float(offset)
		var first_hit: KinematicCollision3D
		for index in 26:
			var step_hit := actor.move_and_collide(Vector3(0,0,-.1))
			if step_hit != null:
				first_hit = step_hit
				break
		print("PARTITION_STEPS offset=",offset," final=",actor.position," collision=",first_hit.get_collider() if first_hit != null else null)
	quit()

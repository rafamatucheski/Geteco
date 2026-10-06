extends SceneTree
## Physical contracts of the four actual NativePlace rooms; depth/FPS need rendered Main separately.
const HOMES := preload("res://world/desert/village/DesertVillageHomes.gd")
const NATIVE := preload("res://world/places/NativePlace.gd")
const ACTOR := preload("res://scripts/Actor.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition: failures.append(message)

func run() -> void:
	var stage:=Node3D.new()
	root.add_child(stage)
	var seen_ids: Dictionary={}
	var sizes: Dictionary={}
	for definition in HOMES.definitions():
		var room:=NATIVE.new()
		room.definition=definition
		stage.add_child(room)
		await physics_frame
		await physics_frame
		var id: String=definition.id
		var resident: Dictionary=definition.resident_data
		var size: Vector2=definition.size
		sizes[str(size)]=true
		check(room.reward_points.size()==3,id+" has all three physically admitted rewards")
		check(room.model.find_children("*","OmniLight3D",true,false).size()==2,id+" has two bounded motivated lights")
		check(not room.model.is_processing() and not room.model.is_physics_processing(),id+" static model has no runtime loop")
		for reward in definition.rewards:
			check(not seen_ids.has(reward.id),id+" globally unique reward receipt "+str(reward.id))
			seen_ids[reward.id]=true
			var actual: Vector3=room.reward_points[definition.rewards.find(reward)].position
			check(actual.is_equal_approx(room.to_global(reward.local_position)),id+" reward uses authored position without fallback")
		for is_player in [true,false]:
			var actor:=ACTOR.new()
			actor.is_player=is_player
			actor.controlled_automatically=true
			actor.disable_mode=CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
			stage.add_child(actor)
			actor.set_physics_process(false)
			actor.set_process(false)
			await physics_frame
			var who: String="Dante" if is_player else "resident"
			var points: Array[Vector3]=[definition.spawn,definition.exit,resident.floor_point,resident.cooking_point]
			for reward in definition.rewards: points.append(reward.local_position)
			for point in points:
				actor.position=point+Vector3(0,.04,0)
				check(room.is_floor_clear(point,.32),id+" "+who+" footprint clear "+str(point))
				check(not actor.test_move(actor.global_transform,Vector3.UP*.002),id+" "+who+" full capsule clear "+str(point))
				var ray:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*.20,point-Vector3.UP*.30,1)
				var hit:=stage.get_world_3d().direct_space_state.intersect_ray(ray)
				check(not hit.is_empty() and absf(hit.position.y+.02)<.025,id+" floor support "+str(point))
			actor.position=definition.spawn
			check(not actor.test_move(actor.global_transform,definition.exit-definition.spawn),id+" "+who+" can walk from spawn to exit")
			var swept:=0
			for bounds in room.solid_bounds:
				var center: Vector3=bounds.get_center()
				for side in [Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK]:
					var half: float=bounds.size.x*.5 if absf(side.x)>.5 else bounds.size.z*.5
					var start: Vector3=Vector3(center.x,.04,center.z)+side*(half+.55)
					if absf(start.x)>size.x*.5-.4 or absf(start.z)>size.y*.5-.4: continue
					if not room.is_floor_clear(start,.32): continue
					actor.position=start
					check(actor.test_move(actor.global_transform,-side*(half+1.1)),id+" "+who+" swept body stops at "+str(bounds))
					swept+=1
					break
			check(swept>=10,id+" "+who+" exercised at least ten reachable wall/furniture faces")
			actor.free()
		var bed: Vector3=resident.sleep_point
		var bed_query:=PhysicsRayQueryParameters3D.create(bed+Vector3.UP*.4,bed-Vector3.UP*.25,1)
		var bed_hit:=stage.get_world_3d().direct_space_state.intersect_ray(bed_query)
		check(not bed_hit.is_empty() and absf(bed_hit.position.y-.63)<.015,id+" sleep anchor supported by mattress, separate from headboard")
		room.set_active(false)
		check(not room.visible and room.process_mode==Node.PROCESS_MODE_DISABLED,id+" inactive room disables effects and rendering")
		room.free()
		await physics_frame
	check(sizes.size()==4,"Four independently proportioned authored floor plans")
	check(seen_ids.size()==12,"Twelve unique persistent cash/food/drink rewards")
	stage.free()
	for failure in failures: push_error(failure)
	print("DESERT_VILLAGE_HOMES ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

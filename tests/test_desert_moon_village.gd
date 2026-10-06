extends SceneTree
## Real region admission/re-entry plus swept moves with the production actor
## capsule for player and NPC. Rendered depth/performance remain separate.
const REGION := preload("res://world/desert/DesertRegion.gd")
const VILLAGE := preload("res://world/desert/DesertMoonVillage.gd")
const ACTOR := preload("res://scripts/Actor.gd")
var failures: Array[String]=[]
var checks := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures.append(label)
		push_error(label)

func run() -> void:
	create_timer(120.0).timeout.connect(func(): push_error("Village contract exceeded finite 120s budget"); quit(2))
	var region := REGION.new()
	region.initial_prewarm_only=true
	root.add_child(region)
	check(region.entries.filter(func(entry: Dictionary): return str(entry.id).begins_with("santa_lua_home_")).size()==4,"four distinct home accesses registered in real region")
	region.set_process(false)
	# A restored actor cannot cross a new house during the deferred art queue.
	for cycle in 2:
		check(region.prepare_collision_at(VILLAGE.CENTER),"village admission accepted")
		check(not region.is_streaming_idle(),"art still pending during admission")
		for i in 3: await physics_frame
		var ray := PhysicsRayQueryParameters3D.create(Vector3(-550,1,-842)+Vector3.RIGHT*12,Vector3(-550,1,-842),1)
		check(not region.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(),"house solid ready before art cycle "+str(cycle))
		region.release_chunks()
		for i in 3: await physics_frame
	region.set_process(true)
	region.set_focus(VILLAGE.CENTER)
	for i in 240:
		if region.is_streaming_idle(): break
		await process_frame
	check(region.is_streaming_idle(),"village streaming completes finitely")
	await physics_frame
	await physics_frame
	check(region.find_children("santa_lua_*","Node3D",true,false).size()>=7,"authored village is integrated in real streamed region")
	for player in [true,false]:
		var actor := ACTOR.new()
		actor.is_player=player
		actor.controlled_automatically=true
		actor.disable_mode=CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		root.add_child(actor)
		actor.set_physics_process(false)
		actor.process_mode=Node.PROCESS_MODE_DISABLED
		await physics_frame
		var who := "player" if player else "npc"
		for probe in [
			{"id":"adobe house","start":Vector3(-541,.07,-842),"motion":Vector3(-16,0,0)},
			{"id":"porch bench","start":Vector3(-542.1,.07,-838.92),"motion":Vector3(-5,0,0)},
			{"id":"courtyard bench","start":Vector3(-535,.07,-828),"motion":Vector3(-6,0,0)},
			{"id":"water barrel","start":Vector3(-513,.07,-836),"motion":Vector3(-5,0,0)},
			{"id":"tower leg","start":Vector3(-548.2,.07,-785),"motion":Vector3(0,0,-6)},
			{"id":"fence","start":Vector3(-558,.07,-842),"motion":Vector3(-7,0,0)},
			{"id":"store","start":Vector3(-528,.07,-802),"motion":Vector3(0,0,15)},
		]:
			actor.position=probe.start
			var collision := actor.move_and_collide(probe.motion)
			check(collision!=null,who+" blocks "+probe.id)
			check(actor.position.distance_to(probe.start)<Vector3(probe.motion).length()-.25,who+" cannot tunnel through "+probe.id)
		for path in [
			[Vector3(-528,.07,-875),Vector3(-528,.07,-852),Vector3(-528,.07,-829),Vector3(-528,.07,-805)],
			[Vector3(-528,.07,-831),Vector3(-540,.07,-831),Vector3(-540,.07,-842)],
			[Vector3(-528,.07,-829),Vector3(-516,.07,-829),Vector3(-516,.07,-816)],
			[Vector3(-543.85,.08,-842),Vector3(-544.95,.08,-842)],
			[Vector3(-512.15,.08,-842),Vector3(-511.05,.08,-842)],
			[Vector3(-543.85,.08,-816),Vector3(-544.95,.08,-816)],
			[Vector3(-512.15,.08,-816),Vector3(-511.05,.08,-816)],
		]:
			actor.position=path[0]
			check(not actor.test_move(actor.global_transform,Vector3.UP*.001),who+" starts in clear approach")
			for i in range(1,path.size()):
				var target: Vector3=path[i]
				var collision := actor.move_and_collide(target-actor.position)
				check(collision==null and actor.position.distance_to(target)<.025,who+" walks courtyard/access segment "+str(i))
		actor.free()
	region.set_night_lights(1.0)
	var lamps := region.find_children("PorchLanternLight","OmniLight3D",true,false)
	check(lamps.size()==3,"only three local porch lights")
	for lamp in lamps: check(lamp.light_energy>0 and lamp.omni_range<=11 and not lamp.shadow_enabled,"small warm lamp follows night level")
	region.set_night_lights(0.0)
	for lamp in lamps: check(is_zero_approx(lamp.light_energy),"porch light off in daylight")
	region.release_chunks()
	for i in 3: await physics_frame
	check(region.chunks.is_empty() and region._lamps.is_empty(),"release clears village geometry and light ownership")
	region.set_focus(VILLAGE.CENTER)
	for i in 240:
		if region.is_streaming_idle(): break
		await process_frame
	check(region.find_children("PorchLanternLight","OmniLight3D",true,false).size()==3,"return rebuilds exactly three lights without duplicates")
	region.free()
	print("DESERT_MOON_VILLAGE checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)

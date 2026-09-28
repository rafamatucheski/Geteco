extends SceneTree
const PRESENTATION := preload("res://runtime/UrbanTransitPresentation.gd")
const SERVICE := preload("res://runtime/transit/UrbanBusService.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
func run() -> void:
	var presentation := PRESENTATION.new()
	presentation.configure(null)
	root.add_child(presentation)
	var ground := StaticBody3D.new()
	var ground_col := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size=Vector3(1000,1,1000)
	ground_col.shape=ground_box; ground_col.position.y=-.5
	ground.add_child(ground_col); root.add_child(ground)
	var actor := CharacterBody3D.new()
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius=.3; capsule.height=1.7
	col.shape=capsule; col.position.y=.86
	actor.add_child(col)
	actor.collision_layer=2; actor.collision_mask=1
	actor.floor_snap_length=.3
	root.add_child(actor)
	for index in 6:
		var definition: Dictionary=presentation.definitions[index]
		var art= presentation.build_geometry(presentation,definition)
		var model=art.find_child("StationModel",true,false)
		if model==null: model=art.find_child("StationTerminalModel",true,false)
		await physics_frame
		await physics_frame
		var foot:=SERVICE.station_point(definition,Vector2(-96,8))
		var ray:=PhysicsRayQueryParameters3D.create(foot+Vector3.UP,foot-Vector3.UP,1)
		var hit=actor.get_world_3d().direct_space_state.intersect_ray(ray)
		check(not hit.is_empty() and absf(hit.position.y-.2)<.01,"Station %d supports feet on TOP of platform" % index)
		for door in 3:
			var x: float=SERVICE.GATE_X[door]
			var inside:=SERVICE.station_point(definition,Vector2(x,12),.23)
			var outside:=SERVICE.station_point(definition,Vector2(x,47),.23)
			actor.global_position=inside
			check(actor.test_move(actor.global_transform,outside-inside),"Closed gate %d/%d blocks full capsule" % [index,door])
		model.set_boarding_gate(true)
		await physics_frame
		await physics_frame
		for door in 3:
			var x: float=SERVICE.GATE_X[door]
			var inside:=SERVICE.station_point(definition,Vector2(x,12),.23)
			var outside:=SERVICE.station_point(definition,Vector2(x,47),.23)
			actor.global_position=inside
			check(not actor.test_move(actor.global_transform,outside-inside),"Open gate %d/%d admits full capsule" % [index,door])
		actor.global_position=SERVICE.station_point(definition,Vector2(-101,8),.23)
		var bench:=SERVICE.station_point(definition,Vector2(-101,-20),.23)
		check(actor.test_move(actor.global_transform,bench-actor.global_position),"Station bench blocks player/NPC sized capsule")
		var ramp_foot:=SERVICE.station_point(definition,Vector2(200,8),.02)
		var ramp_top:=SERVICE.station_point(definition,Vector2(140,8),.2)
		actor.global_position=ramp_foot
		for target in [ramp_top,ramp_foot]:
			for frame in 240:
				await physics_frame
				var direction: Vector3=target-actor.global_position
				direction.y=0
				actor.velocity=direction.normalized()*2.0+Vector3.DOWN*2.0
				actor.move_and_slide()
				if direction.length()<.1: break
			check(actor.global_position.distance_to(target)<.2,"Station %d ramp supports physical ascent/descent" % index)
		art.free()
	print("BIARTICULATED_PLATFORM ",checks," checks ",failures," failures")
	quit(1 if failures else 0)

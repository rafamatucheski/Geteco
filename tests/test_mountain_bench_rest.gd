extends SceneTree
var failures:=0
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	if not value:failures+=1;push_error(label)
func body_at(parent:Node2D,point:Vector2,size:Vector2)->StaticBody2D:
	var body:=StaticBody2D.new()
	body.position=point
	body.collision_layer=1
	var shape:=CollisionShape2D.new()
	shape.shape=RectangleShape2D.new()
	shape.shape.size=size
	body.add_child(shape)
	parent.add_child(body)
	return body
func run()->void:
	var world:=Node2D.new()
	root.add_child(world)
	current_scene=world
	var player:=CharacterBody2D.new()
	player.add_to_group("player")
	world.add_child(player)
	var bench:=body_at(world,Vector2.ZERO,Vector2(38,10))
	var seat:=Marker2D.new()
	seat.add_to_group("mountain_bench_seat")
	seat.set_meta("bench_body",bench)
	seat.set_meta("approach_offset",Vector2(0,28))
	seat.set_meta("facing",Vector2.DOWN)
	seat.set_meta("seat_height",0.45)
	seat.set_meta("visual_seat_offset",Vector2(0,-5))
	seat.set_meta("scope","shelter")
	world.add_child(seat)
	var resident=preload("res://world/mountain_pass/WinterResident.gd").new()
	resident.position=Vector2(-70,28)
	world.add_child(resident)
	var competitor=preload("res://world/mountain_pass/WinterResident.gd").new()
	competitor.position=Vector2(55,35)
	world.add_child(competitor)
	competitor.set_physics_process(false)
	var wall:=body_at(world,Vector2(-30,22),Vector2(12,42))
	await physics_frame
	await physics_frame
	check(not resident.request_bench_rest(180,"village"),"Village travelers do not claim unrelated shelter seats")
	check(resident.request_bench_rest(180,"shelter"),"First resident reserves free seat")
	check(not competitor.request_bench_rest(180),"Another resident cannot reserve occupied seat")
	var prior:Vector2=resident.global_position
	var wall_hit:=false
	var jumps:=false
	for frame in 900:
		await physics_frame
		wall_hit=wall_hit or Rect2(Vector2(-42,-5),Vector2(24,54)).has_point(resident.global_position)
		jumps=jumps or prior.distance_to(resident.global_position)>2.0
		prior=resident.global_position
		if resident.bench_state()=="resting":break
	check(resident.bench_state()=="resting","Resident physically reaches seat and finishes sitting")
	check(not wall_hit and not jumps,"Approach respects actual wall collision without snapping")
	check(resident.model.sit_amount>.99 and resident.model.knees[0].rotation.x>.8,"Knees bend and hips lower into a seated pose")
	check(resident.get_collision_exceptions().has(bench) and not resident.get_collision_exceptions().has(wall),"Only the supporting bench receives a temporary collision exception")
	for frame in 1700:
		await physics_frame
		if resident._bench_rest.completed_rests==1:break
	check(resident.bench_state()=="idle" and resident._bench_rest.completed_rests==1,"Rest completes, resident stands and leaves through the front")
	check(not seat.has_meta("bench_occupant_id") and resident.get_collision_exceptions().is_empty(),"Leaving releases seat and restores bench collision")
	check(resident.model.sit_amount==0.0,"Standing restores neutral pose")
	seat.set_meta("occlusion_z_index",3)
	check(resident.request_bench_rest(180),"Seat can be reserved again after leaving")
	for frame in 500:
		await physics_frame
		if resident.bench_state()=="resting":break
	resident.hear_gunfire(Vector2(-100,0),Vector2(20,0))
	check(resident.bench_state()=="standing","Threat interrupts rest with a standing animation")
	for frame in 500:
		await physics_frame
		if resident.bench_state()=="idle":break
	check(resident.bench_state()=="idle" and not seat.has_meta("bench_occupant_id") and resident.presentation_sprite.z_index==0,"Threatened resident leaves, restores depth and frees seat before fleeing")
	check(competitor.request_bench_rest(180),"Another resident can claim released seat")
	competitor.queue_free()
	await process_frame
	await process_frame
	check(not seat.has_meta("bench_occupant_id"),"Deleting a resident releases seat ownership")
	var victim=preload("res://world/mountain_pass/WinterResident.gd").new()
	victim.position=Vector2(35,28)
	world.add_child(victim)
	check(victim.request_bench_rest(180),"A new resident may reserve after deletion")
	for frame in 500:
		await physics_frame
		if victim.bench_state()=="resting":break
	victim.take_damage(100)
	check(victim.is_dead and not seat.has_meta("bench_occupant_id") and victim.get_collision_exceptions().is_empty() and victim.presentation_sprite.z_index==0,"Death frees a seated resident's reservation, depth override and support exception")
	var shelter=preload("res://world/mountain_pass/MountainProp.gd").new()
	shelter.model_script=preload("res://world/mountain_pass/art/winter_props/PatrolShelter3D.gd")
	shelter.open_front=true
	shelter.position=Vector2(250,0)
	world.add_child(shelter)
	preload("res://world/mountain_pass/transit/MountainBenchGeometry.gd").install_prop(shelter,"PatrolShelter3D")
	var sheltered=preload("res://world/mountain_pass/WinterResident.gd").new()
	sheltered.position=Vector2(250,70)
	world.add_child(sheltered)
	await physics_frame
	await physics_frame
	for marker in get_nodes_in_group("mountain_bench_seat"):
		if marker.get_parent()!=shelter:continue
		for point in [marker.global_position,marker.to_global(marker.get_meta("approach_offset"))]:
			var query:=PhysicsShapeQueryParameters2D.new()
			query.shape=CircleShape2D.new()
			query.shape.radius=7
			query.transform=Transform2D(0,point)
			query.collision_mask=3
			query.exclude=[sheltered.get_rid(),marker.get_meta("bench_body").get_rid()]
			for hit in sheltered.get_world_2d().direct_space_state.intersect_shape(query):print("SHELTER_SEAT_BLOCKER ",point," ",hit.collider.get_path())
	check(sheltered.request_bench_rest(110,"shelter"),"Real shelter has an accessible internal seat")
	for frame in 900:
		await physics_frame
		if sheltered.bench_state()=="resting":break
	check(sheltered.bench_state()=="resting","Resident passes through real shelter doorway and sits inside")
	check(sheltered.presentation_sprite.z_index+sheltered.z_index<shelter.z_index,"Roof occludes seated interior resident while actor interaction layer remains intact")
	for frame in 1700:
		await physics_frame
		if sheltered._bench_rest.completed_rests==1:break
	check(sheltered._bench_rest.completed_rests==1 and sheltered.get_collision_exceptions().is_empty(),"Resident reverses internal doorway route and releases support")
	check(sheltered.presentation_sprite.z_index==0 and sheltered.z_index==9,"Leaving restores character presentation depth")
	print("MOUNTAIN_BENCH_REST failures=",failures)
	world.queue_free()
	for frame in 4:await process_frame
	quit(0 if failures==0 else 1)

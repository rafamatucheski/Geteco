extends SceneTree
## Contrato físico do paddock separado da arrancada. Oclusão visual, continuidade
## de luz e tempo de quadro exigem jogo renderizado, fora desta fixture.
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const REGION := preload("res://world/desert/DesertRegion.gd")
const MEET := preload("res://world/desert/drag_meet/DesertDragMeet.gd")
const ROSTER := preload("res://runtime/desert/drag_meet/DragMeetRoster.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	create_timer(60).timeout.connect(func(): push_error("DRAG_MEET_WORLD timeout"); quit(3))
	_run.call_deferred()

func _check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures.append(label)

func _run() -> void:
	var roads := LAYOUT.roads()
	for point in [LAYOUT.drag_start_point(),LAYOUT.drag_staging_point(),LAYOUT.drag_meet_center(),LAYOUT.drag_vicente_point(),LAYOUT.drag_workshop_point()]:
		var nearest := INF
		for road in roads:
			if not road.traffic: continue
			for i in range(1,road.points.size()):
				var a: Vector3=road.points[i-1]
				var b: Vector3=road.points[i]
				nearest=minf(nearest,Vector2(point.x,point.z).distance_to(Geometry2D.get_closest_point_to_segment(Vector2(point.x,point.z),Vector2(a.x,a.z),Vector2(b.x,b.z)))-float(road.width)*.5)
		_check(nearest>=150.0,"Meeting activity point is at least 150m away from ambient highway: "+str(point))
		_check(LAYOUT.contains(point),"Meeting point remains within desert bounds")
	var strip: Dictionary={}
	var access: Dictionary={}
	for road in roads:
		if road.id=="desert_drag_strip": strip=road
		if road.id=="desert_drag_access": access=road
	_check(not strip.is_empty() and not strip.traffic and not access.is_empty() and not access.traffic,"Access and strip remain private geometry excluded from ambient traffic")
	var finish := LAYOUT.drag_start_point()+LAYOUT.drag_direction()*800.0
	_check(Vector3(strip.points[-1]).distance_to(finish)>=180.0,"800m race preserves at least180m braking runoff")
	_check(Vector3(access.points[-1]).distance_to(LAYOUT.drag_start_point())<40.0,"Access reaches pre-grid side of strip")
	var region := REGION.new()
	region.initial_focus=LAYOUT.drag_meet_center()
	root.add_child(region)
	await _settle(region)
	_check(region.is_streaming_idle(),"Meeting chunk construction finishes")
	var points: Array[Vector3]=[
		LAYOUT.drag_staging_point(),LAYOUT.drag_start_point()+Vector3(0,0,2),
		LAYOUT.drag_vicente_point(),
	]
	for id in ROSTER.LEADERS:
		points.append(ROSTER.LEADERS[id])
		_check(LAYOUT.drag_opponent_point(id)==ROSTER.LEADERS[id],"Race opponent and layout share the same social island: "+str(id))
	for guest in ROSTER.guests():
		points.append(guest.point)
		var start: Vector3=guest.point
		var end: Vector3=guest.walk_end
		if start.distance_to(end)<.01: continue
		var steps := ceili(start.distance_to(end)/.5)
		for i in range(1,steps+1): points.append(start.lerp(end,float(i)/steps))
	for offset in [Vector3(-3,0,0),Vector3(3,0,0),Vector3(-5,0,4.5),Vector3(-3.5,0,6),Vector3(3.5,0,6),Vector3(5,0,4.5)]:
		points.append(LAYOUT.drag_vicente_point()+offset)
	for point in points:
		_check(_floor(point),"Authored meeting/actor position has physical support: "+str(point))
		_check(_clear(point),"Authored meeting/actor capsule is free of scene solids: "+str(point))
	for road_point: Vector3 in access.points:
		if road_point.x<-1050.0: continue # distant approach chunks are checked separately below
		_check(_clear(road_point),"Private access remains clear at authored turn: "+str(road_point))
	var expected := MEET.car_spots().size()
	_check(expected>=45 and expected<=55,"The dense meet contains45–55 authored static display cars")
	_check(_cars(region)==expected,"All authored parked cars are instantiated once")
	var hero_models := {"livia_faisca":"desert_faisca_rally","raul_coyote":"desert_coyote_drag","jessica_jetta":"jessica_jetta_gli","nadir_mirage":"desert_mirage_gt"}
	for id in hero_models:
		var hero := region.find_child("DragMeetCar_"+str(id),true,false)
		_check(hero!=null and hero.get_meta("desert_car_id","")==hero_models[id],"Rival's actual authored car is displayed: "+str(id))
	_check(region.find_child("GolUnderRepair",true,false)!=null,"Digo's Gol stays physically present in his working garage")
	for car in MEET.car_spots():
		_check(not _clear(car.position),"Parked display car has a real solid footprint: "+str(car.id))
	# A aproximação reta completa de oito metros continua utilizável entre as fileiras,
	# incluindo a folga do veículo dos dois lados da linha central.
	for x in range(-1034,-947,3):
		for offset in [-3.0,0.0,3.0]:
			var point := Vector3(x,0,-1280+offset)
			_check(_floor(point) and _clear(point),"Eight-metre main aisle retains floor and clearance: "+str(point))
	_check(not region._decoration_clear(Vector2(LAYOUT.drag_meet_center().x,LAYOUT.drag_meet_center().z),3.0),"Scatter reserves the whole meeting footprint")
	for point in [Vector3(-1120,0,-1264),Vector3(-1090,0,-1280),finish,finish+Vector3(175,0,0)]:
		region.prepare_collision_at(point)
		await physics_frame
		_check(_floor(point),"Private approach/finish/runoff has actual streamed support: "+str(point))
	region.release_chunks()
	await process_frame
	_check(region.chunks.is_empty(),"Meeting props and collisions release with their chunks")
	region.set_focus(LAYOUT.drag_meet_center())
	await _settle(region)
	_check(_cars(region)==expected,"Streaming back reconstructs cars without duplicates")
	region.free()
	for failure in failures: push_error(failure)
	print("DRAG_MEET_WORLD checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _settle(region: Node3D) -> void:
	for i in 360:
		if region.is_streaming_idle(): break
		await process_frame
	await physics_frame
	await physics_frame

func _cars(region: Node3D) -> int:
	var result := 0
	for node in region.find_children("*","Node3D",true,false):
		if node.has_meta("drag_meet_car_id"): result+=1
	return result

func _floor(point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.3,point-Vector3.UP*.3,1)
	return not root.world_3d.direct_space_state.intersect_ray(query).is_empty()

func _clear(point: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius=.34
	capsule.height=1.78
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape=capsule
	query.transform=Transform3D(Basis.IDENTITY,point+Vector3.UP*.96)
	query.collision_mask=1
	return root.world_3d.direct_space_state.intersect_shape(query,1).is_empty()

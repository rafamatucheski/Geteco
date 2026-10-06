extends SceneTree
## Real edited geography, no save writes; verifies the complete footprint and
## physical access using a car-sized body, separately from rendered validation.
const REGION := preload("res://world/editing/EditableRegion.gd")
const LAYOUT := preload("res://world/roadside_parking/RoadsideParkingLayout.gd")
const BAY := preload("res://world/roadside_parking/RoadsideParkingBay.gd")
var failures: Array[String] = []

func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func _run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("Requires --no-save")
		quit(2)
		return
	for region_id in ["harbor","mountain"]:
		var region := REGION.build_region(region_id)
		region.prepare_data()
		var sites := LAYOUT.sites(region)
		_check(sites.size()>=2,region_id+": at least two usable roadside pockets")
		if region_id=="harbor":
			for road: Dictionary in region.roads:
				if str(road.id).trim_prefix("road/")=="dock_street":
					var old_dock:=LAYOUT._resolve(region,road,["old_dock","dock_street",Vector2(112,137.5),1.0,2],0.0)
					_check(LAYOUT.rejection_reason(region,old_dock)=="transit_station","live edited transit station excludes former dock bay")
				if road.id!="market_street": continue
				var old_site:=LAYOUT._resolve(region,road,["old_terminal","market_street",Vector2(111,78),-1.0,2],0.0)
				_check(LAYOUT.rejection_reason(region,old_site)=="terminal_access","terminal bus access and benches remain free")
		else:
			for road: Dictionary in region.roads:
				if str(road.id).trim_prefix("road/")!="mountain_pass": continue
				var old_forest:=LAYOUT._resolve(region,road,["old_forest","mountain_pass",Vector2(620,-285),-1.0,2],0.0)
				_check(LAYOUT.rejection_reason(region,old_forest)=="shared_connection","shared tunnel shell excludes former forest bay")
		var ids := {}
		for site in sites:
			print("PARKING_SITE ",site.id," ",site.position," slots=",site.slots.size())
			_check(not ids.has(site.id),site.id+": unique identity")
			ids[site.id]=true
			_check(site.slots.size() in [1,2],site.id+": bounded 1/2-car footprint")
			_check(LAYOUT.rejection_reason(region,site).is_empty(),site.id+": all geographic clearance checks")
			region.buildings.append({"position":site.slots[0].position,"size":Vector2(5,7),"editor_rotation":.7})
			_check(LAYOUT.rejection_reason(region,site)=="building",site.id+": an edited building excludes this footprint")
			region.buildings.pop_back()
			for slot: Dictionary in site.slots:
				_check((slot.position-site.edge).dot(site.outward)>=2.0,site.id+": vehicle fully outside the lane")
				_check((slot.explore_position-slot.position).dot(site.outward)>=2.8,site.id+": pedestrian leaves onto outer shoulder")
				_check((-Basis(Vector3.UP,float(slot.yaw)).z).dot(site.forward)>.999,site.id+": correct driving direction")
		# Test generated floor access independently: through-traffic must never
		# meet a new vertical barrier when crossing either end or the open mouth.
		var stage := Node3D.new()
		root.add_child(stage)
		for site in sites: BAY.build(stage,site)
		await physics_frame
		await physics_frame
		for site in sites:
			for slot: Dictionary in site.slots:
				var query := PhysicsRayQueryParameters3D.create(slot.position+Vector3.UP*2,slot.position+Vector3.DOWN,1)
				var hit := root.world_3d.direct_space_state.intersect_ray(query)
				_check(not hit.is_empty(),site.id+": parking floor supports wheels")
				if not hit.is_empty(): _check(absf(hit.position.y-BAY.COLLISION_Y)<.005,site.id+": support matches adjoining road ground plane")
				var body := CharacterBody3D.new()
				body.collision_layer=2
				body.collision_mask=1
				var collision := CollisionShape3D.new()
				var shape := BoxShape3D.new()
				shape.size=Vector3(1.85,1.3,4.7)
				collision.shape=shape
				collision.position.y=.72
				body.add_child(collision)
				stage.add_child(body)
				body.position=slot.lane_position+Vector3.UP*.04
				body.rotation.y=slot.yaw
				_check(body.move_and_collide(slot.position-body.position,true)==null,site.id+": car can enter pull-off")
				body.position=slot.position+Vector3.UP*.04
				_check(body.move_and_collide(slot.lane_position-body.position,true)==null,site.id+": car can leave pull-off")
				# Resting wheels/chassis, unlike the raised spawn probe above: this
				# caught the former 4.5 cm bay lip blocking real front/reverse entry.
				collision.position.y=.65
				body.position=Vector3(slot.lane_position.x,.001,slot.lane_position.z)
				var on_grade:=Vector3(slot.position.x,.001,slot.position.z)
				_check(body.move_and_collide(on_grade-body.position,true)==null,site.id+": resting chassis enters without a raised floor lip")
				body.position=on_grade
				_check(body.move_and_collide(Vector3(slot.lane_position.x,.001,slot.lane_position.z)-body.position,true)==null,site.id+": resting chassis exits on grade")
				body.free()
		stage.free()
		if "--parking-layout-scene" in OS.get_cmdline_user_args():
			await _real_scene(region,sites)
		region.free()
	for failure in failures: push_error(failure)
	print("ROADSIDE_PARKING_LAYOUT ","PASS" if failures.is_empty() else "FAIL"," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func _real_scene(region: Node3D, sites: Array[Dictionary]) -> void:
	region.initial_prewarm_only=true
	root.add_child(region)
	# Complete the actual chunks, including authored props and the final city
	# dressing; prepare_collision_at alone deliberately supplies surfaces first.
	for site in sites:
		for dx in [-20.0,0.0,20.0]:
			for dz in [-20.0,0.0,20.0]:
				region._ensure_chunk(region._cell(site.position+Vector3(dx,0,dz)))
	await physics_frame
	await physics_frame
	for site in sites:
		for slot: Dictionary in site.slots:
			var car := BoxShape3D.new()
			car.size=Vector3(2.1,1.4,4.7)
			var label: String=site.id+"/"+str(slot.id)
			_check(_sweep_clear(car,.7,slot.lane_position,slot.position,slot.yaw),label+": real scene lane to bay")
			_check(_sweep_clear(car,.7,slot.position,slot.lane_position,slot.yaw),label+": real scene bay to lane")
			_check(_sweep_clear(car,.7,slot.position,slot.departure,slot.yaw),label+": real scene departure")
			var person := CapsuleShape3D.new()
			person.radius=.3
			person.height=1.7
			var door: Vector3=slot.position+site.outward*1.35
			_check(_sweep_clear(person,.85,door,slot.explore_position,0),label+": pedestrian dismount and exploration")
			_check(_sweep_clear(person,.85,slot.explore_position,door,0),label+": pedestrian return")
			for point: Vector3 in [slot.position,door,slot.explore_position]:
				var ray:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*1.5,point+Vector3.DOWN,1)
				var hit:=root.world_3d.direct_space_state.intersect_ray(ray)
				_check(not hit.is_empty(),label+": real ground support")
				if not hit.is_empty(): _check(absf(hit.position.y-LAYOUT.SURFACE_Y)<.08,label+": no buried bay or raised obstacle")
		print("PARKING_SCENE_SITE ",site.id," checked")

func _sweep_clear(shape: Shape3D, center_height: float, start: Vector3, finish: Vector3, yaw: float) -> bool:
	var body:=CharacterBody3D.new()
	body.collision_layer=2
	body.collision_mask=1
	var collision:=CollisionShape3D.new()
	collision.shape=shape
	collision.position.y=center_height
	body.add_child(collision)
	root.add_child(body)
	body.position=start+Vector3.UP*.10
	body.rotation.y=yaw
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=shape
	query.transform=Transform3D(body.basis,body.position+Vector3.UP*center_height)
	query.collision_mask=1
	var free_start:=root.world_3d.direct_space_state.intersect_shape(query,1).is_empty()
	var hit:=body.move_and_collide(finish-start,true)
	if hit!=null: print("PARKING_SWEEP_OBSTACLE ",start," -> ",finish," collider=",hit.get_collider().name," at=",hit.get_position())
	body.free()
	return free_start and hit==null

extends SceneTree
## Colisão real do deserto em streaming, varreduras completas do corpo nos dois sentidos na
## entrada da rodovia/obra e checagens da câmera de terreno. Isto não é teste de FPS.
const LAYOUT := preload("res://world/mining/MiningLayout.gd")
const EXTERIOR := preload("res://world/mining/MiningExterior.gd")
const REGION := preload("res://world/desert/DesertRegion.gd")
const DESERT := preload("res://world/desert/DesertLayout.gd")
const CAMERA := preload("res://world/desert/DesertTerrainCamera.gd")
var failures: Array[String]=[]
var checks := 0
var region: Node3D
var sweep_reports: Array[Dictionary]=[]
var _last_cell := Vector2i(99999,99999)

func _initialize() -> void:
	create_timer(150).timeout.connect(func(): push_error("MINING_ACCESS timeout"); quit(3))
	_run.call_deferred()

func _check(value: bool, label: String) -> void:
	checks+=1
	print("MINING_ACCESS ","PASS " if value else "FAIL ",label)
	if not value: failures.append(label)

func _run() -> void:
	var authored := LAYOUT.roads()
	_check(authored.size()==2 and authored[0].id=="mining_access" and authored[1].id=="mining_haul_road" and not authored[0].traffic and not authored[1].traffic,"access and descending haul road are private dirt routes, excluded from public ambient traffic")
	var haul: PackedVector3Array=authored[1].points
	var length := 0.0
	var steepest := 0.0
	for i in range(1,haul.size()):
		var difference: Vector3=haul[i]-haul[i-1]
		length+=difference.length()
		steepest=maxf(steepest,absf(difference.y)/maxf(Vector2(difference.x,difference.z).length(),.001))
	_check(haul[0].distance_to(LAYOUT.GATE)<.001 and haul[-1].y<-27.5 and length>500 and steepest<.14,"continuous 14 m spiral reaches a real 28 m excavation with truck-compatible gradient")
	var highway: Dictionary={}
	for road in DESERT.roads():
		if road.id=="desert_salt_highway": highway=road
	var start: Vector3=authored[0].points[0]
	var p := Vector2(start.x,start.z)
	var junction_distance := INF
	for i in range(1,highway.points.size()):
		var a := Vector2(highway.points[i-1].x,highway.points[i-1].z)
		var b := Vector2(highway.points[i].x,highway.points[i].z)
		junction_distance=minf(junction_distance,p.distance_to(Geometry2D.get_closest_point_to_segment(p,a,b)))
	_check(junction_distance<.001 and is_zero_approx(start.y),"private access actually meets the highway at the same elevation")
	region=REGION.build_region("desert",LAYOUT.GATE+Vector3(0,0,20))
	root.add_child(region)
	for frame in 900:
		await physics_frame
		if region.is_streaming_idle(): break
	_check(region.is_streaming_idle(),"real desert streaming settles at access and guardhouse")
	var map_route: Dictionary={}
	for road in region.map_routes():
		if road.id=="mining_access": map_route=road
	_check(not map_route.is_empty() and map_route.points==authored[0].points,"map/geography expose the same centreline as dirt geometry and clearance")
	for path_point: Vector3 in authored[0].points:
		_check(not LAYOUT.reservation_clear(Vector2(path_point.x,path_point.z),5),"procedural props cannot occupy authored mining approach: "+str(path_point))
	_check(not LAYOUT.reservation_clear(Vector2(LAYOUT.GATE.x,LAYOUT.GATE.z),5),"procedural props cannot occupy the mining entrance")
	if "--diagnostic-only" in OS.get_cmdline_user_args():
		await _sweep("giant_diagnostic",Vector3(4.6,4.2,8.0),false)
		region.free()
		print("MINING_ACCESS_DIAGNOSTIC ",JSON.stringify(sweep_reports))
		quit(0 if failures.is_empty() else 1)
		return
	await _sweep("ordinary_car",Vector3(2.1,1.35,4.8),false)
	await _sweep("ordinary_car_return",Vector3(2.1,1.35,4.8),true)
	await _sweep("giant_haul_truck",Vector3(4.6,4.2,8.0),false)
	await _sweep("giant_haul_truck_return",Vector3(4.6,4.2,8.0),true)
	await _benches_and_camera()
	region.free()
	print("MINING_ACCESS_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"sweeps":sweep_reports,"note":"Actual region colliders, whole-body casts/intersections and four footprint support rays at <=0.5m intervals. No input steering or visual/FPS claim."}))
	quit(0 if failures.is_empty() else 1)

func _sweep(id: String,size: Vector3,reverse: bool) -> void:
	var path: PackedVector3Array=LAYOUT.roads()[0].points.duplicate()
	var haul: PackedVector3Array=LAYOUT.roads()[1].points
	for i in range(1,haul.size()): path.append(haul[i])
	if reverse: path.reverse()
	var shape := BoxShape3D.new()
	shape.size=size
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape=shape
	query.collision_mask=3
	query.margin=.025
	var space := region.get_world_3d().direct_space_state
	var collisions: Array[String]=[]
	var support_failures := 0
	var samples := 0
	var casts_blocked := 0
	var details: Array[Dictionary]=[]
	var seen_shapes: Dictionary={}
	var support_details: Array[Dictionary]=[]
	for i in range(1,path.size()):
		var a: Vector3=path[i-1]
		var b: Vector3=path[i]
		await _ensure_at((a+b)*.5)
		var direction := (b-a).normalized()
		var basis := Basis.looking_at(direction,Vector3.UP)
		var count := ceili(a.distance_to(b)/.5)
		for step in range(count+1):
			var point := a.lerp(b,float(step)/float(count))
			var center := point+basis.y*(size.y*.5+.22)
			query.transform=Transform3D(basis,center)
			query.motion=Vector3.ZERO
			for hit in space.intersect_shape(query,8):
				var label := str(hit.collider.get_path())
				if not collisions.has(label): collisions.append(label)
				_contact_detail(hit,point,i,"straight",details,seen_shapes)
			if step<count:
				query.motion=(b-a)/float(count)
				var sweep := space.cast_motion(query)
				if sweep[0]<.999: casts_blocked+=1
			for side in [-1.0,1.0]:
				for end in [-1.0,1.0]:
					var corner := point+basis*Vector3(float(side)*size.x*.5,0,float(end)*size.z*.5)
					var ray := PhysicsRayQueryParameters3D.create(corner+Vector3.UP*.45,corner-Vector3.UP*.3,1)
					var hit := space.intersect_ray(ray)
					if hit.is_empty() or absf(float(hit.position.y)-corner.y)>.15:
						support_failures+=1
						if support_details.size()<24:
							var support:={"segment":i,"point":str(point),"corner":str(corner),"surface":EXTERIOR.surface_height(Vector2(corner.x,corner.z)),"hit":str(hit.get("position",Vector3.INF)),"collider":str(hit.collider.get_path()) if not hit.is_empty() else "none"}
							support_details.append(support)
							print("MINING_SUPPORT_DETAIL ",JSON.stringify(support))
			samples+=1
			if samples%80==0: await physics_frame
		# Confere o envelope completo de curva, não só os dois rumos retos.
		if i<path.size()-1:
			var next := (path[i+1]-b).normalized()
			for turn in range(1,9):
				var turning_basis := Basis.looking_at(direction.lerp(next,float(turn)/8.0).normalized(),Vector3.UP)
				query.transform=Transform3D(turning_basis,b+turning_basis.y*(size.y*.5+.22))
				query.motion=Vector3.ZERO
				for hit in space.intersect_shape(query,8):
					var label := str(hit.collider.get_path())
					if not collisions.has(label): collisions.append(label)
					_contact_detail(hit,b,i,"turn",details,seen_shapes)
	var report := {"id":id,"samples":samples,"solid_contacts":collisions,"blocked_casts":casts_blocked,"missing_or_high_support":support_failures,"contact_details":details,"support_details":support_details}
	sweep_reports.append(report)
	_check(samples>1300 and collisions.is_empty() and casts_blocked==0 and support_failures==0,"whole physical vehicle clears highway, gate and full descent/ascent: "+id+" "+JSON.stringify(report))

func _contact_detail(hit: Dictionary,point: Vector3,segment: int,phase: String,details: Array[Dictionary],seen: Dictionary) -> void:
	var body: CollisionObject3D=hit.collider
	var owner_id:=body.shape_find_owner(int(hit.shape))
	var shape: Node=body.shape_owner_get_owner(owner_id)
	var label:=str(shape.get_path()) if is_instance_valid(shape) else str(body.get_path())+" shape="+str(hit.shape)
	if seen.has(label): return
	seen[label]=true
	var detail:={"point":str(point),"segment":segment,"phase":phase,"shape":label,"shape_position":str(shape.global_position) if shape is Node3D else "none"}
	if shape is CollisionShape3D:
		detail["shape_resource"]=str(shape.shape)
		if shape.shape is BoxShape3D: detail["shape_size"]=str(shape.shape.size)
	details.append(detail)
	print("MINING_CONTACT_DETAIL ",JSON.stringify(detail))

func _ensure_at(point: Vector3) -> void:
	var cell := Vector2i(floori(point.x/96),floori(point.z/96))
	if cell==_last_cell: return
	_last_cell=cell
	region.set_focus(point)
	region.prepare_collision_at(point)
	for frame in 600:
		await physics_frame
		if region.is_streaming_idle(): break
	await physics_frame

func _benches_and_camera() -> void:
	var probes := [LAYOUT.CENTER+Vector3(0,0,-80),LAYOUT.CENTER+Vector3(2,0,-104),LAYOUT.CENTER+Vector3(-73,0,-58),LAYOUT.SECRET_RETURN]
	for point in probes:
		region.set_focus(point)
		region.prepare_collision_at(point)
		await physics_frame
		await physics_frame
		var ray := PhysicsRayQueryParameters3D.create(Vector3(point.x,32,point.z),Vector3(point.x,-34,point.z),1)
		var hit := region.get_world_3d().direct_space_state.intersect_ray(ray)
		var expected := EXTERIOR.surface_height(Vector2(point.x,point.z))
		_check(not hit.is_empty() and absf(float(hit.position.y)-expected)<.04,"height API agrees with rendered terrain collision at "+str(point))
	var camera := CAMERA.new()
	var clearance_failures := 0
	for point in [LAYOUT.SECRET_RETURN+Vector3.UP*.85,LAYOUT.CENTER+Vector3(24,-27.15,-20),LAYOUT.CENTER+Vector3(0,-27.15,0)]:
		for i in 8:
			var offset := Vector3(0,25.3,25.3).rotated(Vector3.UP,float(i)*TAU/8.0)
			camera.offset_for(point,offset,.1,true,true,Vector2(43,24),.1,point,.6,Vector3.ZERO)
			var diagnostic: Dictionary=camera.diagnostics()
			if not diagnostic.active or diagnostic.pitch_limit_reached or float(diagnostic.near_plane_conservative_clearance)<.95: clearance_failures+=1
	_check(clearance_failures==0,"quarry camera near-plane and target solver clears all eight headings at three work-floor locations")

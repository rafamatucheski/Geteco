extends SceneTree
## Layout novo do acostamento: orçamento, folga sólida real, espectadores protegidos e
## as faixas livres de corrida/serviço. Não infere aparência nem tempo de quadro.
const MEET:=preload("res://world/desert/drag_meet/DesertDragMeet.gd")
const G:=preload("res://world/desert/DesertGeometry.gd")
const COVER:=preload("res://world/desert/DesertGroundCover.gd")
var failures: Array[String]=[]
var checks:=0

func _initialize() -> void:
	create_timer(60).timeout.connect(func(): push_error("MEET_COMPOSITION timeout"); quit(3))
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	print("MEET_COMPOSITION ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func run() -> void:
	var scene:=Node3D.new()
	root.add_child(scene)
	var strip:=MEET.strip_records()
	var people:=strip.filter(func(row): return row.type=="strip_spectator")
	var cars:=strip.filter(func(row): return row.type=="strip_car")
	check(people.size()==24 and cars.size()==12,"redistribution preserves 24 people and 12 cars")
	var identities: Dictionary={}
	var groups: Dictionary={}
	for row in people:
		identities[row.data.identity]=true
		groups[row.data.focus.x]=true
	check(identities.size()==24 and groups.size()==8,"eight groups retain unique actor identities")
	var points: Array=groups.keys()
	points.sort()
	var largest:=0.0
	for index in range(1,points.size()): largest=maxf(largest,float(points[index])-float(points[index-1]))
	check(largest<=143.0 and points[0]<=-898 and points[-1]>=-105,"course pockets cover start through finish without the former 199 m gap")
	var records:=MEET.records()
	check(records.filter(func(row): return row.get("type","")=="tent").size()==7,"no additional tent budget")
	var floor_material:=StandardMaterial3D.new()
	G.quad(scene,"ShoulderFloor",PackedVector3Array([Vector3(-940,0,-1360),Vector3(110,0,-1360),Vector3(110,0,-1300),Vector3(-940,0,-1300)]),floor_material,true)
	for row in records:
		if row.get("kind","")!="drag_meet" or row.get("type","")=="strip_spectator": continue
		if row.position.z<=-1328 and row.position.z>=-1344: MEET.build_record(scene,row)
	for frame in 3: await physics_frame
	var space:=scene.get_world_3d().direct_space_state
	var capsule:=CapsuleShape3D.new()
	capsule.radius=.32
	capsule.height=1.7
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=capsule
	query.collision_mask=1
	var clear:=true
	var protected:=true
	for row in people:
		query.transform=Transform3D(Basis(),row.position+Vector3.UP*.9)
		if not space.intersect_shape(query,1).is_empty(): clear=false
		var ray:=PhysicsRayQueryParameters3D.create(row.position+Vector3.UP*.55,Vector3(row.position.x,.58,-1320),1)
		if space.intersect_ray(ray).is_empty(): protected=false
	check(clear,"all 24 actual spawn capsules clear parked vehicles, tent posts and equipment")
	check(protected,"each spectator has an actual solid between them and the racing lane")
	var car_shape:=BoxShape3D.new()
	car_shape.size=Vector3(4.8,1.5,2.2)
	query.shape=car_shape
	var roads_clear:=true
	for z in [-1322.0,-1318.0,-1350.0]:
		for x in range(-936,91,3):
			query.transform=Transform3D(Basis(),Vector3(x,.85,z))
			if not space.intersect_shape(query,1).is_empty(): roads_clear=false
	check(roads_clear,"two race lanes and the service return remain clear for a car-sized hull")
	var aabb_node:=MultiMeshInstance3D.new()
	var batch:=MultiMesh.new()
	batch.transform_format=MultiMesh.TRANSFORM_3D
	batch.use_colors=true
	batch.mesh=COVER.meshes()[0]
	batch.instance_count=2
	batch.set_instance_transform(0,Transform3D(Basis(),Vector3(-960,0,-1440)))
	batch.set_instance_transform(1,Transform3D(Basis(),Vector3(-864,0,-1344)))
	batch.set_instance_color(0,Color(.8,.9,.7))
	batch.set_instance_color(1,Color(.9,.8,.7))
	aabb_node.multimesh=batch
	scene.add_child(aabb_node)
	var saved:=batch.buffer.duplicate()
	COVER.configure_drag_visibility(aabb_node,0)
	var material:=aabb_node.material_override as StandardMaterial3D
	check(saved==batch.buffer and batch.instance_count==2,"spatial fade preserves instance transforms, colours and breakable indices")
	check(material.distance_fade_mode==BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER and material.distance_fade_min_distance>material.distance_fade_max_distance,"Mobile-supported material fades away toward the far distance")
	check(aabb_node.visibility_range_end>material.distance_fade_min_distance+aabb_node.get_aabb().size.length()*.5,"batch culling cannot cut an instance before its full fade distance")
	check(COVER.material().distance_fade_mode==BaseMaterial3D.DISTANCE_FADE_DISABLED,"global desert material remains unchanged")
	print("MEET_COMPOSITION checks=",checks," failures=",failures.size())
	scene.free()
	quit(0 if failures.is_empty() else 1)

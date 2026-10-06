extends SceneTree
## Physical regression for airborne permanent glass/litter after car impacts.
const PROJECTION := preload("res://gameplay/street_physics/DebrisGroundProjection.gd")
class DebrisDirector:
	extends "res://gameplay/street_physics/StreetPhysics.gd"
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func box(size: Vector3, at: Vector3, layer := 1, rotation_z := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var geometry := BoxShape3D.new()
	geometry.size = size
	shape.shape = geometry
	body.add_child(shape)
	root.add_child(body)
	body.position = at
	body.rotation.z = rotation_z
	return body

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	box(Vector3(12,1,12),Vector3(0,-.5,0))
	box(Vector3(3,1.5,5),Vector3(0,1.2,0),4) # Vehicle roof must not hold debris.
	var slope := box(Vector3(8,1,8),Vector3(20,2,0),1,.18)
	box(Vector3(8,1,8),Vector3(40,7.5,0)) # Elevated bridge deck.
	box(Vector3(8,1,8),Vector3(40,-.5,0))
	box(Vector3(4,1,8),Vector3(58,-.5,0)) # Drop at x=60.
	box(Vector3(4,1,8),Vector3(62,-2.5,0))
	await physics_frame
	await physics_frame
	var space := root.world_3d.direct_space_state
	var offsets: Array[Vector3] = [Vector3(-.1,0,-.1),Vector3(.15,0,0),Vector3(0,0,.15)]
	var flat := PROJECTION.triangle(space,Vector3(0,2,0),offsets)
	check(flat.size()==3,"project glass from window height onto ground")
	for vertex in flat: check(absf(vertex.y-PROJECTION.LIFT)<.002,"vehicle roof excluded, shard on actual floor")
	# Compare with generated productive paving, not merely the physics plane.
	# A .008 lift passed the physical check but hid glass below these overlays.
	var paving := Node3D.new()
	root.add_child(paving)
	var roads = preload("res://world/urban_detail/HarborRoadGeometry3D.gd").new()
	var source_roads: Array[Dictionary] = [{"id":"debris_paving","points":PackedVector3Array([Vector3(-6,0,0),Vector3(6,0,0)]),"width":6.0,"crossings":false}]
	roads.configure(source_roads)
	roads.build_chunk(paving,Rect2(-8,-8,16,16))
	var bay = preload("res://world/roadside_parking/RoadsideParkingBay.gd").build(paving,
		{"id":"debris_paving","region":"harbor","edge":Vector3(0,0,8),"position":Vector3(0,.045,10.25),
		"forward":Vector3.RIGHT,"outward":Vector3.BACK,"road_width":6.0,"half_length":5.9,
		"slots":[{}],"surface":"asphalt","yaw":-PI*.5})
	var road_visual_y := 0.0
	for child in paving.get_children():
		if child is MeshInstance3D and str(child.name).ends_with(roads.ROAD_COLOR.to_html(false)):
			road_visual_y = child.global_position.y+child.mesh.get_aabb().position.y
	var bay_mesh: MeshInstance3D = bay.get_node("PullOffSurface")
	var bay_visual_y := bay_mesh.global_position.y+bay_mesh.mesh.get_aabb().position.y
	check(road_visual_y>0.0 and bay_visual_y>0.0,"actual generated road/bay overlays are above collision")
	for vertex in flat:
		check(vertex.y>maxf(road_visual_y,bay_visual_y) and vertex.y<=.04,"glass remains visible above real paving within 4 cm of support")
	paving.free()
	var elevated := PROJECTION.triangle(space,Vector3(40,9.2,0),offsets)
	check(elevated.size()==3,"bridge deck supports fragments")
	for vertex in elevated: check(absf(vertex.y-8-PROJECTION.LIFT)<.002,"bridge fragments stay on deck, not global y=0")
	var sloping := PROJECTION.triangle(space,Vector3(20,3.5,0),offsets)
	check(sloping.size()==3,"sloping terrain supports fragments")
	for vertex in sloping:
		var local := slope.to_local(vertex)
		check(absf(local.y-(.5+PROJECTION.LIFT))<.002,"vertices follow the slope plane")
	check(PROJECTION.triangle(space,Vector3(59.99,1.2,0),offsets).is_empty(),"one triangle cannot bridge a ledge")
	check(PROJECTION.triangle(space,Vector3(100,1.2,0),offsets).is_empty(),"missing ground does not create suspended fragments")
	var director := DebrisDirector.new()
	root.add_child(director)
	seed(71006)
	director.spawn_glass(Vector3(0,1.3,0),Vector3.RIGHT)
	check(director._litter.size()==1,"glass creates one grouped ground mesh")
	var fragments: MeshInstance3D = director._litter[0]
	check(not fragments.visible,"ground glass waits for the falling burst")
	for vertex: Vector3 in fragments.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		check(absf(fragments.to_global(vertex).y-PROJECTION.LIFT)<.002,"generated permanent glass lies on ground")
	var burst: CPUParticles3D
	for child in director.get_children():
		if child is CPUParticles3D: burst = child
	check(is_instance_valid(burst),"glass has falling transient particles")
	if is_instance_valid(burst):
		check(burst.global_position.is_equal_approx(Vector3(0,1.3,0)),"burst uses real impact height without additional lift")
		check(burst.gravity.y<0 and burst.one_shot,"transient burst falls and expires")
	await create_timer(.7).timeout
	check(fragments.visible,"ground fragments become visible after falling interval")
	var original_count := director._litter.size()
	director.spawn_litter(Vector3(100,1.2,0),Vector3.RIGHT)
	check(director._litter.size()==original_count,"unsupported scatter allocates no mesh")
	for index in 30:
		director._scatter(Vector3(0,1.3,0),Vector3.RIGHT,1,Vector2(.04,.09),Color.WHITE,.9,.01)
	check(director._litter.size()==24,"ground debris keeps existing 24-group bound")
	await process_frame
	var live := 0
	for child in director.get_children():
		if child is MeshInstance3D: live += 1
	check(live<=24,"evicted debris is actually freed")
	await create_timer(4.2).timeout
	live = 0
	for child in director.get_children():
		if child is MeshInstance3D: live += 1
	check(live==0,"ground debris expires after lifetime and fade")
	director.free()
	print("GROUND_DEBRIS_PROJECTION ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)

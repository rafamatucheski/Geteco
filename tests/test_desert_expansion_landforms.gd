extends SceneTree
## Finite physical contracts. The parent task owns serialized real-scene captures
## and frame-time comparison; this test does not approve appearance or FPS.
const LANDFORMS := preload("res://world/desert/expansion/DesertLandforms.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const GEOMETRY := preload("res://world/desert/DesertGeometry.gd")
var failures: Array[String] = []
var checks := 0
var built: Node3D

func _initialize() -> void:
	create_timer(60).timeout.connect(func(): push_error("DESERT_EXPANSION_LANDFORMS timeout"); quit(3))
	_run.call_deferred()

func _check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures.append(label)

func _base_height(point: Vector2) -> float:
	return LAYOUT.surface_height(point)

func _run() -> void:
	var invalid := Node3D.new()
	_check(LANDFORMS.build_chunk(invalid,Rect2(-96,-672,96,96),6102026,Callable())==0 and invalid.get_child_count()==0,"Missing support callable never emits floating geometry")
	invalid.free()
	var road_conflicts := 0
	for road in LAYOUT.roads():
		for point in road.points:
			if LANDFORMS.placement_clear(Vector2(point.x,point.z),1.0): road_conflicts+=1
	_check(road_conflicts==0,"Every authored road rejects new solid footprints")
	for building in LAYOUT.buildings():
		_check(not LANDFORMS.placement_clear(Vector2(building.position.x,building.position.z),1.0),"Building reserve retained: "+str(building.id))
	_check(LANDFORMS.reservation_clear(Vector2(-900,-1750),4.0),"Expansion leaves the existing canyon untouched")
	_check(not LANDFORMS.placement_clear(Vector2(-900,-1750),4.0),"Expansion cannot generate southern canyon props")
	var cells: Dictionary = {}
	for location in LANDFORMS.locations():
		var cell := Vector2i(floori(location.position.x/96.0),floori(location.position.z/96.0))
		for x in range(-1,2):
			for z in range(-1,2): cells[cell+Vector2i(x,z)]=true
	built=Node3D.new()
	built.name="DesertExpansionLandformsTest"
	root.add_child(built)
	var first_count := 0
	for cell in cells:
		var rect := Rect2(Vector2(cell)*96.0,Vector2.ONE*96.0)
		var chunk := Node3D.new()
		chunk.name="Chunk_%d_%d"%[cell.x,cell.y]
		built.add_child(chunk)
		first_count+=LANDFORMS.build_chunk(chunk,rect,6102026,_base_height)
		GEOMETRY.quad(chunk,"ExistingGround",PackedVector3Array([
			Vector3(rect.position.x,0,rect.position.y),Vector3(rect.end.x,0,rect.position.y),
			Vector3(rect.end.x,0,rect.end.y),Vector3(rect.position.x,0,rect.end.y)
		]),GEOMETRY.material(Color("b9a079"),true),true)
	_check(first_count>0,"Authored neighbourhoods produce actual landforms")
	var ids: Dictionary = {}
	for node in built.find_children("*","Node3D",true,false):
		var id: String = node.get_meta("desert_landform_id","")
		if not id.is_empty(): ids[id]=int(ids.get(id,0))+1
	_check(ids.size()==4 and ids.values().all(func(count): return int(count)==1),"Arch and three rock families have exactly one owner across adjacent chunks")
	await physics_frame
	await physics_frame
	var unsupported := 0
	var mismatched := 0
	var unsafe_slopes := 0
	var sampled := 0
	for mesh in built.find_children("*","MeshInstance3D",true,false):
		if not mesh.get_meta("desert_expansion_ground",false): continue
		var arrays: Array = mesh.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in range(0,vertices.size(),27):
			if i+2>=vertices.size(): break
			var position: Vector3 = mesh.to_global((vertices[i]+vertices[i+1]+vertices[i+2])/3.0)
			var hit := _ray(position+Vector3.UP*4.0,position-Vector3.UP*4.0)
			sampled+=1
			if hit.is_empty(): unsupported+=1
			elif absf(float(hit.position.y)-position.y)>.025: mismatched+=1
			if normals[i].y<cos(deg_to_rad(30.0)): unsafe_slopes+=1
	_check(sampled>100,"Physical oracle samples dune, wash and salt interiors")
	_check(unsupported==0 and mismatched==0,"Rendered ground is supported within 2.5cm: missing=%d mismatch=%d"%[unsupported,mismatched])
	_check(unsafe_slopes==0,"Authored banks and dunes remain within a thirty-degree walking slope")
	var height_mismatches := 0
	for x in range(-54,5,2):
		var point := Vector2(float(x),-622.0)
		var expected: float = LANDFORMS.surface_height(point,_base_height)
		var hit := _ray(Vector3(point.x,5,point.y),Vector3(point.x,-1,point.y))
		if hit.is_empty() or absf(float(hit.position.y)-expected)>.004: height_mismatches+=1
	_check(height_mismatches==0,"Exact height API matches real dune collision along the crossing")
	var dune_crest := _ray(Vector3(-25,5,-622),Vector3(-25,-1,-622))
	_check(not dune_crest.is_empty() and float(dune_crest.position.y)>1.7,"Dunes have real elevation and physical support")
	_check(_ray(Vector3(-790,1.1,-707),Vector3(-790,1.1,-673)).is_empty(),"Natural arch has a traversable opening")
	_check(not _ray(Vector3(-804,1,-690),Vector3(-798,1,-690)).is_empty(),"Arch foot blocks a body instead of being visual only")
	_check(not _ray(Vector3(-790,15,-690),Vector3(-790,3,-690)).is_empty(),"Arch roof has matching physical support")
	for id in ["desert_hoodoo","desert_basalt_fan","desert_balanced_rock"]:
		var found := false
		for location in LANDFORMS.locations():
			if location.id!=id: continue
			var at: Vector3 = location.position
			var hit := _ray(at+Vector3.UP*20,at+Vector3.UP*.1)
			found=not hit.is_empty() and float(hit.position.y)>2.0
		_check(found,"Distinct large rock is physically solid: "+id)
	var seam := -672.0
	var crossing := 0
	for x in range(-804,-775,3):
		var a := Vector3(float(x),15,seam-.01)
		var b := Vector3(float(x),15,seam+.01)
		if _ray(a,a-Vector3.UP*16).is_empty() or _ray(b,b-Vector3.UP*16).is_empty(): crossing+=1
	_check(crossing==0,"Ground persists across the arch neighbourhood chunk seam")
	var deterministic_a := Node3D.new()
	var deterministic_b := Node3D.new()
	var test_rect := Rect2(-96,-672,96,96)
	LANDFORMS.build_chunk(deterministic_a,test_rect,6102026,_base_height)
	LANDFORMS.build_chunk(deterministic_b,test_rect,6102026,_base_height)
	_check(_signature(deterministic_a)==_signature(deterministic_b),"Leaving and rebuilding a chunk preserves geometry and placement")
	deterministic_a.free()
	deterministic_b.free()
	await _dune_entry_sweep()
	built.free()
	for failure in failures: push_error(failure)
	print("DESERT_EXPANSION_LANDFORMS_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"ground_samples":sampled,"landforms":first_count}))
	quit(0 if failures.is_empty() else 1)

func _dune_entry_sweep() -> void:
	# Avertical ray allowed the former16mm skirt, but an ordinary upright vehicle
	# box struck its open edge as a wall. Reproduce that physical entry directly.
	var body := CharacterBody3D.new()
	body.name="BisonSizedDuneEntrySweep"
	body.collision_layer=4
	body.collision_mask=1
	body.floor_snap_length=.4
	var shape := BoxShape3D.new()
	shape.size=Vector3(2.04,1.83,5.20)
	var collider := CollisionShape3D.new()
	collider.shape=shape
	collider.position.y=.915
	body.add_child(collider)
	built.add_child(body)
	body.position=Vector3(-54,.12,-622)
	body.rotation.y=-PI*.5
	var maximum_y := body.position.y
	var walls: Array[String]=[]
	for i in 600:
		await physics_frame
		var step := 1.0/float(Engine.physics_ticks_per_second)
		body.velocity=Vector3(3.0,0.0 if body.is_on_floor() else body.velocity.y-20.0*step,0)
		body.move_and_slide()
		maximum_y=maxf(maximum_y,body.position.y)
		for slide in body.get_slide_collision_count():
			var hit := body.get_slide_collision(slide)
			if absf(hit.get_normal().y)<.65:
				var label := str(hit.get_collider().get_path())+" normal="+str(hit.get_normal())
				if not walls.has(label): walls.append(label)
		if body.position.x>=-38.0: break
	_check(body.position.x>=-38.0 and maximum_y>.4 and walls.is_empty(),"Bison-sized physical box enters dune continuously: position=%s peak=%.3f walls=%s"%[body.position,maximum_y,walls])
	body.free()

func _ray(start: Vector3,end: Vector3) -> Dictionary:
	return root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start,end,1))

func _signature(parent: Node3D) -> String:
	var parts := PackedStringArray()
	for node in parent.find_children("*","MeshInstance3D",true,false):
		var arrays: Array = node.mesh.surface_get_arrays(0)
		parts.append(str(node.name)+str(node.transform)+str(hash(arrays[Mesh.ARRAY_VERTEX]))+str(hash(arrays[Mesh.ARRAY_COLOR])))
	return "|".join(parts)

extends SceneTree

const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const REGION := preload("res://world/regions/NativeRegion.gd")
const TERRACE := preload("res://world/urban_detail/HarborRestaurantTerrace3D.gd")
const DRESSING := preload("res://world/urban_detail/HarborAreaDressing3D.gd")
const SCALE := 1.0/16.0

var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: return
	failures.append(label)
	push_error("FAIL: "+label)

func run() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var connection := CONNECTION.new()
	fixture.add_child(connection)
	await physics_frame
	var gap := connection.get_node_or_null("HarborConnectorGapAsphalt") as MeshInstance3D
	var gap_collision := connection.get_node_or_null("HarborConnectorGapCollision") as MeshInstance3D
	check(gap != null and gap.mesh != null,"Seam owns the V1-shaped asphalt gap")
	check(gap_collision != null and gap_collision.find_child("HarborConnectorGapBody",true,false)!=null,"Seam owns one dedicated non-road support surface")
	var polygon := CONNECTION.inner_gap_polygon()
	check(polygon.size()==26,"Seam samples both V1 lane envelopes at 13 points")
	check(is_equal_approx(polygon[0].x,6500.0*SCALE) and is_equal_approx(polygon[12].x,7300.0*SCALE),"Seam asphalt spans the original inbound lane end through the bridge junction")
	var gap_point := (polygon[6]+polygon[19])*.5
	var seam_ray := PhysicsRayQueryParameters3D.create(Vector3(gap_point.x,2,gap_point.y),Vector3(gap_point.x,-.2,gap_point.y),1)
	var seam_hit := fixture.get_world_3d().direct_space_state.intersect_ray(seam_ray)
	check(not seam_hit.is_empty() and seam_hit.collider.name=="HarborConnectorGapBody","Gap collision supports the exposed convergence before the lower deck")

	var expected := {
		"anchor":[Vector2(555,1132),Vector2(685,1132)],
		"tideline":[Vector2(5735,1644),Vector2(5845,1644)],
		"early_shift":[Vector2(6145,-1238),Vector2(6255,-1238)]}
	var region := REGION.build_region("harbor",Vector3(620*SCALE,0,1132*SCALE))
	fixture.add_child(region)
	await process_frame
	var found := {}
	for values in region.records.values():
		for record in values:
			if record.kind != "harbor_restaurant": continue
			if not found.has(record.venue_id): found[record.venue_id] = []
			found[record.venue_id].append(Vector2(record.position.x,record.position.z)/SCALE)
	for venue_id in expected:
		check(found.has(venue_id) and found[venue_id].size()==2,"%s keeps both productive tables"%venue_id)
		for point in expected[venue_id]: check(found.get(venue_id,[]).has(point),"%s keeps exact anchor %s"%[venue_id,point])

	var terrace := TERRACE.new()
	terrace.configure("anchor",0,Color("b96a46"))
	terrace.position = Vector3(0,0,25)
	fixture.add_child(terrace)
	for zone in ["cobra","salvage","cemetery"]:
		var dressing := DRESSING.new()
		dressing.configure(zone)
		dressing.position = Vector3(40+fixture.get_child_count()*50,0,0)
		fixture.add_child(dressing)
	await physics_frame
	var parasol := terrace.get_node_or_null("Parasol")
	check(parasol != null and parasol.get_child_count()==8,"Restaurant includes the original eight-panel parasol")
	var furniture_body := terrace.get_node_or_null("TerraceFurnitureSolid") as StaticBody3D
	check(furniture_body != null and furniture_body.get_child_count()==3,"Table and both chairs have explicit collision")
	var walker := CharacterBody3D.new()
	walker.collision_layer = 2
	walker.collision_mask = 1
	var walker_shape := CollisionShape3D.new()
	var walker_capsule := CapsuleShape3D.new()
	walker_capsule.radius = .28
	walker_capsule.height = 1.7
	walker_shape.shape = walker_capsule
	walker_shape.position.y = .85
	walker.add_child(walker_shape)
	fixture.add_child(walker)
	walker.position = Vector3(-2.0,0,25)
	check(walker.move_and_collide(Vector3(1.4,0,0),true)!=null,"Restaurant chair physically blocks pedestrian traversal")
	check(terrace.find_children("*","SubViewport",true,false).is_empty(),"Terrace uses direct native geometry")
	for child in fixture.get_children():
		if child.get_script()==DRESSING:
			check(child.get_node_or_null("AuthoredDressingSolids")!=null,"%s dressing exposes separate collision"%child.zone_id)
			check(not child.find_children("*","MeshInstance3D",true,false).is_empty(),"%s dressing exposes separate occluding geometry"%child.zone_id)

	print("HARBOR_FIDELITY_CONTRACT_%s failures=%d"%["PASS" if failures.is_empty() else "FAIL",failures.size()])
	quit(0 if failures.is_empty() else 1)

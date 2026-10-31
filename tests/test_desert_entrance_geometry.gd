extends SceneTree
const BOUNDARY:=preload("res://world/regions/ScenarioBoundary3D.gd")
const BRIDGE:=preload("res://world/north_gateway/NorthGatewayLayout.gd")
var failed:=false
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	print("ENTRANCE_GEOMETRY ","PASS " if value else "FAIL ",label)
	failed=failed or not value
func run() -> void:
	# A mesma serra fechada precisa encarar o observador de qualquer lado, nos dois eixos.
	for vertical in [true,false]:
		var parent:=Node3D.new()
		BOUNDARY._strip(parent,Rect2(-20,-20,40,40),Vector2(0,-8) if vertical else Vector2(-8,0),Vector2(0,8) if vertical else Vector2(8,0),func(_p: Vector2): return 0.0,false)
		var mesh: Mesh=parent.get_child(0).mesh
		var faces:=mesh.get_faces()
		var all_outward:=true
		var side_faces:=0
		for i in range(0,faces.size(),3):
			var center: Vector3=(faces[i]+faces[i+1]+faces[i+2])/3
			var normal: Vector3=(faces[i+2]-faces[i]).cross(faces[i+1]-faces[i]).normalized()
			var across: float=center.x if vertical else center.z
			var lateral: float=normal.x if vertical else normal.z
			if absf(across)>4.5 and center.y> -15 and center.y<1 and absf(lateral)>.5:
				side_faces+=1
				all_outward=all_outward and lateral*across>0
		check(side_faces>0 and all_outward,"opaque outward faces for "+("north/south" if vertical else "east/west")+" extrusion")
		parent.free()
	check(is_equal_approx(BRIDGE.deck_half_width(Vector3(342.5,2.4,-373.5)),6.2),"bridge meets 10m road with usable sidewalks")
	var previous:=BRIDGE.deck_half_width(Vector3(342.5,2.4,-343))
	var gradual:=true
	for z in range(344,374):
		var width:=BRIDGE.deck_half_width(Vector3(342.5,2.4,-z))
		gradual=gradual and absf(width-previous)<.05
		previous=width
	check(gradual,"no abrupt widening at former turnaround")
	var body:=StaticBody3D.new()
	body.name="SandstoneVolumes"
	body.position=Vector3(420,14,-574)
	var collider:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=Vector3(40,28,40)
	collider.shape=shape
	body.add_child(collider)
	root.add_child(body)
	for i in 3: await physics_frame
	var safety:=preload("res://world/desert/entrance/DesertBoundaryCamera.gd").new()
	var nominal:=Vector3(19.4,23,19.4)
	var corrected:=safety.offset_for(Vector3(385,0,-590),nominal,Vector2(40,24),.1,.016,true)
	check(corrected.length()>nominal.length() and corrected.normalized().is_equal_approx(nominal.normalized()),"near-plane rock obstruction moves lens back without changing composition")
	var query:=PhysicsShapeQueryParameters3D.new()
	var plane:=BoxShape3D.new()
	plane.size=Vector3(40,24,.2)
	query.shape=plane
	query.transform=Transform3D(Basis.looking_at(-corrected.normalized()),Vector3(385,0,-590)+corrected-corrected.normalized()*.1)
	check(root.world_3d.direct_space_state.intersect_shape(query).is_empty(),"entire corrected near plane clears physical rock")
	check(safety.offset_for(Vector3(0,0,-900),nominal,Vector2(40,24),.1,.016,true)==nominal,"ordinary desert framing is unchanged away from border")
	body.queue_free()
	quit(1 if failed else 0)

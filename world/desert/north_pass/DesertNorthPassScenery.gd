extends RefCounted
const L:=preload("res://world/desert/north_pass/DesertNorthPassLayout.gd")
const G:=preload("res://world/desert/DesertGeometry.gd")
const ROCK:=preload("res://world/desert/DesertSurfaceRocks.gd")

static func build_chunk(parent: Node3D, rect: Rect2, completed:=false) -> void:
	if not L.enabled(): return
	# One continuous cut on either side joins the work barrier and reaches the
	# northern map boundary. Physical hulls are made from the actual mesh.
	for side in [-1,1]:
		var inner: float=L.LEFT_INNER if side<0 else L.RIGHT_INNER
		var outer: float=inner+float(side)*22.0
		var extent:=Rect2(minf(inner,outer),-1950,22,235).intersection(rect)
		if extent.has_area(): _cliff(parent,"NorthPassCliff",extent,side)
	if rect.has_point(Vector2(L.GATE.x,L.GATE.z)):
		var gate:=Node3D.new()
		gate.name="NorthPassRoadworks"
		parent.add_child(gate)
		gate.add_to_group(L.GROUP)
		_cliff(gate,"LandslideSolid",Rect2(L.LEFT_INNER-.5,-1819,L.RIGHT_INNER-L.LEFT_INNER+1,16),0)
		for i in 7:
			ROCK.rock(gate,"FallenSandstone",Vector3(331.8+float(i)*3.5,.7,-1800.8+sin(float(i)*1.5)),Vector3(4.7,2.8,4.2),Color("ae8c64"),true)
		for i in 6:
			var x:=332+float(i)*4.2
			G.box(gate,"ConcreteBarrier",Vector3(x,.62,-1796),Vector3(4.25,1.24,.75),Color("b8ae94"),true)
			for stripe in 4:
				var paint:=G.box(gate,"BarrierWarning",Vector3(x-1.65+float(stripe)*.95,.73,-1795.61),Vector3(.36,.62,.025),Color("d48540"))
				paint.rotation.z=-.3
		# Warning triangle is a functional road sign without explanatory text.
		for x in [334.5,350.5]:
			G.box(gate,"RoadSignPole",Vector3(x,1.05,-1756),Vector3(.095,2.1,.095),Color("757d72"),true)
			var warning_sign:=G.box(gate,"FallingRockWarning",Vector3(x,1.93,-1756),Vector3(.95,.95,.07),Color("d9a843"))
			warning_sign.rotation.z=PI*.25
			for p in [Vector3(-.17,2.15,.047),Vector3(.05,1.92,.047),Vector3(.2,1.71,.047)]:
				G.box(gate,"FallingRockSymbol",Vector3(x,p.y,-1756+p.z)+Vector3(p.x,0,0),Vector3(.17,.18,.025),Color("393e37"))
		set_completed(gate,completed)
	# A safe terminal within existing map bounds. This is no invented map3.
	if rect.has_point(Vector2(L.END.x,L.END.z)):
		G.box(parent,"NorthMapEndGuardrail",L.END+Vector3(0,.73,0),Vector3(26,.44,.25),Color("929b92"),true)
		for x in [-12,-8,-4,0,4,8,12]: G.box(parent,"GuardrailPost",L.END+Vector3(x,.52,0),Vector3(.18,1.04,.18),Color("737b71"),true)

static func set_completed(gate: Node3D, completed: bool) -> void:
	if gate.has_meta("pass_completed") and gate.get_meta("pass_completed")==completed: return
	gate.set_meta("pass_completed",completed)
	gate.visible=not completed
	for body in gate.find_children("*","StaticBody3D",true,false): body.collision_layer=0 if completed else 1

static func _cliff(parent: Node3D, label: String, area: Rect2, side: int) -> void:
	# Global cut lines and functions keep height/silhouette exact at chunk seams.
	var cuts: Array[float]=[area.position.y]
	var cut:=ceilf(area.position.y/12.0)*12.0
	while cut<area.end.y:
		if cut>area.position.y: cuts.append(cut)
		cut+=12.0
	cuts.append(area.end.y)
	var surface:=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in cuts.size()-1:
		var a:=_section(area,cuts[segment],side)
		var b:=_section(area,cuts[segment+1],side)
		for j in a.size():
			var k: int=(j+1)%a.size()
			for point in [a[j],a[k],b[k],a[j],b[k],b[j]]: surface.add_vertex(point)
		# Close chunk ends using the same profile; neighboring sections meet exactly.
		for j in range(1,a.size()-1):
			for point in [a[0],a[j+1],a[j],b[0],b[j],b[j+1]]: surface.add_vertex(point)
	surface.generate_normals()
	var mesh:=surface.commit()
	var node:=MeshInstance3D.new()
	node.name=label
	node.mesh=mesh
	node.material_override=preload("res://world/desert/DesertTerrainMesh.gd").material()
	parent.add_child(node)
	var body:=StaticBody3D.new()
	body.collision_layer=1
	body.collision_mask=0
	var collider:=CollisionShape3D.new()
	collider.shape=mesh.create_trimesh_shape()
	body.add_child(collider)
	node.add_child(body)

static func _section(area: Rect2, z: float, side: int) -> PackedVector3Array:
	# A steep low toe prevents climbing, while the broken crest recedes away
	# from the road so the normal gameplay camera can see actors on shoulders.
	var height:=9.0+2.0*sin(z*.025)+sin(z*.13)
	var profile: Array[Vector2]=[
		Vector2(0,-.6),Vector2(.012,height*.28),Vector2(.08,height*.52),
		Vector2(.31+.025*sin(z*.061),height),Vector2(.60,height*.76),
		Vector2(.86,height*.22),Vector2(1,-.6)]
	if side==0:
		profile=[Vector2(0,-.6),Vector2(.025,height*.38),Vector2(.20,height*.73),Vector2(.48,height),Vector2(.78,height*.81),Vector2(.975,height*.35),Vector2(1,-.6)]
	var points:=PackedVector3Array()
	for sample in profile:
		var x:=area.position.x+area.size.x*sample.x
		if side<0: x=area.end.x-area.size.x*sample.x
		points.append(Vector3(x,sample.y,z))
	if side<0: points.reverse()
	return points

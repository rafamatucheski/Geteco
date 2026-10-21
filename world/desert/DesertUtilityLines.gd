extends RefCounted
## Static distribution network. Shared poles at branch junctions, visible ceramic
## insulators and three continuous sagging conductors; no light or frame loop.
const G := preload("res://world/desert/DesertGeometry.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const HEIGHT := 9.4
const SPACING := 46.0
const WIRE_RADIUS := .038

static func records() -> Array[Dictionary]:
	var poles: Dictionary = {}
	var spans: Array[Dictionary] = []
	# Deliberate shared endpoints keep town and truck-stop feeds connected.
	var lines: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(354.5,-466),Vector2(354.5,-478),Vector2(354.5,-527),Vector2(354.5,-860),Vector2(339.27,-896.77),Vector2(302.5,-912),Vector2(-1020,-912),Vector2(-1020,-888),Vector2(-1039.8,-879.8),Vector2(-1048,-860),Vector2(-1048,-764),Vector2(-1048,-724),Vector2(-1048,-580),Vector2(-1039.8,-560.2),Vector2(-1020,-552),Vector2(-1020,-527)]),
		PackedVector2Array([Vector2(-1020,-527),Vector2(-377,-527),Vector2(-97,-527),Vector2(354.5,-527)]),
		PackedVector2Array([Vector2(-377,-527),Vector2(-377,-652),Vector2(-97,-652),Vector2(-97,-527)]),
		PackedVector2Array([Vector2(354.5,-478),Vector2(316,-478),Vector2(316,-517)]),
	]
	if preload("res://world/desert/north_pass/DesertNorthPassLayout.gd").enabled():
		# Keep both poles and the continuous conductors outside the new north
		# carriageway. The old rounded-corner pole now stood inside its lane.
		lines[0][4]=Vector2(354.5,-912)
	for line in lines:
		var previous := ""
		for i in range(1,line.size()):
			var start := line[i-1]
			var finish := line[i]
			var count := maxi(1,ceili(start.distance_to(finish)/SPACING))
			var direction := start.direction_to(finish)
			for j in range(count+1):
				if i>1 and j==0: continue
				var point := start.lerp(finish,float(j)/count)
				var key := "%d:%d"%[roundi(point.x*100),roundi(point.y*100)]
				if not poles.has(key):
					poles[key]={"kind":"utility_pole","position":Vector3(point.x,LAYOUT.surface_height(point),point.y),"direction":direction,"transformer":false,"id":key}
				if not previous.is_empty() and previous!=key: spans.append({"from":previous,"to":key})
				previous=key
	var result: Array[Dictionary] = []
	for pole: Dictionary in poles.values(): result.append(pole)
	for span in spans:
		var a: Dictionary = poles[span.from]
		var b: Dictionary = poles[span.to]
		result.append({"kind":"utility_span","position":(a.position+b.position)*.5,"a":a.position,"b":b.position,"axis_a":_crossarm(a.direction),"axis_b":_crossarm(b.direction)})
	# Secondary feeds end at visible attachment brackets on occupied buildings.
	for service in [
		{"pole":"31600:-51700","to":Vector3(284.6,3.2,-514.8)},
		{"pole":"-9700:-65200","to":Vector3(-127.1,4.6,-621)},
		{"pole":"-37700:-52700","to":Vector3(-346.7,3.1,-577)},
	]:
		var source: Dictionary = poles[service.pole]
		source.transformer=true
		var start: Vector3 = source.position+Vector3(0,HEIGHT-.8,0)
		var end: Vector3 = service.to
		result.append({"kind":"utility_service","position":(start+end)*.5,"a":start,"b":end})
	return result

static func build_record(parent: Node3D, record: Dictionary) -> void:
	match record.kind:
		"utility_pole": _pole(parent,record)
		"utility_span":
			var curves: Array[PackedVector3Array] = []
			for offset: float in [-.9,0.0,.9]:
				var a: Vector3 = record.a+Vector3.UP*(HEIGHT+.26)+record.axis_a*offset
				var b: Vector3 = record.b+Vector3.UP*(HEIGHT+.26)+record.axis_b*offset
				curves.append(_sag(a,b,clampf(a.distance_to(b)*.016,.28,.8)))
			_wires(parent,curves,"OverheadConductors")
		"utility_service":
			var end: Vector3 = record.b
			G.box(parent,"ServiceBracket",end,Vector3(.24,.35,.18),Color("62584a"))
			G.cylinder(parent,"ServiceInsulator",end+Vector3(0,.18,0),.08,.2,Color("bdbba6"))
			_wires(parent,[_sag(record.a,end,.35)],"BuildingServiceCable")

static func _crossarm(direction: Vector2) -> Vector3:
	return Vector3(-direction.y,0,direction.x)

static func _pole(parent: Node3D, record: Dictionary) -> void:
	var node := Node3D.new(); node.name="UtilityPole"; node.position=record.position
	parent.add_child(node)
	var pole := G.cylinder(node,"WeatheredTimber",Vector3(0,HEIGHT*.5,0),.17,HEIGHT,Color("76604a"),true)
	pole.mesh.top_radius=.105
	var axis := _crossarm(record.direction)
	var arm := G.box(node,"Crossarm",Vector3(0,HEIGHT,0),Vector3(2.35,.14,.13),Color("76604a"))
	arm.rotation.y=-atan2(axis.z,axis.x)
	for side: float in [-1.0,1.0]:
		var brace := G.box(node,"CrossarmBrace",Vector3(0,HEIGHT-.34,0)+axis*side*.4,Vector3(.08,.95,.065),Color("777771"))
		brace.rotation.z=side*-.65
		brace.rotation.y=arm.rotation.y
	for offset: float in [-.9,0.0,.9]:
		var at: Vector3 = Vector3(0,HEIGHT+.14,0)+axis*offset
		G.cylinder(node,"CeramicInsulator",at,.095,.22,Color("c3c1ae"))
		G.cylinder(node,"InsulatorSkirt",at-Vector3(0,.025,0),.135,.045,Color("b9b9a4"))
	if bool(record.transformer):
		G.cylinder(node,"Transformer",Vector3(.28,HEIGHT-1,0),.29,.95,Color("8b9389"))
		G.box(node,"TransformerBracket",Vector3(.15,HEIGHT-1.48,0),Vector3(.55,.1,.42),Color("625b4c"))
	G.batch_repeated_meshes(node)

static func _sag(a: Vector3, b: Vector3, sag: float) -> PackedVector3Array:
	var result := PackedVector3Array()
	for i in 9:
		var fraction := float(i)/8
		result.append(a.lerp(b,fraction)-Vector3.UP*(4*sag*fraction*(1-fraction)))
	return result

static func _wires(parent: Node3D, curves: Array[PackedVector3Array], name: String) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for curve in curves:
		for i in range(1,curve.size()):
			var a := curve[i-1]; var b := curve[i]
			var direction := a.direction_to(b)
			var across := direction.cross(Vector3.UP).normalized()
			var up := across.cross(direction).normalized()
			for face in 5:
				var angle := TAU*float(face)/5
				var next := TAU*float(face+1)/5
				var n0 := across*cos(angle)+up*sin(angle)
				var n1 := across*cos(next)+up*sin(next)
				var corners: Array[Vector3] = [a+n0*WIRE_RADIUS,a+n1*WIRE_RADIUS,b+n1*WIRE_RADIUS,b+n0*WIRE_RADIUS]
				for index in [0,1,2,0,2,3]:
					vertices.append(corners[index]); normals.append(n0 if index==0 or index==3 else n1)
	var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node := MeshInstance3D.new(); node.name=name; node.mesh=mesh
	node.material_override=G.material(Color("494b43")); node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)

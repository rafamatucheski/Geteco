extends RefCounted
## Shared, authored low-poly motocross geometry. No physics, riders or effects.
static var _sets: Dictionary = {}
static var _materials: Dictionary = {}

static func build(bike: Node3D) -> void:
	if _sets.is_empty():
		_sets.body = _body().finish()
		_sets.front = _front_parts().finish()
		_sets.wheel = _wheel().finish()
	bike.visual = Node3D.new()
	bike.visual.name = "MotocrossVisual"
	bike.add_child(bike.visual)
	_place(bike.visual, "body", bike.paint_color)
	bike._front = Node3D.new()
	bike._front.name = "SteeringFork"
	bike._front.position = Vector3(0, .36, -.88)
	bike.visual.add_child(bike._front)
	_place(bike._front, "front", bike.paint_color)
	for side in [-1.0, 1.0]:
		var grip := Marker3D.new()
		grip.name = "GripLeft" if side < 0 else "GripRight"
		grip.position = Vector3(side * .39, .85, .32)
		bike._front.add_child(grip)
		var peg := Marker3D.new()
		peg.name = "FootpegLeft" if side < 0 else "FootpegRight"
		peg.position = Vector3(side * .27, .39, .08)
		bike.visual.add_child(peg)
	for index in 2:
		var wheel := Node3D.new()
		wheel.name = "FrontWheel" if index == 0 else "RearWheel"
		wheel.position = Vector3.ZERO if index == 0 else Vector3(0, .36, .83)
		(bike._front if index == 0 else bike.visual).add_child(wheel)
		_place(wheel, "wheel", bike.paint_color)
		bike._wheels.append(wheel)
	bike.visual.set_meta("motocross_art_triangles", triangle_count())

static func triangle_count() -> int:
	var total := 0
	for key in _sets:
		for part in _sets[key]:
			var arrays: Array = part.mesh.surface_get_arrays(0)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			# Whole-number grouping/index; preserve integer truncation and precision.
			@warning_ignore("integer_division")
			total += (indices.size() / 3) * (2 if key == "wheel" else 1)
	return total

static func _place(parent: Node3D, key: String, paint: Color) -> void:
	for part in _sets[key]:
		var instance := MeshInstance3D.new()
		instance.name = str(part.slot).capitalize()
		instance.mesh = part.mesh
		instance.material_override = _material(part.slot, paint)
		parent.add_child(instance)

static func _material(slot: String, paint: Color) -> StandardMaterial3D:
	var colors := {"paint": paint, "tire": Color("262a29"), "seat": Color("353b3c"), "metal": Color("aab3b0"), "engine": Color("596463"), "plate": Color("e8e7dc"), "bronze": Color("8d7257")}
	var key := slot + (paint.to_html() if slot == "paint" else "")
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = colors[slot]
		material.roughness = .77 if slot in ["tire", "seat"] else .46
		material.metallic = .65 if slot in ["metal", "engine", "bronze"] else .0
		_materials[key] = material
	return _materials[key]

static func _body() -> Builder:
	var b := Builder.new()
	# Narrow saddle and tapered tank, with curved rather than boxy silhouettes.
	b.loft([Vector4(-.46,.85,.075,.085),Vector4(-.30,.87,.155,.16),Vector4(-.02,.84,.17,.14),Vector4(.24,.81,.12,.075)], "paint", 8)
	b.loft([Vector4(-.25,.983,.105,.035),Vector4(-.04,1.002,.135,.040),Vector4(.38,.98,.15,.045),Vector4(.70,.94,.115,.028)], "seat", 8)
	b.loft([Vector4(.46,.942,.135,.028),Vector4(.76,.96,.14,.025),Vector4(1.00,.95,.125,.02),Vector4(1.22,.90,.075,.018)], "paint", 6)
	for side in [-1.0,1.0]:
		# Sculpted radiator shrouds and separate flowing number panels.
		b.panel([Vector3(side*.145,.94,-.51),Vector3(side*.21,.91,-.25),Vector3(side*.19,.74,-.06),Vector3(side*.13,.60,-.17),Vector3(side*.12,.71,-.47)],"paint",Vector3.RIGHT*side)
		b.panel([Vector3(side*.165,.90,.08),Vector3(side*.19,.88,.49),Vector3(side*.14,.72,.65),Vector3(side*.15,.66,.22)],"plate",Vector3.RIGHT*side)
		b.rod(Vector3(side*.105,.36,.05),Vector3(side*.125,.96,-.54),.028,"metal")
		b.rod(Vector3(side*.105,.36,.05),Vector3(side*.14,.83,.55),.028,"metal")
		b.rod(Vector3(side*.14,.83,.55),Vector3(side*.125,.96,-.54),.021,"engine")
		b.rod(Vector3(side*.15,.40,.07),Vector3(side*.15,.36,.83),.035,"metal")
		b.rod(Vector3(side*.16,.39,.08),Vector3(side*.35,.39,.08),.034,"engine")
		for tooth in 3:
			b.box(Vector3(.045,.026,.065),Vector3(side*(.21+tooth*.05),.42,.08),"metal")
	# Compact rounded engine cases, cooling fins and exposed skid plate.
	b.ellipsoid(Vector3(0,.48,.06),Vector3(.17,.15,.23),"engine",10,5)
	b.ellipsoid(Vector3(-.175,.47,.10),Vector3(.022,.105,.12),"metal",8,4)
	b.ellipsoid(Vector3(.175,.48,.10),Vector3(.022,.105,.12),"metal",8,4)
	for index in 5:
		b.box(Vector3(.24,.018,.18),Vector3(0,.60+index*.031,-.115),"engine")
	b.loft([Vector4(-.23,.35,.09,.025),Vector4(.03,.31,.14,.024),Vector4(.30,.34,.105,.02)],"metal",6)
	# Shock spring, tucked exhaust and a tapered silencer.
	b.rod(Vector3(0,.44,.31),Vector3(0,.86,.40),.042,"engine")
	for ring in 7:
		b.torus(Vector3(0,.48+ring*.046,.32+ring*.010),.051,.010,.010,10,4,"bronze",false)
	b.rod(Vector3(.13,.65,-.18),Vector3(.26,.58,-.31),.041,"bronze")
	b.rod(Vector3(.26,.58,-.31),Vector3(.26,.46,-.02),.041,"bronze")
	b.rod(Vector3(.26,.46,-.02),Vector3(.24,.69,.53),.037,"bronze")
	b.rod(Vector3(.23,.73,.51),Vector3(.23,.84,.93),.073,"metal",8)
	b.rod(Vector3(.23,.84,.91),Vector3(.23,.85,.97),.043,"seat",8)
	# Rear sprocket/chain suggest mechanics without a filled wheel disk.
	b.rod(Vector3(-.19,.30,.04),Vector3(-.19,.23,.79),.012,"engine",4)
	b.rod(Vector3(-.19,.52,.04),Vector3(-.19,.49,.79),.012,"engine",4)
	return b

static func _front_parts() -> Builder:
	var b := Builder.new()
	for side in [-1.0,1.0]:
		b.rod(Vector3(side*.13,0,0),Vector3(side*.13,.43,.12),.028,"metal")
		b.rod(Vector3(side*.13,.34,.10),Vector3(side*.13,.79,.24),.043,"bronze")
		b.rod(Vector3(side*.13,.05,.014),Vector3(side*.13,.27,.078),.039,"paint")
		b.rod(Vector3(0,.83,.22),Vector3(side*.24,.83,.24),.024,"metal")
		b.rod(Vector3(side*.24,.83,.24),Vector3(side*.32,.85,.32),.024,"metal")
		b.rod(Vector3(side*.31,.85,.32),Vector3(side*.47,.85,.32),.032,"seat",8)
		b.rod(Vector3(side*.47,.85,.32),Vector3(side*.47,.85,.32)+Vector3(0,.001,0),.034,"metal",6)
	b.rod(Vector3(-.17,.61,.175),Vector3(.17,.61,.175),.029,"engine")
	b.rod(Vector3(-.17,.76,.225),Vector3(.17,.76,.225),.029,"engine")
	b.fender(Vector3(0,.035,-.04),.52,-1.04,.84,.14,"paint")
	b.panel([Vector3(-.13,.82,.10),Vector3(.13,.82,.10),Vector3(.15,.57,.025),Vector3(0,.51,.005),Vector3(-.15,.57,.025)],"plate",Vector3.FORWARD)
	# Brake line and short levers, routed clear of the exact grip anchors.
	b.rod(Vector3(.29,.84,.30),Vector3(.42,.81,.245),.010,"metal",4)
	b.rod(Vector3(-.29,.84,.30),Vector3(-.42,.81,.245),.010,"metal",4)
	b.rod(Vector3(-.16,.72,.16),Vector3(-.18,.20,.045),.009,"seat",4)
	return b

static func _wheel() -> Builder:
	var b := Builder.new()
	# A true open torus: daylight remains visible between every spoke.
	b.torus(Vector3.ZERO,.282,.078,.088,24,8,"tire")
	for side in [-1.0,1.0]:
		b.torus(Vector3(side*.054,0,0),.225,.012,.014,20,4,"metal")
		for index in 8:
			var a := float(index)*TAU/8.0 + (0.13 if side>0 else 0.0)
			var end := Vector3(side*.047,cos(a)*.224,sin(a)*.224)
			var spoke := Vector3(side*.043,cos(a+.28)*.046,sin(a+.28)*.046)
			b.rod(spoke,end,.006,"metal",4)
	b.rod(Vector3(-.083,0,0),Vector3(.083,0,0),.048,"engine",8)
	for index in 24:
		var angle := float(index)*TAU/24.0
		var at := Vector3((-.027 if index%2==0 else .027),cos(angle)*.354,sin(angle)*.354)
		b.box(Vector3(.097,.027,.051),at,"tire",Vector3(angle,0,(.13 if index%2==0 else -.13)))
	return b

class Builder:
	var batches: Dictionary = {}
	var vertex_counts: Dictionary = {}
	func surface(slot: String) -> SurfaceTool:
		if not batches.has(slot):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			batches[slot] = st
			vertex_counts[slot] = 0
		return batches[slot]
	func tri(a: Vector3,b: Vector3,c: Vector3,na: Vector3,nb: Vector3,nc: Vector3,slot: String) -> void:
		if (c-a).cross(b-a).length_squared()<1e-12: return
		var st := surface(slot)
		if (c-a).cross(b-a).dot(na+nb+nc)<0:
			var p:=b;b=c;c=p
			var n:=nb;nb=nc;nc=n
		for entry in [[a,na],[b,nb],[c,nc]]:
			st.set_normal(entry[1])
			st.add_vertex(entry[0])
			# PrimitiveMesh batches already carry indices. Every handcrafted
			# vertex needs an index too, or the torus/loft disappears in a batch
			# containing an indexed cylinder/box despite correct face winding.
			st.add_index(int(vertex_counts[slot]))
			vertex_counts[slot] = int(vertex_counts[slot])+1
	func quad(a: Vector3,b: Vector3,c: Vector3,d: Vector3,normal: Vector3,slot: String) -> void:
		tri(a,b,c,normal,normal,normal,slot)
		tri(a,c,d,normal,normal,normal,slot)
	func primitive(mesh: PrimitiveMesh,where: Transform3D,slot: String) -> void:
		var source:=ArrayMesh.new()
		source.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,mesh.get_mesh_arrays())
		surface(slot).append_from(source,0,where)
		vertex_counts[slot] = int(vertex_counts[slot])+mesh.get_mesh_arrays()[Mesh.ARRAY_VERTEX].size()
	func box(size: Vector3,at: Vector3,slot: String,angles:=Vector3.ZERO) -> void:
		var mesh:=BoxMesh.new();mesh.size=size
		primitive(mesh,Transform3D(Basis.from_euler(angles),at),slot)
	func rod(a: Vector3,b: Vector3,radius: float,slot: String,sides:=6) -> void:
		var mesh:=CylinderMesh.new()
		mesh.top_radius=radius;mesh.bottom_radius=radius;mesh.height=a.distance_to(b);mesh.radial_segments=sides;mesh.rings=0
		primitive(mesh,Transform3D(Basis(Quaternion(Vector3.UP,(b-a).normalized())),(a+b)*.5),slot)
	func ellipsoid(at: Vector3,radii: Vector3,slot: String,sides:=10,rings:=5) -> void:
		var mesh:=SphereMesh.new();mesh.radius=1;mesh.height=2;mesh.radial_segments=sides;mesh.rings=rings
		primitive(mesh,Transform3D(Basis.from_scale(radii),at),slot)
	func panel(points: Array,slot: String,normal: Vector3) -> void:
		var center:=Vector3.ZERO
		for point in points: center+=point
		center/=points.size()
		for index in points.size():
			var a:Vector3=points[index];var b:Vector3=points[(index+1)%points.size()]
			tri(center,a,b,normal,normal,normal,slot)
			quad(a,b,b-normal*.018,a-normal*.018,(b-a).cross(normal).normalized(),slot)
	func loft(rings: Array,slot: String,sides:=8) -> void:
		for index in rings.size()-1:
			var a:Vector4=rings[index];var b:Vector4=rings[index+1]
			for side in sides:
				var t:=float(side)*TAU/sides;var u:=float(side+1)*TAU/sides
				var p:=Vector3(sin(t)*a.z,a.y+cos(t)*a.w,a.x)
				var q:=Vector3(sin(t)*b.z,b.y+cos(t)*b.w,b.x)
				var r:=Vector3(sin(u)*b.z,b.y+cos(u)*b.w,b.x)
				var s:=Vector3(sin(u)*a.z,a.y+cos(u)*a.w,a.x)
				var normal:=Vector3(sin((t+u)*.5),cos((t+u)*.5),0)
				quad(p,q,r,s,normal,slot)
		for end in [0,rings.size()-1]:
			var ring:Vector4=rings[end]
			var center:=Vector3(0,ring.y,ring.x)
			var normal:=Vector3.FORWARD if end==0 else Vector3.BACK
			for side in sides:
				var t:=float(side)*TAU/sides;var u:=float(side+1)*TAU/sides
				tri(center,Vector3(sin(t)*ring.z,ring.y+cos(t)*ring.w,ring.x),Vector3(sin(u)*ring.z,ring.y+cos(u)*ring.w,ring.x),normal,normal,normal,slot)
	func torus(center:Vector3,major:float,radial:float,axial:float,segments:int,sides:int,slot:String,axis_x:=true) -> void:
		for segment in segments:
			for side in sides:
				var vertices:Array[Vector3]=[];var normals:Array[Vector3]=[]
				for uv in [Vector2(segment,side),Vector2(segment+1,side),Vector2(segment+1,side+1),Vector2(segment,side+1)]:
					var a:float=uv.x*TAU/segments;var b:float=uv.y*TAU/sides
					var p:=Vector3(sin(b)*axial,cos(a)*(major+cos(b)*radial),sin(a)*(major+cos(b)*radial))
					var n:=Vector3(sin(b)/axial,cos(a)*cos(b)/radial,sin(a)*cos(b)/radial).normalized()
					if not axis_x:p=Vector3(p.y,p.x,p.z);n=Vector3(n.y,n.x,n.z)
					vertices.append(center+p);normals.append(n)
				tri(vertices[0],vertices[1],vertices[2],normals[0],normals[1],normals[2],slot)
				tri(vertices[0],vertices[2],vertices[3],normals[0],normals[2],normals[3],slot)
	func fender(center:Vector3,radius:float,start:float,end:float,width:float,slot:String) -> void:
		var sections:Array=[]
		for index in 9:
			var t:=float(index)/8;var angle:=lerpf(start,end,t)
			var normal:=Vector3(0,cos(angle),sin(angle))
			var p:=center+normal*radius
			var w:=width*lerpf(.72,1.0,sin(t*PI))
			sections.append([p+Vector3(-w,0,0),p+normal*.025,p+Vector3(w,0,0),p-normal*.012])
		for index in 8:
			var normal:=Vector3(0,cos(lerpf(start,end,(index+.5)/8)),sin(lerpf(start,end,(index+.5)/8)))
			for side in 4:
				var a:Vector3=sections[index][side];var b:Vector3=sections[index+1][side]
				var c:Vector3=sections[index+1][(side+1)%4];var d:Vector3=sections[index][(side+1)%4]
				quad(a,b,c,d,normal if side<2 else -normal,slot)
	func finish() -> Array:
		var result:Array=[]
		for slot in batches:
			var st:SurfaceTool=batches[slot]
			st.index()
			result.append({"slot":slot,"mesh":st.commit()})
		return result

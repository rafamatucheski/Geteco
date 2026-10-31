extends RefCounted
## Todos os desenhos mantêm o raio externo e a área de contato do pneu doador.
## X é o eixo de giro; o mesmo kit funciona no showroom e nos pivôs de direção.
static func build(design: String, radius: float, color: Color, width: float = .22, rim_ratio: float = .70) -> Node3D:
	var root := Node3D.new()
	root.name = "TuningWheel"
	var metal := material(color,.27,.78)
	var rubber := material(Color("171b20"),.91,0.0)
	var dark := material(Color("242a30"),.58,.35)
	var mesh := ArrayMesh.new()
	var tyre := SurfaceTool.new()
	tyre.begin(Mesh.PRIMITIVE_TRIANGLES)
	var alloy := SurfaceTool.new()
	alloy.begin(Mesh.PRIMITIVE_TRIANGLES)
	var recess := SurfaceTool.new()
	recess.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim := radius * rim_ratio
	for i in 32:
		var a := TAU*float(i)/32.0
		var b := TAU*float(i+1)/32.0
		quad(tyre,point(-width*.5,radius,a),point(width*.5,radius,a),point(width*.5,radius,b),point(-width*.5,radius,b))
		for side in [-1.0,1.0]:
			var x: float = side*width*.5
			quad(tyre,point(x,rim,a),point(x,radius,a),point(x,radius,b),point(x,rim,b))
			quad(alloy,point(x,rim*.91,a),point(x,rim,a),point(x,rim,b),point(x,rim*.91,b))
			triangle(recess,Vector3(side*width*.38,0,0),point(side*width*.38,rim*.95,a),point(side*width*.38,rim*.95,b))
	var spokes: int = {"five_spoke":5,"six_spoke":6,"mesh":10,"multi_spoke":15}.get(design,8)
	for side in [-1.0,1.0]:
		var x: float = side*(width*.5+.003)
		for i in spokes:
			var angle := TAU*float(i)/float(spokes)
			var sweep := .24 if design == "turbine" else 0.0
			var spread: float = {"five_spoke":.11,"six_spoke":.085,"multi_spoke":.03}.get(design,.055)
			quad(alloy,point(x,rim*.16,angle-spread),point(x,rim*.94,angle+sweep-spread),point(x,rim*.94,angle+sweep+spread),point(x,rim*.16,angle+spread))
			if design == "mesh":
				quad(alloy,point(x,rim*.25,angle-.08),point(x,rim*.94,angle+.40),point(x,rim*.94,angle+.46),point(x,rim*.25,angle))
		for i in 16:
			triangle(alloy,Vector3(x,0,0),point(x,rim*.20,TAU*i/16.0),point(x,rim*.20,TAU*(i+1)/16.0))
	for entry in [[tyre,rubber],[alloy,metal],[recess,dark]]:
		entry[0].generate_normals()
		entry[0].set_material(entry[1])
		entry[0].commit(mesh)
	var part := MeshInstance3D.new()
	part.mesh = mesh
	root.add_child(part)
	root.set_meta("alloy_material",metal)
	root.set_meta("outside_radius",radius)
	root.set_meta("rim_ratio",rim_ratio)
	return root

static func point(x: float, r: float, a: float) -> Vector3:
	return Vector3(x,sin(a)*r,cos(a)*r)

static func triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(c); st.add_vertex(b); st.add_vertex(a)

static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	triangle(st,a,b,c); triangle(st,a,c,d)

static func material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	result.metallic = metallic
	return result

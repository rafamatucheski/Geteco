extends RefCounted
## Offline authoring primitives: one colored material per finished assembly.
var surface := SurfaceTool.new()
var triangles := 0
const DARK := Color("182126")
const STEEL := Color("a1b0b6")
func _init() -> void: surface.begin(Mesh.PRIMITIVE_TRIANGLES)
func tri(a: Vector3,b: Vector3,c: Vector3,n: Vector3,color: Color) -> void:
	var v := [a,b,c]
	if (b-a).cross(c-a).dot(n)>0: v=[a,c,b]
	for p: Vector3 in v:
		surface.set_normal(n.normalized())
		surface.set_color(color)
		surface.set_uv(Vector2(p.x,p.z))
		surface.add_vertex(p)
	triangles+=1
func quad(a: Vector3,b: Vector3,c: Vector3,d: Vector3,n: Vector3,color: Color) -> void:
	tri(a,b,c,n,color); tri(a,c,d,n,color)
func box(at: Vector3,size: Vector3,color: Color,basis := Basis.IDENTITY) -> void:
	var mesh := BoxMesh.new()
	mesh.size=size
	append(mesh,Transform3D(basis,at),color)
func append(mesh: Mesh,xf: Transform3D,color: Color) -> void:
	var a := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
	if indices.is_empty():
		for i in vertices.size(): indices.append(i)
	for i in indices:
		surface.set_normal((xf.basis*normals[i]).normalized())
		surface.set_color(color)
		surface.set_uv(Vector2(vertices[i].x,vertices[i].z))
		surface.add_vertex(xf*vertices[i])
	triangles+=indices.size()/3
func cylinder(at: Vector3,r: float,h: float,color: Color,basis := Basis.IDENTITY,n := 12) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius=r; mesh.bottom_radius=r; mesh.height=h
	mesh.radial_segments=n; mesh.rings=1
	append(mesh,Transform3D(basis,at),color)
func beam(a: Vector3,b: Vector3,width: float,color: Color) -> void:
	var y := (b-a).normalized()
	var x := y.cross(Vector3.UP).normalized()
	if x.length_squared()<.001: x=Vector3.RIGHT
	var z := x.cross(y).normalized()
	box((a+b)*.5,Vector3(width,a.distance_to(b),width),color,Basis(x,y,z))
func disc(center: Vector3,r: float,normal: Vector3,color: Color,n:=16,inner:=0.0) -> void:
	var u:=Vector3.UP if absf(normal.x)>.5 else Vector3.RIGHT
	var v:=normal.cross(u).normalized()
	for i in n:
		var a := TAU*i/n
		var b := TAU*(i+1)/n
		if inner==0:
			tri(center,center+(u*cos(a)+v*sin(a))*r,center+(u*cos(b)+v*sin(b))*r,normal,color)
		else:
			quad(center+(u*cos(a)+v*sin(a))*r,center+(u*cos(b)+v*sin(b))*r,center+(u*cos(b)+v*sin(b))*inner,center+(u*cos(a)+v*sin(a))*inner,normal,color)
func material(key: String="service_detail") -> StandardMaterial3D:
	var m:=StandardMaterial3D.new()
	m.resource_name=key
	m.vertex_color_use_as_albedo=true
	m.vertex_color_is_srgb=true
	m.roughness=.5
	m.metallic=.25
	return m
func finish(name_: String,mat: StandardMaterial3D=null) -> MeshInstance3D:
	surface.index()
	var part:=MeshInstance3D.new()
	part.name=name_
	part.mesh=surface.commit()
	part.material_override=mat if mat else material()
	part.set_meta("vehicle_material_key",part.material_override.resource_name)
	part.set_meta("batch_preserve_geometry",true)
	part.set_meta("batch_ratio",1.0)
	return part
func wheel(center: Vector3,r: float,w: float,style: String) -> void:
	var side:=signf(center.x)
	var n:=Vector3(side,0,0)
	# Quatro faixas afuniladas de pneu usam normais radiais suaves e uma silhueta de 24 lados.
	var profile: Array[Vector2]=[Vector2(-w*.5,r*.72),Vector2(-w*.5,r*.90),Vector2(-w*.37,r),Vector2(w*.37,r),Vector2(w*.5,r*.90),Vector2(w*.5,r*.72)]
	for j in profile.size()-1:
		for i in 24:
			var aa:=TAU*i/24.0
			var bb:=TAU*(i+1)/24.0
			var a:=profile[j]; var b:=profile[j+1]
			var color:=Color("171d20") if j==2 else Color("272e32")
			quad(center+Vector3(a.x,sin(aa)*a.y,cos(aa)*a.y),center+Vector3(a.x,sin(bb)*a.y,cos(bb)*a.y),center+Vector3(b.x,sin(bb)*b.y,cos(bb)*b.y),center+Vector3(b.x,sin(aa)*b.y,cos(aa)*b.y),Vector3(0,sin((aa+bb)*.5),cos((aa+bb)*.5)),color)
	var face:=center+n*(w*.5+.006)
	disc(face,r*.71,n,STEEL,24,r*.62)
	disc(face+n*.002,r*.62,n,Color("4a545a"),24)
	if style=="police":
		for i in 5:
			var a:=TAU*i/5.0
			var radial:=Vector3(0,sin(a),cos(a))
			var tangent:=Vector3(0,cos(a),-sin(a))
			quad(face+n*.005+radial*r*.15-tangent*r*.075,face+n*.005+radial*r*.15+tangent*r*.075,face+n*.005+radial*r*.63+tangent*r*.095,face+n*.005+radial*r*.63-tangent*r*.095,n,STEEL)
	else:
		for i in 8:
			var a:=TAU*i/8.0
			disc(face+n*.004+Vector3(0,sin(a),cos(a))*r*.47,r*.065,n,DARK,6)
	disc(face+n*.013,r*.21,n,STEEL,12)
	for i in 6:
		var a:=TAU*i/6.0
		disc(face+n*.016+Vector3(0,sin(a),cos(a))*r*.27,r*.028,n,Color("dce0da"),5)

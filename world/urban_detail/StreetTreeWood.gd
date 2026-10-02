extends RefCounted
## One cached mesh: tapered bark, high forks and fine vertical bark ridges.
const KIT := preload("res://world/city_look/CityPropKit.gd")
static var cached: ArrayMesh

static func mesh() -> ArrayMesh:
	if cached != null: return cached
	var t := SurfaceTool.new()
	t.begin(Mesh.PRIMITIVE_TRIANGLES)
	t.set_smooth_group(-1)
	KIT.cylinder(t,Vector3.ZERO,.22,3.0,Color("66513a"),9,.095)
	for i in 9:
		var a := TAU*i/9.0
		var r := .204
		KIT.box(t,Vector3(cos(a)*r,.68,sin(a)*r),Vector3(.028,1.1+float(i%3)*.15,.027),Color("473e30"),a)
	for i in 3:
		var a := TAU*i/3.0+.3
		var start := Vector3(0,2.0+i*.16,0)
		var end := Vector3(cos(a)*.65,3.16+float(i%2)*.15,sin(a)*.65)
		var direction := end-start
		var branch := SurfaceTool.new()
		branch.begin(Mesh.PRIMITIVE_TRIANGLES)
		KIT.cylinder(branch,Vector3.ZERO,.095,direction.length(),Color("786047"),6,.035)
		branch.generate_normals()
		var basis := Basis(Quaternion(Vector3.UP,direction.normalized()))
		t.append_from(branch.commit(),0,Transform3D(basis,start))
	t.generate_normals()
	cached=t.commit()
	return cached

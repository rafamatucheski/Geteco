extends RefCounted
## Cabine fechada na cor da carroceria, com vidros embutidos, ombros afunilados e teto abaulado.
## Fica separada para que o vinil possa projetar na mesma superfície definida do teto.
static func roof_point(s: Dictionary,x: float,z: float) -> Vector3:
	var w := float(s["size"][0])
	var h := float(s["size"][1])
	var l := float(s["size"][2])
	var t := clampf((z/l-float(s.roof_front))/(float(s.roof_back)-float(s.roof_front)),0.0,1.0)
	var y := h-.105+.04*sin(t*PI)+.065*(1.0-pow(x/(w*.365),2))
	return Vector3(x,y,z)

static func _side_point(s: Dictionary,side: float,z: float,y: float,offset := 0.0) -> Vector3:
	var w := float(s["size"][0])
	var h := float(s["size"][1])
	var belt := float(s.shoulder)+.005
	var t := clampf((y-belt)/(h-.105-belt),0.0,1.0)
	return Vector3(side*(w*lerpf(.425,.365,t)+offset),y,z)

static func create(root: Node3D,s: Dictionary,paint: Material,glass: Material,dark: Material) -> void:
	var w := float(s["size"][0])
	var h := float(s["size"][1])
	var l := float(s["size"][2])
	var belt := float(s.shoulder)+.005
	var front := l*float(s.cabin_front)
	var back := l*float(s.cabin_back)
	var roof_front := l*float(s.roof_front)
	var roof_back := l*float(s.roof_back)
	var shell := SurfaceTool.new()
	var windows := SurfaceTool.new()
	var pillar := SurfaceTool.new()
	for st: SurfaceTool in [shell,windows,pillar]: st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Molduras pintadas cercam aberturas reais de janela. O sistema de embarque deixa
	# o vidro translúcido, então não pode haver lâmina escondida na cor da carroceria atrás dele.
	for side in [-1.0,1.0]:
		var outside := [_side_point(s,side,front,belt),_side_point(s,side,roof_front,h-.105),_side_point(s,side,roof_back,h-.105),_side_point(s,side,back,belt)]
		var inside := [_side_point(s,side,front+.090,belt+.043),_side_point(s,side,roof_front+.060,h-.15),_side_point(s,side,roof_back-.065,h-.15),_side_point(s,side,back-.12,belt+.043)]
		for edge in 4:
			var next := (edge+1)%4
			_quad(shell,outside[edge],outside[next],inside[next],inside[edge],Vector3(side,0,0))
		var offset := Vector3(side*.004,0,0)
		_quad(windows,inside[0]+offset,inside[1]+offset,inside[2]+offset,inside[3]+offset,Vector3(side,0,0))
		var divider := clampf(l*float(s.door_back),roof_front+.085,roof_back-.06)
		_quad(pillar,_side_point(s,side,divider-.025,belt+.035,.007),_side_point(s,side,divider-.025,h-.14,.007),_side_point(s,side,divider+.025,h-.14,.007),_side_point(s,side,divider+.025,belt+.035,.007),Vector3(side,0,0))
	# Teto abaulado: o perfil é levemente curvo ao longo da largura e do comprimento do teto.
	for longitudinal in 5:
		var z0 := lerpf(roof_front,roof_back,float(longitudinal)/5.0)
		var z1 := lerpf(roof_front,roof_back,float(longitudinal+1)/5.0)
		for across in 10:
			var x0 := lerpf(-w*.365,w*.365,float(across)/10.0)
			var x1 := lerpf(-w*.365,w*.365,float(across+1)/10.0)
			_quad(shell,roof_point(s,x0,z0),roof_point(s,x1,z0),roof_point(s,x1,z1),roof_point(s,x0,z1),Vector3.UP)
	# The roof sides rise slightly along their crown; close those small edge strips.
	for side in [-1.0,1.0]:
		for i in 5:
			var z0 := lerpf(roof_front,roof_back,float(i)/5.0)
			var z1 := lerpf(roof_front,roof_back,float(i+1)/5.0)
			_quad(shell,Vector3(side*w*.365,h-.105,z0),roof_point(s,side*w*.365,z0),roof_point(s,side*w*.365,z1),Vector3(side*w*.365,h-.105,z1),Vector3(side,0,0))
	for end in [-1.0,1.0]:
		var outward := Vector3(0,.5,end).normalized()
		for across in 10:
			var u0 := lerpf(-1.0,1.0,float(across)/10.0)
			var u1 := lerpf(-1.0,1.0,float(across+1)/10.0)
			_quad(shell,_end_point(s,end,u0,0),_end_point(s,end,u1,0),_end_point(s,end,u1,.085),_end_point(s,end,u0,.085),outward)
			_quad(shell,_end_point(s,end,u0,.93),_end_point(s,end,u1,.93),_end_point(s,end,u1,1),_end_point(s,end,u0,1),outward)
			var shift := Vector3(0,.003,end*.004)
			_quad(windows,_end_point(s,end,u0*.92,.085)+shift,_end_point(s,end,u1*.92,.085)+shift,_end_point(s,end,u1*.92,.93)+shift,_end_point(s,end,u0*.92,.93)+shift,outward)
		for side in [-1.0,1.0]:
			_quad(shell,_end_point(s,end,side,.085),_end_point(s,end,side*.92,.085),_end_point(s,end,side*.92,.93),_end_point(s,end,side,.93),outward)
	_add(root,"CabinShell",shell,paint)
	_add(root,"CabinGlass",windows,glass)
	_add(root,"CabinWindowDivision",pillar,dark)

static func _end_point(s: Dictionary,end: float,u: float,t: float) -> Vector3:
	var w := float(s["size"][0])
	var l := float(s["size"][2])
	var lower_z := l*float(s.cabin_front if end<0 else s.cabin_back)
	var upper_z := l*float(s.roof_front if end<0 else s.roof_back)
	return Vector3(u*w*.425,float(s.shoulder)+.005,lower_z).lerp(roof_point(s,u*w*.365,upper_z),t)

static func _quad(st: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,d: Vector3,outward: Vector3) -> void:
	_triangle(st,a,b,c,outward)
	_triangle(st,a,c,d,outward)

static func _triangle(st: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,outward: Vector3) -> void:
	var normal := (c-a).cross(b-a).normalized()
	var points := [a,b,c]
	if normal.dot(outward)<0.0:
		points=[a,c,b]
		normal=-normal
	for point: Vector3 in points:
		st.set_normal(normal)
		st.set_uv(Vector2(point.x,point.z))
		st.add_vertex(point)

static func _add(root: Node3D,label: String,st: SurfaceTool,mat: Material) -> void:
	var node := MeshInstance3D.new()
	node.name=label
	node.mesh=st.commit()
	node.material_override=mat
	root.add_child(node)

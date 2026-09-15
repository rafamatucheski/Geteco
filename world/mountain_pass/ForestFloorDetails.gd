extends Node2D
## Small, walkable forest litter and shallow hollows, authored once per cluster.
var variant_seed := 0
var fruiting := false
var snowy := false
var details: Array[Dictionary] = []
var _mesh: ArrayMesh
var _vertices := PackedVector3Array()
var _colors := PackedColorArray()
var _transform := Transform2D.IDENTITY
func _ready() -> void:
	z_as_relative=false
	z_index=4
	var rng := RandomNumberGenerator.new()
	rng.seed=variant_seed
	for i in 7:
		var angle := rng.randf()*TAU
		var point := Vector2(cos(angle)*rng.randf_range(12,25),sin(angle)*rng.randf_range(9,20))
		details.append({"p":point,"a":angle,"kind":(i%2 if fruiting else posmod(variant_seed+i,5)),"size":rng.randf_range(.75,1.3)})
	_build_mesh()
	queue_redraw()
func _build_mesh() -> void:
	for detail in details:
		_transform=Transform2D(detail.a,Vector2.ONE*detail.size,0,detail.p)
		match detail.kind:
			0:
				_circle(Vector2(1,1),1.7,Color(0,0,0,.18))
				_circle(Vector2.ZERO,1.3,Color("ab4c31") if fruiting else Color("645039"))
				_line(Vector2(0,-1),Vector2(1,-2),Color("43412d"),.65)
			1:
				_line(Vector2(-4,-1),Vector2(5,1),Color("5b4431"),1.5)
				_line(Vector2(0,0),Vector2(2,-3),Color("6d5339"),.9)
			2:
				_circle(Vector2.ZERO,2.0,Color("726e5b"))
				_line(Vector2(-1,-1),Vector2(1,-1),Color("96917a"),1.1)
			3:
				_transform=Transform2D(detail.a,Vector2(1,.60)*detail.size,0,detail.p)
				_circle(Vector2.ZERO,6,Color(.12,.10,.07,.16))
				_circle(Vector2(0,-1),4.5,Color(.10,.08,.05,.23))
				for i in 8:
					_line(Vector2.from_angle(.1+i*2.5/8)*5,Vector2.from_angle(.1+(i+1)*2.5/8)*5,Color(.39,.32,.22,.32),1)
			4:
				for stem in 3:
					_line(Vector2(stem*2,2),Vector2(stem*2,-1),Color("a79d81"),.8)
					_circle(Vector2(stem*2,-1),1.6,Color("897657"))
		if snowy:
			_circle(Vector2(-1,-1),1.2,Color("c4d1d4"))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=_vertices
	arrays[Mesh.ARRAY_COLOR]=_colors
	_mesh=ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_vertices.clear()
	_colors.clear()

func _triangle(a: Vector2,b: Vector2,c: Vector2,color: Color) -> void:
	for p in [a,b,c]:
		var point: Vector2=_transform*p
		_vertices.append(Vector3(point.x,point.y,0))
		_colors.append(color)
func _circle(center: Vector2,radius: float,color: Color) -> void:
	for i in 10:
		_triangle(center,center+Vector2.from_angle(i*TAU/10)*radius,center+Vector2.from_angle((i+1)*TAU/10)*radius,color)
func _line(a: Vector2,b: Vector2,color: Color,width: float) -> void:
	var offset := (b-a).normalized().orthogonal()*width*.5
	_triangle(a-offset,a+offset,b-offset,color)
	_triangle(a+offset,b+offset,b-offset,color)
func _draw() -> void:
	if _mesh!=null: draw_mesh(_mesh,null)

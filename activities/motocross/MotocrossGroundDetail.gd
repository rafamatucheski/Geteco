extends Node3D
## Bounded, spatially culled grass. Same blade geometry/material as Harbor.
const GRASS := preload("res://world/urban_detail/HarborGrassTufts.gd")
const AREA := Rect2(-247,-147,160,125)
# Paddock furniture, the mechanic's tent and the bleacher's worn footprint.
const CLEAR := [Rect2(-238,-39,13,9),Rect2(-237,-31,7,6),Rect2(-217,-38,6,13),Rect2(-229,-40,9,18),Rect2(-222.5,-33,6,5.5),Rect2(-211,-68.5,10,6.5)]
var course: Node3D
var tuft_count := 0
static var _ground: ShaderMaterial
static var _grass: StandardMaterial3D

static func bind_textures(material: ShaderMaterial) -> void:
	material.set_shader_parameter("grass_texture",GRASS.ground_material("grass").albedo_texture)
	material.set_shader_parameter("earth_texture",preload("res://world/urban_detail/RuralGroundMaterial.gd").material().get_shader_parameter("earth_texture"))

static func ground_material() -> ShaderMaterial:
	if _ground == null:
		_ground = ShaderMaterial.new()
		_ground.shader = preload("res://activities/motocross/MotocrossGround.gdshader")
		bind_textures(_ground)
	return _ground

static func grass_material() -> StandardMaterial3D:
	if _grass == null:
		_grass = GRASS._tuft_material().duplicate()
		_grass.albedo_color = Color(.56,.68,.39)
		_grass.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return _grass

func yard_height(p: Vector2) -> float:
	# A single connected raised earth apron supports the original feet/benches
	# at 13 cm, tapering into native ground instead of separate box-shaped pads.
	var edge := minf(minf(p.x+239,-209-p.x),minf(p.y+40,-24-p.y))
	return maxf(course.surface_height(p),.128*smoothstep(-2,0,edge))+.002

func _yard() -> void:
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(-43,24):
		for x in range(-242,-206):
			for offset in [Vector2.ZERO,Vector2.RIGHT,Vector2.DOWN,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
				var p: Vector2 = Vector2(x,z)+offset
				surface.add_vertex(Vector3(p.x,yard_height(p),p.y))
	surface.generate_normals()
	var mesh := surface.commit()
	var display := MeshInstance3D.new(); display.name = "ConnectedEarthYard"
	display.mesh = mesh; display.material_override = ground_material()
	display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(display)
	var body := StaticBody3D.new(); body.name = "ConnectedYardFloor"
	var shape := CollisionShape3D.new(); shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape); add_child(body)

var _rng := RandomNumberGenerator.new()
var _cells: Array[Vector2i] = []
var _cell_index := 0
var _attempt := 0
var _pending: Array[Transform3D] = []

## O piso do pátio sai no _ready; os tufos (~15 mil tentativas) saem em fatias de 2 ms por
## quadro, com a mesma sequência de sorteios de antes, então o desenho é idêntico.
func _ready() -> void:
	name = "MotocrossGrass"
	_yard()
	_rng.seed = 38491
	for z in range(-147,-22,24):
		for x in range(-247,-87,24): _cells.append(Vector2i(x,z))
	set_process(true)

func finish_build() -> void:
	while _cell_index < _cells.size(): _slice(INF)

func _process(_delta: float) -> void:
	if _cell_index >= _cells.size():
		set_process(false)
		return
	_slice(2000.0)

func _slice(budget_usec: float) -> void:
	var began := Time.get_ticks_usec()
	while _cell_index < _cells.size():
		var cell := _cells[_cell_index]
		var x := cell.x
		var z := cell.y
		while _attempt < 440:
			_attempt += 1
			var p := Vector2(x+_rng.randf()*24,z+_rng.randf()*24)
			if not AREA.has_point(p): continue
			var blocked := false
			for rect in CLEAR:
				if rect.grow(.6).has_point(p): blocked = true; break
			if blocked: continue
			var near: Dictionary = course.nearest(Vector3(p.x,0,p.y))
			if float(near.lateral)<course.HALF_WIDTH+1.2: continue
			var height: float = yard_height(p) if Rect2(-242,-43,36,67).has_point(p) else course.surface_height(p)
			var scale_value := _rng.randf_range(.65,1.4)
			_pending.append(Transform3D(Basis(Vector3.UP,_rng.randf()*TAU).scaled(Vector3.ONE*scale_value),Vector3(p.x-x,height-.025,p.y-z)))
			if _attempt % 20 == 0 and Time.get_ticks_usec()-began >= budget_usec: return
		if not _pending.is_empty():
			var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = GRASS._tuft_mesh(); mm.instance_count = _pending.size()
			for i in _pending.size(): mm.set_instance_transform(i,_pending[i])
			var display := MultiMeshInstance3D.new()
			display.multimesh = mm
			display.material_override = grass_material()
			display.position = Vector3(x,0,z)
			display.visibility_range_end = 100
			display.visibility_range_end_margin = 15
			display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(display)
			tuft_count += _pending.size()
		_pending = []
		_attempt = 0
		_cell_index += 1
		if Time.get_ticks_usec()-began >= budget_usec: return

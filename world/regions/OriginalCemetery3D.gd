extends Node3D
## Layout externo de HarborGame/HarborCemetery, em metros nativos.
## A fachada do zelador continua pertencendo ao PlaceCatalog. Sem estado de sepultamento/gameplay aqui.
const SOURCE_CENTER := Vector2(-650, 1740)
const SCALE := 1.0 / 16.0
const LOT_SIZE := Vector2(780, 700)
const PINE := preload("res://world/regions/NativePine.gd")
const GRASS := preload("res://world/urban_detail/HarborGrassTufts.gd")
const CUT := preload("res://world/urban_detail/GroundCut.gd")
const PATH_RECTS: Array[Rect2] = [Rect2(-14,-350,28,700),Rect2(-25,-490,50,140),Rect2(-247,-178,24,33),Rect2(-235,-157,235,24)]
## Gramado e caminhos ganham textura projetada no mundo; antes eram cubos de cor lisa
## e o cemitério lia como chão chapado (feedback de 25/09/2026).
var batches: Dictionary = {}
var solids: StaticBody3D

static func world_position() -> Vector3:
	return Vector3(SOURCE_CENTER.x, 0, SOURCE_CENTER.y) * SCALE

static func path_footprints(origin: Vector2) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for rect in PATH_RECTS: result.append(CUT.rect_polygon(Rect2(rect.position*SCALE+origin,rect.size*SCALE)))
	return result

func _build_ground() -> void:
	var paths := path_footprints(Vector2.ZERO)
	var cover: Array[PackedVector2Array] = []
	var region := get_parent()
	while region != null and not ("harbor_road_geometry" in region): region = region.get_parent()
	if region != null and region.harbor_road_geometry != null:
		for polygon in region.harbor_road_geometry._layers[0].polygons:
			var local := PackedVector2Array()
			for point in polygon: local.append(point-Vector2(global_position.x,global_position.z))
			cover.append(local)
	if region != null and "harbor_facade_ground" in region:
		var origin := Vector2(global_position.x,global_position.z)
		var lot_bounds := Rect2(origin-LOT_SIZE*SCALE*.5,LOT_SIZE*SCALE)
		for polygon in region.harbor_facade_ground:
			if not CUT.bounds(polygon).intersects(lot_bounds): continue
			var local := PackedVector2Array()
			for point in polygon: local.append(point-origin)
			cover.append(local)
	for path in paths:
		_ground("CemeteryPath",CUT.subtract_exact([path],cover),GRASS.ground_material("gravel"))
		cover.append(path)
	var lot := Rect2(-LOT_SIZE*SCALE*.5,LOT_SIZE*SCALE)
	_ground("CemeteryLawn",CUT.subtract_exact([CUT.rect_polygon(lot)],cover),preload("res://world/urban_detail/HarborPaving.gd").lawn_material(Color("566d58")))
	_solid(Vector3(0,-.025,0),Vector3(lot.size.x,.05,lot.size.y))

func _ground(label: String, polygons: Array[PackedVector2Array], material: Material) -> void:
	var mesh := CUT.flat_mesh(polygons,0.002,1.0)
	if mesh == null: return
	var floor_node := MeshInstance3D.new()
	floor_node.name = label
	floor_node.set_meta("harbor_owned_ground",true)
	floor_node.mesh = mesh
	floor_node.material_override = material
	floor_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_node)

func _ready() -> void:
	name = "OriginalCemetery"
	solids = StaticBody3D.new()
	solids.name = "CemeterySolids"
	solids.collision_layer = 1
	solids.collision_mask = 0
	add_child(solids)
	_build_ground()
	# Portão norte: 52 pixels fonte, 3.25 m antes dos dois pilares de pedra.
	for segment in [
		[Vector2(-390,-350),Vector2(-26,-350)],
		[Vector2(26,-350),Vector2(390,-350)],
		[Vector2(390,-350),Vector2(390,350)],
		[Vector2(390,350),Vector2(-390,350)],
		[Vector2(-390,350),Vector2(-390,-350)]]:
		var a: Vector2 = segment[0]
		var b: Vector2 = segment[1]
		var midpoint: Vector2 = (a+b)*.5*SCALE
		_box(Vector3(midpoint.x,.50,midpoint.y), Vector3(absf(b.x-a.x)*SCALE+.5,1,absf(b.y-a.y)*SCALE+.5), "444d49", true)
	for x in [-26,26]:
		_box(Vector3(x*SCALE,.7,-350*SCALE), Vector3(.5,1.4,.65), "4a4840", true)
	for x in [-290,-210,-130,130,210,290]:
		for y in [-240,-160,-80,20,110,200]:
			if (x <= -210 and y == -240) or (x < 0 and y == -160): continue
			_tomb(Vector2(x,y+12)*SCALE, posmod(x*73+y*37,4))
	for x in [-350,350]:
		for y in range(-270,291,140):
			if x < 0 and y < -100: continue
			var tree: Node3D = PINE.create(1,false)
			tree.position = Vector3(x*SCALE,0,y*SCALE)
			tree.scale = Vector3.ONE*.85
			add_child(tree)
			_solid(tree.position+Vector3.UP*1.25,Vector3(.4,2.5,.4))
	for x in [-210,210]:
		var point := Vector3(x*SCALE,0,280*SCALE)
		var seat := preload("res://world/urban_detail/BenchFinish.gd").create(60*SCALE, 12*SCALE, .54, 1.14, Color("756c54"), Color("444d49"))
		seat.position = point
		seat.rotation.y = PI
		add_child(seat)
		var first_shape := solids.get_child_count()
		_solid(point+Vector3.UP*.47,Vector3(60*SCALE,.14,12*SCALE))
		_solid(point+Vector3(0,.84,.32),Vector3(60*SCALE,.6,.12))
		for side in [-1,1]: _solid(point+Vector3(side*1.25,.22,0),Vector3(.14,.44,.6))
		preload("res://gameplay/street_physics/FragileProps3D.gd").register_node("bench_seat",seat,self,{},solids.get_children().slice(first_shape))
	for point in [Vector2(-35,-340),Vector2(35,-340),Vector2(-40,50),Vector2(40,280)]:
		var base := Vector3(point.x*SCALE,0,point.y*SCALE)
		_box(base+Vector3.UP*1.3,Vector3(.10,2.6,.10),"444d49",true)
		_box(base+Vector3.UP*2.65,Vector3(.28,.25,.28),"d3b487")
	_flush()
	_grass()

## Tufos no gramado, fora dos caminhos, túmulos, bancos, árvores e muro.
func _grass() -> void:
	var lot := LOT_SIZE*SCALE
	var keep_out: Array = [
		Rect2(Vector2(-14,-350)*SCALE,Vector2(28,700)*SCALE).grow(.3),
		Rect2(Vector2(-25,-490)*SCALE,Vector2(50,140)*SCALE).grow(.3),
		Rect2(Vector2(-247,-178)*SCALE,Vector2(24,33)*SCALE).grow(.3),
		Rect2(Vector2(-235,-157)*SCALE,Vector2(235,24)*SCALE).grow(.3)]
	for x in [-290,-210,-130,130,210,290]:
		for y in [-240,-160,-80,20,110,200]:
			keep_out.append(Rect2(Vector2(x,y+12)*SCALE-Vector2(1.6,2.6),Vector2(3.2,5.0)))
	for x in [-210,210]: keep_out.append(Rect2(Vector2(x-34,262)*SCALE,Vector2(68,36)*SCALE))
	for x in [-350,350]:
		for y in range(-270,291,140): keep_out.append(Rect2(Vector2(x,y)*SCALE-Vector2(.8,.8),Vector2(1.6,1.6)))
	GRASS.scatter(self,Rect2(-lot*.5+Vector2(.8,.8),lot-Vector2(1.6,1.6)),keep_out,.8,7503,.002)

func _tomb(point: Vector2, variant: int) -> void:
	# As unidades do modelo CemeteryGrave3D original projetam a 20px; a geografia da V2 é 16px/m.
	var origin := Vector3(point.x,0,point.y)
	var model_scale := 1.25
	for part in [
		[Vector3(0,.08,0),Vector3(2.1,.16,3.5),"505953"],
		[Vector3(0,.35,0),Vector3(1.85,.38,3.22),"777f79"],
		[Vector3(0,.60,0),Vector3(1.98,.12,3.36),"a2a598"],
		[Vector3(0,.677,.12),Vector3(1.54,.035,2.72),"777f79"],
		[Vector3(0,.74,-1.35),Vector3(1.85,.17,.55),"505953"],
		[Vector3(0,1.3,-1.35),Vector3(1.55,1.08,.27),"777f79"],
		[Vector3(0,1.88,-1.35),Vector3(1.66,.12,.36),"a2a598"],
		[Vector3(0,1.38,-1.204),Vector3(.92,.58,.018),"505953"],
		[Vector3(0,1.39,-1.187),Vector3(.055,.36,.025),"a2a598"],
		[Vector3(0,1.45,-1.184),Vector3(.24,.055,.025),"a2a598"]]:
		var local_point: Vector3 = part[0]
		var size: Vector3 = part[1]
		_box(origin+local_point*model_scale,size*model_scale,part[2])
	# Área física exata, com lápide separada para os tiros não acertarem ar vazio.
	_solid(origin+Vector3(0,.43,0),Vector3(2.1,.69,3.5)*model_scale)
	_solid(origin+Vector3(0,1.30,-1.35)*model_scale,Vector3(1.66,1.2,.36)*model_scale)
	var vase := origin+Vector3(.55,.85,.95)*model_scale
	_box(vase,Vector3(.22,.38,.22),"78624a")
	var colors := ["d1c8ad","b98898","c4a25e","617957"]
	for i in 5:
		var flower := vase+Vector3(sin(i*2.4)*.16,.4,cos(i*2.4)*.16)
		_box(flower-Vector3.UP*.13,Vector3(.025,.3,.025),"41523b")
		_box(flower,Vector3(.12,.10,.12),colors[variant])

func _box(point: Vector3, size: Vector3, color: String, solid: bool = false) -> void:
	if not batches.has(color): batches[color] = []
	batches[color].append(Transform3D(Basis.from_scale(size),point))
	if solid: _solid(point,size)

func _solid(point: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.position = point
	collider.shape = shape
	solids.add_child(collider)

func _flush() -> void:
	for color in batches:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(color)
		material.roughness = .92
		if color == "27362f": material = preload("res://world/urban_detail/HarborPaving.gd").lawn_material(Color("566d58"))
		elif color == "777366": material = GRASS.ground_material("gravel")
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE
		cube.material = material
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.mesh = cube
		instances.instance_count = batches[color].size()
		for i in instances.instance_count: instances.set_instance_transform(i,batches[color][i])
		var display := MultiMeshInstance3D.new()
		display.multimesh = instances
		if Engine.get_meta("geteco_live_preview_build",false): display.set_meta("preview_instance_transforms",batches[color])
		add_child(display)
	batches.clear()

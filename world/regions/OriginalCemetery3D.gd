extends Node3D
## Exterior layout from HarborGame/HarborCemetery, in native metres.
## The keeper facade remains owned by PlaceCatalog. No burial/gameplay state here.
const SOURCE_CENTER := Vector2(-650, 1740)
const SCALE := 1.0 / 16.0
const LOT_SIZE := Vector2(780, 700)
const PINE := preload("res://world/regions/NativePine.gd")
const GRASS := preload("res://world/urban_detail/HarborGrassTufts.gd")
## Gramado e caminhos ganham textura projetada no mundo; antes eram cubos de cor lisa
## e o cemitério lia como chão chapado (feedback de 25/09/2026).
var batches: Dictionary = {}
var solids: StaticBody3D

static func world_position() -> Vector3:
	return Vector3(SOURCE_CENTER.x, 0, SOURCE_CENTER.y) * SCALE

func _ready() -> void:
	name = "OriginalCemetery"
	solids = StaticBody3D.new()
	solids.name = "CemeterySolids"
	solids.collision_layer = 1
	solids.collision_mask = 0
	add_child(solids)
	_box(Vector3(0, -.025, 0), Vector3(LOT_SIZE.x*SCALE, .05, LOT_SIZE.y*SCALE), "27362f", true)
	_path(Vector2(0, 0), Vector2(28, 700))
	_path(Vector2(0, -420), Vector2(50, 140))
	_path(Vector2(-235, -161.5), Vector2(24, 33))
	_path(Vector2(-117.5, -145), Vector2(235, 24))
	# North gate: 52 source pixels, 3.25 m before the two stone posts.
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
		_box(point+Vector3.UP*.47,Vector3(60*SCALE,.14,12*SCALE),"514d43",true)
		_box(point+Vector3(0,.84,.32),Vector3(60*SCALE,.6,.12),"514d43",true)
		for side in [-1,1]: _box(point+Vector3(side*1.25,.22,0),Vector3(.14,.44,.6),"444d49",true)
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

func _path(point: Vector2, size: Vector2) -> void:
	_box(Vector3(point.x*SCALE,.014,point.y*SCALE),Vector3(size.x*SCALE,.018,size.y*SCALE),"777366")

func _tomb(point: Vector2, variant: int) -> void:
	# Original CemeteryGrave3D model units project at 20px; V2 geography is 16px/m.
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
	# Exact physical footprint, with separate headstone so shots do not hit empty air.
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
		if color == "27362f": material = GRASS.ground_material()
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
		add_child(display)
	batches.clear()

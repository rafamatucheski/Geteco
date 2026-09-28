extends Node3D
## Static roadside stop in Harbor coordinates. Homes are closed exterior scenery.
const ORIGIN := Vector3(-330,0,108)
const FOOTPRINT := Rect2(-418,62,176,88)
const TONICO_POINT := Vector3(-353,0,101)
const PUMP_POINT := Vector3(-342,0,101)
const BELT_POINT := Vector3(-397,0,133)
const CRANK_POINT := Vector3(-270,0,135)
const ACCESS_START := Vector2(-290,10)
const ACCESS_END := Vector2(-290,78)
const STATION_PIVOT := Vector3(-28,0,-16)
const STATION_BASIS := Basis(Vector3(.78,0,0),Vector3(0,.8,0),Vector3(0,0,.74))
const STATION_TRANSFORM := Transform3D(STATION_BASIS,STATION_PIVOT-STATION_BASIS*STATION_PIVOT)
const HOME_LAYOUT := [
	[Vector3(-73,0,-21),"a49673",PI*.5],
	[Vector3(-76,0,9),"989e82",1.48],
	[Vector3(-47,0,30),"ac8d72",3.28],
	[Vector3(-14,0,31),"929e94",2.97],
	[Vector3(20,0,29),"b4aa87",3.35],
	[Vector3(70,0,-27),"9f8976",-.65]]
var solids: Array[StaticBody3D] = []
var placements: Array[Dictionary] = []
var houses: Array[Vector3] = []
var parts: Dictionary = {}
var editor_batches: Dictionary = {}
var _batches: Dictionary = {}
var _paint_materials: Dictionary = {}
var _roof: Node3D
var _tire_roof: MeshInstance3D
var _fixed: Node3D
var tonico: CharacterBody3D
var _pump_lens: MeshInstance3D
var repaired := false
var _player: Node3D
var _scan := 0.0
var _active := true
var _author_transform := Transform3D.IDENTITY
var _cutaway := false
var _tire_cutaway := false
var _current_home_roof: Node3D
var homes: Node3D

func _ready() -> void:
	name = "TruckersVillageVisuals"
	position = ORIGIN
	_fixed = Node3D.new()
	_fixed.name = "VillageDetails"
	add_child(_fixed)
	_roof = Node3D.new()
	_roof.name = "StationCanopy"
	add_child(_roof)
	_ground()
	_station()
	_homes()
	preload("res://gameplay/urban_v1/TruckersVillageDressing.gd").dress_common_yard(self)
	_tire_shop()
	_farm_cart(Vector3(58,0,18))
	_scrap_corner()
	preload("res://gameplay/urban_v1/TruckersVillageDressing.gd").pedestrian_entry(self)
	preload("res://gameplay/urban_v1/TruckersVillageDressing.gd").shop_counter(self)
	preload("res://gameplay/urban_v1/TruckersVillageVegetation.gd").build(self)
	_part("belt",BELT_POINT-ORIGIN)
	_part("crank",CRANK_POINT-ORIGIN)
	_flush()
	tonico = preload("res://gameplay/urban_v1/TruckersVillageResident.gd").new()
	tonico.configure({"id":"tonico","variant":3,"stationary":true,"position":TONICO_POINT-ORIGIN})
	add_child(tonico)
	set_process(is_instance_valid(_player))

func configure_player(player: Node3D) -> void:
	_player = player
	set_process(_active and is_instance_valid(player))

func _process(delta: float) -> void:
	_scan -= delta
	if _scan > 0: return
	_scan = .15
	if not is_instance_valid(_player):
		set_process(false)
		return
	var at := _player.global_position
	var station_at: Vector3 = STATION_TRANSFORM.affine_inverse()*(at-ORIGIN)
	set_cutaway(Rect2(-48,-27,41,29).has_point(Vector2(station_at.x,station_at.z)))
	var tire_inside := Rect2(-278,97,18,16).has_point(Vector2(at.x,at.z))
	if tire_inside != _tire_cutaway:
		_tire_cutaway = tire_inside
		_fade_mesh(_tire_roof,tire_inside)

func set_region_active(active: bool) -> void:
	_active = active
	set_process(active and is_instance_valid(_player))
	visible = active
	for body in solids: body.collision_layer = 1 if active else 0
	if is_instance_valid(tonico):
		tonico.set_active(active)

func set_cutaway(active: bool) -> void:
	if active == _cutaway: return
	_cutaway = active
	for mesh in _roof.get_children(): _fade_mesh(mesh,active)

func _fade_mesh(mesh: GeometryInstance3D,active: bool) -> void:
	# Material alpha is supported by the Mobile renderer; the outline of the
	# roof remains visible while people, pumps and interactions stay readable.
	if not mesh.has_meta("cutaway_paint"):
		var source: Material = mesh.material_override
		if source == null and mesh is MultiMeshInstance3D: source=mesh.multimesh.mesh.surface_get_material(0)
		var paint := source.duplicate() as StandardMaterial3D
		mesh.material_override=paint
		mesh.set_meta("cutaway_paint",paint)
	var material: StandardMaterial3D = mesh.get_meta("cutaway_paint")
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA if active else BaseMaterial3D.TRANSPARENCY_DISABLED
	material.albedo_color.a=.09 if active else 1.0
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if active else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func set_part_collected(id: String,collected: bool) -> void:
	if parts.has(id): parts[id].visible = not collected

func set_repaired(value: bool) -> void:
	repaired = value
	if is_instance_valid(_pump_lens):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("91ab6b") if value else Color("754531")
		_pump_lens.material_override = material

func _ground() -> void:
	# The approach is a real editor road. Only worn yards and walking paths
	# belong to this place; there is no rectangle spanning the highway.
	preload("res://gameplay/urban_v1/TruckersVillageGround.gd").build(self,HOME_LAYOUT)
	_author_transform=STATION_TRANSFORM
	for x in range(-46,-9,6): _box(Vector3(x,.056,-13),Vector3(.025,.008,26),"747466")
	for z in [-22.0,-15.0,-8.0]: _box(Vector3(-29,.057,z),Vector3(38,.008,.025),"747466")
	for p in [Vector3(-37,0,-17),Vector3(-19,0,-9)]:
		_box(p+Vector3(0,.06,0),Vector3(3.2,.008,.045),"514f45",Vector3(0,.5,0))
		_box(p+Vector3(1,.061,.6),Vector3(1.8,.008,.04),"514f45",Vector3(0,-.6,0))
	_author_transform=Transform3D.IDENTITY

func _station() -> void:
	_author_transform=STATION_TRANSFORM
	_box(Vector3(-30,1.6,-34),Vector3(24,3.2,10),"b1a68c")
	_solid("TonicoShop",Vector3(-30,1.6,-34),Vector3(24,3.2,10))
	for x in [-37.5,-23.0]:
		_box(Vector3(x,1.85,-28.94),Vector3(4.3,1.5,.10),"465455")
		for edge in [-2.24,2.24]: _box(Vector3(x+edge,1.8,-28.82),Vector3(.14,1.7,.18),"6b5842")
		_box(Vector3(x,1.85,-28.80),Vector3(.10,1.5,.12),"aa9d79")
	_box(Vector3(-30,1.15,-28.91),Vector3(1.3,2.3,.14),"60533f")
	_box(Vector3(-29.55,1.1,-28.79),Vector3(.1,.12,.06),"bba781")
	_box(Vector3(-30,3.37,-34),Vector3(25,.23,11),"755541",Vector3(0,0,.025))
	for x in range(-42,-17): _box(Vector3(x,3.51,-34),Vector3(.06,.045,11),"8e6750")
	_box(Vector3(-30,3.0,-28.78),Vector3(10,.6,.18),"666d58")
	_label("Posto do Tonico",Vector3(-30,3.03,-28.66),.024)
	for x in [-44.0,-12.0]:
		for z in [-23.0,-5.0]:
			_box(Vector3(x,2.7,z),Vector3(.34,5.4,.34),"aaa18b")
			_box(Vector3(x,.55,z),Vector3(.38,1.1,.38),"765441")
			_solid("CanopyPost",Vector3(x,2.7,z),Vector3(.38,5.4,.38))
	_box(Vector3(-28,5.45,-14),Vector3(35,.16,21),"715240",Vector3.ZERO,true)
	for z in [-24.5,-3.5]: _box(Vector3(-28,5.28,z),Vector3(35,.38,.17),"827a60",Vector3.ZERO,true)
	for x in [-45.5,-10.5]: _box(Vector3(x,5.28,-14),Vector3(.17,.38,21),"827a60",Vector3.ZERO,true)
	for x in range(-45,-10): _box(Vector3(x,5.57,-14),Vector3(.065,.04,21),"a17e5b",Vector3.ZERO,true)
	for p in [Vector3(-39,5.55,-20),Vector3(-18,5.55,-8),Vector3(-29,5.55,-12)]: _box(p,Vector3(4,.03,2.5),"594c3e",Vector3.ZERO,true)
	for x in [-34.0,-17.0]: _pump(Vector3(x,0,-12))
	_box(Vector3(33,2.9,-37),Vector3(.2,5.8,.2),"5b594d")
	_solid("SignPole",Vector3(33,2.9,-37),Vector3(.2,5.8,.2))
	_box(Vector3(33,5.3,-37),Vector3(6.8,1.65,.22),"857047")
	_label("Tonico",Vector3(33,5.32,-36.84),.040)
	_bench(Vector3(-39,0,-26))
	_box(Vector3(-34,.47,-26),Vector3(1.1,.94,.55),"536051")
	_solid("ShopCooler",Vector3(-34,.47,-26),Vector3(1.1,.94,.55))
	# Compressor is separate from the old fuel pumps; restoring it enables repairs.
	_cylinder(Vector3(-9,.55,-7),.45,1.6,"89694c",Vector3(0,0,PI*.5))
	_box(Vector3(-9,1.04,-7),Vector3(.6,.3,.45),"494e43")
	_pump_lens = MeshInstance3D.new()
	_pump_lens.name = "CompressorRepairIndicator"
	var lens := BoxMesh.new()
	lens.size = Vector3(.16,.1,.025)
	_pump_lens.mesh = lens
	_pump_lens.transform = STATION_TRANSFORM*Transform3D(Basis.IDENTITY,Vector3(-9,1.08,-6.76))
	add_child(_pump_lens)
	set_repaired(false)
	_solid("AirCompressor",Vector3(-9,.7,-7),Vector3(1.8,1.4,1))
	for x in [-10.0,-10.8]: _box(Vector3(x,.09,-7),Vector3(.065,.06,1.5),"32392d")
	_box(Vector3(-10.4,.09,-6.25),Vector3(.8,.06,.065),"32392d")
	for p in [Vector3(-37,2.7,-28.5),Vector3(-23,2.7,-28.5)]: _lamp(p)
	_author_transform=Transform3D.IDENTITY

func _pump(at: Vector3) -> void:
	_box(at+Vector3(0,.10,0),Vector3(1.4,.2,1.2),"79796a")
	_box(at+Vector3(0,.64,0),Vector3(.74,1.0,.62),"93664c")
	_box(at+Vector3(0,1.43,0),Vector3(.94,.7,.69),"b4aa86")
	_box(at+Vector3(0,1.54,.36),Vector3(.66,.29,.045),"303833")
	for x in [-.22,-.07,.08,.23]:
		_box(at+Vector3(x,1.55,.389),Vector3(.115,.21,.018),"ded5ac")
		_box(at+Vector3(x,1.55,.40),Vector3(.045,.075,.01),"4c5146")
	for z in [-.32,.32]: _box(at+Vector3(.57,.73,z),Vector3(.065,1.1,.065),"30352f")
	_box(at+Vector3(.57,.18,0),Vector3(.065,.07,.64),"30352f")
	_box(at+Vector3(.53,1.31,.32),Vector3(.11,.32,.12),"797d6d",Vector3(0,0,-.4))
	_box(at+Vector3(-.2,.4,.326),Vector3(.25,.25,.025),"5d4938")
	_solid("MechanicalPump",at+Vector3(0,.9,0),Vector3(1.4,1.8,1.2))

func _homes() -> void:
	homes=preload("res://gameplay/urban_v1/TruckersVillageHomes.gd").new()
	add_child(homes)
	homes.build(self,HOME_LAYOUT)
	for index in HOME_LAYOUT.size():
		var entry: Array = HOME_LAYOUT[index]
		_author_transform = Transform3D(Basis(Vector3.UP,entry[2]),entry[0])
		_current_home_roof=homes.homes[index].roof
		preload("res://gameplay/urban_v1/TruckersVillageDressing.gd").dress_home(self,index)
	_author_transform = Transform3D.IDENTITY
	_current_home_roof=null

func _tire_shop() -> void:
	var at := Vector3(61,0,-4)
	_box(at+Vector3(0,1.7,-5),Vector3(15,3.4,.25),"8c7960")
	_solid("TireShopRear",at+Vector3(0,1.7,-5),Vector3(15,3.4,.25))
	for x in [-7.5,7.5]:
		_box(at+Vector3(x,1.7,0),Vector3(.22,3.4,10),"8c7960")
		_solid("TireShopSide",at+Vector3(x,1.7,0),Vector3(.22,3.4,10))
	# The open workshop is walkable too: its roof must reveal the same floor
	# and native actors when entered, independently of the fuel canopy.
	_tire_roof = MeshInstance3D.new()
	_tire_roof.name = "TireShopRoof"
	var roof_mesh := BoxMesh.new()
	roof_mesh.size = Vector3(16,.16,11)
	_tire_roof.mesh = roof_mesh
	_tire_roof.position = at+Vector3(0,3.65,0)
	_tire_roof.rotation.z = .045
	var roof_material := StandardMaterial3D.new()
	roof_material.albedo_color = Color("6c6854")
	roof_material.roughness = .91
	_tire_roof.material_override = roof_material
	add_child(_tire_roof)
	_box(at+Vector3(0,3.27,5.0),Vector3(4.5,.65,.18),"62533e")
	_label("Zeca",at+Vector3(0,3.27,5.11),.035)
	for x in [-5.8,5.8]:
		for y in [.24,.68,1.12]: _cylinder(at+Vector3(x,y,2.7),.65,.4,"30352f")
		_solid("TireStack",at+Vector3(x,.7,2.7),Vector3(1.3,1.4,1.3))
	_box(at+Vector3(-3,.9,-3.8),Vector3(4,.16,1.5),"73674f")
	for x in [-4.6,-1.4]: _box(at+Vector3(x,.42,-3.8),Vector3(.15,.84,1.25),"595b4b")
	_solid("TireShopBench",at+Vector3(-3,.5,-3.8),Vector3(4,1,1.5))
	_cylinder(at+Vector3(4,.7,-3.5),.5,1.8,"795b48",Vector3(0,0,PI*.5))
	_solid("Compressor",at+Vector3(4,.65,-3.5),Vector3(2,1.3,1.1))
	_lamp(at+Vector3(0,3.1,-4.6))

func _farm_cart(at: Vector3) -> void:
	# A retired hand cart keeps the east scavenging corner pedestrian.
	for x in [-1.1,1.1]:
		for z in [-1.6,1.6]:
			_cylinder(at+Vector3(x,.55,z),.52,.18,"403c2f",Vector3(0,0,PI*.5))
			_cylinder(at+Vector3(x*1.09,.55,z),.32,.20,"88704a",Vector3(0,0,PI*.5))
	_box(at+Vector3(0,.79,0),Vector3(2.1,.18,4.9),"79613f")
	for side in [-1.0,1.0]:
		for y in [1.1,1.45]: _box(at+Vector3(side*1.0,y,0),Vector3(.12,.22,4.9),"87704d")
		for z in [-2.2,0,2.2]: _box(at+Vector3(side*1.02,1.26,z),Vector3(.10,1.0,.12),"635941")
		_box(at+Vector3(side*.65,.68,3.2),Vector3(.1,.12,2),"796b49")
	for p in [Vector3(-.5,1.12,-1.4),Vector3(.4,1.05,.8)]:
		_box(at+p,Vector3(.8,.55,1.1),"9c8d62",Vector3(0,.2,0))
	_solid("FarmCart",at+Vector3(0,.83,0),Vector3(2.5,1.66,4.9))

func _scrap_corner() -> void:
	for p in [Vector3(-78,0,26),Vector3(-74,0,31),Vector3(-64,0,31)]:
		_box(p+Vector3(0,.65,0),Vector3(2.7,1.3,1.9),"775640")
		_box(p+Vector3(.3,1.32,0),Vector3(1.4,.1,1.5),"8b7556",Vector3(.07,0,.16))
		_solid("SalvageCrate",p+Vector3(0,.75,0),Vector3(2.7,1.5,1.9))
	for x in [-82.0,-77.0,-62.0,-57.0]:
		_box(Vector3(x,.8,36),Vector3(.15,1.6,.15),"786c50")
		_solid("FencePost",Vector3(x,.8,36),Vector3(.15,1.6,.15))
	for x in [-79.5,-59.5]:
		for y in [.5,1.1]: _box(Vector3(x,y,36),Vector3(5,.12,.12),"817456")
		_solid("FencePanel",Vector3(x,.8,36),Vector3(5,1.6,.15))

func _part(id: String,at: Vector3) -> void:
	var holder := Node3D.new()
	holder.name = "Find_"+id
	holder.position = at
	add_child(holder)
	parts[id] = holder
	var mesh := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("ab884a") if id == "crank" else Color("373d30")
	material.roughness = .8
	if id == "belt":
		var torus := TorusMesh.new()
		torus.inner_radius = .18
		torus.outer_radius = .25
		torus.rings = 12
		torus.ring_segments = 6
		mesh.mesh = torus
	else:
		var crank := BoxMesh.new()
		crank.size = Vector3(.12,.12,.65)
		mesh.mesh = crank
		var handle := MeshInstance3D.new()
		var handle_mesh := BoxMesh.new()
		handle_mesh.size = Vector3(.3,.12,.12)
		handle.mesh = handle_mesh
		handle.position = Vector3(.1,.12,.3)
		handle.material_override = material
		holder.add_child(handle)
	mesh.position.y = .13
	mesh.material_override = material
	holder.add_child(mesh)

func _bench(at: Vector3) -> void:
	_box(at+Vector3(0,.48,0),Vector3(2.2,.14,.58),"766449")
	_box(at+Vector3(0,.88,-.25),Vector3(2.2,.6,.09),"827052")
	for x in [-.8,.8]: _box(at+Vector3(x,.23,0),Vector3(.13,.46,.45),"5b5845")
	_solid("WoodenBench",at+Vector3(0,.55,0),Vector3(2.2,1.1,.65))

func _lamp(at: Vector3) -> void:
	_box(at,Vector3(.34,.14,.24),"514f3f")
	_box(at+Vector3(0,-.08,.02),Vector3(.26,.035,.19),"dbc190")
	var fitting := Node3D.new()
	fitting.transform = _author_transform*Transform3D(Basis.IDENTITY,at)
	add_child(fitting)
	fitting.add_to_group(&"city_local_light_source")
	fitting.set_meta("local_light",{"range":7.0,"energy":.85,"color":Color("ffcf89")})

func _label(value: String,at: Vector3,pixel: float) -> void:
	var label := Label3D.new()
	label.text = value
	label.transform = _author_transform*Transform3D(Basis.IDENTITY,at)
	label.pixel_size = pixel
	label.font_size = 40
	label.outline_size = 0
	label.modulate = Color("dfd1a1")
	label.no_depth_test = false
	add_child(label)

func _box(at: Vector3,size: Vector3,color: String,angles := Vector3.ZERO,roof := false) -> void:
	_put("box",at,size,color,angles,roof)

func _cylinder(at: Vector3,radius: float,height: float,color: String,angles := Vector3.ZERO) -> void:
	_put("cylinder",at,Vector3(radius*2,height,radius*2),color,angles,false)

func _put(kind: String,at: Vector3,size: Vector3,color: String,angles: Vector3,roof: bool) -> void:
	var authored := _author_transform*Transform3D(Basis.from_euler(angles).scaled(size),at)
	var cell := Vector2i(floori(authored.origin.x/32),floori(authored.origin.z/32))
	# Authored paint is material albedo: MultiMesh instance-color readback and
	# some renderer paths cannot reliably preserve that channel for this scene.
	var owner: Node3D = (_current_home_roof if is_instance_valid(_current_home_roof) else _roof) if roof else _fixed
	var key := "%s_%s_%s_%s"%[kind,cell,owner.get_instance_id(),color]
	if not _batches.has(key): _batches[key] = {"kind":kind,"owner":owner,"paint":color,"transforms":[],"colors":[]}
	_batches[key].transforms.append(authored)
	_batches[key].colors.append(Color(color))

func _solid(id: String,at: Vector3,size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = id
	body.transform = _author_transform*Transform3D(Basis.IDENTITY,at)
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("interior_solid_id",id)
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	solids.append(body)
	placements.append({"id":id,"center":body.position,"basis":body.basis,"size":size})

func _flush() -> void:
	for key in _batches:
		var batch: Dictionary = _batches[key]
		var mesh: PrimitiveMesh
		if batch.kind == "box": mesh = BoxMesh.new()
		else:
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = .5
			cylinder.bottom_radius = .5
			cylinder.height = 1
			cylinder.radial_segments = 12
			cylinder.rings = 1
			mesh = cylinder
		if not _paint_materials.has(batch.paint):
			var paint := StandardMaterial3D.new()
			paint.albedo_color = Color(batch.paint)
			paint.roughness = .91
			_paint_materials[batch.paint] = paint
		mesh.material = _paint_materials[batch.paint]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = batch.transforms.size()
		for index in multi.instance_count:
			multi.set_instance_transform(index,batch.transforms[index])
		var display := MultiMeshInstance3D.new()
		display.name = key.validate_node_name()
		display.multimesh = multi
		display.set_meta("editor_transforms",batch.transforms)
		display.set_meta("editor_colors",batch.colors)
		var owner: Node3D = batch.owner
		owner.add_child(display)
		# Authored transforms live in village coordinates, including rotated homes.
		display.transform=owner.global_transform.affine_inverse()*global_transform
		editor_batches[String(display.get_path())] = batch.duplicate(true)
	_batches.clear()

extends Node3D
## Native clandestine room. The place adapter owns travel, camera and rewards.
const SPAWN_POINT := Vector3(0,0,3)
const EXIT_POINT := Vector3(0,0,4)
const WEAPON_POINT := Vector3(0,0,-3)
const CASH_POINT := Vector3(3,0,1)
const ROOM_BOUNDS := Rect2(-6,-5,12,10)
var solids: Array[StaticBody3D] = []
var floor_body: StaticBody3D
var roof_parts: Array[Node3D] = []
var facade_parts: Array[Node3D] = []
var lights: Array[OmniLight3D] = []
var active := true
var _cutaway := true
var _fixed: Node3D
var _roof: Node3D
var _front: Node3D
var _materials := {}
var _batches := {}

func _ready() -> void:
	name = "VerticeUndercroft"
	_fixed = _group("RoomAndFurniture")
	_roof = _group("CeilingCutaway")
	_front = _group("FrontWallCutaway")
	roof_parts.append(_roof)
	facade_parts.append(_front)
	_shell()
	_workbench()
	_armory()
	_rest_corner()
	_services()
	_exit_ladder()
	_commit()
	set_cutaway(_cutaway)
	set_active(active)

func set_active(value: bool) -> void:
	active = value
	visible = value
	for body in solids: body.collision_layer = 1 if value else 0
	if is_instance_valid(floor_body): floor_body.collision_layer = 1 if value else 0
	for light in lights: light.visible = value
	set_process(false)
	set_physics_process(false)

func set_cutaway(value: bool) -> void:
	_cutaway = value
	for part in roof_parts: part.visible = not value
	for part in facade_parts: part.visible = not value

func _group(id: String) -> Node3D:
	var group := Node3D.new()
	group.name = id
	add_child(group)
	return group

func _shell() -> void:
	_box(Vector3(0,-.12,0),Vector3(12.4,.24,10.4),"floor")
	floor_body = _solid("Floor",Vector3(0,-.12,0),Vector3(12.4,.24,10.4),false)
	floor_body.set_meta("interior_floor",true)
	for spec in [["WestWall",Vector3(-6,1.6,0),Vector3(.24,3.2,10.3)],
		["EastWall",Vector3(6,1.6,0),Vector3(.24,3.2,10.3)],
		["BackWall",Vector3(0,1.6,-5),Vector3(12,3.2,.24)]]:
		_box(spec[1],spec[2],"concrete")
		_solid(spec[0],spec[1],spec[2])
	_box(Vector3(0,1.6,5),Vector3(12,3.2,.24),"concrete",_front)
	_solid("FrontWall",Vector3(0,1.6,5),Vector3(12,3.2,.24))
	_box(Vector3(0,3.26,0),Vector3(12.2,.16,10.2),"concrete",_roof)
	# Formwork seams and a worn lower wall band give concrete actual scale.
	for x in [-5.9,5.9]:
		_box(Vector3(x,.46,0),Vector3(.03,.86,9.9),"wall_band")
		for z in [-4.8,-2.4,0,2.4,4.8]:
			_box(Vector3(x,1.65,z),Vector3(.036,2.9,.018),"seam")
	_box(Vector3(0,.46,-4.86),Vector3(11.8,.86,.035),"wall_band")
	for x in [-5.7,-3.3,-.9,1.5,3.9]:
		_box(Vector3(x,1.62,-4.865),Vector3(.018,3.0,.028),"seam")
	for x in [-4,0,4]:
		_box(Vector3(x,3.07,0),Vector3(.24,.22,10),"steel",_roof)
	for z in [-4.6,4.6]:
		_box(Vector3(0,.025,z),Vector3(11.7,.05,.18),"steel")
	# Floor drain is flush and walkable, not an invisible collision obstacle.
	_box(Vector3(-2.7,.014,1.4),Vector3(.65,.02,.65),"dark")
	for i in 7: _box(Vector3(-2.97+i*.09,.031,1.4),Vector3(.035,.016,.61),"steel")
	for z in [-2.0,1.0]:
		_box(Vector3(-1.85,.012,z),Vector3(.065,.012,1.05),"ochre")

func _workbench() -> void:
	# A single full-volume body blocks the table, including the space below it.
	_solid("Workbench",Vector3(-5.02,.6,-2.2),Vector3(1.42,1.2,3.25))
	_box(Vector3(-5.02,1.01,-2.2),Vector3(1.42,.13,3.25),"wood")
	for x in [-5.58,-4.46]:
		for z in [-3.61,-.79]: _box(Vector3(x,.49,z),Vector3(.09,.96,.09),"steel")
	_box(Vector3(-5.02,.23,-2.2),Vector3(1.2,.08,2.95),"steel")
	_box(Vector3(-5.87,1.94,-2.2),Vector3(.055,1.22,3.1),"paint")
	for z in [-3.4,-3.0,-2.6,-2.2,-1.8,-1.4,-1.0]:
		for y in [1.55,1.82,2.09,2.36]: _box(Vector3(-5.83,y,z),Vector3(.018,.028,.028),"dark")
	for z in [-3.25,-2.7,-2.15]:
		_box(Vector3(-5.79,1.9,z),Vector3(.055,.36,.055),"steel")
		_box(Vector3(-5.79,2.08,z),Vector3(.07,.07,.16),"steel")
	_box(Vector3(-4.7,1.17,-3.24),Vector3(.45,.24,.34),"steel")
	_box(Vector3(-4.7,1.33,-3.24),Vector3(.51,.07,.13),"dark")
	_box(Vector3(-5.06,1.092,-1.86),Vector3(.7,.025,.8),"paper",null,Vector3(0,.18,0))
	for z in [-2.02,-1.83,-1.64]: _box(Vector3(-5.04,1.108,z),Vector3(.48,.009,.012),"pencil")
	_box(Vector3(-5.22,.46,-2.9),Vector3(.7,.38,.77),"ammo")
	_box(Vector3(-5.22,.66,-2.9),Vector3(.73,.035,.8),"steel")
	_cylinder(Vector3(-4.66,1.16,-1.03),.14,.19,"ceramic")
	_cylinder(Vector3(-4.66,1.26,-1.03),.108,.015,"dark")
	for z in [-.98,-.84,-.70]: _cylinder(Vector3(-5.15,1.135,z),.037,.115,"brass")

func _armory() -> void:
	_solid("ArmoryCabinet",Vector3(3.5,1.16,-4.32),Vector3(1.8,2.32,.94))
	_box(Vector3(3.5,1.16,-4.32),Vector3(1.8,2.32,.94),"paint")
	for x in [3.04,3.96]:
		_box(Vector3(x,1.18,-3.836),Vector3(.85,2.13,.045),"ammo")
		for y in [1.85,1.94,2.03]: _box(Vector3(x,y,-3.807),Vector3(.5,.025,.018),"dark")
		_box(Vector3(x+(0.3 if x<3.5 else -.3),1.2,-3.78),Vector3(.06,.3,.06),"steel")
	_box(Vector3(3.5,1.16,-3.78),Vector3(.19,.14,.08),"brass")
	# Ammunition cases remain beside the cabinet, leaving the reward aisle open.
	_solid("AmmoCases",Vector3(5.12,.5,-2.6),Vector3(1.15,1,1.1))
	for y in [.23,.69]:
		_box(Vector3(5.12,y,-2.6),Vector3(1.15,.43,1.1),"ammo")
		_box(Vector3(5.12,y+.22,-2.6),Vector3(1.18,.045,1.13),"steel")
		for x in [4.8,5.44]: _box(Vector3(x,y,-2.035),Vector3(.075,.22,.045),"brass")
	# Map fragments and pins imply a hidden operation without explanatory text.
	_box(Vector3(-.3,1.95,-4.86),Vector3(2.5,1.28,.035),"wood")
	for i in 3:
		_box(Vector3(-1.08+i*.78,1.98,-4.83),Vector3(.69,.9,.025),"paper",null,Vector3(0,0,.06*(i-1)))
		_box(Vector3(-1.08+i*.78,2.36,-4.805),Vector3(.045,.045,.02),"red")
	for x in [-1.2,-.3,.6]:
		_box(Vector3(x,1.97,-4.808),Vector3(.025,.57,.008),"pencil",null,Vector3(0,0,.25))

func _rest_corner() -> void:
	_solid("Cot",Vector3(4.86,.48,1.9),Vector3(1.65,.96,2.3))
	_box(Vector3(4.86,.38,1.9),Vector3(1.6,.12,2.25),"steel")
	for x in [4.16,5.56]:
		for z in [.91,2.89]: _box(Vector3(x,.22,z),Vector3(.06,.44,.06),"steel")
	_box(Vector3(4.86,.53,1.9),Vector3(1.5,.22,2.15),"canvas")
	_box(Vector3(4.86,.66,2.28),Vector3(1.53,.1,1.42),"blanket")
	for x in [4.25,4.62,5.05,5.49]: _box(Vector3(x,.72,2.28),Vector3(.025,.013,1.4),"cloth_seam")
	_box(Vector3(4.86,.73,1.16),Vector3(.88,.23,.47),"linen")
	_solid("RadioTable",Vector3(4.82,.59,-.35),Vector3(1.65,1.18,1.0))
	_box(Vector3(4.82,.76,-.35),Vector3(1.65,.11,1),"wood")
	for x in [4.11,5.53]:
		for z in [-.74,.04]: _box(Vector3(x,.38,z),Vector3(.08,.76,.08),"steel")
	_box(Vector3(4.73,1.02,-.4),Vector3(.94,.44,.44),"dark")
	_box(Vector3(4.51,1.04,-.167),Vector3(.39,.31,.025),"steel")
	for x in [4.38,4.45,4.52,4.59,4.66]: _box(Vector3(x,1.04,-.148),Vector3(.014,.26,.018),"dark")
	_box(Vector3(4.99,1.08,-.161),Vector3(.24,.07,.028),"dial")
	_cylinder(Vector3(4.95,.95,-.15),.09,.035,"steel",Vector3(PI*.5,0,0))
	_cylinder(Vector3(5.12,.95,-.15),.06,.035,"steel",Vector3(PI*.5,0,0))
	_cylinder(Vector3(5.04,1.61,-.48),.019,.82,"steel",Vector3(0,0,-.15))
	_solid("TravelCase",Vector3(-4.7,.36,3.3),Vector3(1.8,.72,1.02))
	_box(Vector3(-4.7,.36,3.3),Vector3(1.8,.72,1.02),"canvas")
	for x in [-5.18,-4.22]: _box(Vector3(x,.73,3.3),Vector3(.075,.035,1.02),"dark")
	_box(Vector3(-4.7,.43,3.835),Vector3(.36,.1,.075),"steel")
	_solid("SupplyCrates",Vector3(-5.15,.54,1.07),Vector3(1.1,1.08,1.18))
	_box(Vector3(-5.15,.54,1.07),Vector3(1.1,1.08,1.18),"wood")
	for y in [.19,.52,.85]: _box(Vector3(-5.15,y,1.67),Vector3(1.13,.075,.045),"wood_edge")
	for x in [-5.57,-4.73]: _box(Vector3(x,.55,1.7),Vector3(.09,1.05,.06),"steel")

func _services() -> void:
	for x in [-5.65,-5.36]:
		_cylinder(Vector3(x,2.82,0),.105,9.8,"copper",Vector3(PI*.5,0,0))
		for z in [-4,-1.5,1,3.5]: _box(Vector3(x,2.88,z),Vector3(.17,.025,.1),"steel")
	_cylinder(Vector3(-5.65,1.67,4.1),.105,2.3,"copper")
	_cylinder(Vector3(-5.53,1.37,4.1),.27,.06,"red",Vector3(0,0,PI*.5))
	_box(Vector3(5.86,2.15,3.8),Vector3(.15,.84,.67),"steel")
	for z in [3.64,3.94]: _box(Vector3(5.768,2.19,z),Vector3(.04,.3,.14),"dark")
	_box(Vector3(5.746,2.13,3.94),Vector3(.055,.1,.075),"red")
	for spec in [[Vector3(-3.7,2.85,-1.9),Color("ffd3a0"),6.8,1.3],
		[Vector3(3.6,2.75,1.5),Color("a8c5c0"),6.2,.9]]:
		var point: Vector3 = spec[0]
		_box(point+Vector3(0,.06,0),Vector3(.22,.09,1.15),"steel")
		_box(point,Vector3(.16,.06,1.04),"lamp")
		var light := OmniLight3D.new()
		light.position = point-Vector3.UP*.12
		light.light_color = spec[1]
		light.light_energy = spec[3]
		light.omni_range = spec[2]
		light.shadow_enabled = false
		add_child(light)
		lights.append(light)

func _exit_ladder() -> void:
	_solid("ExitLadder",Vector3(0,1.54,4.76),Vector3(1.13,3.08,.18))
	for x in [-.5,.5]: _cylinder(Vector3(x,1.55,4.75),.055,3.1,"steel")
	for i in 10: _cylinder(Vector3(0,.22+i*.3,4.72),.038,1.02,"steel",Vector3(0,0,PI*.5))
	_box(Vector3(0,3.16,4.16),Vector3(1.35,.11,1.3),"steel",_roof)
	for x in [-.69,.69]: _box(Vector3(x,3.08,4.17),Vector3(.06,.14,1.38),"ochre",_roof)

func _material(key: String) -> Material:
	if _materials.has(key): return _materials[key]
	var colors := {"floor":"61665b","concrete":"8b8c7f","wall_band":"58645b","seam":"565c53",
		"steel":"69716a","dark":"282f2d","paint":"5b6a5c","ammo":"465347","wood":"806b4e",
		"wood_edge":"9a8160","paper":"c7bd91","pencil":"788171","brass":"ad9461","red":"954b3b",
		"canvas":"70756a","blanket":"535f50","cloth_seam":"727e66","linen":"b5b4a0","ceramic":"a2a68d",
		"copper":"85715b","ochre":"baa363","dial":"cba65c","lamp":"e7dcc3"}
	var result := StandardMaterial3D.new()
	result.albedo_color = Color(colors[key])
	result.roughness = .9
	if key in ["steel","brass","copper"]:
		result.metallic = .45
		result.roughness = .57
	if key in ["lamp","dial"]:
		result.emission_enabled = true
		result.emission = result.albedo_color
		result.emission_energy_multiplier = .4
	if key in ["concrete","floor","wood"]:
		var noise := FastNoiseLite.new()
		noise.seed = 9301+key.length()
		noise.frequency = .018 if key != "wood" else .035
		var ramp := Gradient.new()
		ramp.set_color(0,Color(.87,.87,.87))
		ramp.set_color(1,Color(1.03,1.03,1.03))
		var texture := NoiseTexture2D.new()
		texture.width = 128
		texture.height = 128
		texture.noise = noise
		texture.color_ramp = ramp
		texture.seamless = true
		result.albedo_texture = texture
		result.uv1_triplanar = true
		result.uv1_scale = Vector3.ONE*.6
	_materials[key] = result
	return result

func _box(at: Vector3,size: Vector3,key: String,group: Node3D = null,angles := Vector3.ZERO) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_append(mesh,Transform3D(Basis.from_euler(angles),at),key,group)

func _cylinder(at: Vector3,diameter: float,height: float,key: String,angles := Vector3.ZERO) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = diameter*.5
	mesh.bottom_radius = diameter*.5
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 1
	_append(mesh,Transform3D(Basis.from_euler(angles),at),key,_fixed)

func _append(mesh: Mesh,transform: Transform3D,key: String,group: Node3D) -> void:
	if group == null: group = _fixed
	var batch_key := str(group.get_instance_id())+":"+key
	if not _batches.has(batch_key):
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[batch_key] = {"builder":builder,"group":group,"material":_material(key)}
	_batches[batch_key].builder.append_from(mesh,0,transform)

func _solid(id: String,at: Vector3,size: Vector3,obstacle := true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = id+"Solid"
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("interior_solid_id","vertice_undercroft/"+id)
	body.set_meta("bounds",AABB(at-size*.5,size))
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	if obstacle: solids.append(body)
	return body

func _commit() -> void:
	for batch in _batches.values():
		var display := MeshInstance3D.new()
		display.name = "StaticDetailBatch"
		display.mesh = batch.builder.commit()
		display.material_override = batch.material
		batch.group.add_child(display)
	_batches.clear()

extends Node3D
## Shared low-poly winter meshes; static groups render once with their surroundings.
const FLOOR_Y := 0.76822128
static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}
var features: Array[Dictionary] = []

static func floor_point(point: Vector2) -> Vector3:
	return Vector3(point.x/18.0,0,point.y/(18.0*FLOOR_Y))

func build(entries: Array[Dictionary]) -> void:
	if _materials.is_empty():
		for pair in [["bark","554237"],["cut","b6946b"],["ring","795b40"],["rock","687780"],["lichen","879183"],["snow","c6d5d9"],["needles","314d42"],["light_needles","476252"]]:
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(pair[1])
			material.roughness = 0.95
			_materials[pair[0]] = material
		var snow := preload("res://world/mountain_pass/MountainGroundMaterials.gd").material_3d("snow")
		snow.albedo_color = Color("c6d5d9")
		_materials["snow"] = snow
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var feature := Node3D.new()
		feature.name = "%s%02d" % [String(entry.kind).capitalize(),index]
		feature.position = floor_point(entry.point)
		feature.scale = Vector3.ONE*float(entry.get("scale",1.0))
		feature.rotation.y = -float(entry.get("angle",0.0))
		add_child(feature)
		match entry.kind:
			"pine": _pine(feature,index)
			"rock": _rock(feature,index)
			"log": _log(feature,index)
			"branches": _branches(feature,index)
		features.append({"root":feature,"kind":entry.kind,"solid":entry.kind!="branches","point":entry.point})

func dress_base(feature: Dictionary, seed_value: int) -> void:
	var parent: Node3D = feature.root
	var radius := 1.45 if feature.kind in ["pine","log"] else .83
	_mesh(parent,"stone",Vector3(-.1,.036,.06),Vector3(radius,.025,radius*.68),"snow")
	# Fallen needles and twig fragments collect under trees, around rock groups
	# and along logs, instead of becoming evenly scattered isolated props.
	for index in 11:
		var angle := float(index)*2.39996+float(seed_value)*.23
		var reach := radius*(.47+float(index%4)*.15)
		var a := Vector3(cos(angle)*reach,.067,sin(angle)*reach*.71)
		var b := a+Vector3(cos(angle+.9)*.12,.0,sin(angle+.9)*.12)
		_rod(parent,a,b,.008,"ring" if index%3 else "needles")

func _pine(parent: Node3D, variant: int) -> void:
	_rod(parent,Vector3.ZERO,Vector3(0.07,3.7,0),0.115,"bark")
	# Layered branch clusters have separate asymmetric snowy cushions. Their
	# offset silhouettes avoid the perfect cone stacks used by distant trees.
	for tier in 4:
		var reach := 1.05-float(tier)*0.22
		var height := 1.05+float(tier)*0.77
		for arm in 5:
			var angle := float(arm)*TAU/5.0+float(tier)*0.57+float(variant)*0.31
			var length := reach*(0.78+float(posmod(arm*7+variant,5))*0.07)
			var center := Vector3(cos(angle)*length*0.56,height+sin(angle*2.0)*0.06,sin(angle)*length*0.56)
			_rod(parent,Vector3(0,height+0.08,0),center+Vector3(cos(angle)*length*.23,-0.1,sin(angle)*length*.23),0.035,"bark")
			var shape := Vector3(length*.83,0.30+reach*.08,length*.52)
			var needles := _mesh(parent,"stone",center,shape,"needles" if arm%2 else "light_needles")
			needles.rotation.y = -angle
			var snow := _mesh(parent,"stone",center+Vector3(-0.045,0.19,0.025),shape*Vector3(.87,.62,.85),"snow")
			snow.rotation.y = needles.rotation.y
	_mesh(parent,"stone",Vector3(0.07,3.86,0),Vector3(.22,.45,.21),"needles")
	_mesh(parent,"stone",Vector3(.04,4.05,0),Vector3(.16,.25,.16),"snow")
	for arm in 4:
		var angle := float(arm)*TAU/4+0.3
		_rod(parent,Vector3.ZERO,Vector3(cos(angle)*.37,.025,sin(angle)*.3),.055,"bark")

func _rock(parent: Node3D, variant: int) -> void:
	var main := _mesh(parent,"stone",Vector3(0,.29,0),Vector3(.70,.43,.51),"rock")
	main.rotation_degrees = Vector3(5,variant*37,12)
	_mesh(parent,"stone",Vector3(-.14,.61,-.035),Vector3(.51,.12,.35),"snow")
	var chip := _mesh(parent,"stone",Vector3(.55,.12,.26),Vector3(.28,.19,.24),"lichen")
	chip.rotation.y = float(variant)
	_mesh(parent,"stone",Vector3(-.58,.08,.31),Vector3(.16,.1,.12),"rock")

func _log(parent: Node3D, variant: int) -> void:
	var a := Vector3(-1.12,.22,0)
	var b := Vector3(1.13,.29,.10)
	_rod(parent,a,b,.20,"bark")
	_rod(parent,a-Vector3(.005,0,0),a+Vector3(.012,0,0),.166,"cut")
	_rod(parent,b-Vector3(.008,0,0),b+Vector3(.012,0,0),.16,"cut")
	_rod(parent,b+Vector3(.013,0,0),b+Vector3(.017,0,0),.092,"ring")
	_rod(parent,b+Vector3(.018,0,0),b+Vector3(.021,0,0),.067,"cut")
	for ridge in 4:
		var z := (float(ridge)-1.5)*.09
		_rod(parent,a+Vector3(.1,.14,z),b+Vector3(-.12,.13,z),.017,"ring")
	_mesh(parent,"stone",Vector3(-.14,.42,.02),Vector3(.93,.09,.17),"snow")
	_rod(parent,Vector3(-.18,.27,.04),Vector3(-.35,.45,.55),.055,"bark")
	_rod(parent,Vector3(-.35,.45,.55),Vector3(-.09,.51,.68),.023,"bark")
	if variant%2 == 0: _mesh(parent,"stone",Vector3(.70,.06,.41),Vector3(.15,.09,.1),"rock")

func _branches(parent: Node3D, variant: int) -> void:
	_rod(parent,Vector3(-.68,.06,-.10),Vector3(.7,.06,.15),.025,"bark")
	_rod(parent,Vector3(-.24,.065,-.02),Vector3(.08,.07,-.44),.018,"bark")
	_rod(parent,Vector3(.17,.068,.05),Vector3(.55,.07,.48),.017,"bark")
	_rod(parent,Vector3(.30,.07,.06),Vector3(.62,.07,-.20),.013,"bark")
	_mesh(parent,"stone",Vector3(-.28,.08,.03),Vector3(.2,.035,.11),"snow")
	if variant%3==0: _mesh(parent,"stone",Vector3(.45,.06,.1),Vector3(.17,.1,.11),"needles")

func _rod(parent: Node3D, a: Vector3, b: Vector3, radius: float, material: String) -> MeshInstance3D:
	var instance := _mesh(parent,"cylinder",(a+b)*.5,Vector3(radius,a.distance_to(b),radius),material)
	instance.quaternion = Quaternion(Vector3.UP,a.direction_to(b))
	return instance

func _mesh(parent: Node3D, kind: String, point: Vector3, size: Vector3, material: String) -> MeshInstance3D:
	if not _meshes.has(kind):
		if kind=="cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 1.0
			cylinder.bottom_radius = 1.0
			cylinder.height = 1.0
			cylinder.radial_segments = 7
			_meshes[kind] = cylinder
		else:
			var stone := SphereMesh.new()
			stone.radius = 1.0
			stone.height = 2.0
			stone.radial_segments = 7
			stone.rings = 3
			_meshes[kind] = stone
	var instance := MeshInstance3D.new()
	instance.mesh = _meshes[kind]
	instance.material_override = _materials[material]
	instance.position = point
	instance.scale = size
	parent.add_child(instance)
	return instance

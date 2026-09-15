extends Node3D
## Raised stone tomb, modeled in metres; the view projects its solid footprint.
var planting: Node3D
var stems: Array[MeshInstance3D] = []
var blooms: Array[MeshInstance3D] = []

func _init() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("777f79")
	stone.roughness = .92
	var edge := StandardMaterial3D.new()
	edge.albedo_color = Color("505953")
	edge.roughness = .95
	var inset := StandardMaterial3D.new()
	inset.albedo_color = Color("a2a598")
	inset.roughness = .8
	box(Vector3(2.1,.16,3.5), Vector3(0,.08,0), edge)
	box(Vector3(1.85,.38,3.22), Vector3(0,.35,0), stone)
	box(Vector3(1.98,.12,3.36), Vector3(0,.60,0), inset)
	box(Vector3(1.54,.035,2.72), Vector3(0,.677,.12), stone)
	box(Vector3(1.85,.17,.55), Vector3(0,.74,-1.35), edge)
	box(Vector3(1.55,1.08,.27), Vector3(0,1.30,-1.35), stone)
	box(Vector3(1.66,.12,.36), Vector3(0,1.88,-1.35), inset)
	box(Vector3(.92,.58,.018), Vector3(0,1.38,-1.204), edge)
	box(Vector3(.055,.36,.025), Vector3(0,1.39,-1.187), inset)
	box(Vector3(.24,.055,.025), Vector3(0,1.45,-1.184), inset)
	planting = Node3D.new()
	planting.name = "Planting"
	add_child(planting)
	var bronze := StandardMaterial3D.new()
	bronze.albedo_color = Color("78624a")
	bronze.metallic = .45
	bronze.roughness = .6
	var vase := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = .13
	cylinder.bottom_radius = .09
	cylinder.height = .3
	cylinder.radial_segments = 12
	vase.mesh = cylinder
	vase.material_override = bronze
	vase.position = Vector3(.55,.84,.95)
	planting.add_child(vase)
	var leaves := StandardMaterial3D.new()
	leaves.albedo_color = Color("41523b")
	var petals := StandardMaterial3D.new()
	petals.albedo_color = Color("b8a5a0")
	for i in 5:
		var x := .55 + sin(i*2.4)*.13
		var z := .95 + cos(i*2.4)*.13
		box(Vector3(.025,.3,.025),Vector3(x,1.06,z),leaves)
		var stem := get_child(get_child_count()-1) as MeshInstance3D
		stem.reparent(planting, false)
		stems.append(stem)
		var flower := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = .09
		sphere.height = .10
		sphere.radial_segments = 12
		sphere.rings = 6
		flower.mesh = sphere
		flower.material_override = petals
		flower.position = Vector3(x,1.23,z)
		planting.add_child(flower)
		blooms.append(flower)
	set_plant_variant(0)

func set_plant_variant(identity: int) -> void:
	# Stable per grave: never reshuffle arrangements when the cemetery reloads.
	var rng := RandomNumberGenerator.new()
	rng.seed = identity + 7319
	var style := posmod(identity, 4)
	var placements := [Vector2(-.55,.95), Vector2(.55,.95), Vector2(-.53,-.55), Vector2(.53,.20), Vector2(0,.80)]
	var place: Vector2 = placements[posmod(identity / 4, placements.size())]
	planting.position = Vector3(place.x-.55, 0, place.y-.95)
	var colors := [Color("d1c8ad"), Color("b98898"), Color("c4a25e"), Color("617957")]
	var petal_material := blooms[0].material_override as StandardMaterial3D
	petal_material.albedo_color = colors[style]
	petal_material.roughness = .9
	for i in blooms.size():
		var angle := i * TAU / blooms.size() + rng.randf_range(-.25,.25)
		var spread := .12 if style == 2 else .17
		var point := Vector3(.55+sin(angle)*spread, 0, .95+cos(angle)*spread)
		var height := rng.randf_range(.22,.39) if style != 3 else rng.randf_range(.12,.24)
		stems[i].position = Vector3(point.x,.99+height*.5,point.z)
		stems[i].scale.y = height/.3
		blooms[i].position = Vector3(point.x,.99+height,point.z)
		blooms[i].scale = Vector3(.75,1.8,.75) if style == 2 else (Vector3(.8,.55,1.9) if style == 3 else Vector3.ONE*rng.randf_range(.85,1.15))
		blooms[i].rotation.y = angle
		blooms[i].rotation.z = .3*sin(angle) if style == 3 else 0.0

func box(size: Vector3, point: Vector3, material: Material) -> void:
	var piece := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	piece.mesh = mesh
	piece.material_override = material
	piece.position = point
	add_child(piece)

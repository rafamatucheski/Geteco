extends Node3D
## Static city geometry is grouped by material, with explicit physical footprints.
const COUPE := preload("res://assets/Coupe.scn")
var materials: Dictionary = {}
var batches: Dictionary = {}
var solids: Array[StaticBody3D] = []
var car_template: Node3D

func _ready() -> void:
	_build()
	_flush_batches()

func material(color: String, metallic := 0.0) -> StandardMaterial3D:
	if not materials.has(color):
		var result := StandardMaterial3D.new()
		result.albedo_color = Color(color)
		result.roughness = 0.78 if metallic == 0 else 0.35
		result.metallic = metallic
		materials[color] = result
	return materials[color]

func box(point: Vector3, dimensions: Vector3, color: String, solid := false, label := "") -> void:
	var key := "box_" + color
	if not batches.has(key):
		var mesh := BoxMesh.new()
		batches[key] = {"mesh": mesh, "material": material(color), "transforms": []}
	batches[key].transforms.append(Transform3D(Basis.from_scale(dimensions), point))
	if solid: collider(point, dimensions, label)

func collider(point: Vector3, dimensions: Vector3, label: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label if not label.is_empty() else "Solid"
	body.position = point
	body.collision_layer = 1
	body.collision_mask = 2
	body.set_meta("footprint", dimensions)
	var shape := CollisionShape3D.new()
	var bounds := BoxShape3D.new()
	bounds.size = dimensions
	shape.shape = bounds
	body.add_child(shape)
	add_child(body)
	solids.append(body)
	return body

func _flush_batches() -> void:
	for key in batches:
		var batch: Dictionary = batches[key]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = batch.mesh
		multi.instance_count = batch.transforms.size()
		for i in multi.instance_count: multi.set_instance_transform(i, batch.transforms[i])
		var instance := MultiMeshInstance3D.new()
		instance.name = key
		instance.multimesh = multi
		instance.material_override = batch.material
		add_child(instance)
	batches.clear()

func _build() -> void:
	box(Vector3(0,-0.25,0), Vector3(94,0.5,94), "536f59", true, "Ground")
	box(Vector3(0,0.005,0), Vector3(12,0.01,88), "343e44")
	box(Vector3(0,0.007,0), Vector3(88,0.01,12), "343e44")
	for side in [-1,1]:
		box(Vector3(side*37,0.008,0), Vector3(8,0.01,88), "343e44")
		box(Vector3(0,0.008,side*37), Vector3(88,0.01,8), "343e44")
		box(Vector3(side*45,0.45,0), Vector3(0.4,0.9,90), "8a9688", true, "Boundary")
		box(Vector3(0,0.45,side*45), Vector3(90,0.9,0.4), "8a9688", true, "Boundary")
	for xsign in [-1,1]:
		for zsign in [-1,1]:
			var center := Vector3(xsign*19.5,0,zsign*19.5)
			box(center+Vector3(0,0.012,0), Vector3(27,0.02,27), "c1bcaa")
			for seam in range(7,33,2):
				box(Vector3(xsign*seam,0.025,zsign*19.5), Vector3(0.025,0.008,27), "ada998")
				box(Vector3(xsign*19.5,0.025,zsign*seam), Vector3(27,0.008,0.025), "ada998")
			var height := 5.4 if zsign > 0 else 7.2
			if xsign > 0 or zsign > 0 or "--sandbox" in OS.get_cmdline_user_args():
				_building(Vector3(xsign*21,0,zsign*21), height, "b98362" if xsign < 0 else "749b94", "" if xsign < 0 and zsign < 0 else ("Aurora" if zsign < 0 else ("Union" if xsign < 0 else "Oliva")))
			for along in [15,24,28]:
				_tree(Vector3(xsign*10.7,0,zsign*along), along)
			_bench(Vector3(xsign*10.2,0,zsign*20))
			_lamp(Vector3(xsign*6.5,0,zsign*10))
			_lamp(Vector3(xsign*6.5,0,zsign*30))
	for along in range(-42,44,4):
		if abs(along) < 8: continue
		for stripe in [-0.15,0.15]:
			box(Vector3(stripe,0.022,along),Vector3(0.08,0.012,2.1),"d7bc73")
			box(Vector3(along,0.022,stripe),Vector3(2.1,0.012,0.08),"d7bc73")
	for side in [-1,1]:
		for stripe in range(-4,5):
			box(Vector3(stripe,0.026,side*5.0),Vector3(0.55,0.01,1.7),"ece6ce")
			box(Vector3(side*5.0,0.026,stripe),Vector3(1.7,0.01,0.55),"ece6ce")
	_build_car_template()
	for side in [-1,1]:
		for along in [-25,-16,16,25]:
			var car := car_template.duplicate() as Node3D
			car.name = "Coupe"
			car.position = Vector3(side*4.25,0.03,along)
			car.rotation.y = PI if side < 0 else 0.0
			add_child(car)
			collider(car.position+Vector3(0,0.7,0),Vector3(2.0,1.4,4.5),"ParkedCar")
	car_template.free()
	car_template = null
	# A small solid prop provides a repeatable depth/collision reference.
	box(Vector3(-10,0.65,2),Vector3(1.3,1.3,1.3),"9c764e",true,"Crate")
	for y in [0.16,1.10]: box(Vector3(-10,y,2),Vector3(1.34,0.12,1.34),"6b5138")

func _building(center: Vector3, height: float, color: String, title: String) -> void:
	box(center+Vector3(0,height/2,0),Vector3(17,height,17),color,true,"Building_"+title)
	box(center+Vector3(0,0.3,0),Vector3(17.3,0.6,17.3),"8b8d81",true,"Plinth_"+title)
	box(center+Vector3(0,height+0.12,0),Vector3(17.5,0.24,17.5),"ddd3b9")
	box(center+Vector3(0,height+0.25,0),Vector3(16.5,0.16,16.5),"485951")
	for side in [-1,1]:
		for along in [-6,-3,0,3,6]:
			for level in [1.6,3.8]:
				box(center+Vector3(along,level,side*8.52),Vector3(1.9,1.65,0.08),"344e58")
				box(center+Vector3(side*8.52,level,along),Vector3(0.08,1.65,1.9),"344e58")
				box(center+Vector3(along,level-0.87,side*8.63),Vector3(2.12,0.14,0.27),"e5d6b7")
				box(center+Vector3(side*8.63,level-0.87,along),Vector3(0.27,0.14,2.12),"e5d6b7")
	var front := -signf(center.z)
	box(center+Vector3(0,1.3,front*8.59),Vector3(2.0,2.6,0.12),"263b40")
	box(center+Vector3(0,3.2,front*8.9),Vector3(7,0.26,1.6),"ebe0c0")
	var sign_node := Label3D.new()
	sign_node.text = title
	sign_node.font_size = 100
	sign_node.pixel_size = 0.007
	sign_node.modulate = Color("f4e5c8")
	sign_node.outline_size = 0
	sign_node.position = center+Vector3(0,4.5,front*8.60)
	if front < 0: sign_node.rotation.y = PI
	add_child(sign_node)
	box(center+Vector3(4,height+0.7,3),Vector3(2.3,1.1,1.8),"9ca9a2")

func _tree(point: Vector3, variant: int) -> void:
	box(point+Vector3(0,0.22,0),Vector3(1.4,0.44,1.4),"a9a18c",true,"TreePlanter")
	box(point+Vector3(0,1.65,0),Vector3(0.26,3.0,0.26),"70533c")
	var key := "crown"
	if not batches.has(key):
		var sphere := SphereMesh.new()
		sphere.radial_segments = 12
		sphere.rings = 6
		batches[key] = {"mesh": sphere, "material": material("53764e"), "transforms": []}
	for i in 3:
		var offset := Vector3(sin(i*2.1+variant)*0.7,3.1+i*0.3,cos(i*2.1)*0.6)
		batches[key].transforms.append(Transform3D(Basis.from_scale(Vector3(2.8,1.6,2.7)),point+offset))

func _bench(point: Vector3) -> void:
	collider(point+Vector3(0,0.5,0),Vector3(0.85,1.0,2.4),"Bench")
	for i in 4:
		box(point+Vector3(-0.30+i*0.2,0.48,0),Vector3(0.16,0.11,2.3),"856044")
		box(point+Vector3(0.38,0.6+i*0.15,0),Vector3(0.11,0.11,2.3),"856044")
	for side in [-1,1]: box(point+Vector3(0,0.24,side*0.85),Vector3(0.65,0.48,0.10),"36454a")

func _lamp(point: Vector3) -> void:
	box(point+Vector3(0,2.6,0),Vector3(0.14,5.2,0.14),"36454a",true,"Lamp")
	box(point+Vector3(0.4,5.2,0),Vector3(0.9,0.12,0.13),"36454a")
	box(point+Vector3(0.8,5.12,0),Vector3(0.65,0.16,0.35),"dfd6b6")

func _build_car_template() -> void:
	# Self-contained, script-free snapshot of the current game's prepared coupe.
	# Eight instances share the original 38 meshes and materials.
	car_template = COUPE.instantiate()
	var palette := {
		"paint": ["b83632",0.25,0.24], "rubber": ["171b20",0.0,0.9],
		"trim": ["30373d",0.15,0.45], "glass": ["243a47",0.35,0.17],
		"alloy": ["b5bdc3",0.72,0.24], "headlight": ["e6f0ed",0.15,0.16],
		"brake": ["cd6133",0.2,0.4], "rotor": ["515963",0.55,0.55],
		"smoked_lens": ["293b44",0.35,0.16], "tail": ["eb3832",0.1,0.25]
	}
	var car_materials: Dictionary = {}
	for key in palette:
		var entry: Array = palette[key]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(entry[0])
		mat.metallic = entry[1]
		mat.roughness = entry[2]
		if key == "glass": mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		if key in ["headlight","tail"]:
			mat.emission_enabled = true
			mat.emission = mat.albedo_color
			mat.emission_energy_multiplier = 0.3 if key == "headlight" else 0.65
		car_materials[key] = mat
	for part in car_template.get_children():
		var key := str(part.get_meta("coupe_damage_material_key",""))
		assert(car_materials.has(key),"Original coupe material missing: "+key)
		part.material_override = car_materials[key]

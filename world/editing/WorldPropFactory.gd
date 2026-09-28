@tool
extends RefCounted
## Small shared meshes, static collision, no processing or lights.
const SIZES := {"pallet":Vector2(1.2,1),"pallet_stack":Vector2(1.2,1),"crate":Vector2(1,1),"barrel":Vector2(.65,.65),"dumpster":Vector2(1.8,1),"trash_bags":Vector2(1.1,.85),"bin":Vector2(.6,.6),"barrier":Vector2(2,.5),"footbridge":Vector2(2.6,34.6)}
static var materials: Dictionary = {}
static func material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = .88
		materials[key] = mat
	return materials[key]
static func box(parent: Node3D,at: Vector3,size: Vector3,color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material(color)
	node.position = at
	parent.add_child(node)
	return node
static func solid(parent: Node3D,at: Vector3,size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	collider.position = at
	body.add_child(collider)
	parent.add_child(body)
static func pallet(parent: Node3D,y: float) -> void:
	for x in [-.45,0,.45]: box(parent,Vector3(x,y+.09,0),Vector3(.14,.16,1),Color("705237"))
	for z in [-.4,-.2,0,.2,.4]: box(parent,Vector3(0,y+.20,z),Vector3(1.2,.07,.15),Color("b99768"))
	for z in [-.4,0,.4]: box(parent,Vector3(0,y+.025,z),Vector3(1.2,.05,.15),Color("937149"))
static func create(row: Dictionary) -> Node3D:
	if str(row.model) == "footbridge":
		# Passarela tem medidas próprias (largura x comprimento total) e colisão
		# andável; a caixa sólida genérica dos objetos a bloquearia inteira.
		var bridge := preload("res://world/urban_detail/UrbanFootbridge3D.gd").new()
		bridge.name = "WorldProp_footbridge"
		bridge.set_meta("editor_id",row.id)
		bridge.width = float(row.size[0])
		bridge.length = float(row.size[1])
		bridge.accent = Color(str(row.get("color","3f6e8c")))
		bridge.build()
		bridge.rotation.y = deg_to_rad(float(row.get("rotation",0)))
		return bridge
	var root := Node3D.new()
	root.name = "WorldProp_"+str(row.model)
	root.set_meta("editor_id",row.id)
	var color := Color(str(row.get("color","a98857")))
	var height := .25
	var footprint: Vector2 = SIZES.get(row.model,Vector2.ONE)
	match str(row.model):
		"pallet", "pallet_stack":
			var count := 4 if row.model == "pallet_stack" else 1
			for i in count: pallet(root,i*.25)
			height = count*.25
		"crate":
			height = 1
			box(root,Vector3(0,.5,0),Vector3(.96,.96,.96),color)
			for x in [-.45,.45]:
				for z in [-.505,.505]: box(root,Vector3(x,.5,z),Vector3(.10,1,.06),color.lightened(.18))
			for y in [.12,.88]: box(root,Vector3(0,y,.54),Vector3(1,.10,.08),color.darkened(.16))
		"barrel":
			height = .92
			for part in [[.45,.88,.31],[.12,.06,.33],[.78,.06,.33]]:
				var mesh := CylinderMesh.new()
				mesh.top_radius = part[2]
				mesh.bottom_radius = part[2]
				mesh.height = part[1]
				mesh.radial_segments = 12
				var node := MeshInstance3D.new()
				node.mesh = mesh
				node.position.y = part[0]
				node.material_override = material(color if part[1] > .1 else Color("464c48"))
				root.add_child(node)
		"dumpster":
			height = 1.2
			box(root,Vector3(0,.63,0),Vector3(1.8,1.03,1),color)
			box(root,Vector3(0,1.19,0),Vector3(1.88,.10,1.08),Color("313d36"))
			for x in [-.82,.82]:
				box(root,Vector3(x,.18,0),Vector3(.17,.3,.85),Color("232927"))
				box(root,Vector3(x,.85,.55),Vector3(.3,.09,.12),Color("89948b"))
		"trash_bags":
			height = .8
			for i in 3:
				var node := MeshInstance3D.new()
				var mesh := SphereMesh.new()
				mesh.radius = .29
				mesh.height = .65
				mesh.radial_segments = 10
				mesh.rings = 5
				node.mesh = mesh
				node.material_override = material(Color("303b36").lightened(i*.035))
				node.position = Vector3((i-1)*.29,.32,-.12 if i == 1 else .12)
				node.rotation.z = (i-1)*.18
				root.add_child(node)
				box(root,node.position+Vector3(0,.34,0),Vector3(.10,.12,.10),Color("424b44"))
		"bin":
			height = .96
			box(root,Vector3(0,.47,0),Vector3(.56,.88,.56),color)
			box(root,Vector3(0,.94,0),Vector3(.63,.06,.63),Color("364d3c"))
			box(root,Vector3(0,.76,.32),Vector3(.32,.08,.10),Color("839185"))
		"barrier":
			height = .92
			box(root,Vector3(0,.14,0),Vector3(2,.28,.50),color)
			box(root,Vector3(0,.58,0),Vector3(2,.66,.30),color.lightened(.07))
			for x in [-.65,0,.65]: box(root,Vector3(x,.66,.158),Vector3(.25,.16,.018),Color("d0ad52"))
	solid(root,Vector3(0,height*.5,0),Vector3(footprint.x,height,footprint.y))
	root.scale = Vector3.ONE*float(row.get("scale",1))
	root.rotation.y = deg_to_rad(float(row.get("rotation",0)))
	return root

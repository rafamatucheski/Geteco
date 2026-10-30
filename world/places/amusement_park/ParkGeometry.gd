extends Node3D
## Static material batches; tagged solids retain complete authored volumes.
const EXTERIOR_FINISH := preload("res://world/mountain_detail/MountainInteriorFinish.gd")
const EXTERIOR_RECIPES := {
	"wood":["745e49","423e4a","6d5b4e","e1cfa4","ae8856","957250","38625f","8f734e","873e4a","d1ab59","63769a"],
	"stone":["8b8270","71665f","5a5049","706457","b59368"],
	"metal":["385b59","d1ab59","b96748","d9ba75","3e6d67","45615d","38625f","292f38","9ca8ae","b9965a","272d35"],
	"exterior_paint":["38625f","d0a655","773746","d9ba75","928171","4c4552","5c5260","873e4a","d1ab59","63769a","e1cfa4"],
}
const EXTERIOR_PAINT_PARTS := ["GatePillar","GateCap","GateHeader","StationCanopy","CanopyStripe","DoorJamb","Tower","RoofRidge","BoothStripe","BoothRoof","WardrobeRoof","LumeStallRoof","AwningStripe"]
## Opt-in só do Parque Lume exterior: a mesma base monta o interior da Umbra.
var painted_exterior := false

static func exterior_enabled() -> bool:
	return OS.get_environment("GETECO_PAINTED_PARK_EXTERIOR") != "0"

static func prewarm_materials() -> Array[Material]:
	var result: Array[Material] = []
	if exterior_enabled():
		for kind in EXTERIOR_RECIPES:
			for color_key in EXTERIOR_RECIPES[kind]: result.append(_exterior_material(str(kind),str(color_key)))
	return result

static func _exterior_material(kind: String, color_key: String) -> StandardMaterial3D:
	var finish: String = {"wood":"wood","stone":"cast","metal":"painted","exterior_paint":"painted"}[kind]
	return EXTERIOR_FINISH.material(finish,Color(color_key),.48 if kind=="metal" else .84,.55 if kind=="metal" else 0.0)

const SURFACES := preload("res://world/places/ShopInteriorMaterials.gd")
## Superfícies grandes da Umbra (21/10/2026): texturas de 1024 px emendáveis no lugar dos ladrilhos
## procedurais de 64 px. Mesmas opções de material do ShopInteriorMaterials (textura + triplanar local),
## então o shader é o mesmo já compilado; só a imagem muda. [textura, metros por repetição].
const UMBRA_SURFACES := {
	"wallpaper": [preload("res://assets/textures/umbra/umbra_wallpaper.jpg"), 1.6],
	"floorboards": [preload("res://assets/textures/umbra/umbra_floor.jpg"), 2.4],
	"crypt": [preload("res://assets/textures/umbra/umbra_stone.jpg"), 2.2],
	"velvet": [preload("res://assets/textures/umbra/umbra_velvet.jpg"), 1.2],
}
## GETECO_UMBRA_CLASSIC=1 volta aos ladrilhos procedurais (A/B e salvaguarda; ver UmbraCreature).
const UMBRA_CLASSIC_KIND := {"wallpaper":"wood","floorboards":"wood","crypt":"stone","velvet":"cloth"}
var solid_inventory: Array[Dictionary] = []
var direct_collisions := false
var _materials: Dictionary = {}
var _batches: Dictionary = {}
var _body: StaticBody3D

func material(color: String, kind := "paint") -> StandardMaterial3D:
	if painted_exterior and exterior_enabled() and color in EXTERIOR_RECIPES.get(kind,[]): return _exterior_material(kind,color)
	var key := color + kind
	if _materials.has(key): return _materials[key]
	var result: StandardMaterial3D
	if UMBRA_SURFACES.has(kind) and OS.get_environment("GETECO_UMBRA_CLASSIC") == "1":
		result = SURFACES.material(UMBRA_CLASSIC_KIND[kind],Color(color))
	elif UMBRA_SURFACES.has(kind): result = _umbra_surface(kind,Color(color))
	elif kind in ["wood","stone","cloth"]: result = SURFACES.material(kind,Color(color))
	else:
		result = StandardMaterial3D.new()
		result.albedo_color = Color(color)
		result.roughness = .78
		if kind == "metal":
			result.metallic = .55
			result.roughness = .48
		elif kind == "glow":
			result.emission_enabled = true
			result.emission = Color(color)
			result.emission_energy_multiplier = .65
	_materials[key] = result
	return result

## A cor do autor só escurece/clareia a imagem: a textura já traz o tom.
func _umbra_surface(kind: String, tint: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	var value := clampf(tint.get_luminance()*2.6, .55, 1.0)
	result.albedo_color = Color(value, value, value)
	result.albedo_texture = UMBRA_SURFACES[kind][0]
	result.roughness = .95 if kind == "velvet" else .84
	result.uv1_triplanar = true
	result.uv1_scale = Vector3.ONE/float(UMBRA_SURFACES[kind][1])
	return result

func box(label: String, at: Vector3, size: Vector3, color: String, solid := false, kind := "paint", box_basis := Basis.IDENTITY) -> void:
	if painted_exterior and exterior_enabled() and kind=="paint" and label in EXTERIOR_PAINT_PARTS: kind="exterior_paint"
	var mesh := BoxMesh.new()
	mesh.size = size
	var box_transform := Transform3D(box_basis,at)
	if solid and not direct_collisions:
		var node := MeshInstance3D.new()
		node.name = label
		node.mesh = mesh
		node.transform = box_transform
		node.material_override = material(color,kind)
		node.set_meta("interior_solid_id",label)
		add_child(node)
	else: append_mesh(mesh,box_transform,color,kind)
	if solid:
		solid_inventory.append({"id":label,"bounds":box_transform*AABB(-size*.5,size)})
		if direct_collisions: collision_box(label,at,size,box_basis)

func cylinder(at: Vector3, radius: float, height: float, color: String, kind := "paint", cylinder_basis := Basis.IDENTITY) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	append_mesh(mesh,Transform3D(cylinder_basis,at),color,kind)

func ball(at: Vector3, size: Vector3, color: String, kind := "paint") -> void:
	var mesh := SphereMesh.new()
	mesh.radius = .5
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 6
	append_mesh(mesh,Transform3D(Basis.IDENTITY.scaled(size),at),color,kind)

func beam(a: Vector3, b: Vector3, width: float, height: float, color: String, kind := "paint") -> void:
	var direction := (b-a).normalized()
	var right := Vector3.UP.cross(direction).normalized()
	if right.length_squared() < .01: right = Vector3.RIGHT
	box("Beam",(a+b)*.5,Vector3(width,height,a.distance_to(b)),color,false,kind,Basis(right,direction.cross(right).normalized(),direction))

func append_mesh(mesh: Mesh, mesh_transform: Transform3D, color: String, kind := "paint") -> void:
	var st := batch(color,kind)
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var count := indices.size() if not indices.is_empty() else vertices.size()
	var normal_basis := mesh_transform.basis.inverse().transposed()
	for i in count:
		var index := indices[i] if not indices.is_empty() else i
		st.set_normal((normal_basis*normals[index]).normalized())
		st.set_uv(uvs[index] if index<uvs.size() else Vector2.ZERO)
		st.add_vertex(mesh_transform*vertices[index])

func batch(color: String, kind: String) -> SurfaceTool:
	var key := color+":"+kind
	if not _batches.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = st
	return _batches[key]

func collision_box(label: String, at: Vector3, size: Vector3, box_basis := Basis.IDENTITY) -> void:
	if not is_instance_valid(_body):
		_body = StaticBody3D.new()
		_body.name = "ParkSolids"
		_body.collision_layer = 1
		_body.collision_mask = 0
		add_child(_body)
	var node := CollisionShape3D.new()
	node.name = label
	var shape := BoxShape3D.new()
	shape.size = size
	node.shape = shape
	node.transform = Transform3D(box_basis,at)
	node.set_meta("interior_solid_id",label)
	_body.add_child(node)

func flush() -> void:
	for key in _batches:
		var node := MeshInstance3D.new()
		node.name = "ParkBatch_"+str(key).replace(":","_")
		node.mesh = _batches[key].commit()
		var parts := str(key).split(":")
		node.material_override = material(parts[0],parts[1])
		add_child(node)
	_batches.clear()

func sign_text(text: String, at: Vector3, size := 90, yaw := 0.0) -> void:
	var label := Label3D.new()
	label.name = "Name_"+text
	label.text = text
	label.position = at
	label.rotation.y = yaw
	label.font_size = size
	label.pixel_size = .012
	label.outline_size = 6
	label.modulate = Color("f7e9c2")
	add_child(label)

func lantern(at: Vector3, color: String, range_value: float, energy := 1.25) -> void:
	box("LanternFrame",at,Vector3(.31,.46,.31),"34313b",false,"metal")
	box("LanternGlass",at+Vector3(0,0,.017),Vector3(.23,.31,.33),color,false,"glow")
	var light := OmniLight3D.new()
	light.name = "LanternLight"
	light.position = at
	light.light_color = Color(color)
	light.light_energy = energy
	light.omni_range = range_value
	light.omni_attenuation = 1.55
	light.shadow_enabled = true
	light.light_size = .16
	add_child(light)

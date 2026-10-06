extends RefCounted
## Static, life-sized paper, cord and seal on existing surfaces. No extra light,
## actor, viewport or per-frame animation; streaming follows the existing host.
const POINTS := {
	"cargo_identified":Vector3(-.605,.84,2.65),
	"cargo_manifest":Vector3(.62,.238,-5.25),
	"cave_shelter":Vector3(-3.1,.13,2.05),
	"vicente_note":Vector3(-1.4,.035,-2.6)
}

static func attach(host: Node3D, cave: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "MountainStoryEvidence"
	host.add_child(root)
	var paper := _material("c8b992")
	var ink := _material("3d4140")
	var red := _material("872e2b")
	if cave:
		# Existing map board remains a shallow, walkable prop. The separate note
		# lies in free floor space, clear of cot, lantern, weapons and expedition.
		var map_note := _document(root,POINTS.cave_shelter,paper,ink)
		map_note.rotation.y = -.25
		_cord(root,POINTS.cave_shelter+Vector3(.17,.015,.08),_material("876c42"))
		_document(root,POINTS.vicente_note,paper,ink)
		_cord(root,POINTS.vicente_note+Vector3(.18,.018,0),_material("876c42"))
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = .031
		torus.outer_radius = .052
		torus.rings = 12
		torus.ring_segments = 5
		ring.mesh = torus
		ring.material_override = _material("929b9d",.55)
		ring.position = POINTS.vicente_note+Vector3(.19,.023,.07)
		root.add_child(ring)
	else:
		# Label is flush with the already-solid crate, facing the clear aisle.
		_box(root,POINTS.cargo_identified,Vector3(.012,.43,.36),red)
		_snake(root,POINTS.cargo_identified+Vector3(.009,0,0),_material("c4ae75"))
		_document(root,POINTS.cargo_manifest,paper,ink)
		_box(root,POINTS.cargo_manifest+Vector3(.10,.013,-.1),Vector3(.085,.009,.06),red)
	return root

static func _material(html: String, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(html)
	material.roughness = .84
	material.metallic = metallic
	return material

static func _box(parent: Node3D, point: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = point
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

static func _document(parent: Node3D, point: Vector3, paper: Material, ink: Material) -> Node3D:
	var node := Node3D.new()
	node.position = point
	parent.add_child(node)
	_box(node,Vector3.ZERO,Vector3(.3,.012,.38),paper)
	# Sparse strokes make an actual sheet legible without decorative prose.
	for index in 4:
		_box(node,Vector3(-.01,.007,-.105+index*.055),Vector3(.20-float(index%2)*.04,.003,.009),ink)
	return node

static func _cord(parent: Node3D, point: Vector3, material: Material) -> void:
	for index in 3:
		var segment := _box(parent,point+Vector3(.012*index,0,.045*index),Vector3(.012,.009,.063),material)
		segment.rotation.y = -.35 if index%2 == 0 else .3

static func _snake(parent: Node3D, point: Vector3, material: StandardMaterial3D) -> void:
	# One mesh for the gang's bent snake silhouette on the crate seal.
	var path := PackedVector2Array([Vector2(-.07,-.13),Vector2(.045,-.09),Vector2(.06,-.03),Vector2(-.055,.025),Vector2(-.06,.09),Vector2(.035,.14)])
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in path.size()-1:
		var a := path[index]
		var b := path[index+1]
		var normal := Vector2(-(b-a).y,(b-a).x).normalized()*.02
		for p in [a-normal,b-normal,b+normal,a-normal,b+normal,a+normal]:
			surface.add_vertex(Vector3(0,p.y,p.x))
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = surface.commit()
	mesh.material_override = material
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.position = point
	parent.add_child(mesh)

extends RefCounted
## Chunk-owned geometry, no timers, lights or per-frame processing.
const COLLISION_FACES := preload("res://world/chunk_bake/CollisionFaces.gd")
const COURSE := preload("res://world/mountain_jeep/MountainJeepCourse.gd")
static var _soil: ShaderMaterial
static var _paint: Dictionary = {}

static func build(parent: Node3D, record: Dictionary) -> void:
	if record.variant == "crest":
		_build_crest(parent,float(record.from),float(record.to))
		return
	var root := Node3D.new()
	root.name = "JeepStart" if record.variant == "start" else "JeepCheckpoint"
	root.position=record.position
	root.rotation.y=atan2(-record.forward.x,-record.forward.z)
	root.set_meta("mountain_jeep_gate",true)
	parent.add_child(root)
	var body := StaticBody3D.new()
	body.collision_layer=1
	body.collision_mask=0
	root.add_child(body)
	var arch: bool=record.variant=="start" or bool(record.get("finish",false))
	for side in [-1.0,1.0]:
		var x: float=side*(COURSE.WIDTH*.5+.40)
		var foot: float=-root.position.y*smoothstep(COURSE.WIDTH*.5,COURSE.WIDTH*.5+COURSE.SHOULDER,absf(x))
		_box(body,Vector3(x,.80+foot,0),Vector3(.16,1.6,.16),Color("52483b"),true)
		_box(body,Vector3(x,1.27+foot,0),Vector3(.40,.42,.10),Color("eac364"),false)
		_box(body,Vector3(x,.21+foot,0),Vector3(.34,.42,.34),Color("615c52"),true)
		if arch: _box(body,Vector3(x,2.28+foot,0),Vector3(.16,1.4,.16),Color("52483b"),true)
	if arch:
		_box(body,Vector3(0,3.0,0),Vector3(COURSE.WIDTH+1.0,.28,.18),Color("dadbd0"),true)
		for i in 12:
			_box(body,Vector3(-3.1+float(i)*.54,3.0,-.10),Vector3(.27,.25,.035),Color("252b2c"),false)

static func _box(parent: Node3D, point: Vector3, size: Vector3, color: Color, solid: bool) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size=size
	mesh.mesh=box
	mesh.position=point
	if not _paint.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color=color
		material.roughness=.95
		_paint[color]=material
	mesh.material_override=_paint[color]
	parent.add_child(mesh)
	if solid:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size=size
		collision.shape=shape
		collision.position=point
		parent.add_child(collision)

static func _crest_vertex(distance: float, lateral: float) -> Vector3:
	var sample := COURSE.sample(distance)
	var forward: Vector3=sample.forward
	var side := Vector3(forward.z,0,-forward.x)
	var amount := 1.0-smoothstep(COURSE.WIDTH*.5,COURSE.WIDTH*.5+COURSE.SHOULDER,absf(lateral))
	var point: Vector3=sample.position+side*lateral
	# Edges meet the terrain at exactly zero. Only the raised area has a new top.
	point.y=COURSE.rise(distance)*amount
	return point

static func _build_crest(parent: Node3D, first: float, last: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var widths := [-COURSE.WIDTH*.5-COURSE.SHOULDER,-COURSE.WIDTH*.5,0.0,COURSE.WIDTH*.5,COURSE.WIDTH*.5+COURSE.SHOULDER]
	var count := ceili(last-first)
	for i in count:
		var a := lerpf(first,last,float(i)/float(count))
		var b := lerpf(first,last,float(i+1)/float(count))
		for j in range(widths.size()-1):
			var vertices := [_crest_vertex(a,widths[j]),_crest_vertex(b,widths[j]),_crest_vertex(a,widths[j+1]),_crest_vertex(b,widths[j+1])]
			var uv := [Vector2(widths[j],a),Vector2(widths[j],b),Vector2(widths[j+1],a),Vector2(widths[j+1],b)]
			for triangle in [[0,1,2],[2,1,3]]:
				# Godot's front faces are clockwise, as in MountainTerrain3D.
				if (vertices[triangle[1]]-vertices[triangle[0]]).cross(vertices[triangle[2]]-vertices[triangle[0]]).y>0: triangle.reverse()
				for index in triangle:
					surface.set_uv(uv[index])
					surface.add_vertex(vertices[index])
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name="JeepTrailCrest"
	# Malha e colisão das mesmas arrays da CPU: create_trimesh_shape lia a malha de volta da GPU (auditoria 19/10).
	var built: Array=COLLISION_FACES.commit_with_shape(surface)
	mesh.mesh=built[0]
	if _soil==null:
		_soil=ShaderMaterial.new()
		_soil.shader=preload("res://world/mountain_jeep/jeep_trail.gdshader")
	mesh.material_override=_soil
	parent.add_child(mesh)
	# These exact triangles provide the wheels' support and match the rendered crest.
	var body := StaticBody3D.new()
	body.collision_layer=1
	body.collision_mask=0
	body.set_meta("vehicle_ramp_structure",true)
	body.set_meta("mountain_jeep_crest",true)
	var collision := CollisionShape3D.new()
	collision.shape=built[1]
	body.add_child(collision)
	parent.add_child(body)

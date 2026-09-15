extends Node2D
## One opaque mesh under the body, retained until the bank resets/unloads.
var guard: Node2D
var visual: MeshInstance3D
var outline := PackedVector2Array()
var room: Node2D
var elapsed := 0.0
var floor_outline := PackedVector2Array()

func _ready() -> void:
	name="BankGuardBloodPool"
	room=get_parent()
	add_to_group("bank_guard_blood")
	preload("res://guns/combat/BloodTransferSystem.gd").ensure.call_deferred(self)
	visual=MeshInstance3D.new()
	visual.name="BloodOnBankFloor"
	var vertices:=PackedVector3Array()
	var colors:=PackedColorArray()
	var normals:=PackedVector3Array()
	var rng:=RandomNumberGenerator.new()
	rng.seed=guard.get_instance_id()
	var phase:=rng.randf_range(0,TAU)
	for i in 32:
		var angle:=TAU*i/32.0
		var radius:=.76+.09*sin(angle*5+phase)+rng.randf_range(-.035,.035)
		floor_outline.append(Vector2(cos(angle)*radius,sin(angle)*radius*.72))
	_append_polygon(floor_outline,0.0,Color("59191e"),vertices,normals,colors)
	var inner:=PackedVector2Array()
	for point in floor_outline: inner.append(point*.77+Vector2(.025,-.035))
	_append_polygon(inner,.002,Color("84232b"),vertices,normals,colors)
	for i in 7:
		var angle:=rng.randf_range(0,TAU)
		var center:=Vector2(cos(angle),sin(angle)*.72)*rng.randf_range(.82,1.05)
		var droplet:=PackedVector2Array()
		var radius:=rng.randf_range(.018,.055)
		for j in 8: droplet.append(center+Vector2.from_angle(TAU*j/8.0)*radius)
		_append_polygon(droplet,.001,Color("6b1d23"),vertices,normals,colors)
	var arrays:=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_COLOR]=colors
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	visual.mesh=mesh
	var material:=StandardMaterial3D.new()
	material.vertex_color_use_as_albedo=true
	material.roughness=.72
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	visual.material_override=material
	visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	room.view.add_child(visual)
	_process(0)

func _append_polygon(polygon: PackedVector2Array, height: float, color: Color, vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray) -> void:
	for index in Geometry2D.triangulate_polygon(polygon):
		var point:=polygon[index]
		vertices.append(Vector3(point.x,height,point.y))
		normals.append(Vector3.UP)
		# Vertex colors are linear; authoring sRGB values directly turns dark
		# blood pink under the room's lighting.
		colors.append(color.srgb_to_linear())

func _process(delta: float) -> void:
	elapsed+=delta
	if not is_instance_valid(guard):
		set_process(false)
		return
	var torso:=guard.get("torso_node") as Node3D
	var center:Vector3
	if is_instance_valid(torso): center=torso.global_position
	else: center=guard.model.to_global(Vector3(0,.85,0))
	visual.position=Vector3(center.x,.024,center.z)
	visual.scale=Vector3.ONE*lerpf(.2,1.0,smoothstep(0,1.7,elapsed))
	global_position=room.to_global(room.project_floor(Vector2(center.x,center.z)))
	outline.clear()
	for point in floor_outline:
		var projected:Vector2=room.to_global(room.project_floor(Vector2(center.x,center.z)+point*visual.scale.x))
		outline.append(to_local(projected))
	if elapsed>=1.7 and not guard.fall_presentation.active: set_process(false)

func _exit_tree() -> void:
	if is_instance_valid(visual): visual.queue_free()

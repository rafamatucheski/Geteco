extends SceneTree
## Carro da frota (modelo atual de caixas) ao lado do carro do Meshy, mesmo palco, câmeras de 3/4, frente, lado e topo.
## Uso: "$GODOT" --path . --script res://tools/capture_car_compare.gd -- --glb=res://assets/fleet/meshy/metro_hatch_body.glb --out=res://evidence/npc-meshy/car
var glb := ""
var output_dir := "res://evidence/npc-meshy/car"
var camera: Camera3D
var yaw_extra := 0.0
var prebuilt := false
var spinners: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--glb="): glb = arg.substr(6)
		elif arg.begins_with("--out="): output_dir = arg.substr(6)
		elif arg.begins_with("--yaw="): yaw_extra = float(arg.substr(6))
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	root.size = Vector2i(1600, 700)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("8fa3ad")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("b9c4cc")
	env.environment.ambient_light_energy = 0.9
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	stage.add_child(ground)
	var old_car := (load("res://assets/fleet/metro_hatch.scn") as PackedScene).instantiate() as Node3D
	old_car.position = Vector3(-2.6, 0, 0)
	stage.add_child(old_car)
	var report := "carro atual: %d malhas, %d triângulos\n" % [_count_meshes(old_car), _count_triangles(old_car)]
	if glb != "":
		var holder := Node3D.new()
		stage.add_child(holder)
		var new_car := (load(glb) as PackedScene).instantiate() as Node3D
		holder.add_child(new_car)
		if glb.ends_with(".scn"):
			# Cena já pronta (frente em -Z, em metros, rodas separadas): só posiciona ao lado do carro atual.
			holder.position = Vector3(2.6, 0, 0)
			spinners = new_car.find_children("Wheel_*", "MeshInstance3D", true, false)
			report += "carro do Meshy (pronto): %d malhas, %d triângulos, tamanho %s
" % [_count_meshes(new_car), _count_triangles(new_car), str(_bounds(new_car).size)]
		else:
			var raw := _bounds(new_car)
			# Comprimento no eixo Z como na frota (3,87 m do hatch atual); gira 90° se o GLB vier ao longo de X.
			new_car.rotation.y = deg_to_rad((90.0 if raw.size.x > raw.size.z else 0.0) + yaw_extra)
			var fit := 3.87 / _bounds(new_car).size.z
			holder.scale = Vector3.ONE * fit
			var box := _bounds(holder)
			holder.position = Vector3(2.6 - box.get_center().x, -box.position.y, -box.get_center().z)
			report += "carro do Meshy: %d malhas, %d triângulos, tamanho final %s (escala %.2f)
" % [_count_meshes(new_car), _count_triangles(new_car), str(_bounds(holder).size), fit]
	camera = Camera3D.new()
	camera.fov = 32.0
	stage.add_child(camera)
	camera.current = true
	for i in 12: await process_frame
	# Roda as quatro rodas 50° em torno do próprio eixo (mesma transformação que o veículo aplica).
	for wheel in spinners:
		var center: Vector3 = wheel.get_meta("wheel_center")
		var spin := Basis(Vector3.RIGHT, deg_to_rad(50.0))
		wheel.transform = Transform3D(spin, center - spin * center)
	var views := {"tres_quartos": Vector3(5.5, 2.4, 7.5), "lado": Vector3(10.0, 1.2, 0.0), "frente": Vector3(0, 1.4, 10.0), "topo": Vector3(0.1, 11.0, 2.0)}
	for view_name in views:
		camera.position = views[view_name]
		camera.look_at(Vector3(0, 0.7, 0), Vector3.UP)
		for i in 6: await process_frame
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%s.png" % [output_dir, view_name]))
	print(report)
	quit(0)

func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in node.find_children("*", "MeshInstance3D", true, false):
		if (child as MeshInstance3D).mesh != null: out.append(child)
	return out

func _count_meshes(node: Node) -> int: return _meshes(node).size()

func _count_triangles(node: Node) -> int:
	var total := 0
	for mesh_node in _meshes(node):
		for s in mesh_node.mesh.get_surface_count():
			var arrays := mesh_node.mesh.surface_get_arrays(s)
			total += (arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	return total

func _bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh_node in _meshes(node):
		var part: AABB = mesh_node.global_transform * mesh_node.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box

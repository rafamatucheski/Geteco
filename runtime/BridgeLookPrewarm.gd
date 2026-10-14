extends RefCounted
## Desenha sob a cortina os materiais do acabamento da ponte cidade–serra (shader de concreto procedural e aço
## com cor no vértice). Sem isto o shader compilava no primeiro desenho da ponte: picos de 0,35–0,95 s no HUD
## das capturas de 14/10, contra 25–60 ms sem o acabamento. Mesma receita de VehicleMaterialVariantPrewarm:
## caixas temporárias na frente da câmera por alguns quadros, com sombra, e o material fica retido.
const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const GUARDS := preload("res://gameplay/emergency/EffectsPrewarm.gd")
const DRAW_FRAMES := 3
const MAX_WAIT_FRAMES := 24
static var _done := false
static var last_summary: Dictionary = {}

static func run(host: Node3D, curtain: CanvasLayer) -> void:
	if _done or not CONNECTION.look_enabled or DisplayServer.get_name() == "headless": return
	if "--no-prewarm" in OS.get_cmdline_user_args() or not GUARDS._covered_loading(host, curtain): return
	var camera := host.get("camera") as Camera3D
	if not GUARDS._current_camera(host, camera): return
	var began := Time.get_ticks_usec()
	CONNECTION._look_concrete()
	CONNECTION._look_steel()
	var materials: Array = CONNECTION._look_materials.values()
	var visual := Node3D.new()
	visual.name = "BridgeLookPrewarm"
	visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var box := BoxMesh.new()
	box.size = Vector3.ONE * .5
	for index in materials.size():
		var part := MeshInstance3D.new()
		part.mesh = box
		part.material_override = materials[index]
		part.position = Vector3((index - (materials.size() - 1) * .5) * .7, 0, 0)
		visual.add_child(part)
	host.add_child(visual)
	var draws: Array[int] = [0]
	var count_draw := func() -> void: draws[0] += 1
	RenderingServer.frame_post_draw.connect(count_draw)
	var completed := false
	for frame in MAX_WAIT_FRAMES:
		visual.global_transform = Transform3D(camera.global_basis, camera.global_position - camera.global_basis.z * 9.0)
		await host.get_tree().process_frame
		if not GUARDS._covered_loading(host, curtain) or not is_instance_valid(visual): break
		if draws[0] >= DRAW_FRAMES:
			completed = true
			break
	if RenderingServer.frame_post_draw.is_connected(count_draw): RenderingServer.frame_post_draw.disconnect(count_draw)
	if is_instance_valid(visual): visual.free()
	_done = completed
	last_summary = {"materials": materials.size(), "completed": completed, "draws": draws[0], "usec": Time.get_ticks_usec() - began}
	print("Materiais da ponte preparados: ", JSON.stringify(last_summary))

extends RefCounted
## Desenha sob a cortina uma caixa de cada variante de shader dos materiais família da fusão por trecho, e a
## cópia com alfa do corte do túnel de cada uma. Mesma receita de BridgeLookPrewarm/VehicleMaterialVariantPrewarm.
## Sem isto, cache de shader frio fazia a fusão travar até 1,3 s ao entrar em trechos novos (15/10).
const VARIANTS := preload("res://world/chunk_bake/FamilyShaderVariants.gd")
const MERGE := preload("res://world/chunk_bake/ChunkCellMerge.gd")
const CUTAWAY := preload("res://world/urban_detail/TunnelCutaway.gd")
const GUARDS := preload("res://gameplay/emergency/EffectsPrewarm.gd")
const DRAW_FRAMES := 3
const MAX_WAIT_FRAMES := 30
static var _retained: Array[Material] = []
static var _done := false
static var last_summary: Dictionary = {}

static func run(host: Node3D, curtain: CanvasLayer) -> void:
	if _done or not MERGE.enabled or DisplayServer.get_name() == "headless": return
	if "--no-prewarm" in OS.get_cmdline_user_args() or not GUARDS._covered_loading(host, curtain): return
	var camera := host.get("camera") as Camera3D
	if not GUARDS._current_camera(host, camera): return
	var began := Time.get_ticks_usec()
	var materials: Array[Material] = []
	for variant in VARIANTS.known().values():
		var material := VARIANTS.build(variant)
		materials.append(material)
		materials.append(CUTAWAY.make_alpha_copy(material))
	if materials.is_empty(): return
	var visual := Node3D.new()
	visual.name = "FamilyVariantPrewarm"
	visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Mesmo formato de vértice dos lotes (ChunkCellMerge._build_batch): posição, normal, UV e cor, com tangente
	# só quando o material usa mapa de normal. O formato também entra no pipeline compilado.
	var plain := _quad(false)
	var tangent := _quad(true)
	var columns := maxi(1, ceili(sqrt(float(materials.size()))))
	for index in materials.size():
		var part := MeshInstance3D.new()
		var material := materials[index] as StandardMaterial3D
		part.mesh = tangent if material != null and material.normal_enabled else plain
		part.material_override = materials[index]
		part.position = Vector3((index % columns - (columns - 1) * .5) * .35, -floorf(float(index) / columns) * .35, 0)
		visual.add_child(part)
	host.add_child(visual)
	var draws: Array[int] = [0]
	var count_draw := func() -> void: draws[0] += 1
	# Peças escondidas primeiro: os trabalhadores do motor compilam em paralelo (runtime/HiddenCompile.gd).
	await preload("res://runtime/HiddenCompile.gd").prepare(visual, host.get_tree())
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
	if completed: _retained.append_array(materials)
	_done = completed
	last_summary = {"variants": materials.size() / 2, "completed": completed, "draws": draws[0], "usec": Time.get_ticks_usec() - began}
	print("Variantes da fusão preparadas: ", JSON.stringify(last_summary))

static func _quad(with_tangent: bool) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-.15, -.15, 0), Vector3(.15, -.15, 0), Vector3(.15, .15, 0), Vector3(-.15, .15, 0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	if with_tangent: arrays[Mesh.ARRAY_TANGENT] = PackedFloat32Array([1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

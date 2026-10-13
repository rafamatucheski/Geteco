extends RefCounted
## Carrega e desenha uma vez cada corpo do Meshy atrás da tela de carregamento.
##
## O primeiro pedestre de cada corpo lia o GLB do disco no meio do jogo (`MeshyBodyRig.build` faz
## `load(source_path)`): no release de 2026-10-13 um `population_spawn` custou 559 ms e outros dois
## 85-102 ms por sessão, contra ~3 ms dos demais. Os PackedScene ficam presos aqui para não saírem do
## cache, e um modelo de cada corpo é desenhado alguns quadros para compilar o shader e a pele.
const CIVILIAN := preload("res://assets/CivilianModel.gd")
const GUARDS := preload("res://gameplay/emergency/EffectsPrewarm.gd")
const ROOT := "res://assets/civilians/meshy/"
const DRAW_FRAMES := 3
const MAX_WAIT_FRAMES := 30
static var _held: Array[Resource] = []
static var _done := false

## GLBs de todas as pastas do Meshy. No export o diretório lista `x.glb.import`/`.remap`, não o GLB.
static func body_paths() -> PackedStringArray:
	var found := PackedStringArray()
	var folders := DirAccess.get_directories_at(ROOT)
	for folder in folders:
		for file in DirAccess.get_files_at(ROOT + folder):
			var name := file.trim_suffix(".import").trim_suffix(".remap")
			if not name.ends_with(".glb"): continue
			var path := ROOT + folder + "/" + name
			if not found.has(path) and ResourceLoader.exists(path): found.append(path)
	return found

static func run(host: Node3D, curtain: CanvasLayer) -> void:
	if _done or "--no-prewarm" in OS.get_cmdline_user_args(): return
	var tree := host.get_tree()
	var paths := body_paths()
	for path in paths:
		var packed := load(path)
		if packed != null: _held.append(packed)
		await tree.process_frame
		if not is_instance_valid(host) or not host.is_inside_tree(): return
	_done = true
	if DisplayServer.get_name() == "headless": return
	if not GUARDS._covered_loading(host, curtain): return
	var camera := host.get("camera") as Camera3D
	if not GUARDS._current_camera(host, camera): return
	var visual := Node3D.new()
	visual.name = "MeshyBodyPrewarm"
	visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for index in paths.size():
		var model := CIVILIAN.new()
		model.body_source = paths[index]
		model.position = Vector3((index - paths.size() * 0.5) * 0.8, 0, 0)
		visual.add_child(model)
	host.add_child(visual)
	var draws: Array[int] = [0]
	var count_draw := func() -> void: draws[0] += 1
	RenderingServer.frame_post_draw.connect(count_draw)
	for frame in MAX_WAIT_FRAMES:
		if not is_instance_valid(visual) or not GUARDS._current_camera(host, camera): break
		visual.global_transform = Transform3D(camera.global_basis, camera.global_position - camera.global_basis.z * 12.0)
		await tree.process_frame
		if not GUARDS._covered_loading(host, curtain): break
		if draws[0] >= DRAW_FRAMES: break
	if RenderingServer.frame_post_draw.is_connected(count_draw):
		RenderingServer.frame_post_draw.disconnect(count_draw)
	if is_instance_valid(visual): visual.free()

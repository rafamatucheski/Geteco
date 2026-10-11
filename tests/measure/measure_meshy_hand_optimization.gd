extends "res://tests/measure/measure_police_crowd.gd"
## Mesmas mãos V11 e animação: cálculo da arma/cadeia alternado A/B/B/A/A/B.
## --include-legacy acrescenta o corpo anterior em nove rodadas balanceadas, com importação equivalente.
var sample_index := 0
const RIG := preload("res://assets/civilians/MeshyBodyRig.gd")
var compare_legacy := false
var retained_scenes: Array[PackedScene] = []
var variant_paths: Array[String] = []

func _process(delta: float) -> bool:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		push_error("Medição interrompida: janela minimizada deixa de renderizar")
		quit(2)
		return false
	return super._process(delta)

func _initialize() -> void:
	kinds = ["original", "optimized", "optimized", "original", "original", "optimized"]
	output_dir = "res://evidence/npc-meshy/hands-perf-20261011/pose-stage"
	compare_legacy = "--include-legacy" in OS.get_cmdline_user_args()
	if compare_legacy:
		# Cada condição ocupa início/meio/fim de um bloco; mesma importação para os três controles.
		kinds = ["legacy", "original", "optimized", "original", "optimized", "legacy", "optimized", "legacy", "original"]
	super._initialize()
	if compare_legacy:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
		for source in ["res://evidence/npc-meshy/hands-review-20261011/suit_m_before.glb", "res://assets/civilians/meshy/police/suit_m.glb"]:
			var document := GLTFDocument.new()
			var state := GLTFState.new()
			assert(document.append_from_file(source, state) == OK)
			var scene := document.generate_scene(state)
			var packed := PackedScene.new()
			assert(packed.pack(scene) == OK)
			var destination := "%s/variant-%d.tscn" % [output_dir, variant_paths.size()]
			assert(ResourceSaver.save(packed, destination, ResourceSaver.FLAG_BUNDLE_RESOURCES) == OK)
			scene.free()
			variant_paths.append(destination)
			retained_scenes.append(load(destination))

func _configure_kind(kind: String) -> void:
	CATALOG.enabled = true
	MODEL.optimize_weapon_targets = kind == "optimized"
	RIG.optimize_pose_chain = MODEL.optimize_weapon_targets
	RIG.palm_grips = kind != "legacy"
	var source := variant_paths[0 if kind == "legacy" else 1] if compare_legacy else "res://assets/civilians/meshy/police/suit_m.glb"
	for tier in 5: CATALOG.override[tier] = source
	clock = 0.0

func _sample(_round_name: String, kind: String) -> void:
	await process_frame
	for officer in officers:
		assert(officer.body.palm_grip_enabled == (kind != "legacy"))
		assert(officer.body.mesh_node.mesh.get_surface_count() == (1 if kind == "legacy" else 2))
		if kind != "legacy": assert(officer.body.mesh_node.get_blend_shape_count() == 2)
	var label := kind
	await super._sample("hands_%d_%s" % [sample_index, label], label)
	var over66 := 0
	for value in frame_ms:
		if value > 66.7: over66 += 1
	rounds.back()["over66"] = over66
	var raw := FileAccess.open("%s/raw-%d.json" % [output_dir, sample_index], FileAccess.WRITE)
	raw.store_string(JSON.stringify({"frame_ms": frame_ms, "draw_calls": draw_calls}))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/stage-%d.png" % [output_dir, sample_index]))
	sample_index += 1

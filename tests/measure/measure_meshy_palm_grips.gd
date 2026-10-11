extends "res://tests/measure/measure_police_crowd.gd"
## Mesmas luzes/armas/câmera; alterna pacote anterior e revisado no processo, sem trocar arquivos de produção.
const RIG := preload("res://assets/civilians/MeshyBodyRig.gd")
var sample_index := 0
var baseline_path := ""
var revised_path := ""

func _initialize() -> void:
	kinds = ["new", "new", "new", "new", "new", "new"]
	output_dir = "res://evidence/npc-meshy/hands-review-20261011/perf-palms"
	baseline_path = "res://evidence/npc-meshy/hands-review-20261011/suit_m_before.tscn"
	revised_path = "res://evidence/npc-meshy/hands-review-20261011/suit_m_revised.tscn"
	# Ambos passam pelo mesmo caminho de leitura, sem assimetria do cache de importação/LOD.
	for pair in [["res://evidence/npc-meshy/hands-review-20261011/suit_m_before.glb", baseline_path],
		["res://assets/civilians/meshy/police/suit_m.glb", revised_path]]:
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		assert(document.append_from_file(pair[0], state) == OK)
		var scene := document.generate_scene(state)
		var packed := PackedScene.new()
		assert(packed.pack(scene) == OK)
		assert(ResourceSaver.save(packed, pair[1], ResourceSaver.FLAG_BUNDLE_RESOURCES) == OK)
		scene.free()
	super._initialize()

func _configure_kind(_kind: String) -> void:
	CATALOG.enabled = true
	RIG.palm_grips = sample_index in [1, 2, 5]
	for tier in 5:
		CATALOG.override[tier] = revised_path if RIG.palm_grips else baseline_path

func _sample(_round_name: String, _kind: String) -> void:
	var refined := sample_index in [1, 2, 5]
	RIG.palm_grips = refined
	var label := "palms" if refined else "wrists"
	await process_frame # O corpo produtivo é instalado de forma deferida.
	for officer in officers:
		assert(officer.body != null and officer.body.palm_grip_enabled == refined, "perfil errado no A/B")
		assert(officer.body.mesh_node.mesh.get_surface_count() == (2 if refined else 1), "geometria errada no A/B")
	print("PALMS_VARIANT ", label, " officers=", officers.size(), " source=", revised_path if refined else baseline_path)
	await super._sample("palms_%d_%s" % [sample_index, label], label)
	var over66 := 0
	for value in frame_ms:
		if value > 66.7: over66 += 1
	rounds.back()["over66"] = over66
	var raw := FileAccess.open("%s/raw-%d-%s.json" % [output_dir, sample_index, label], FileAccess.WRITE)
	raw.store_string(JSON.stringify({"frame_ms": frame_ms, "draw_calls": draw_calls}))
	sample_index += 1

extends "res://tests/measure/measure_police_crowd.gd"
## Isola o custo da correção: mesmos GLBs/policiais, alternando apenas a IK e alinhamento dos ombros no processo.
const RIG := preload("res://assets/civilians/MeshyBodyRig.gd")
var sample_index := 0

func _initialize() -> void:
	kinds = ["new", "new", "new", "new", "new", "new"]
	output_dir = "res://evidence/npc-meshy/refinement-20261011/perf-contact"
	super._initialize()

func _sample(_round_name: String, _kind: String) -> void:
	var refined := sample_index in [1, 2, 5]
	RIG.correct_hand_reach = refined
	var label := "refined" if refined else "legacy"
	await super._sample("contact_%d_%s" % [sample_index, label], label)
	var over66 := 0
	for value in frame_ms:
		if value > 66.7: over66 += 1
	rounds.back()["over66"] = over66
	var raw := FileAccess.open("%s/raw-%d-%s.json" % [output_dir, sample_index, label], FileAccess.WRITE)
	raw.store_string(JSON.stringify({"frame_ms": frame_ms, "draw_calls": draw_calls}))
	sample_index += 1

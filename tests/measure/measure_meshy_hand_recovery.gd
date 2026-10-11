extends "res://tests/measure/measure_meshy_palm_grips.gd"
## Confirma recuperação contra a referência anterior às mãos V11.
## Ambos GLBs passam pelo mesmo importador sem LOD; mesma fixture do registro da regressão.
var retained_scenes: Array[PackedScene] = []

func _process(delta: float) -> bool:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		push_error("Medição interrompida: janela minimizada deixa de renderizar")
		quit(2)
		return false
	return super._process(delta)

func _initialize() -> void:
	super._initialize()
	# Evita releitura da cena textual entre rodadas; não altera a amostragem.
	retained_scenes = [load(baseline_path), load(revised_path)]

func _configure_kind(kind: String) -> void:
	super._configure_kind(kind)
	MODEL.optimize_weapon_targets = sample_index in [1, 2, 5]
	RIG.optimize_pose_chain = MODEL.optimize_weapon_targets
	clock = 0.0

func _sample(round_name: String, kind: String) -> void:
	await super._sample(round_name, kind)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/stage-%d.png" % [output_dir, sample_index - 1]))

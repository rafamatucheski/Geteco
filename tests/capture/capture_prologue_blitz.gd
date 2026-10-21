extends SceneTree
## Capturas dos dois pontos de vista da blitz (autoplay) em evidence/prologue-blitz-<data>/.
## Só revisão visual: não mede desempenho. Precisa de janela (sem --headless).
const BLITZ := preload("res://runtime/prologue/BlitzScene.gd")
const SHOTS := {
	"dante": [["dante_open", 3.0, "01_radio"], ["dante_open+", 1.0, "02_lanterna"], ["dante_walk", 2.0, "03_nuca"],
		["dante_door", 2.4, "04_rosto_vicente"], ["dante_door", 7.0, "05_ordem"], ["dante_cuff", 1.6, "06_maos"]],
	"vicente": [["vicente_drive", 3.0, "11_estrada"], ["vicente_drive", 16.0, "12_giroflex"], ["vicente_wait", 2.0, "13_cabine"],
		["vicente_face", 2.5, "14_rosto_dante"]],
}
var folder := "res://evidence/prologue-blitz-20261021/"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for pov in SHOTS:
		var done := [false]
		var scene = BLITZ.start(null, pov, func(): done[0] = true)
		scene.autoplay = true
		for shot in SHOTS[pov]:
			# "+" no fim: só depois do sinal da lanterna (o sinal zera o relógio do estágio).
			var stage: String = str(shot[0]).trim_suffix("+")
			var after_signal := str(shot[0]).ends_with("+")
			while not done[0] and not (scene.stage == stage and scene.stage_time >= shot[1] and (not after_signal or scene.signaled)):
				await process_frame
			if done[0]: break
			await RenderingServer.frame_post_draw
			var path: String = folder + "%s.png" % shot[2]
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
			print("CAPTURE ", path, " stage=", scene.stage, " t=", snappedf(scene.stage_time, .1))
		if is_instance_valid(scene): scene.pace = 6.0
		while not done[0]: await process_frame
	quit(0)

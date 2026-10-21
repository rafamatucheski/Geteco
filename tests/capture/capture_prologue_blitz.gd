extends SceneTree
## Capturas dos dois pontos de vista da blitz (autoplay) em evidence/prologue-blitz-<data>/.
## Só revisão visual: não mede desempenho. Precisa de janela (sem --headless).
const BLITZ := preload("res://runtime/prologue/BlitzScene.gd")
const SHOTS := {
	"dante": [["dante_open", 3.0, "01_radio"], ["dante_open", 7.5, "02_desvio"], ["dante_open+", 1.0, "03_lanterna"],
		["dante_walk", 3.0, "04_nuca"], ["dante_ask", .8, "05_batida"], ["dante_ask", 5.0, "06_rosto_vicente"],
		["dante_ask", 9.0, "07_desce"], ["dante_ambush", .5, "08_tiro"], ["dante_fight", 1.5, "09_mira"], ["dante_fight!", 1.3, "09b_morte"],
		["dante_flee", 1.2, "10_fuga"], ["dante_wounded", 2.0, "11_ferido"], ["dante_cuff", 1.6, "12_maos"]],
	"vicente": [["vicente_drive", 3.0, "21_estrada"], ["vicente_drive", 16.0, "22_giroflex"], ["vicente_wait", 2.0, "23_cabine"],
		["vicente_face", 2.5, "24_rosto_dante"]],
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
			# "!" no fim: só depois de o atirador cair (a morte zera o relógio do estágio).
			var after_kill := str(shot[0]).ends_with("!")
			stage = stage.trim_suffix("!")
			while not done[0] and not (scene.stage == stage and scene.stage_time >= shot[1] and (not after_signal or scene.signaled) and (not after_kill or scene.shooter_health <= 0)):
				await process_frame
			if done[0]: break
			await RenderingServer.frame_post_draw
			var path: String = folder + "%s.png" % shot[2]
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
			print("CAPTURE ", path, " stage=", scene.stage, " t=", snappedf(scene.stage_time, .1))
		if is_instance_valid(scene): scene.pace = 6.0
		while not done[0]: await process_frame
	quit(0)

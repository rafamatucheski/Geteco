extends SceneTree
## Gera e salva os WAVs entregáveis da Monaliza (carro pessoal do Dante) em
## audio/monaliza_review/, mais a demonstração composta para audição.
##
## Rodar (headless, não precisa de renderer -- só grava PCM em disco):
##   "D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe" ^
##     --headless --path "D:/geteco/game" --script res://audio/monaliza_review/export_monaliza_audio.gd

const KIT := preload("res://audio/monaliza_review/MonalizaAudioKit.gd")
const OUT_DIR := "D:/geteco/game/audio/monaliza_review/"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var results := {}
	results["engine.wav"] = KIT.generate_engine_stream().save_to_wav(OUT_DIR + "engine.wav")
	results["turbo_spool.wav"] = KIT.generate_turbo_spool_stream().save_to_wav(OUT_DIR + "turbo_spool.wav")
	results["turbo_release.wav"] = KIT.generate_turbo_release_stream().save_to_wav(OUT_DIR + "turbo_release.wav")
	results["turbo_shift.wav"] = KIT.generate_turbo_shift_stream().save_to_wav(OUT_DIR + "turbo_shift.wav")
	results["ignition.wav"] = KIT.generate_ignition_stream().save_to_wav(OUT_DIR + "ignition.wav")
	results["demo_start_accelerate_release.wav"] = KIT.generate_demo_stream().save_to_wav(OUT_DIR + "demo_start_accelerate_release.wav")

	var all_ok := true
	for file_name in results.keys():
		var err = results[file_name]
		print("SAVE ", file_name, " -> ", err, (" (OK)" if err == OK else " (FAIL)"))
		all_ok = all_ok and err == OK

	print("MONALIZA_AUDIO_EXPORT all_ok=", all_ok)
	quit(0 if all_ok else 1)

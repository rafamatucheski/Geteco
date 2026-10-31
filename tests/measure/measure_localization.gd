extends "res://tests/measure/measure_performance_plan.gd"
## Diagnóstico controlado de custo da localização na cena de produção real.
## A tradução desligada é uma linha de base de diagnóstico, não uma linha de base histórica do código.
func run() -> void:
	var settings := root.get_node("V2Settings")
	settings.text_language = "en"
	for argument in OS.get_cmdline_user_args():
		if argument == "--translation-disabled":
			settings.text_language = "pt_BR"
			preload("res://runtime/Localization.gd").uninstall()
	await super.run()

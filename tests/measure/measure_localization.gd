extends "res://tests/measure/measure_performance_plan.gd"
## Controlled localization-cost diagnostic in the actual production scene.
## Disabled translation is a diagnostic baseline, not a historical source baseline.
func run() -> void:
	var settings := root.get_node("V2Settings")
	settings.text_language = "en"
	for argument in OS.get_cmdline_user_args():
		if argument == "--translation-disabled":
			settings.text_language = "pt_BR"
			preload("res://runtime/Localization.gd").uninstall()
	await super.run()

extends SceneTree
## Presentation remains bilingual without changing identifiers or audio preferences.
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func translated(source: String, expected: String) -> void:
	var actual := String(TranslationServer.translate(source))
	check(actual == expected, "Translation: %s => %s; expected %s" % [source, actual, expected])

func _run() -> void:
	var localization := preload("res://runtime/Localization.gd")
	localization.install()
	var old_locale := TranslationServer.get_locale()
	var settings := root.get_node_or_null("V2Settings")
	var old_voice: String = settings.voice_language if settings != null else ""
	TranslationServer.set_locale("en")
	translated("NOVO JOGO", "NEW GAME")
	translated("Inventário · R$ 123", "Inventory · R$ 123")
	translated("Comprar Pistola", "Buy Pistol")
	translated("Monaliza · Concluído", "Monaliza · Complete")
	translated("Roupa: 60% de proteção ao frio", "Clothing: 60% cold protection")
	translated("Volume geral", "Master volume")
	translated("Aproxime a traseira do guincho do carro.", "Move the rear of the tow truck near the car.")
	translated("cobra_contact", "cobra_contact")
	translated("Maciota", "Maciota")
	var source := String(TranslationServer.translate("Vença %d provas diferentes")) % 3
	check(source == "Win 3 different events", "Format template translates before interpolation")
	TranslationServer.set_locale("pt_BR")
	translated("NEW GAME", "NOVO JOGO")
	translated("Inventory · R$ 123", "Inventário · R$ 123")
	translated("Monaliza · Complete", "Monaliza · Concluído")
	translated("Master volume", "Volume geral")
	translated("Alpha build · work in progress · v0.3.2", "Versão alfa · em desenvolvimento · v0.3.2")
	check(settings == null or settings.voice_language == old_voice, "Text locale never changes voice preference")
	TranslationServer.set_locale("en")
	translated("NEW GAME", "NEW GAME")
	TranslationServer.set_locale(old_locale)
	print("LOCALIZATION_PRESENTATION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

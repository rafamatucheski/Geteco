extends SceneTree
## A Monaliza aparecia na baia sem explicação (playtest de 21/10): o fim da M01 agora traz o
## Maciota apresentando o carro, nos dois idiomas, com as falas reconhecidas pela direção de voz.
const DIALOGUE := preload("res://systems/campaign/OriginalDialogue.gd")
const VOICE_BANK := preload("res://audio/DirectedVoiceBank.gd")
var failures := 0

func _check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func _initialize() -> void:
	var dialogue = DIALOGUE.new()
	_check(dialogue.lines("primeiro_giro_finish").size() == 3, "fim original da M01 preservado")
	for language in ["pt_BR", "en"]:
		var intro: Array = dialogue.lines("monaliza_intro", language)
		_check(intro.size() == 3, "apresentação da Monaliza em " + language)
		_check(intro.size() == 3 and "Monaliza" in str(intro[0].message) and str(intro[0].speaker) == "MACIOTA", "Maciota abre apresentando a Monaliza em " + language)
	for row in dialogue.lines("monaliza_intro", "pt_BR"):
		var canonical: Dictionary = VOICE_BANK.canonical(str(row.message), str(row.speaker).to_lower())
		_check(not canonical.is_empty() and not VOICE_BANK.profile(canonical).is_empty(), "direção e elenco conhecem: " + str(row.message).left(32))
	var source := FileAccess.get_file_as_string("res://runtime/MissionWorld.gd")
	_check("dialogue.lines(\"monaliza_intro\"" in source, "MissionWorld encadeia a apresentação no fim da M01")
	print("monaliza_intro: ", "OK" if failures == 0 else "FALHOU (%d)" % failures)
	quit(0 if failures == 0 else 1)

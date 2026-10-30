extends SceneTree
## Sons da trilha de jipe: largada, chegada e dinheiro (uma vez cada, sem repetir em rajada).
const CONTROLLER := preload("res://activities/mountain_jeep/MountainJeepController.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
const REWARD_AUDIO := preload("res://gameplay/RewardAudio.gd")
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("JEEP_SOUNDS ", "PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func _playing(pool: Node) -> int:
	var n := 0
	for voice in pool.get_children():
		if voice.playing: n += 1
	return n
func run() -> void:
	# Cues da trilha
	var jeep := CONTROLLER.new()
	root.add_child(jeep)
	jeep._setup_cues()
	check(jeep._cue_voice != null and jeep._cue_voice.get_parent() == jeep, "voz de cue criada")
	for kind in ["countdown", "checkpoint", "complete"]:
		check(CONTROLLER.CUES.activity(kind) != null, "WAV %s existe e importa" % kind)
	jeep._cue("countdown")
	check(jeep._cue_voice.playing and jeep.played_cues == ["countdown"], "largada toca a contagem")
	jeep._cue("complete")
	check(jeep.played_cues == ["countdown", "complete"] and jeep._cue_voice.playing, "chegada toca o cue de conclusão")
	# O controlador realmente chama os cues nos pontos certos (largada, portão, chegada).
	var src := FileAccess.get_file_as_string("res://activities/mountain_jeep/MountainJeepController.gd")
	check(src.contains('_cue("countdown")') and src.contains('_cue("checkpoint")') and src.contains('_cue("complete")'), "controlador dispara largada, portão e chegada")
	# Dinheiro: ponto central da carteira
	var economy := ECONOMY.new()
	var got: Array[int] = []
	economy.money_gained.connect(func(a): got.append(a))
	economy.grant_reward("jeep_test_a", 700)
	check(got == [700], "grant_reward avisa uma vez")
	economy.grant_reward("jeep_test_a", 700)
	check(got == [700], "recibo repetido não paga nem avisa")
	economy.grant_reward("jeep_test_zero", 0)
	economy.collect_loose_cash(50)
	check(got == [700, 50], "dinheiro solto avisa; valor zero não")
	# Som de dinheiro com proteção contra rajada
	REWARD_AUDIO.play(root, "cash")
	var pool := root.get_node_or_null("RewardAudioVoices")
	check(pool != null and _playing(pool) == 1, "dinheiro toca o som cash")
	REWARD_AUDIO.play(root, "cash")
	check(_playing(pool) == 1, "rajada de dinheiro é coalescida")
	print("JEEP_SOUNDS ", "PASS" if failures == 0 else "FAIL", " falhas=", failures)
	quit(0 if failures == 0 else 1)

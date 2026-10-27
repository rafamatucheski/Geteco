extends SceneTree
## Vozes de dor por pessoa (27/10/2026): cada corpo tem timbre fixo (grupo + tom), pessoas diferentes
## soam diferentes, corpo sem gênero conhecido não ganha voz de homem por padrão, mulher usa banco
## feminino, e as tomadas e os impactos de bala no corpo não se repetem em seguida. Não ouve nada:
## confere arquivos, escolha e faixa de tom.
const BANK := preload("res://audio/PainVoiceBank.gd")
const AUDIO := preload("res://gameplay/CombatAudio.gd")

class Body extends Node3D:
	var wardrobe := {}

class Person extends CharacterBody3D:
	var visual: Node3D
	var dead := false

var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PAIN_BANK PASS " if ok else "PAIN_BANK FAIL ") + label)
	if not ok:
		failures.append(label)
		push_error(label)

func person(female: Variant, label: String) -> Person:
	var actor := Person.new()
	actor.name = label
	var body := Body.new()
	if female is bool: body.wardrobe = {"female": female}
	actor.add_child(body)
	actor.visual = body
	root.add_child(actor)
	return actor

func run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2710
	for gender in BANK.GROUPS:
		for kind in BANK.GROUPS[gender]:
			for group in BANK.GROUPS[gender][kind]:
				var count := BANK.takes(gender, kind, group).size()
				print("PAIN_BANK %s/%s/%s: %d tomadas" % [gender, kind, group, count])
	check(BANK.takes("female", "light", "young").size() + BANK.takes("female", "light", "mature").size() >= 3, "banco feminino de gemido tem pelo menos 3 tomadas")
	check(BANK.takes("male", "light", "adult").size() + BANK.takes("male", "light", "young").size() + BANK.takes("male", "light", "older").size() >= 3, "banco masculino de gemido tem pelo menos 3 tomadas")
	check(not BANK.takes("female", "heavy", "any").is_empty() and not BANK.takes("male", "heavy", "any").is_empty(), "gritos fortes gravados para os dois gêneros")
	var unknown := person(null, "SemGenero")
	check(BANK.pick(unknown, "light", rng).is_empty(), "corpo sem gênero conhecido não ganha voz de homem por padrão")
	var woman := person(true, "Mulher")
	var choice := BANK.pick(woman, "light", rng)
	check(not choice.is_empty() and str(woman.get_meta("pain_voice").gender) == "female", "mulher grita com o banco feminino")
	var first: Dictionary = woman.get_meta("pain_voice").duplicate()
	BANK.pick(woman, "heavy", rng)
	check(woman.get_meta("pain_voice") == first, "a mesma pessoa mantém grupo e tom entre um grito e outro")
	var pitches := {}
	var groups := {}
	for index in 16:
		var man := person(false, "Homem%d" % index)
		var picked := BANK.pick(man, "light", rng)
		if picked.is_empty(): continue
		var who: Dictionary = man.get_meta("pain_voice")
		pitches[snappedf(float(who.pitch), 0.001)] = true
		groups[str(who.group)] = true
		check(float(who.pitch) >= BANK.PITCH_RANGE.male.x and float(who.pitch) <= BANK.PITCH_RANGE.male.y, "tom do homem %d dentro da faixa" % index)
	check(pitches.size() >= 10, "16 homens soam com pelo menos 10 tons diferentes (%d)" % pitches.size())
	check(groups.size() >= 2, "homens se dividem entre grupos de voz gravados (%d)" % groups.size())
	var repeats := 0
	var last: AudioStream = null
	for index in 40:
		var take: Dictionary = BANK.pick(woman, "heavy", rng)
		if take.is_empty(): break
		if take.stream == last: repeats += 1
		last = take.stream
	check(repeats == 0, "grito forte não repete a mesma tomada em seguida")
	for kind in ["flesh", "vest"]:
		var previous: AudioStream = null
		var repeated := 0
		var found := 0
		for index in 30:
			var hit := AUDIO.body_hit_take(kind, rng)
			if hit == null: break
			found += 1
			if hit == previous: repeated += 1
			previous = hit
		check(found > 0 and repeated == 0, "bala no corpo (%s) gravada e sem repetir em seguida" % kind)
	print("PAIN_BANK failures=", failures)
	quit(0 if failures.is_empty() else 1)

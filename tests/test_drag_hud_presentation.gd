extends SceneTree
## HUD da arrancada: uma instrução por vez, semáforo no conta-giros, nitro
## ausente declarado e textos da corrida e do resultado traduzidos em inglês.
## Não desenha nem mede: a leitura visual fica com as capturas.
const HUD := preload("res://activities/desert_drag/DesertDragHUD.gd")
const DRIVE := preload("res://gameplay/desert_cars/DesertDrivetrain.gd")
const CHALLENGE := preload("res://activities/desert_drag/DragRivalChallengeController.gd")
const TELEMETRY := preload("res://activities/desert_drag/DragRivalChallengeTelemetry.gd")
# Palavras que só existem no português destas telas; nenhuma pode sobrar em inglês.
# "LIMITE " leva o espaço porque LIMITER é inglês.
const PORTUGUESE := ["ACELER", "GIRO", "TROC", "MARCHA", "LARGADA", "FAIXA", "LIMITE ", "ERROS", "BOAS",
	"PASSAGEM", "NOITE", "DESAFIO", "PROVA", "RECORDE", "CONSERVE", "REPITA", "PATINAGEM", "ESPAÇO",
	"À FRENTE", "ATRÁS", "SEM ", "º", "ANTECIPE", "SOLTE", "EXPERIMENTE", "PARCIAIS", "TOLERÂNCIA", "ATUAL"]
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("DRAG_HUD FAIL ", message)

func english(source: String) -> void:
	var shown := String(TranslationServer.translate(source))
	var upper := shown.to_upper()
	var leftover := PORTUGUESE.filter(func(word): return word in upper)
	check(leftover.is_empty(), "inglês sem português: '%s' -> '%s' %s" % [source, shown, leftover])

func run() -> void:
	var hud := HUD.new()
	var drive := DRIVE.new()
	drive.configure("desert_faisca", {})
	drive.race_mode = true
	hud.update_state(drive, 800.0, 0.0, 0.0, "3", "Digo")
	check(not hud._nitro_installed, "carro sem nitro é declarado sem nitro")
	drive.configure("desert_faisca", {"nitro":"nitro_race"})
	drive.race_mode = true
	hud.update_state(drive, 800.0, 0.0, 0.0, "3", "Digo")
	check(hud._nitro_installed, "nitro instalado continua com barra e tecla")

	# Semáforo da largada: 3, 2, 1 acendem uma, duas e três lâmpadas; verde ao largar.
	hud.show_start_lights = true
	for row in [["3", 1], ["2", 2], ["1", 3]]:
		hud.headline = row[0]
		check(hud.start_lamps_lit(true) == row[1], "contagem %s acende %d lâmpadas" % row)
	hud.show_start_lights = false
	hud.headline = ""
	hud.racing = true
	hud.seconds = .2
	check(hud.start_lamps_lit(false) == -1, "logo depois da largada o semáforo fica verde")
	hud.seconds = 1.0
	check(hud.start_lamps_lit(false) == 0, "depois do verde o casulo volta às luzes de troca")

	# Instrução única: troca devida agora vence o veredito da troca anterior.
	hud.gear = 2
	hud._max_gear = 6
	hud._shift_active = false
	hud.feedback = "TROCA IDEAL"
	var band: float = hud._good_from(false) + .02
	var line: Array = hud.message(false, band)
	check(line[0] == "TROQUE AGORA" and line[1] == HUD.AMBER, "faixa de troca vence o veredito: " + str(line))
	line = hud.message(false, .995)
	check(line[0] == "NO LIMITE" and line[1] == HUD.CORAL, "limitador vence o veredito: " + str(line))
	line = hud.message(false, .3)
	check(line[0] == "TROCA IDEAL" and line[1] == HUD.AMBER, "fora da faixa o veredito positivo aparece em âmbar")
	hud.feedback = "Adiantou"
	line = hud.message(false, .3)
	check(line[0] == "ADIANTOU" and line[1] == HUD.CORAL, "veredito negativo aparece em coral")
	hud._shift_active = true
	line = hud.message(false, .3)
	check(line[0] == "ADIANTOU", "durante a troca o veredito recém-dado fica visível")
	hud._shift_active = false
	hud.feedback = ""
	hud.gear = 6
	line = hud.message(false, .995)
	check(line[0] == "ÚLTIMA MARCHA", "na última marcha não pede troca nem acusa limite")
	line = hud.message(true, .55)
	check(line[0] == "GIRO IDEAL" and line[1] == HUD.AMBER, "preparação no centro da faixa")
	line = hud.message(true, .9)
	check(line[0] == "ALIVIE O ACELERADOR" and line[1] == HUD.CORAL, "preparação acima da faixa alerta em coral")
	hud.free()

	preload("res://runtime/Localization.gd").install()
	var old_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	for text in ["ACELERAR", "ESPAÇO", "TROCAR", "ABANDONAR", "PAUSA", "SEM NITRO", "NITRO", "MARCHA", "TEMPO",
			"1º / 2", "2º / 2", "LADO A LADO", "ACELERE ATÉ A FAIXA", "ALIVIE O ACELERADOR", "SEGURE O GIRO",
			"GIRO IDEAL", "TROCANDO", "ÚLTIMA MARCHA", "NO LIMITE", "TROQUE AGORA", "PREPARE A TROCA", "FREANDO",
			"LARGADA IDEAL", "BOA LARGADA", "PATINOU", "GIRO BAIXO", "TROCA IDEAL", "BOA TROCA", "ADIANTOU", "ATRASOU",
			"ARRANCADA · 800 M", "NOITE DE ACERTO · 2/3", "DESAFIO · LÍVIA"]:
		english(text)
	# Objetivos ao vivo dos desafios, formatados pelo controlador real.
	var challenge := CHALLENGE.new()
	var telemetry := TELEMETRY.new()
	challenge._telemetry = telemetry
	challenge._reference_seconds = 12.345
	telemetry.first60_seconds = 4.0
	telemetry.spin60_seconds = .5
	telemetry.tail_entry_speed = 60.0
	telemetry.tail_min_speed = 57.0
	for launch in ["", "BOA LARGADA", "GIRO BAIXO"]:
		telemetry.launch = launch
		for key in ["digo:0", "digo:1", "raul:0", "raul:1", "livia:0", "livia:1", "jessica:0", "jessica:1",
				"nadir:0", "nadir:1", "rauhz:0", "rauhz:1"]:
			challenge._armed = {"rival_id":key.get_slice(":", 0), "step":int(key.get_slice(":", 1))}
			var status := challenge.live_status()
			check(not status.is_empty(), "objetivo ao vivo existe para " + key)
			english(status)
	challenge.free()
	# Resultado: as mesmas composições que DesertDragResults desenha.
	for text in ["VER PASSAGEM", "VER RESULTADO", "SUA PASSAGEM", "LARGADA IDEAL · %s · nitro 1.4 s" % String(TranslationServer.translate("%d boas trocas")) % 4,
			"BOA LARGADA · %s" % String(TranslationServer.translate("%d boas / %d erros")) % [3, 1],
			"Limitador %.2f s · nitro %.2f s · máxima %.0f km/h" % [.42, 1.3, 211.0],
			"%.3f s %s" % [.819, TranslationServer.translate("À FRENTE")], "%.3f s %s" % [.2, TranslationServer.translate("ATRÁS")],
			"Compare as parciais com outra passada usando o mesmo acerto.", "Prepare mais giro antes do verde.",
			"Solte um pouco o acelerador antes do verde.", "Troque dentro da faixa âmbar para manter o motor cheio.",
			"Antecipe a próxima marcha antes de segurar o limitador.", "Experimente mais aderência para aproveitar a força na saída.",
			"REPETIR NOITE", "VER A NOITE", "PRÓXIMA PROVA", "REPETIR PROVA", "VER DESAFIOS", "NOITE VENCIDA", "NOITE CONCLUÍDA",
			"PASSAGEM VENCIDA", "PASSAGEM CONCLUÍDA", "PEÇA CONQUISTADA", "PROVA CUMPRIDA", "TENTE OUTRO ACERTO",
			"SEM PONTOS NO RANKING", "RIVAL NÃO COMPLETOU"]:
		english(text)
	# O português continua a fonte: nada disso pode mudar a tela em pt_BR.
	TranslationServer.set_locale("pt_BR")
	check(String(TranslationServer.translate("ESPAÇO")) == "ESPAÇO", "pt_BR mantém ESPAÇO")
	check(String(TranslationServer.translate("1º / 2")) == "1º / 2", "pt_BR mantém a posição")
	check(String(TranslationServer.translate("Trocas boas 1 / 2 · erros 0")) == "Trocas boas 1 / 2 · erros 0", "pt_BR mantém o objetivo")
	TranslationServer.set_locale(old_locale)
	print("DRAG_HUD_PRESENTATION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

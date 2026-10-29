extends SceneTree
## Contrato dos bancos de névoa (FogBanks): quando aparecem, como andam com o vento e quando somem.
## Não abre o mundo: o nó solto, como test_wind_field.
const FOG := preload("res://runtime/atmosphere/FogBanks.gd")
var _failures := 0
var _checks := 0

func _initialize() -> void:
	create_timer(20).timeout.connect(func(): quit(3))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FOG_BANKS falhou: ", label)

func run() -> void:
	# Quantidade: (hora, chuva, nuvens, litoral, serra, frente fria).
	var noon_clear := FOG.amount_for(.5, 0, 0, 1, 0, 0)
	var dawn := FOG.amount_for(.26, 0, 0, 1, 0, 0)
	var storm := FOG.amount_for(.5, 1, 1, 1, 0, 0)
	var drizzle := FOG.amount_for(.5, .22, .72, 1, 0, 0)
	var desert_storm := FOG.amount_for(.26, 1, 1, 0, 0, 0)
	var serra_front := FOG.amount_for(.5, 0, 0, 0, 1, 1)
	var serra_noon := FOG.amount_for(.5, 0, 0, 0, 1, 0)
	check(noon_clear < .01, "meio-dia limpo com névoa: %s" % noon_clear)
	check(dawn > .6, "madrugada no litoral sem bruma: %s" % dawn)
	check(storm > .6 and drizzle > .2 and drizzle < storm, "chuva sem névoa ou garoa > tempestade: %s / %s" % [drizzle, storm])
	check(desert_storm < .001, "deserto com névoa: %s" % desert_storm)
	check(serra_front > .6 and serra_noon < .01, "serra: frente %s, meio-dia %s" % [serra_front, serra_noon])
	check(FOG.amount_for(1.26, 0, 0, 1, 0, 0) == dawn, "hora fora de 0..1 muda a névoa")

	var fog := FOG.new()
	root.add_child(fog)
	check(fog.planes.size() == FOG.LAYERS.size() and not fog.visible, "camadas ou visibilidade inicial")
	# Primeira condição vale na hora (carregar de madrugada já mostra a névoa).
	fog.set_conditions(.8, Color(.5, .55, .6), false)
	check(is_equal_approx(fog.amount, .8), "primeira condição não entrou na hora: %s" % fog.amount)
	var wind := Vector3(8, 0, -2)
	var focus := Vector3(500, 3, -200)
	var seconds := 2.0
	for i in 120: fog.advance(seconds/120.0, wind, focus)
	check(fog.visible, "névoa não apareceu")
	# Desenho anda a favor do vento: o arrasto do shader é -v·t (reduzido ao período).
	var expected := Vector2(fposmod(-wind.x*FOG.DRIFT*seconds, FOG.WRAP_METRES), fposmod(-wind.z*FOG.DRIFT*seconds, FOG.WRAP_METRES))
	check(fog.drift.distance_to(expected) < .01, "arrasto %s, esperado %s" % [fog.drift, expected])
	check(fog.global_position.is_equal_approx(focus), "planos não seguem o foco: %s" % fog.global_position)
	var low: float = fog.planes[0].get_instance_shader_parameter("opacity")
	check(low > .15 and fog.planes[0].position.y < fog.planes[2].position.y, "camada baixa fraca ou fora de ordem: %s" % low)
	# Período do shader: CELL*PERIOD. Mudar um sem o outro faz o desenho pular na volta.
	var source := FileAccess.get_file_as_string("res://runtime/atmosphere/fog_banks.gdshader")
	check("CELL = 18.0" in source and "PERIOD = 64.0" in source and is_equal_approx(FOG.WRAP_METRES, 18.0*64.0), "período do shader descasou do arrasto")
	# Pulo de 1 m não sacode a névoa; teleporte de 40 m reposiciona.
	fog.advance(1.0/60.0, wind, focus+Vector3.UP)
	check(fog.global_position.y < focus.y+.1, "pulo levou a névoa junto: %s" % fog.global_position.y)
	fog.advance(1.0/60.0, wind, focus+Vector3.UP*40)
	check(is_equal_approx(fog.global_position.y, focus.y+40), "teleporte deixou a névoa para trás")
	# Interior esconde no mesmo quadro; tempo limpo esvai devagar.
	fog.set_conditions(.8, Color.WHITE, true)
	fog.advance(1.0/60.0, wind, focus)
	check(not fog.visible, "névoa dentro de casa")
	fog.set_conditions(0.0, Color.WHITE, false)
	fog.advance(1.0, wind, focus)
	check(fog.visible and fog.amount > .5, "névoa sumiu de repente: %s" % fog.amount)
	for i in 60: fog.advance(1.0, wind, focus)
	check(not fog.visible, "névoa não esvaiu no tempo limpo: %s" % fog.amount)
	# Pré-aquecimento força tudo; ao soltar, a próxima condição vale na hora.
	fog.force = true
	fog.advance(1.0/60.0, wind, focus)
	check(fog.visible and fog.amount == 1.0, "pré-aquecimento não desenhou")
	fog.force = false
	fog.set_conditions(0.0, Color.WHITE, false)
	fog.advance(1.0/60.0, wind, focus)
	check(not fog.visible, "névoa forçada ficou depois da cortina: %s" % fog.amount)
	fog.free()
	if _failures > 0:
		printerr("FOG_BANKS %d de %d verificações falharam" % [_failures, _checks])
		quit(1)
		return
	print("FOG_BANKS %d verificações: quando aparece, vento, foco, alturas, período, interior e pré-aquecimento" % _checks)
	print("FOG_BANKS madrugada %.2f, garoa %.2f, tempestade %.2f, serra na frente %.2f" % [dawn, drizzle, storm, serra_front])
	quit(0)

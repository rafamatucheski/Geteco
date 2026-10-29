extends SceneTree
## Contrato dos detritos do vento: papel e folhas (WindDebris) e a areia do deserto
## (DesertAmbientLife) seguindo o WindField. Não abre o mundo.
const DEBRIS := preload("res://runtime/atmosphere/WindDebris.gd")
const WIND := preload("res://runtime/atmosphere/WindField.gd")
const AMBIENT := preload("res://world/desert/DesertAmbientLife.gd")
var _failures := 0
var _checks := 0

func _initialize() -> void:
	create_timer(30).timeout.connect(func(): quit(3))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("WIND_DEBRIS falhou: ", label)

func run() -> void:
	# Quantidade: (rajada, m/s, deserto).
	var calm := DEBRIS.amount_for(0.0, 2.3, 0)
	var clear_gust := DEBRIS.amount_for(.35, 3.2, 0)
	var storm_gust := DEBRIS.amount_for(.95, 10.0, 0)
	check(calm < .001, "papel voando no calmo: %s" % calm)
	check(clear_gust > .1 and clear_gust < storm_gust and storm_gust > .95, "rajada não levanta: %s / %s" % [clear_gust, storm_gust])
	check(DEBRIS.amount_for(.95, 10.0, 1.0) == 0.0, "papel no deserto")
	check(DEBRIS.amount_for(.95, 1.0, 0) < .001, "rajada sem vento levanta papel")

	var debris := DEBRIS.new()
	root.add_child(debris)
	check(debris.emitter.process_material.anim_offset_max == 1.0 and debris.emitter.draw_pass_1.material.particles_anim_h_frames == 4, "atlas sem sorteio de quadro")
	var focus := Vector3(300, 2, -80)
	var wind := Vector3(8, 0, -2)
	debris.set_conditions(0.0, false)
	debris.advance(wind, .9, focus)
	var direction := wind.normalized()
	check(debris.visible and debris.emitter.emitting and debris.ratio > .9, "rajada de tempestade sem papel: %s" % debris.ratio)
	check(debris.process.direction.x > .9 and debris.process.direction.y > 0, "papel não segue o vento: %s" % debris.process.direction)
	check(debris.emitter.global_position.distance_to(focus - direction*DEBRIS.UPWIND + Vector3.UP*DEBRIS.LIFT) < .01, "emissor fora da barlavento: %s" % debris.emitter.global_position)
	check(debris.process.initial_velocity_max > wind.length(), "papel mais lento que o vento")
	debris.advance(wind, 0.0, focus)
	check(not debris.emitter.emitting, "calmo continua soltando papel")
	debris.set_conditions(0.0, true)
	debris.advance(wind, .9, focus)
	check(not debris.visible and not debris.emitter.emitting, "papel dentro de casa")
	debris.set_conditions(1.0, false)
	debris.advance(wind, .9, focus)
	check(not debris.emitter.emitting, "papel no deserto")
	# Pré-aquecimento solta tudo mesmo sem vento e com abrigo.
	debris.set_conditions(0.0, true)
	debris.force = true
	debris.advance(Vector3.ZERO, 0.0, focus)
	check(debris.visible and debris.emitter.emitting and debris.ratio == 1.0, "pré-aquecimento não desenhou")
	debris.force = false
	debris.advance(Vector3.ZERO, 0.0, focus)
	check(not debris.visible, "papel forçado ficou depois da cortina")
	debris.free()

	# Areia do deserto: direção e velocidade do vento compartilhado; sem ele, o desenho antigo.
	var ambient := AMBIENT.new()
	root.add_child(ambient)
	var field := WIND.new()
	field.seed_with(5)
	for i in 120: field.advance(1.0/60.0, Vector2(22, 3), 0.0)
	WIND.current = field
	ambient.set_focus(Vector3(-200, 0, -900))
	ambient._tick = 1.0
	ambient._physics_process(.1)
	var sand := ambient._wind.process_material as ParticleProcessMaterial
	var desert_dir := field.velocity.normalized()
	check(Vector2(sand.direction.x, sand.direction.z).normalized().dot(Vector2(desert_dir.x, desert_dir.z)) > .99, "areia fora do vento: %s × %s" % [sand.direction, desert_dir])
	check(sand.initial_velocity_min > 1.0 and sand.initial_velocity_max < 4.5, "areia rápida ou lenta demais: %s..%s" % [sand.initial_velocity_min, sand.initial_velocity_max])
	var upwind: Vector3 = ambient._wind.global_position - Vector3(-200, 0, -900)
	check(Vector2(upwind.x, upwind.z).dot(Vector2(desert_dir.x, desert_dir.z)) < -9.0, "areia não nasce a barlavento: %s" % upwind)
	WIND.current = null
	ambient._tick = 1.0
	ambient._physics_process(.1)
	check(ambient._wind.global_position.x < -200.0 and ambient._wind.global_position.z > -900.0, "sem vento compartilhado a areia mudou de lugar")
	ambient.free()

	if _failures > 0:
		printerr("WIND_DEBRIS %d de %d verificações falharam" % [_failures, _checks])
		quit(1)
		return
	print("WIND_DEBRIS %d verificações: rajada, deserto, abrigo, barlavento, pré-aquecimento e areia" % _checks)
	print("WIND_DEBRIS fração: calmo %.2f, rajada de céu limpo %.2f, tempestade %.2f" % [calm, clear_gust, storm_gust])
	quit(0)

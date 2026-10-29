extends SceneTree
## Contrato do vento compartilhado (WindField) e da chuva levada por ele.
## Não abre o mundo: mede o vento sozinho e os emissores soltos, como test_drag_rain.
const WIND := preload("res://runtime/atmosphere/WindField.gd")
const RAIN := preload("res://runtime/atmosphere/CoastalRainPresentation.gd")
const HARBOR_WIND := Vector2(11, -3)
var _failures := 0
var _checks := 0

func _initialize() -> void:
	create_timer(20).timeout.connect(func(): quit(3))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("WIND_FIELD falhou: ", label)

## Dois minutos de vento a 60 Hz; devolve rajada mínima/máxima, velocidade média e máxima e o vento médio.
func sample(storm: float, seed_value: int, profile := HARBOR_WIND) -> Dictionary:
	var field := WIND.new()
	field.seed_with(seed_value)
	var low := 1.0
	var high := 0.0
	var speed_sum := 0.0
	var speed_max := 0.0
	var mean := Vector3.ZERO
	var steps := 120*60
	for i in steps:
		field.advance(1.0/60.0, profile, storm)
		if i < 600: continue
		low = minf(low, field.gust)
		high = maxf(high, field.gust)
		speed_sum += field.velocity.length()
		speed_max = maxf(speed_max, field.velocity.length())
		mean += field.velocity
	return {"low": low, "high": high, "speed": speed_sum/float(steps-600), "max": speed_max, "mean": mean/float(steps-600)}

func run() -> void:
	var drizzle := sample(.22, 7)
	var storm := sample(1.0, 7)
	# Rajadas existem e voltam ao calmo; tempestade sopra mais que garoa.
	check(drizzle.high > .12 and drizzle.low < .03, "garoa sem rajada e calmaria: %s" % drizzle)
	check(storm.high > drizzle.high, "tempestade não supera a garoa: %s × %s" % [storm.high, drizzle.high])
	check(storm.speed > drizzle.speed*1.3, "velocidade média da tempestade baixa: %s × %s" % [storm.speed, drizzle.speed])
	# Porto (11, -3) km/h: vento médio a favor de +x e limitado (m/s), sem virar furacão.
	var harbor_dir := Vector3(HARBOR_WIND.x, 0, HARBOR_WIND.y).normalized()
	check(storm.mean.normalized().dot(harbor_dir) > .95, "direção média fora do perfil: %s" % storm.mean)
	check(storm.max < 13.0 and drizzle.max < 6.5, "vento acima do teto: %s / %s m/s" % [storm.max, drizzle.max])
	check(drizzle.speed > 2.0, "garoa sem vento nenhum: %s m/s" % drizzle.speed)
	# Perfil que passa pelo zero (porto→costa) não zera nem vira a direção de repente.
	var field := WIND.new()
	field.seed_with(3)
	field.advance(.1, HARBOR_WIND, .5)
	var before := field.direction
	field.advance(.1, Vector2(.2, .1), .5)
	check(field.direction.dot(before) > .9 and field.direction.is_normalized(), "direção pulou no vento nulo: %s" % field.direction)

	# Chuva: com o vento ligado a gota deita na velocidade e a cortina é empurrada.
	var emitter := GPUParticles3D.new()
	emitter.emitting = false
	emitter.process_material = ParticleProcessMaterial.new()
	(emitter.process_material as ParticleProcessMaterial).gravity = RAIN.GRAVITY
	var quad := QuadMesh.new()
	quad.material = StandardMaterial3D.new()
	quad.material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	emitter.draw_pass_1 = quad
	root.add_child(emitter)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.look_at_from_position(Vector3(0, 20, 20), Vector3.ZERO)
	WIND.enabled = true
	RAIN.configure(emitter)
	check(emitter.transform_align == GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY, "gota não alinha à velocidade")
	check(quad.material.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED, "billboard da material desfaz o alinhamento")
	var process := emitter.process_material as ParticleProcessMaterial
	emitter.global_position = Vector3(0, 10, 0)
	RAIN.blow(emitter, Vector3(8, 0, -2), camera)
	check(process.direction.x > .2 and process.direction.y < -.9, "direção não segue o vento: %s" % process.direction)
	check(process.gravity.x > 0 and is_equal_approx(process.gravity.y, RAIN.GRAVITY.y), "empurrão errado: %s" % process.gravity)
	check(emitter.global_position.x < 0, "volume não nasce a barlavento: %s" % emitter.global_position)
	# Vista de cima a gota encurta; o traço compensa sem passar do teto.
	RAIN.apply(emitter, 1.0, 1.0, camera, Vector3(8, 0, -2))
	check(quad.size.y > 1.12 and quad.size.y <= 1.6, "traço sem compensação: %s" % quad.size)
	# Câmera da arrancada dirige a própria chuva: o empurrão do vento sai.
	camera.set_meta("drag_precipitation", true)
	var drag_direction := process.direction
	RAIN.blow(emitter, Vector3(8, 0, -2), camera)
	check(process.gravity == RAIN.GRAVITY and process.direction == drag_direction, "vento briga com a arrancada")
	camera.remove_meta("drag_precipitation")

	# GETECO_WIND_GUSTS=0: emissor novo fica como antes (billboard, sem alinhamento).
	WIND.enabled = false
	var old := GPUParticles3D.new()
	old.process_material = ParticleProcessMaterial.new()
	old.draw_pass_1 = QuadMesh.new()
	old.draw_pass_1.material = StandardMaterial3D.new()
	old.draw_pass_1.material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	RAIN.configure(old)
	check(old.transform_align == GPUParticles3D.TRANSFORM_ALIGN_DISABLED and old.draw_pass_1.material.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED, "interruptor desligado mudou a chuva")
	RAIN.apply(old, .5, 1.0, camera)
	check(old.draw_pass_1.size.is_equal_approx(Vector2(lerpf(.05, .072, .5), lerpf(.56, 1.12, .5))), "tamanho antigo mudou: %s" % old.draw_pass_1.size)
	WIND.enabled = true
	old.free()
	emitter.free()
	camera.free()
	if _failures > 0:
		printerr("WIND_FIELD %d de %d verificações falharam" % [_failures, _checks])
		quit(1)
		return
	print("WIND_FIELD %d verificações: rajadas, teto, direção, chuva alinhada, arrancada e interruptor" % _checks)
	print("WIND_FIELD garoa: média %.1f m/s, máx %.1f m/s, rajada até %.2f; tempestade: média %.1f m/s, máx %.1f m/s, rajada até %.2f" % [
		drizzle.speed, drizzle.max, drizzle.high, storm.speed, storm.max, storm.high])
	quit(0)

extends RefCounted
## Presentation of the existing local rain volume. Weather still owns emission,
## regional exposure, shelter visibility, wind, coverage and particle lifetime.
## Surface spray is bounded separately by RainGroundPresentation.
const MAX_DROPS := 1400
const WIND := preload("res://runtime/atmosphere/WindField.gd")
## Queda média das gotas (velocidade inicial 12–18 m/s) e a gravidade autorada.
const FALL_SPEED := 15.0
const GRAVITY := Vector3(0, -5, 0)
## Parte do vento sai na velocidade inicial; o resto empurra a gota em queda, e é
## esse empurrão que faz a cortina inteira balançar junto quando a rajada chega.
const LAUNCH := .6
const PUSH := .8
## As gotas caem ~10 m em ~0,6 s e andam ~metade do vento nesse tempo: nascem a
## barlavento para a chuva cair sobre a vista, não ao lado dela.
const DRIFT_SECONDS := .4

static func configure(emitter: GPUParticles3D) -> void:
	emitter.amount = MAX_DROPS
	# Slightly longer than the old half-metre marks: the elevated gameplay camera
	# should read falling rain without turning every drop into a thick white line.
	(emitter.draw_pass_1 as QuadMesh).size = Vector2(.065, .72)
	if WIND.enabled:
		# Com vento a gota precisa deitar no sentido em que anda; o billboard da
		# material a deixava sempre em pé na tela. É a mesma variante que a câmera
		# da arrancada já usa, e o RainPrewarm a desenha sob a cortina.
		(emitter.draw_pass_1.material as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		emitter.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY

static func apply(emitter: GPUParticles3D, strength: float, daylight: float, camera: Camera3D, wind := Vector3.ZERO) -> void:
	var rain := clampf(strength, 0.0, 1.0)
	var light := clampf(daylight, 0.0, 1.0)
	var material := emitter.draw_pass_1.material as StandardMaterial3D
	# Unshaded drops must not glow white at night. Keep a cool, subdued silver
	# against both the dark road and the pale concrete, with storm density owned
	# by Weather.amount_ratio (drizzle keeps its original active drop count).
	var tint := Color("708692").lerp(Color("b0bfc5"), light)
	tint.a = lerpf(.32, .66, rain) * lerpf(.72, 1.0, light)
	material.albedo_color = tint
	# The low race camera has its own wind/velocity alignment and drop scale.
	if is_instance_valid(camera) and camera.get_meta("drag_precipitation", false) == true:
		return
	var size := Vector2(lerpf(.05, .072, rain), lerpf(.56, 1.12, rain))
	if WIND.enabled:
		# Alinhada à velocidade, a gota vista de cima encurta; compensa para manter
		# o traço que o billboard dava na câmera alta do jogo.
		size.y = minf(size.y/_visible_fraction(wind, camera), 1.6)
		(emitter.draw_pass_1 as QuadMesh).size = size
		return
	(emitter.draw_pass_1 as QuadMesh).size = size
	var process := emitter.process_material as ParticleProcessMaterial
	var gust := sin(Time.get_ticks_msec()*.0007)*.035*rain
	process.direction = Vector3(lerpf(.10,.24,rain)+gust,-1,.05).normalized()

## A cada quadro, depois de PrecipitationCoverage.follow posicionar o volume.
static func blow(emitter: GPUParticles3D, wind: Vector3, camera: Camera3D) -> void:
	var process := emitter.process_material as ParticleProcessMaterial
	if is_instance_valid(camera) and camera.get_meta("drag_precipitation", false) == true:
		# DragRaceRain dirige a direção e a posição; só não pode herdar o empurrão.
		process.gravity = GRAVITY
		return
	process.direction = Vector3(wind.x*LAUNCH, -FALL_SPEED, wind.z*LAUNCH).normalized()
	process.gravity = Vector3(wind.x*PUSH, GRAVITY.y, wind.z*PUSH)
	emitter.global_position -= Vector3(wind.x, 0.0, wind.z)*DRIFT_SECONDS

static func _visible_fraction(wind: Vector3, camera: Camera3D) -> float:
	if not is_instance_valid(camera): return 1.0
	var streak := Vector3(wind.x*(LAUNCH+PUSH*.3), -FALL_SPEED, wind.z*(LAUNCH+PUSH*.3)).normalized()
	var facing := streak.dot(-camera.global_basis.z)
	return maxf(sqrt(maxf(1.0-facing*facing, 0.0)), .55)

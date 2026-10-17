extends RefCounted
## Presentation of the existing local rain volume. Weather still owns emission,
## regional exposure, shelter visibility, wind, coverage and particle lifetime.
## Surface spray is bounded separately by RainGroundPresentation.
const MAX_DROPS := 1400

static func configure(emitter: GPUParticles3D) -> void:
	emitter.amount = MAX_DROPS
	# Slightly longer than the old half-metre marks: the elevated gameplay camera
	# should read falling rain without turning every drop into a thick white line.
	(emitter.draw_pass_1 as QuadMesh).size = Vector2(.065, .72)

static func apply(emitter: GPUParticles3D, strength: float, daylight: float, camera: Camera3D) -> void:
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
	(emitter.draw_pass_1 as QuadMesh).size = Vector2(lerpf(.05, .072, rain), lerpf(.56, 1.12, rain))
	var process := emitter.process_material as ParticleProcessMaterial
	var gust := sin(Time.get_ticks_msec()*.0007)*.035*rain
	process.direction = Vector3(lerpf(.10,.24,rain)+gust,-1,.05).normalized()

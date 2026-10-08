extends RefCounted
## Reuse the normal rain emitter; side-camera presentation owns no extra particles.
var _active := false
var _clock := 0.0
var _direction := Vector3.ZERO
var _alignment := 0
var _billboard := 0
var _drop_size := Vector2.ZERO

func apply(emitter: GPUParticles3D, camera: Camera3D, delta: float, storm: bool) -> void:
	var local: bool = is_instance_valid(camera) and camera.get_meta("drag_precipitation",false)==true
	var process := emitter.process_material as ParticleProcessMaterial
	var material := emitter.draw_pass_1.material as StandardMaterial3D
	if local and not _active:
		_direction = process.direction
		_alignment = emitter.transform_align
		_billboard = material.billboard_mode
		_drop_size = emitter.draw_pass_1.size
		_active = true
	if not local:
		if _active:
			process.direction = _direction
			emitter.transform_align = _alignment as GPUParticles3D.TransformAlign
			material.billboard_mode = _billboard as BaseMaterial3D.BillboardMode
			emitter.draw_pass_1.size = _drop_size
			_active = false
		return
	_clock += delta
	# Wind is world-space: the moving perspective naturally changes its screen angle.
	# Material billboarding would undo the velocity alignment, so use the emitter's.
	material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	emitter.draw_pass_1.size = Vector2(.035,.34)
	emitter.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var gust := .06*sin(_clock*.63)+.025*sin(_clock*1.7)
	process.direction = Vector3((.42 if storm else .16)+gust,-1,.08).normalized()
	# The normal emitter sits around the driver, outside this low side camera.
	# Keep rain in the foreground without increasing its 600-particle budget.
	emitter.global_position = camera.global_position-camera.global_basis.z*12.0+Vector3.UP*8.0

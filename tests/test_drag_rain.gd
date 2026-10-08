extends SceneTree
func _initialize() -> void:
	create_timer(10).timeout.connect(func(): quit(3))
	run.call_deferred()

func run() -> void:
	var rain := preload("res://runtime/atmosphere/DragRaceRain.gd").new()
	var emitter := GPUParticles3D.new()
	emitter.emitting=false
	emitter.process_material=ParticleProcessMaterial.new()
	emitter.draw_pass_1=QuadMesh.new()
	emitter.draw_pass_1.material=StandardMaterial3D.new()
	emitter.draw_pass_1.material.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
	var original: Vector3=emitter.process_material.direction
	var original_size: Vector2=emitter.draw_pass_1.size
	root.add_child(emitter)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.set_meta("drag_precipitation",true)
	rain.apply(emitter,camera,.016,false)
	var gentle: Vector3=emitter.process_material.direction
	assert(emitter.transform_align==GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY)
	assert(emitter.draw_pass_1.material.billboard_mode==BaseMaterial3D.BILLBOARD_DISABLED)
	assert(emitter.draw_pass_1.size.x<.07)
	rain.apply(emitter,camera,.016,true)
	assert(emitter.process_material.direction.x>gentle.x)
	assert(emitter.process_material.direction.y<-.8)
	camera.remove_meta("drag_precipitation")
	rain.apply(emitter,camera,.016,true)
	assert(emitter.process_material.direction==original)
	assert(emitter.transform_align==GPUParticles3D.TRANSFORM_ALIGN_DISABLED)
	assert(emitter.draw_pass_1.material.billboard_mode==BaseMaterial3D.BILLBOARD_ENABLED)
	assert(emitter.draw_pass_1.size==original_size)
	print("DRAG_RAIN 9 assertions passed: velocity alignment, wind, restoration")
	emitter.free()
	camera.free()
	quit()

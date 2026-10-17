extends SceneTree
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60,1,60)
	collision.shape = box
	ground.position.y = -.5
	ground.add_child(collision)
	stage.add_child(ground)
	var effects := preload("res://runtime/atmosphere/RainGroundPresentation.gd").new()
	stage.add_child(effects)
	await physics_frame
	effects.set_conditions(Vector3.ZERO,1.0,1.0,false)
	var before: int = effects.probe_count
	effects._physics_process(.5)
	check(effects.probe_count-before<=2,"A frame hitch cannot create a burst of surface queries")
	await create_timer(.35).timeout
	check(effects.mist.visible and effects.mist.emitting,"Storm mist appears over solid ground")
	check(effects.rings.multimesh.instance_count==128 and effects.drops.multimesh.instance_count==128 and effects.mist.amount==24,"Surface effects have fixed budgets")
	check(effects._cursor>0,"Rain impacts are emitted on physical ground")
	var index: int = (effects._cursor+127)%128
	check(effects.rings.multimesh.get_instance_custom_data(index)==effects.drops.multimesh.get_instance_custom_data(index),"Drop and impact share the same landing time")
	var anchored: Transform3D = effects.rings.multimesh.get_instance_transform(index)
	effects.set_conditions(Vector3(1,0,0),1.0,1.0,false)
	check(effects.rings.multimesh.get_instance_transform(index)==anchored,"Existing contacts stay fixed when the player moves")
	effects.set_conditions(Vector3.ZERO,1.0,1.0,true)
	check(not effects.mist.visible and not effects.rings.visible,"Shelter immediately hides surface effects")
	effects.set_conditions(Vector3(100,0,100),1.0,1.0,false)
	await create_timer(.2).timeout
	check(not effects.mist.visible,"No floating mist when ground is absent")
	ground.position.y = 2.5
	await physics_frame
	effects.set_conditions(Vector3.ZERO,1.0,1.0,false)
	await create_timer(.2).timeout
	check(not effects.mist.visible,"A roof above the player cannot become a ground mist layer")
	check(effects.roof_impact_count>0,"Rain contacts elevated roofs instead of rejecting them")
	effects.set_conditions(Vector3.ZERO,0.0,1.0,false)
	check(not effects.is_processing() and not effects.is_physics_processing(),"Dry weather stops work")
	stage.queue_free()
	await process_frame
	print("RAIN_GROUND failures=",failures)
	quit(0 if failures.is_empty() else 1)

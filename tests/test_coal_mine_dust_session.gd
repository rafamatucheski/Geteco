extends "res://tests/test_mining_session.gd"
## One Main startup reuses the complete coal discovery/save/return route.
## Observe production region hooks at the existing photo milestones; this test
## never calls dust.set_focus/suspend itself and does not certify visual quality.
var _dust_stages: Array[Dictionary]=[]

func photo(label: String) -> void:
	if label=="secret-entrance-day": await _dust_stage("exterior-day",true)
	elif label=="coal-before": await _dust_stage("interior",false)
	await super.photo(label)

func _dust_stage(label: String, expected_active: bool) -> void:
	# The region controller publishes activity at 0.3 s intervals; allow its
	# real update and the emitter's gentle activation to complete naturally.
	await create_timer(1.5).timeout
	var dust: Node3D=world.production.region.get("mining_dust")
	if not check(is_instance_valid(dust),"mine dust resident exists at "+label): return
	var data: Dictionary=dust.debug_snapshot()
	_dust_stages.append({"stage":label,"place":world.session.state.place_id,"actor_position":world.player.global_position,"snapshot":data})
	check(bool(data.active)==expected_active and bool(data.processing)==expected_active and bool(data.visible)==expected_active,"production dust activity follows location at "+label)
	var gpu_matches: bool = not data.sources.is_empty()
	for source: Dictionary in data.sources:
		gpu_matches=gpu_matches and bool(source.emitting)==expected_active
		gpu_matches=gpu_matches and is_equal_approx(float(source.speed_scale),1.0 if expected_active else 0.0)
	check(gpu_matches,"dust GPU emission and simulation follow location at "+label)
	if expected_active:
		check(float(data.strength)>.8 and data.configured,"exterior dust resumes after its smooth density ramp at "+label)
		check(data.ground_y.x<-20.0 and data.ground_y.y<-20.0,"dust sources follow the excavated floor instead of desert datum at "+label)
	else:
		check(world.session.state.place_id==COAL.PLACE_ID and float(data.strength)==0.0,"interior suspends exterior dust without ambient leakage")

func machines() -> void:
	# Parent flow has exited/reentered/exited the actual coal mine by this point.
	await _dust_stage("exterior-return-night",true)
	check(_dust_stages.size()==3,"one Main visit covers dust admission, interior suspension and return")
	await photo("dust-return-night")
	if "--with-machines" in OS.get_cmdline_user_args(): await super.machines()

func finish(code: int) -> void:
	if not output.is_empty():
		FileAccess.open(output.path_join("mining-dust-lifecycle.json"),FileAccess.WRITE).store_string(JSON.stringify({"stages":_dust_stages,"note":"Production DesertRuntime activity hooks and real room transitions. No manual dust activation. Visual density, temporal stability and comparative performance remain separate rendered gates."},"\t"))
	super.finish(code)

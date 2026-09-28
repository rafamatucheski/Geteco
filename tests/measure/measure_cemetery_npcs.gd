extends "res://tests/measure/measure_urban_operations.gd"

func run() -> void:
	await super.run()
	if not is_instance_valid(world) or started == 0: return
	world.session.urban_operations.cemetery.refresh_context()
	world.session.urban_operations.cemetery.register_synthetic_case("benchmark:funeral", "Visitante")
	# Force the fixture before sampling; regular gameplay admission waits offscreen.
	world.session.urban_operations.cemetery._start_trip("benchmark:funeral")
	assert(is_instance_valid(world.session.urban_operations.cemetery.mortician))

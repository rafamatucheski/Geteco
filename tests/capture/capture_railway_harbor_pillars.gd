extends "res://tests/measure/measure_railway.gd"

func capture(id: String) -> void:
	if id != "station": return
	for station_id in ["harbor_central", "harbor_north"]:
		if not await prepare_station(station_id):
			push_error("Could not reach Harbor railway review")
			quit(1)
			return
		var center := Vector3(210, 1, 25) if station_id == "harbor_central" else Vector3(346, 1, -155)
		world.camera.set_process(false)
		world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		world.camera.size = 125
		world.camera.global_position = center + Vector3(40,90,85)
		world.camera.look_at(center)
		await create_timer(10).timeout
		await super.capture(station_id + "-streets")

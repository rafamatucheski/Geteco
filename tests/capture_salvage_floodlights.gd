extends "res://tests/test_salvage_geometry.gd"
const LIGHT_REVIEW := "D:/geteco/artifacts/neco-floodlights-0910/"

func shot(label: String) -> void:
	if label!="01_patio": return
	var lights: Node=yard.art.get_node("IndustrialFloodlights")
	var weather:=get_first_node_in_group("day_night_manager")
	weather.is_dynamic_time=false
	weather.weather_state=0
	weather.time_of_day=.5
	weather._update_lighting()
	check(not lights.is_lit,"Industrial floodlights switch off during the day")
	check(lights._spots.size()==2 and lights._glows.size()==4,"Two industrial masts with twin reflectors")
	await capture_lights("day")
	weather.time_of_day=.0
	weather._update_lighting()
	check(lights.is_lit and lights._pools[0].visible and lights._spots[1].visible,"Night enables both 2D and 3D yard lighting")
	await capture_lights("night")
	lights.set_lit(false)
	await capture_lights("night_unlit")
	weather.time_of_day=.5
	weather.weather_state=2
	weather._update_lighting()
	# Night -> storm stays dark, so use an explicit daylight transition first.
	weather.weather_state=0
	weather._update_lighting()
	weather.weather_state=2
	weather._update_lighting()
	check(lights.is_lit,"Storm darkness also enables the floodlights")
	weather.weather_state=0
	weather.time_of_day=.5
	weather._update_lighting()

func capture_lights(label: String) -> void:
	if not captures: return
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(LIGHT_REVIEW+label+".png")

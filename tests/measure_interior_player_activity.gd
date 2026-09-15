extends "res://tests/test_interior_player_movement.gd"
## Rendered A/B: reproduce the old ambient policy, then restore the fixed policy.
class LegacyActivity:
	extends "res://systems/PopulationActivity.gd"
	func _pinned(actor: Node2D, area: Rect2) -> bool:
		if actor.is_in_group("player"): return false
		return super._pinned(actor,area)
func after_checks(world):
	var player=world.get_node("Player")
	var manager=world.get_node("Interiors")
	var door=world.get_node("District/NorthFrontage2/AmmunationEntrance")
	var room=manager.ammunation_interior
	manager._on_exterior_destination_requested(door,player,door.destination_id,null,&"",room,room.spawn_point)
	world.weather.is_dynamic_time=false
	var stream=world.get_node("ContinuousWorld")
	stream.population_activity.restore_all()
	stream.population_activity=LegacyActivity.new()
	await create_timer(5).timeout
	await sample("legacy_frozen",player)
	stream.population_activity.restore_all()
	stream.population_activity=load("res://systems/PopulationActivity.gd").new()
	await create_timer(5).timeout
	await sample("fixed_active",player)
func sample(label,player):
	var samples:Array[float]=[]
	var start=Time.get_ticks_usec()
	var previous=start
	while Time.get_ticks_usec()-start<30000000:
		await process_frame
		var now=Time.get_ticks_usec()
		samples.append((now-previous)/1000.0)
		previous=now
	var elapsed=(previous-start)/1000000.0
	var trace := FileAccess.open(OS.get_temp_dir().path_join("geteco_interior_"+label+"_frames.json"),FileAccess.WRITE)
	if trace: trace.store_string(JSON.stringify(samples))
	var over33=0
	var over66=0
	for value in samples:
		if value>33.3: over33+=1
		if value>66.7: over66+=1
	samples.sort()
	print("INTERIOR_PERF ",JSON.stringify({"label":label,"seconds":elapsed,"frames":samples.size(),"fps":samples.size()/elapsed,"p50":samples[int(samples.size()*.5)],"p95":samples[int(samples.size()*.95)],"p99":samples[int(samples.size()*.99)],"max":samples[-1],"over33":over33,"over66":over66,"player_active":player.can_process(),"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"cap":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode()}))

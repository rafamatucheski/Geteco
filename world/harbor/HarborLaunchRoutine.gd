extends Node2D
const WORKER = preload("res://world/harbor/HarborDockWorker.gd")
var boats: Array[Dictionary] = []
func _ready() -> void:
	for i in 2:
		var berth := Vector2(6380,3700+i*560)
		var view = preload("res://world/mountain_pass/MountainStaticModelView.gd").new()
		view.position = berth
		view.z_index = 5
		add_child(view)
		view.build_view(preload("res://world/harbor/HarborCargoLaunchModel.gd"),16,20,Vector3.ZERO,Vector3(0,24,20))
		var worker = WORKER.new()
		worker.name = "LaunchLoader%d" % i
		worker.worker_index = i
		worker.work_points = PackedVector2Array([Vector2(6120,berth.y),Vector2(6315,berth.y)])
		worker.station_points = worker.work_points
		worker.work_route = PackedVector2Array([worker.work_points[0],Vector2(6200,berth.y),worker.work_points[1],Vector2(6200,berth.y+18)])
		worker.crate_stock = [30,0]
		add_child(worker)
		worker.crate_handled.connect(func(_point: Vector2): queue_redraw())
		boats.append({view=view,worker=worker,berth=berth,load=0,phase="loading",clock=0.0})
func game_day_seconds() -> float:
	if get_tree().get_first_node_in_group("medical_campaign_clock") != null: return 600.0
	var weather = get_node_or_null("/root/DayNightWeatherManager")
	return float(weather.day_length_seconds) if weather != null else 600.0
func _process(delta: float) -> void:
	for boat in boats:
		var worker = boat.worker
		var view = boat.view
		if boat.phase == "loading":
			if worker.crate_stock[1] > 0:
				boat.load = mini(30,boat.load+worker.crate_stock[1])
				worker.crate_stock[1] = 0
				view.model.set_load(boat.load)
				view.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
			if boat.load == 30 and worker.phase == "rest":
				boat.phase = "departing"
				view.model.rotation.y = PI
				view.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
				boat.clock = 0.0
				_configure_work(worker,boat.berth,false)
		elif boat.phase == "departing":
			boat.clock += delta
			var leg := game_day_seconds()/48.0*.2
			view.position.y = boat.berth.y+1300.0*minf(1,boat.clock/leg)
			if boat.clock >= leg:
				view.hide()
				boat.phase = "away"
				boat.clock = 0.0
		elif boat.phase == "away":
			boat.clock += delta
			if boat.clock >= game_day_seconds()/48.0*.6:
				boat.load = 0
				view.model.set_load(0)
				view.model.rotation.y = 0
				view.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
				view.show()
				boat.phase = "returning"
		elif boat.phase == "returning":
			view.position = view.position.move_toward(boat.berth,delta*1300.0/(game_day_seconds()/48.0*.2))
			if view.position.distance_to(boat.berth) < 1 and not worker.carrying:
				boat.phase = "loading"
				_configure_work(worker,boat.berth,true)
func _configure_work(worker: Node2D, berth: Vector2, loading: bool) -> void:
	worker.station_points = PackedVector2Array([Vector2(6120,berth.y),Vector2(6315 if loading else 6180,berth.y)])
	worker.work_route = PackedVector2Array([worker.station_points[0],Vector2(6160,berth.y),worker.station_points[1],Vector2(6160,berth.y+18)])
	worker.crate_stock = [30 if loading else 3,0]
	worker.source_index = 0
	worker.route_cursor = 0
	worker._set_phase("return")
	worker._pick_new_sidewalk_target()
	queue_redraw()
func _draw() -> void:
	for boat in boats:
		var worker = boat.worker
		if boat.phase == "loading":
			# Fixed transfer platform connects the pier edge to the cargo deck.
			draw_rect(Rect2(boat.berth+Vector2(-65,-12),Vector2(30,24)),Color("938b77"))
		for i in worker.crate_stock[0]:
			preload("res://world/harbor/DockCrateDrawing.gd").draw_crate(self,worker.station_points[0]+Vector2((i%5)*15-30,-float(i/5)*9-18))
		for point in worker.dropped_crates: preload("res://world/harbor/DockCrateDrawing.gd").draw_crate(self,to_local(point))

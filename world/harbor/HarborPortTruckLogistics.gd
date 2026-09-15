extends RefCounted
## One physical carrier per crane. Cargo stays aboard until a future delivery system.
const FACTORY := preload("res://emergency/ModernTrafficFactory.gd")
var port: Node2D
var states: Array[Dictionary] = []
var bay_offsets: Array[float] = []
var lane: Path2D

func build(owner_port: Node2D) -> void:
	port = owner_port
	var y: float = port.cargo_quay_points[0].y
	var route := PackedVector2Array([Vector2(3900,y),Vector2(5630,y),Vector2(5720,y+90),Vector2(5720,5500),Vector2(5630,5620),Vector2(3870,5620),Vector2(3780,5500),Vector2(3780,3500),Vector2(3900,y)])
	lane = FACTORY.create_lane(port,"PortLogisticsCircuit",route)
	lane.set_meta("traffic_lane_loop",true)
	for i in 3:
		var target: Vector2 = port.cargo_quay_points[i]+Vector2(74.0/4.46,0)
		var offset := lane.curve.get_closest_offset(target)
		bay_offsets.append(offset)
		var truck := FACTORY.spawn_moving_vehicle(lane,"PortCargoTruck%d" % i,"cargo_flatbed_truck",maxf(0,offset-210)/lane.curve.get_baked_length(),65,i)
		# Local model override; the rest of the vehicle catalog stays untouched.
		var spec := VehicleCatalog.get_vehicle_spec("cargo_flatbed_truck").duplicate(true)
		spec.model_class = "res://world/harbor/HarborContainerTruckModel.gd"
		spec.target_length = 148.0
		spec.target_width = 46.0
		truck._pending_spec = {}
		truck.target_length = spec.target_length
		truck._setup_3d_model(spec,Color("31577a") if i == 0 else (Color("9e563b") if i == 1 else Color("607b58")))
		truck.body_model.prepare_cargo(i+1)
		truck.set_meta("traffic_stop_offset",offset)
		port.trucks.append(truck)
		states.append({"phase":"approach","remaining":0.0,"bay":i,"loads":0,"loaded":false})
		port.cargo_clocks[i] = 0.0
	port.truck_stops = states
	port._update_hoists()

func available(index: int) -> bool:
	var truck: Node2D = port.trucks[index]
	return is_instance_valid(truck) and not truck.is_driven_by_player and not truck.is_broken and truck.get_parent() is PathFollow2D and not truck.has_meta("vehicle_boarding")

func loading(index: int) -> bool:
	return states.size() > index and states[index].phase == "loading" and available(index)

func carried(index: int) -> bool:
	return states.size() > index and states[index].loaded

func mount_position(index: int) -> Vector2:
	var truck: Node2D = port.trucks[index]
	var camera: Camera3D = truck.body_viewport.get_camera_3d()
	var pixel := camera.unproject_position(truck.body_model.cargo_mount.global_position)
	return port.to_local(truck.visual.to_global(pixel-Vector2(truck.body_viewport.size)*.5))

func update(delta: float) -> void:
	for i in states.size():
		var truck: Node2D = port.trucks[i]
		var state: Dictionary = states[i]
		port.workers[i].set_meta("port_guiding",state.phase in ["loading","securing"] and available(i))
		if not available(i):
			# Never drive a stolen/detached truck or finish a transfer into a missing bed.
			if is_instance_valid(truck): truck.remove_meta("traffic_stop_offset")
			if state.phase == "loading":
				port.cargo_clocks[i] = 0.0
				state.phase = "interrupted"
			continue
		truck.speed = 0.0
		if not port.shift_open: continue
		match state.phase:
			"approach":
				var follow := truck.get_parent() as PathFollow2D
				var remaining: float = bay_offsets[i]-follow.progress
				truck.speed = minf(65,sqrt(maxf(0,remaining)*100))
				if remaining <= .5 and truck._lane_motion_speed < 1:
					state.phase = "waiting"
			"waiting":
				# The empty carrier waits for a load still resting on the ship.
				if fposmod(port.cargo_clocks[i],48) < 4:
					state.phase = "loading"
					port.cargo_clocks[i] = floor(port.cargo_clocks[i]/48)*48
			"securing":
				state.remaining = maxf(0,state.remaining-delta)
				if state.remaining <= 0:
					state.phase = "departed"
					truck.remove_meta("traffic_stop_offset")
			"departed", "interrupted": truck.speed = 65

func finish_loading(index: int) -> void:
	var truck: Node2D = port.trucks[index]
	var state: Dictionary = states[index]
	state.loaded = true
	state.loads += 1
	state.remaining = 3.5
	state.phase = "securing"
	truck.body_model.cargo_mount.show()
	truck.set_meta("port_container_loaded",true)
	truck.body_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	port.hoist_loads[index].hide()
	port.cargo_bodies[index].get_child(0).set_deferred("disabled",true)

func status(index: int) -> String:
	match states[index].phase:
		"approach", "waiting": return "AGUARDANDO CAMINHÃO" if states[index].phase == "approach" else "POSICIONADO"
		"loading": return "CARREGANDO"
		"securing": return "FIXANDO CARGA"
		"departed": return "CARGA LIBERADA"
	return "OPERAÇÃO NO CAIS"

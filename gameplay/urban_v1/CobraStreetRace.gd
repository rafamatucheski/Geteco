extends Node3D
const COURSE := preload("res://gameplay/urban_v1/CobraRaceCourse.gd")
const PROGRESS := preload("res://systems/campaign/CobraStreetProgress.gd")
const PILOT := preload("res://gameplay/urban_v1/CobraRaceDriver.gd")
var session
var racers: Array[Dictionary] = []
var gates: Array[Node3D] = []
var player_car
var running := false
var hud: PanelContainer
var status: Label
var board: Label
var ui_clock := 0.0
var old_transform := Transform3D.IDENTITY
var _old_lock := false

func prepare(owner_session) -> bool:
	session=owner_session
	player_car=session.world.driving.car
	old_transform=player_car.global_transform
	_old_lock=player_car.input_locked
	var sports: Array[String]=["sport_coupe","monaliza","porto_rosso","vertice_midengine"]
	var guest: String=["muscle_classic","cobra_v8"].pick_random()
	var models: Array[String]=["cobra_v8","muscle_classic","ranch_pickup",player_car.archetype,sports.pick_random(),guest]
	var names := ["Takeshi · Cobras" if session.state.campaign.active_id == "cobra_finale" else "Ren · Cobras","Haruka · Cobras","Daichi · Cobras","Você","Maya","Ícaro"]
	var paints := [Color("202d26"),Color("17211d"),Color("29372b"),player_car.paint_color,Color("c64c31"),Color("b8a245")]
	# A largada é transacional: não remove trânsito para forçar espaço.
	if not session.world.production.vehicle_position_clear(player_car,COURSE.grid(3),PI*.5): return false
	for i in 6:
		var vehicle=player_car
		if i!=3:
			vehicle=session.world.production.spawn_vehicle(models[i],COURSE.grid(i),PI*.5)
			if vehicle==null:
				rollback()
				return false
			vehicle.vehicle_id=("cobra_racer_" if i<3 else "street_racer_")+str(Time.get_ticks_usec())
			vehicle.paint_color=paints[i]
			vehicle.set_meta("race_owned",true)
			vehicle.player_damage_attribution=false
			if i<3: preload("res://gameplay/urban_v1/CobraAppearance.gd").race_livery(vehicle)
			var model:=preload("res://gameplay/CobraModel.gd").new()
			model.tier=i%3
			model.seated=true
			model.cobra_uniform=i<3
			var cabin: Dictionary=preload("res://gameplay/VehicleInterior.gd").spec(vehicle)
			model.position=Vector3(cabin.sx,cabin.floor,cabin.sz)
			vehicle.add_child(model)
			model.fit_seat(vehicle,cabin,true)
			vehicle.set_meta("race_driver_model",model)
		var entry:={"car":vehicle,"name":names[i],"cobra":i<3,"player":i==3,"run":{},"elapsed":0.0,"outside":0.0,"finish":INF,"dnf":false,"pilot":null}
		if i!=3:
			entry.pilot=PILOT.new()
			entry.pilot.setup(vehicle,[18.4,18.0,16.6,18.0,19.0,17.8][i],i%2==1)
			entry.pilot.reaction=[.1,.65,.3,0,.25,.55][i]
			entry.pilot.tick(0,true)
		racers.append(entry)
	player_car.place(COURSE.grid(3),PI*.5)
	player_car.speed=0
	player_car.horizontal_velocity=Vector3.ZERO
	player_car.velocity=Vector3.ZERO
	player_car.input_locked=true
	for entry in racers:
		var point: Vector3=entry.car.global_position
		entry.run=PROGRESS.start(entry.car.vehicle_id,Vector2(point.x,point.z))
	_build_gates()
	_build_hud()
	running=true
	return true

func tick(delta: float) -> Dictionary:
	if not running: return {}
	var campaign=session.state.campaign
	var driving=session.world.driving
	if session.world.gameplay.health<=0:
		campaign.cancel("player_death")
		return {"failure":"player_death"}
	var run: Dictionary=campaign.race_status()
	var hold: bool=run.get("countdown",0)>0
	if is_instance_valid(player_car): player_car.input_locked=_old_lock or hold
	for entry in racers:
		if entry.player: continue
		if is_finite(entry.finish): continue
		var vehicle=entry.car
		if not is_instance_valid(vehicle) or vehicle.health<=0:
			entry.dnf=true
			continue
		entry.pilot.tick(delta,hold or entry.dnf)
		if entry.dnf or is_finite(entry.finish): continue
		var point: Vector3=vehicle.global_position
		var state: Dictionary=PROGRESS.tick(entry.run,delta,Vector2(point.x,point.z),vehicle.vehicle_id,vehicle.health>0,entry.elapsed,entry.outside)
		entry.elapsed=state.elapsed
		entry.outside=state.outside
		if not state.failure.is_empty(): entry.dnf=true
		if state.crossed==3:
			entry.finish=entry.elapsed-delta+delta*float(state.get("fraction",1))
			_depart(vehicle) # Libera a chegada, sem estacionar o vencedor na linha.
	var valid: bool=driving.occupied and is_instance_valid(player_car) and driving.car==player_car and session.state.region_id=="harbor" and session.state.place_id.is_empty()
	var point: Vector3=player_car.global_position if is_instance_valid(player_car) else session.world.player.global_position
	var result: Dictionary=campaign.tick_race(delta,Vector2(point.x,point.z),player_car.vehicle_id if valid else "",is_instance_valid(player_car) and player_car.health>0)
	if not result.get("failure","").is_empty(): return result
	var player:=racers[3]
	player.run=campaign.race_status()
	if result.get("crossed",-1)==3: player.finish=float(result.elapsed)-delta+delta*float(result.get("fraction",1))
	var ordered:=standings()
	var place:=ordered.find(player)+1
	campaign.set_street_race_place(place)
	# A missão exige vitória: a prova termina quando o primeiro cruza a linha.
	# Calcula ambos os cruzamentos antes de decidir, inclusive no mesmo frame.
	if is_finite(ordered[0].finish) and not ordered[0].player:
		result.failure="race_lost"
		campaign.cancel("race_lost")
	ui_clock-=delta
	if ui_clock<=0:
		ui_clock=.1
		var remaining:=maxi(0,ceili(COURSE.TIME_LIMIT-float(result.get("elapsed",0))))
		status.text=("LARGADA · %d"%ceili(float(player.run.get("countdown",0)))) if hold else "%d/6  ·  CHECKPOINT %d/4  ·  %02d:%02d"%[place,mini(int(player.run.get("checkpoint",0))+1,4),remaining/60,remaining%60]
		var lines:=PackedStringArray()
		for index in ordered.size():
			var entry: Dictionary=ordered[index]
			lines.append("%d  %s%s"%[index+1,entry.name," · FORA" if entry.dnf else (" · CHEGOU" if is_finite(entry.finish) else "")])
		board.text="\n".join(lines)
		for index in gates.size(): gates[index].visible=index>=int(player.run.get("checkpoint",0))
	return result

func standings() -> Array[Dictionary]:
	var result:=racers.duplicate()
	result.sort_custom(func(a,b):
		if is_finite(a.finish) or is_finite(b.finish): return a.finish<b.finish
		if a.dnf!=b.dnf: return not a.dnf
		if a.run.get("checkpoint",0)!=b.run.get("checkpoint",0): return a.run.get("checkpoint",0)>b.run.get("checkpoint",0)
		return a.run.get("progress",0)>b.run.get("progress",0))
	return result

func rollback() -> void:
	for entry in racers:
		if not entry.player and is_instance_valid(entry.car): entry.car.queue_free()
	racers.clear()
	if is_instance_valid(player_car):
		player_car.global_transform=old_transform
		player_car.input_locked=_old_lock
	running=false
	for gate in gates: gate.queue_free()
	gates.clear()
	if is_instance_valid(hud): hud.queue_free()

func stop() -> void:
	if not running: return
	running=false
	if is_instance_valid(player_car): player_car.input_locked=_old_lock
	for entry in racers:
		if entry.player or not is_instance_valid(entry.car): continue
		var car=entry.car
		car.remove_meta("race_owned")
		car.set_external_driver(false)
		var driver: Node=car.get_meta("race_driver_model",null)
		if is_instance_valid(driver): driver.queue_free()
		car.remove_meta("race_driver_model")
		if session.world.driving.occupied and session.world.driving.car==car:
			car.player_damage_attribution=true
			car.controlled=true
			continue
		_depart(car)
	for gate in gates: gate.queue_free()
	gates.clear()
	if is_instance_valid(hud): hud.queue_free()
	racers.clear()

func _depart(car) -> void:
	car.set_external_driver(false)
	car.set_meta("ambient_traffic",true)
	if car.health>0:
		car.route=session.world.production.ambient_traffic_routes.route_near(car.global_position)
		if car.route!=null:
			car.route_distance=car.route.get_closest_offset(car.global_position)
			car.traffic=true

func _exit_tree() -> void:
	if is_instance_valid(hud): hud.queue_free()
	if running:
		for entry in racers:
			if not entry.player and is_instance_valid(entry.car): entry.car.queue_free()
		if is_instance_valid(player_car): player_car.input_locked=_old_lock

func _build_gates() -> void:
	var blue:=StandardMaterial3D.new()
	blue.albedo_color=Color("2794ff")
	blue.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	for index in 4:
		var gate:=Node3D.new()
		gate.name="BlueCheckpoint%d"%index
		gate.position=COURSE.gate(index)+Vector3.UP*.045
		var direction:=COURSE.forward(index)
		gate.rotation.y=atan2(-direction.x,-direction.z)
		add_child(gate)
		gates.append(gate)
		for side in [-1,1]:
			_box(gate,Vector3(side*COURSE.HALF_GATE,1.2,0),Vector3(.14,2.4,.14),blue)
		_box(gate,Vector3(0,.015,0),Vector3(COURSE.HALF_GATE*2,.03,.18),blue)
		for offset in [-1.5,0.0,1.5]:
			var arrow:=_box(gate,Vector3(offset,.025,-.9),Vector3(.85,.025,.12),blue)
			arrow.rotation.y=-.55
			var other:=_box(gate,Vector3(offset+.7,.025,-.9),Vector3(.85,.025,.12),blue)
			other.rotation.y=.55

func _box(parent: Node3D, point: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var node:=MeshInstance3D.new()
	var box:=BoxMesh.new()
	box.size=size
	node.mesh=box
	node.material_override=material
	node.position=point
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

func _build_hud() -> void:
	hud=PanelContainer.new()
	hud.position=Vector2(888,105)
	hud.custom_minimum_size=Vector2(365,0)
	hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var style:=StyleBoxFlat.new()
	style.bg_color=Color(.025,.045,.075,.91)
	style.border_color=Color("2794ff")
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	style.set_corner_radius_all(6)
	hud.add_theme_stylebox_override("panel",style)
	session.world.hud.add_child(hud)
	var column:=VBoxContainer.new()
	hud.add_child(column)
	status=Label.new()
	status.add_theme_font_size_override("font_size",18)
	status.add_theme_color_override("font_color",Color("79baff"))
	column.add_child(status)
	board=Label.new()
	board.add_theme_font_size_override("font_size",17)
	column.add_child(board)

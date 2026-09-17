extends Node2D
## South of Northstar: a traversable terminal with bounded logistics simulation.
const L := preload("res://world/harbor/HarborSouthPortLayout.gd")
const WORKER := preload("res://world/harbor/HarborDockWorker.gd")
const FACTORY := preload("res://emergency/ModernTrafficFactory.gd")
const MODEL_VIEW := preload("res://world/harbor/HarborPortModelView.gd")
const COLORS := [Color("ae5946"),Color("447f91"),Color("c09b52"),Color("658374"),Color("c5c6b0")]
var workers: Array[Node2D] = []
var trucks: Array[Node2D] = []
var truck_stops: Array[Dictionary] = []
var forklifts: Array[Node2D] = []
var sites: Array[Dictionary] = []
var moving_art: Node2D
var elapsed := 0.0
var cargo_elapsed := 0.0
var active := false
var shift_open := true
var completed_loads := 0
var _scan := 0.0
var _render_tick := 0.0
var _status_label: Label
var _hud: CanvasLayer
var gate_open := false
var checkpoint: Node
var _second_gate_collision: CollisionShape2D
var _gate_collision: CollisionShape2D
var _gate_clearance: RectangleShape2D
var model_views: Array[Node2D] = []
var crane_views: Array[Node2D] = []
var hoist_loads: Array[Node2D] = []
var cargo_clocks: Array[float] = [0.0, 16.0, 32.0]
var cargo_bodies: Array[StaticBody2D] = []
var cargo_ship_points: Array[Vector2] = []
var cargo_quay_points: Array[Vector2] = []
var unloaded_containers := 0
var loaded_containers := 0
var truck_logistics: RefCounted
## GETECO-PERF-03A: fica true só depois que TODA a construção abaixo termina
## (containers, prédios, grua, docas, HUD). HarborPreview._start_review()
## aguarda esta flag antes de marcar world_build_ready — nenhum outro nó lê
## sites/workers/trucks/checkpoint antes disso (ver grep no relatório 03A).
var port_ready := false

class OperationsArt extends Node2D:
	var port: Node2D
	func _draw() -> void: port.draw_operations(self)

func _ready() -> void:
	add_to_group("south_port")
	# GETECO-PERF-03A: _process() lê _hud/_status_label abaixo (criados só ao
	# final); com a construção agora fatiada em vários quadros, um _process()
	# no meio do caminho encontraria essas referências nulas. Sem isso o
	# comportamento já era o mesmo (síncrono, _process nunca corria antes do
	# fim de _ready), então este guard só formaliza a garantia existente.
	set_process(false)
	var batch := preload("res://ui/LoadingWorkBatch.gd").new()
	_build_solids()
	await batch.checkpoint(get_tree())
	await _build_buildings(batch)
	await _build_port_models(batch)
	preload("res://world/harbor/HarborPortDressing.gd").build(self)
	await batch.checkpoint(get_tree())
	await _build_life(batch)
	add_child(preload("res://world/harbor/HarborLaunchRoutine.gd").new())
	_build_markers()
	_build_lights()
	checkpoint = preload("res://world/harbor/HarborPortCheckpoint.gd").new()
	add_child(checkpoint)
	moving_art = OperationsArt.new()
	moving_art.name = "CargoOperations"
	moving_art.port = self
	moving_art.z_index = 6
	add_child(moving_art)
	_hud = CanvasLayer.new()
	_hud.layer = 16
	add_child(_hud)
	_status_label = Label.new()
	_status_label.position = Vector2(24, 92)
	_status_label.add_theme_font_size_override("font_size", 17)
	_status_label.add_theme_color_override("font_outline_color", Color("15232a"))
	_status_label.add_theme_constant_override("outline_size", 6)
	_hud.add_child(_status_label)
	_hud.hide()
	queue_redraw()
	set_process(true)
	port_ready = true

func _solid(rect: Rect2, label: String, layer: int = 1) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = label
	body.collision_layer = layer
	body.collision_mask = 0
	body.add_to_group("metal_prop")
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collision.shape = shape
	collision.position = rect.get_center()
	body.add_child(collision)
	add_child(body)
	return body

func _build_solids() -> void:
	for i in L.containers().size(): _solid(L.containers()[i], "Container%02d" % i)
	for i in L.ship_containers().size(): _solid(L.ship_containers()[i], "ShipContainer%02d" % i)
	_solid(L.WHEELHOUSE,"SantaMareWheelhouseSolid")
	for x in [4214,4282]: _solid(Rect2(x,3120,4,130),"SantaMareGangwayRail")
	# Follow the actual hull, leaving a single opening at the boarding gangway.
	var hull := L.ship_hull()
	for i in hull.size():
		var a: Vector2 = hull[i]
		var b: Vector2 = hull[(i+1)%hull.size()]
		if i == 5:
			_ship_rail(a,Vector2(L.SHIP_GANGWAY.end.x,3120),i)
			_ship_rail(Vector2(L.SHIP_GANGWAY.position.x,3120),b,20)
		else: _ship_rail(a,b,i)
	for i in L.CRANES.size():
		_add_gantry_crane_collision(L.CRANES[i], "CraneBase%d" % i)
	# Continuous gangway rails; offset bollards leave enough room for a person.
	_solid(Rect2(3530,2115,4,1085),"WalkwayWestRail")
	_solid(Rect2(3606,2115,4,1085),"WalkwayEastRail")
	# Real bollards: 24px centre clearance fits the player capsule, not a car.
	for y in [2170,3180]:
		_solid(Rect2(3534,y,24,8),"WalkwayBollardWest")
		_solid(Rect2(3582,y,24,8),"WalkwayBollardEast")
	var gate := _solid(Rect2(3258,3380,52,8),"FreightGate")
	_gate_collision = gate.get_child(0)
	_second_gate_collision = _solid(Rect2(3310,3380,52,8),"FreightGateEast").get_child(0)
	_gate_clearance = RectangleShape2D.new()
	_gate_clearance.size = Vector2(155,260)
	for i in 2:
		var pier: Rect2 = L.PIERS[i]
		_solid(Rect2(pier.position,Vector2(pier.size.x,5)),"PierNorth%d" % i)
		_solid(Rect2(pier.position+Vector2(0,95),Vector2(pier.size.x,5)),"PierSouth%d" % i)
		_solid(Rect2(pier.end-Vector2(5,100),Vector2(5,100)),"PierEnd%d" % i)
	# Aprons remain open where the bridges and wharves meet the terminal.
	_solid(Rect2(3200,3210,8,220),"WestApronNorth")
	_solid(Rect2(3200,3750,8,2250),"WestSeawall")
	_solid(Rect2(3200,5990,2900,10),"SouthSeawall")
	for r in [Rect2(6090,3200,10,450),Rect2(6090,3750,10,460),Rect2(6090,4310,10,1690)]: _solid(r,"EastSeawall")
	# A reserved, physically open cargo bay for a future car-container mission.

func _add_gantry_crane_collision(base: Vector2, label: String) -> void:
	# Torre e pernas bloqueiam quem tenta atravessar o guindaste a pé, mas o
	# pátio logo abaixo da base é onde os caminhões recebem o contêiner: a
	# colisão não desce além da base original (+25 px). Descer até +110 px
	# travava a logística inteira do porto sul (20 falhas em test_south_port).
	_solid(Rect2(base - Vector2(54, 90), Vector2(108, 115)), label + "Structure")


func _ship_rail(a: Vector2,b: Vector2,index: int) -> void:
	var body := _solid(Rect2(Vector2(-(b-a).length()*.5,-2),Vector2((b-a).length(),4)),"SantaMareHullRail%d" % index)
	body.position = (a+b)*.5
	body.rotation = (b-a).angle()

func _build_buildings(batch: RefCounted) -> void:
	var definitions := [
		{"rect":L.WAREHOUSES[0],"title":"ARMAZÉM 07 · CARGA GERAL","kind":"warehouse"},
		{"rect":L.WAREHOUSES[1],"title":"ARMAZÉM 08 · EXPORTAÇÃO","kind":"warehouse"},
		{"rect":Rect2(3400,4050,210,180),"title":"","kind":"office"},
		{"rect":Rect2(3370,5130,200,270),"title":"OFICINA DO CAIS","kind":"warehouse"},
		{"rect":Rect2(3420,3390,85,90),"title":"PORTARIA","kind":"office"},
	]
	for i in definitions.size():
		var item: Dictionary = definitions[i]
		var building := _model(item.kind,item.rect,i,"PortBuilding%d" % i)
		sites.append({"bounds":item.rect,"id":building.name})
		if i != 4 and not item.title.is_empty():
			var sign := Label.new()
			sign.text = item.title
			sign.add_theme_font_size_override("font_size",16 if i < 2 else 11)
			sign.add_theme_color_override("font_color",Color("ece0be"))
			sign.add_theme_color_override("font_outline_color",Color("24383d"))
			sign.add_theme_constant_override("outline_size",3)
			sign.position = Vector2(-item.rect.size.x*.46,item.rect.size.y*.5+8)
			building.add_child(sign)
		await batch.checkpoint(get_tree())

## GETECO-PERF: os 37 modelos aqui embaixo eram construídos ao vivo (SubViewport
## + Camera3D + malha 3D) toda vez que o Porto Sul carregava -- medido pela
## rodada 03A como o maior bloco indivisível do world_build (22-28s). São
## 100% determinísticos dado (kind, tamanho, variant), sem depender de save
## nem RNG, então tools/bake_south_port_models.gd pré-renderiza cada um numa
## textura + extrai a geometria (pontos de içamento da grua, contorno de
## colisão dos prédios) uma única vez. Em tempo real, se existir bake pra este
## label, HarborPortModelBaked.gd só posiciona a textura -- sem 3D nenhum.
## Sem bake (asset ainda não gerado, ou um novo item adicionado depois do
## último bake), cai de volta no caminho ao vivo, idêntico a antes.
const MODEL_VIEW_BAKED := preload("res://world/harbor/HarborPortModelBaked.gd")

func _model(kind: String,rect: Rect2,variant: int,label_text: String) -> Node2D:
	var view: Node2D
	if MODEL_VIEW_BAKED.has_data(label_text):
		var baked := MODEL_VIEW_BAKED.new()
		baked.name = label_text
		add_child(baked)
		baked.setup(kind,rect,label_text)
		view = baked
	else:
		view = MODEL_VIEW.new()
		view.name = label_text
		add_child(view)
		view.setup(kind,rect,variant)
	model_views.append(view)
	return view

## GETECO-PERF-03A: cada _model() cria um SubViewport 3D próprio (câmera, luz,
## malha) — a rodada 01 mediu esse tipo de construção em dezenas/centenas de ms
## por item. Este era o maior bloco indivisível de HarborSouthPort._ready();
## o checkpoint entre cada item deixa o LoadingWorkBatget decidir quantos cabem
## em cada quadro (~6 ms), sem mudar quantidade, ordem ou parâmetros de nenhum.
func _build_port_models(batch: RefCounted) -> void:
	var containers := L.containers()
	for i in containers.size():
		_model("containers",containers[i],i,"CargoStack3D%02d" % i)
		await batch.checkpoint(get_tree())
	_model("ship_cargo",L.SHIP_CARGO,0,"SantaMareCargo3D")
	await batch.checkpoint(get_tree())
	_model("office",L.WHEELHOUSE,2,"SantaMareWheelhouse3D")
	await batch.checkpoint(get_tree())
	for i in L.CRANES.size():
		var base: Vector2 = L.CRANES[i]
		var crane := _model("crane",Rect2(base+Vector2(-35,-360),Vector2(240,410)),i,"QuaysideCrane3D%d" % i)
		crane.z_index = 6
		crane_views.append(crane)
		var cargo := _model("transfer_cargo",Rect2(base,Vector2(96,42)),i+1,"HoistedCargo3D%d" % i)
		cargo.z_index = 7
		hoist_loads.append(cargo)
		var start: Vector3 = crane.model.hoist_start
		var end: Vector3 = crane.model.hoist_end
		cargo_quay_points.append(crane.position+crane.project_floor(Vector2(start.x,start.z)))
		cargo_ship_points.append(crane.position+crane.project_floor(Vector2(end.x,end.z)))
		cargo_bodies.append(_solid(Rect2(-48,-21,96,42),"TransferCargoSolid%d" % i))
		await batch.checkpoint(get_tree())
	_update_hoists()
	for i in 6:
		var rect := Rect2(3970+(i%3)*550,4900 if i < 3 else 5420,130,55)
		_model("supplies",rect,i,"PalletsAndDrums3D%d" % i)
		_solid(rect,"PalletsAndDrumsSolid%d" % i)
		await batch.checkpoint(get_tree())

## GETECO-PERF-03A: os trabalhadores são baratos (Node2D simples, física
## desligada até ficarem ativos), mas truck_logistics.build() e cada forklift
## chamam _setup_3d_model()/ensure_presentation() diretamente — construção 3D
## completa, sem cache aquecido (nenhum dos dois arquétipos está na lista de
## VehicleGeometryCache.prepare_common_models). São os itens caros aqui.
func _build_life(batch: RefCounted) -> void:
	var bases := [Vector2(3900,3370),Vector2(4430,3370),Vector2(5020,3370),Vector2(5860,3760),Vector2(5860,4320),Vector2(4030,5500),Vector2(4920,5500),Vector2(3570,3260),Vector2(3860,3770),Vector2(4430,3770),Vector2(5480,4020),Vector2(4430,4650),Vector2(5550,5410),Vector2(3490,5510),Vector2(4250,3270),Vector2(4400,2880),Vector2(4780,2880),Vector2(5140,2880),Vector2(5410,2990),Vector2(3940,2820)]
	bases.append_array([Vector2(3890,4180),Vector2(4470,4150),Vector2(5100,4160),Vector2(5540,4110),Vector2(3920,4630),Vector2(4540,4620),Vector2(5140,4640),Vector2(5380,4650),Vector2(4160,5510),Vector2(4610,5520),Vector2(5180,5510),Vector2(5810,4970)])
	for i in 3: bases[i] = cargo_quay_points[i]+Vector2(-90,95)
	for i in bases.size():
		var p: Vector2 = bases[i]
		var worker := WORKER.new()
		worker.name = "SouthDockWorker%d" % i
		worker.worker_index = (i%20)+3
		worker.work_route = PackedVector2Array([p,p+Vector2(90,0),p+Vector2(90,65),p+Vector2(0,65)])
		if i < 3: worker.work_route = PackedVector2Array([p,p+Vector2(60,0),p+Vector2(60,24),p+Vector2(0,24)])
		elif i == 7:
			worker.work_route = PackedVector2Array([p,Vector2(3570,2750),Vector2(3570,2230),Vector2(3570,2780)])
		elif i == 14:
			worker.work_route = PackedVector2Array([p,Vector2(4250,3070),Vector2(4250,2890),Vector2(4250,3070)])
		elif i >= 15 and i <= 17:
			worker.work_route = PackedVector2Array([p,p+Vector2(180,0),p+Vector2(180,18),p+Vector2(0,18)])
		elif i == 18:
			worker.work_route = PackedVector2Array([p,Vector2(5490,2990),Vector2(5490,3060),Vector2(5410,3080)])
		elif i == 19:
			worker.work_route = PackedVector2Array([p,Vector2(3960,2820),Vector2(3960,3020),Vector2(3940,3020)])
		worker.work_points = PackedVector2Array([worker.work_route[0],worker.work_route[2]])
		worker.station_points = PackedVector2Array([p-Vector2(0,16),worker.work_points[1]+Vector2(0,16)])
		add_child(worker)
		workers.append(worker)
		worker.set_meta("night_shift",i in [6,7,13,19,20,22,24,27,29,31])
		worker.set_physics_process(false)
		if i % 8 == 7: await batch.checkpoint(get_tree())
	var axe_pickup := WeaponPickup.new()
	axe_pickup.name = "PortMaintenanceAxePickup"
	axe_pickup.weapon_id = &"axe"
	axe_pickup.ammo_amount = 0
	axe_pickup.persistent_loot = true
	axe_pickup.position = Vector2(3970, 4930)
	add_child(axe_pickup)
	await batch.checkpoint(get_tree())

	# Catalog vehicles retain driving, damage, theft and collision behavior.
	truck_logistics = preload("res://world/harbor/HarborPortTruckLogistics.gd").new()
	truck_logistics.build(self)
	await batch.checkpoint(get_tree())
	FACTORY.spawn_parked_vehicle(self,"PortDispatchVan",Vector2(3480,4020),PI*0.5,"dock_delivery_van",0)
	FACTORY.spawn_parked_vehicle(self,"PortServicePickup",Vector2(3480,4160),PI*0.5,"ranch_single",0)
	for i in 2:
		var forklift := FACTORY.spawn_parked_vehicle(self,"Forklift%d" % i,Vector2(4400+i*600,3440),PI*.5,"port_forklift",0)
		forklift.z_index = 5
		forklift.ensure_presentation()
		forklifts.append(forklift)
		for j in 3:
			var crate := preload("res://world/harbor/ForkliftCrate.gd").new()
			crate.name = "ForkliftCrate%d_%d" % [i,j]
			crate.position = Vector2(4480+i*600+j*36,3450)
			add_child(crate)
		await batch.checkpoint(get_tree())

func _build_markers() -> void:
	for entry in [{"id":"SouthPortArrival","p":Vector2(3570,3260)},{"id":"SpecialVehicleContainer","p":Vector2(5290,5870)},{"id":"CargoMissionContact","p":Vector2(3490,3910)},{"id":"CargoDispatch","p":Vector2(5600,5500)}]:
		var marker := Marker2D.new()
		marker.name = entry.id
		marker.position = entry.p
		add_child(marker)

func _focus() -> Vector2:
	var player := get_parent().get_node_or_null("Player") as Node2D
	if player == null: return Vector2.INF
	var travel := get_node_or_null("/root/RegionTravel")
	if travel:
		var car: Node2D = travel.controlled_car()
		if car: return car.global_position
	return player.get_meta("police_exterior_position",player.global_position)

func is_open_at(hour: float) -> bool: return hour >= 6.0 and hour < 18.0

func _process(delta: float) -> void:
	_scan -= delta
	if _scan <= 0:
		_scan = .25
		var focus := _focus()
		active = L.LAND.grow(1200).has_point(focus) or L.WALKWAY.grow(700).has_point(focus)
		var weather = get_parent().get("weather")
		shift_open = is_open_at(float(weather.time_of_day)*24.0) if weather != null else true
		for i in workers.size():
			var worker := workers[i]
			if worker.has_meta("medical_witness") or (worker.has_meta("medical_pending") and not worker.visible): continue
			worker.set_physics_process((active and (shift_open or worker.get_meta("night_shift",false))) or worker.is_scared or worker.is_flying)
		_hud.visible = L.LAND.has_point(focus) or L.WALKWAY.has_point(focus) or L.SHIP_GANGWAY.has_point(focus) or Geometry2D.is_point_in_polygon(focus,L.ship_hull())
		_status_label.text = "PORTO SUL  ·  " + ("OPERAÇÃO DE CARGA 06h–18h" if shift_open else "TURNO NOTURNO · EQUIPE DE MANUTENÇÃO")
		_update_gate(focus)
	if not active: return
	elapsed += delta
	_update_trucks(delta)
	if shift_open:
		cargo_elapsed += delta
		_advance_cargo(delta)
	_render_tick += delta
	if _render_tick >= .1:
		_render_tick = 0
		moving_art.queue_redraw()
		_update_hoists()

func _update_hoists() -> void:
	for i in crane_views.size():
		var pose := cargo_pose(i,cargo_clocks[i])
		if truck_logistics != null and truck_logistics.carried(i):
			hoist_loads[i].hide()
			cargo_bodies[i].get_child(0).set_deferred("disabled",true)
			continue
		hoist_loads[i].show()
		hoist_loads[i].position = pose.ground-Vector2(0,pose.lift)
		hoist_loads[i].z_index = 7 if pose.lift > 0 else 4
		cargo_bodies[i].position = pose.ground
		cargo_bodies[i].get_child(0).set_deferred("disabled",pose.lift > 0 or (truck_logistics != null and truck_logistics.loading(i)))

func cargo_pose(index: int,time: float) -> Dictionary:
	var phase := fposmod(time,48.0)
	var along := 0.0
	var lift := 0.0
	if phase >= 4 and phase < 8: lift = (phase-4)/4.0
	elif phase >= 8 and phase < 16:
		along = smoothstep(8,16,phase)
		lift = 1
	elif phase >= 16 and phase < 20:
		along = 1
		lift = (20-phase)/4.0
	elif phase >= 20 and phase < 28: along = 1
	elif phase >= 28 and phase < 32:
		along = 1
		lift = (phase-28)/4.0
	elif phase >= 32 and phase < 40:
		along = 1-smoothstep(32,40,phase)
		lift = 1
	elif phase >= 40 and phase < 44: lift = (44-phase)/4.0
	var ground := cargo_ship_points[index].lerp(cargo_quay_points[index],along)
	if truck_logistics != null and truck_logistics.loading(index):
		ground = cargo_ship_points[index].lerp(truck_logistics.mount_position(index),along)
	return {"ground":ground,"lift":lift*70.0,"along":along}

func _cargo_bay_occupied(point: Vector2,excluded: Array[RID] = []) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(116,62)
	query.shape = shape
	query.transform = Transform2D(0,point)
	query.collision_mask = 6
	query.exclude = excluded
	return not get_world_2d().direct_space_state.intersect_shape(query,1).is_empty()

func _advance_cargo(delta: float) -> void:
	for i in cargo_clocks.size():
		var before := cargo_clocks[i]
		var after := before+delta
		var phase := fposmod(after,48.0)
		if truck_logistics != null and truck_stops[i].phase in ["approach","waiting"] and fposmod(before,48) < 4:
			cargo_clocks[i] = minf(after,floor(before/48)*48+3.9)
			continue
		if truck_logistics != null and truck_logistics.carried(i):
			# The empty spreader returns; the exported container stays on the truck.
			cargo_clocks[i] = minf(after,ceil(before/48.0)*48.0)
			continue
		# Hold the load until the landing pad is clear of people or vehicles.
		var landing := (phase >= 16 and phase <= 20.5) or (phase >= 40 and phase <= 44.5)
		var excluded: Array[RID] = []
		var to_truck: bool = truck_logistics != null and truck_logistics.loading(i)
		if to_truck: excluded.append(trucks[i].get_rid())
		if landing and _cargo_bay_occupied(cargo_quay_points[i] if phase < 28 else cargo_ship_points[i],excluded): continue
		unloaded_containers += int(floor((after-20)/48.0)-floor((before-20)/48.0))
		loaded_containers += int(floor((after-44)/48.0)-floor((before-44)/48.0))
		cargo_clocks[i] = after
		if to_truck and int(floor((after-20)/48.0)-floor((before-20)/48.0)) > 0:
			truck_logistics.finish_loading(i)
	completed_loads = unloaded_containers+loaded_containers

func _update_trucks(delta: float) -> void:
	if truck_logistics != null: truck_logistics.update(delta)

func _update_gate(focus: Vector2) -> void:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _gate_clearance
	query.transform = Transform2D(0,Vector2(3310,3384))
	query.collision_mask = 6
	var occupants := get_world_2d().direct_space_state.intersect_shape(query,8)
	var occupied := not occupants.is_empty()
	var emergency_access := false
	for hit in occupants:
		var unit: Node = hit.collider
		if unit.is_in_group("emergency_vehicle") and not unit.is_broken and (is_instance_valid(unit.target) or unit.is_returning_to_base):
			emergency_access = true
	# Outbound traffic can always leave; never lower a boom onto an actor.
	var outbound := focus.y > 3384 and focus.y < 3630 and absf(focus.x-3310) < 100
	gate_open = emergency_access or (checkpoint != null and checkpoint.authorized) or (gate_open and occupied) or outbound
	_gate_collision.set_deferred("disabled",gate_open)
	_second_gate_collision.set_deferred("disabled",gate_open)

func _build_lights() -> void:
	for point in [Vector2(3640,3800),Vector2(5600,3850),Vector2(5600,4630),Vector2(3630,4870),Vector2(5600,5790),Vector2(3700,3280),Vector2(5700,3280),Vector2(3470,3320)]:
		var lamp := preload("res://geodata/StreetLamp.gd").new()
		lamp.position = point
		lamp.light_radius = 400
		lamp.light_energy = 1.1
		lamp.light_color = Color("f2dbad")
		add_child(lamp)
	call_deferred("_bind_lights")

func _bind_lights() -> void:
	var weather := get_tree().get_first_node_in_group("day_night_manager")
	if weather == null: return
	for lamp in get_children():
		if lamp is StreetLamp:
			if not weather.time_changed.is_connected(lamp.set_lit): weather.time_changed.connect(lamp.set_lit)
			lamp.set_lit(weather.is_dark)

func _draw() -> void:
	draw_rect(Rect2(L.LAND.position+Vector2(18,22),L.LAND.size),Color("142f38"))
	draw_rect(L.LAND,Color("9c9a88"))
	preload("res://world/harbor/ExteriorFinish.gd").industrial(self,L.LAND.grow(-18),932)
	for x in range(3230,6100,140): draw_line(Vector2(x,3200),Vector2(x,5980),Color("7f857e"),1)
	for y in range(3220,6000,140): draw_line(Vector2(3210,y),Vector2(6090,y),Color("7f857e"),1)
	# Broad apron, separate pedestrian path and a bright north quay edge.
	draw_rect(Rect2(3620,3300,2370,175),Color("6b7776"))
	draw_rect(Rect2(3498,3200,145,300),Color("a7afa0"))
	for y in range(3250,3480,42): draw_line(Vector2(3540,y),Vector2(3600,y),Color("d6d6b9"),3)
	# Match the collision/shoreline envelope so the bend has a visible shoulder
	# between its sidewalk and the coastal guardrail.
	for polygon in Geometry2D.offset_polyline(PackedVector2Array(L.ACCESS),L.ACCESS_LAND_HALF_WIDTH,Geometry2D.JOIN_ROUND,Geometry2D.END_SQUARE):
		draw_colored_polygon(polygon,Color("a7aaa0"))
	_draw_walkway()
	_draw_cargo_ship()
	for i in L.PIERS.size():
		var pier: Rect2 = L.PIERS[i]
		draw_rect(pier,Color("ada88f"))
		for x in range(6110,6330,20): draw_line(Vector2(x,pier.position.y+5),Vector2(x,pier.end.y-5),Color("837e70"),2)
	for x in range(3630,6060,44):
		draw_line(Vector2(x,3208),Vector2(x+16,3230),Color("e0bd62"),9)
	for x in range(3680,6040,150):
		draw_rect(Rect2(x,3195,38,10),Color("22393d"))
		draw_circle(Vector2(x+17,3238),7,Color("354448"))
	var containers := L.containers()
	for i in containers.size():
		var r: Rect2 = containers[i]
		preload("res://world/harbor/UrbanGround.gd").paint(self,r.grow(12),Color("727e77"),"concrete")
	for r in L.WAREHOUSES:
		draw_rect(Rect2(r.position+Vector2(-30,330),r.size*Vector2(1,0)+Vector2(60,130)),Color("747c73"))
		for x in range(int(r.position.x)+30,int(r.end.x),140):
			draw_rect(Rect2(x,r.end.y+4,105,108),Color("c4bc95"),false,3)
	for patch in [Rect2(4040,4240,1450,140),Rect2(4080,4830,1380,95),Rect2(4060,5430,1330,95)]:
		preload("res://world/harbor/UrbanGround.gd").yard(self,patch,int(patch.position.y),true)
	for y in [4020,4160,4300]:
		draw_rect(Rect2(3425,y-45,110,90),Color("d2c7a3"),false,2)
	# Open container shell with space for a future mission vehicle and its exit.
	_draw_ship_gangway()
	for i in cargo_ship_points.size():
		for point in [cargo_ship_points[i],cargo_quay_points[i]]:
			draw_rect(Rect2(point-Vector2(56,28),Vector2(112,56)),Color("dfbb60"),false,2)
	# Open truck apron beneath the rear jibs, separate from the pedestrian walkway.
	for i in cargo_quay_points.size():
		var point: Vector2 = cargo_quay_points[i]
		draw_rect(Rect2(point-Vector2(85,36),Vector2(175,72)),Color("dfbb60"),false,2)
		for x in [-110,125]:
			draw_line(point+Vector2(x-8,20),point+Vector2(x+8,20),Color("eee0ae"),3)
			draw_line(point+Vector2(x+8,20),point+Vector2(x+1,13),Color("eee0ae"),3)

func _draw_ship_gangway() -> void:
	draw_rect(L.SHIP_GANGWAY,Color("aab4a4"))
	draw_rect(L.SHIP_GANGWAY.grow(-5),Color("526d70"))
	for y in range(3100,3250,10): draw_line(Vector2(4224,y),Vector2(4276,y),Color("bdc8b6"),2)
	for x in [4216,4284]:
		draw_line(Vector2(x,3120),Vector2(x,3250),Color("e6c971"),4)
		for y in range(3120,3251,26): draw_circle(Vector2(x,y),3,Color("f3dba0"))

func _draw_walkway() -> void:
	draw_rect(Rect2(L.WALKWAY.position+Vector2(10,10),L.WALKWAY.size),Color("172f37"))
	draw_rect(L.WALKWAY,Color("a3aba0"))
	draw_rect(L.WALKWAY.grow(-6),Color("737f79"))
	for y in range(2120,3220,12): draw_line(Vector2(3541,y),Vector2(3599,y),Color("aab3a3"),2)
	for x in [3532,3608]:
		draw_line(Vector2(x,2115),Vector2(x,3200),Color("e0d0a6"),4)
		for y in range(2140,3190,40): draw_circle(Vector2(x,y),3,Color("f1dfab"))
	for y in [2170,3180]:
		for x in [3544,3596]: draw_circle(Vector2(x,y),5,Color("e8c159"))

func _draw_cargo_ship() -> void:
	var hull := L.ship_hull()
	draw_colored_polygon(hull,Color("183d49"))
	var closed := hull.duplicate()
	closed.append(hull[0])
	draw_polyline(closed,Color("dcc6a0"),5,true)
	draw_rect(Rect2(3930,2760,1510,330),Color("627b78"))
	for x in range(4310,5380,38): draw_line(Vector2(x,2868),Vector2(x+18,2868),Color("d4c28c"),2)
	for x in [3960,5450]: draw_line(Vector2(x,3110),Vector2(x+65,3238),Color("b5ac8d"),2)

static func container(canvas: Node2D, rect: Rect2, color: Color) -> void:
	canvas.draw_rect(Rect2(rect.position+Vector2(7,9),rect.size),Color(0.05,.1,.12,.3))
	canvas.draw_rect(rect,color.darkened(.28))
	canvas.draw_rect(rect.grow(-3),color)
	for x in range(int(rect.position.x)+8,int(rect.end.x)-4,10):
		canvas.draw_line(Vector2(x,rect.position.y+5),Vector2(x,rect.end.y-5),color.lightened(.14),2)
	canvas.draw_line(rect.position+Vector2(3,2),Vector2(rect.end.x-3,rect.position.y+2),color.lightened(.35),2)

static func label(canvas: Node2D, point: Vector2, text: String, size: int, color: Color) -> void:
	canvas.draw_string(ThemeDB.fallback_font,point,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

func draw_operations(canvas: Node2D) -> void:
	for i in crane_views.size():
		var crane := crane_views[i]
		var pose := cargo_pose(i,cargo_clocks[i])
		var trolley: Vector2 = crane.position+crane.project_point(crane.model.hoist_end.lerp(crane.model.hoist_start,pose.along))
		var top: Vector2 = hoist_loads[i].position-Vector2(0,16)
		if truck_logistics != null and truck_logistics.carried(i): top = pose.ground-Vector2(0,pose.lift+16)
		for side in [-1,1]: canvas.draw_line(trolley+Vector2(side*9,0),top+Vector2(side*36,0),Color("e4d6b0"),2)
		canvas.draw_line(top-Vector2(43,0),top+Vector2(43,0),Color("d6b65c"),4)
	for side in [-1,1]:
		var gate_base := Vector2(3310+side*52,3384)
		var gate_tip := gate_base+Vector2(0,-52) if gate_open else gate_base+Vector2(-side*52,0)
		canvas.draw_line(gate_base,gate_tip,Color("e2d8bf"),7)
		for i in 5:
			canvas.draw_line(gate_base.lerp(gate_tip,float(i)/5),gate_base.lerp(gate_tip,float(i)/5+.08),Color("bd6449"),8)
		canvas.draw_circle(gate_base,7,Color("4d5856"))
		canvas.draw_circle(gate_base+Vector2(side*12,0),5,Color("8ecd92") if gate_open else Color("ef6c4f"))
	for worker in workers:
		for i in 2:
			for stock in worker.crate_stock[i]:
				var p: Vector2 = worker.station_points[i]+Vector2(stock*15,0)
				preload("res://world/harbor/DockCrateDrawing.gd").draw_crate(canvas,p)
		for point in worker.dropped_crates:
			preload("res://world/harbor/DockCrateDrawing.gd").draw_crate(canvas,to_local(point))

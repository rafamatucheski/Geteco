extends SceneTree
## Cadeia real em Main: viatura imobilizada -> fuga de trânsito -> percepção
## dos pedestres -> desvio físico -> retomada. Nenhum diretor é desligado.
const ACTOR := preload("res://scripts/Actor.gd")
const DANGER := preload("res://gameplay/civilian_reactions/PedestrianVehicleDanger.gd")
var world
var director
var failures: Array[String] = []
var checks := 0
var results: Array = []
var folder := "res://evidence/auditoria-viaria/2026-10-10-fuga-integrada/final"

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	print("COMBINED_ESCAPE ", "PASS " if ok else "FAIL ", label, " ", detail)
	if not ok: failures.append(label)
func flat(a: Vector3, b: Vector3) -> float: return Vector2(a.x-b.x, a.z-b.z).length()
func outside_road(point: Vector3) -> bool:
	# Geometria do acesso rural carregada no documento (largura 9 m).
	var centerline: Array[Vector3]=[Vector3(-290,0,10),Vector3(-320,0,18),Vector3(-340,0,18),Vector3(-340,0,-2)]
	var distance:=INF
	point.y=0
	for i in range(centerline.size()-1): distance=minf(distance,point.distance_to(Geometry3D.get_closest_point_to_segment(point,centerline[i],centerline[i+1])))
	return distance>4.5
func seconds(duration: float) -> void:
	var deadline := Time.get_ticks_msec() + int(duration * 1000)
	while Time.get_ticks_msec() < deadline: await physics_frame
func ground(point: Vector3) -> Vector3:
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*3,point-Vector3.UP*3,1))
	return hit.position+Vector3.UP*.08 if not hit.is_empty() else point
func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/"+label+".png")
func person(point: Vector3, id: int) -> Dictionary:
	var actor := ACTOR.new()
	actor.identity = id
	world.add_child(actor)
	actor.position = ground(point)
	actor.route = PackedVector3Array([actor.position, actor.position+Vector3.RIGHT*6])
	world.people.append(actor)
	var record := {"actor":actor,"start":actor.position,"anchor":actor.position,"sample_clock":0.0,"stalled":0.0,"max_stalled":0.0,
		"forward_clock":0.0,"max_forward":0.0,"reacted":false,"dodged":false,"hit":false,"moved":0.0,"removed_healthy":false}
	actor.tree_exiting.connect(func(): record.removed_healthy = actor.health==100 and not actor.dead and not actor.has_meta("street_down"))
	return record
func wall_at(point: Vector3, forward: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.name="TemporaryEscapeTestWall"
	wall.collision_layer = 1
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(.4,3,12)
	collider.shape = shape
	wall.add_child(collider)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("64696a")
	mesh.material_override = material
	wall.add_child(mesh)
	world.add_child(wall)
	wall.position = ground(point)+Vector3.UP*1.5
	wall.rotation.y = atan2(-forward.x,-forward.z)
	return wall

func scenario(index: int, force_sidewalk: bool) -> void:
	var prefix := "ciclo_%d" % index
	print("COMBINED_BEGIN ",prefix," population=",world.people.size()," vehicles=",world.production.vehicles.size())
	var witnesses: Array = []
	var walls: Array = []
	if force_sidewalk:
		# Pedestres já caminham na calçada inferior antes das manobras; não
		# dependem do nome do controlador que vier a abrir a fila.
		for point in [Vector3(-333,0,11.5),Vector3(-333,0,12.5),Vector3(-334.5,0,11.5),Vector3(-334.5,0,12.5)]:
			var witness:=person(point,82000+index*100+witnesses.size())
			witness.actor.route=PackedVector3Array([witness.actor.position,witness.actor.position+Vector3.RIGHT*1.5])
			witnesses.append(witness)
		if "--with-test-wall" in OS.get_cmdline_user_args(): walls.append(wall_at(Vector3(-334,0,9.8),Vector3.LEFT))
	var cops: Array = []
	for shift in ([0.0,4.5] if force_sidewalk else [0.0]):
		var cop
		# O trânsito ativo pode ocupar um ponto entre os ciclos. Só admita uma
		# viatura onde a fábrica produtiva confirme espaço físico livre.
		for x_shift in [0.0,-5.0,5.0,-10.0,10.0]:
			cop = world.production.spawn_vehicle("union_sedan" if shift!=0 else "police_cruiser",ground(Vector3((-330 if shift!=0 else -338)+x_shift,0,15.75+shift)),PI*.5)
			if is_instance_valid(cop): break
		check(is_instance_valid(cop),prefix+" viatura física "+str(shift))
		if not is_instance_valid(cop): continue
		if shift==0: cop.set_meta("dispatch_unit",true)
		cop.set_external_driver(true)
		cop.brake_input = true
		# Obstáculo deliberadamente permanente da fixture: mantém o casco real,
		# sem permitir que um empurrão resolva a fila movendo a própria viatura.
		cop.set_physics_process(false)
		cops.append({"car":cop,"start":cop.position})
	var path: Curve3D = world.production.ambient_traffic_routes.route_near(Vector3(-270,0,8),0,Vector3.LEFT)
	check(path != null,prefix+" rota dirigida produtiva")
	if path == null: return
	var offset := path.get_closest_offset(Vector3(-314,0,16))
	var cars: Array = []
	for i in 3:
		var point := path.sample_baked(offset-i*10,true)
		var heading := path.sample_baked(offset-i*10+.5,true)-point
		var car = world.production.spawn_vehicle("union_sedan",ground(point),atan2(-heading.x,-heading.z))
		check(is_instance_valid(car),prefix+" carro da fila "+str(i))
		if not is_instance_valid(car): continue
		car.route = path
		car.route_distance = path.get_closest_offset(point)
		car.traffic = true
		car.set_meta("ambient_traffic",true)
		car.vehicle_id = prefix+"_"+str(i)
		cars.append({"car":car,"start":point,"escape_start":point,"escape_move":0.0,"outside_road":false,"escaped":false,"shift":0.0,"max_move":0.0,"retiring":false,"removed":false,"cleared":false})
	var fired := false
	var video_clock := 0.0
	var video_frames := 0
	var active_clock := 0.0
	var sample_clock := 0.0
	var telemetry: Array = []
	var evades_before: int = director.stats.vehicle_evades
	var scenario_start: float = director.clock
	var previous_clock: float = director.clock
	var deadline := Time.get_ticks_msec()+90000
	await capture(prefix+"_01_fila")
	while Time.get_ticks_msec()<deadline and director.clock-scenario_start<50:
		await physics_frame
		for record in cops:
			if is_instance_valid(record.car):
				# Impactos podem escrever momentum mesmo num casco suspenso. Zere
				# também a velocidade observável, mantendo a ameaça estacionária.
				record.car.velocity=Vector3.ZERO
				record.car.horizontal_velocity=Vector3.ZERO
				record.car.speed=0.0
		var dt: float = director.clock-previous_clock
		previous_clock = director.clock
		for record in cars:
			var car = record.car
			if not is_instance_valid(car): record.removed=true; record.cleared=true; continue
			record.max_move = maxf(record.max_move,flat(car.position,record.start))
			if record.escaped:
				record.escape_move=maxf(record.escape_move,flat(car.position,record.escape_start))
				record.outside_road=record.outside_road or outside_road(car.position)
			record.retiring = record.retiring or car.get_meta("traffic_escape_state","")=="retiring"
			if flat(car.position,Vector3(-338,car.position.y,15.75))>25 and record.max_move>20 and car.position.x<-340: record.cleared=true
			var panic: bool=car.get_meta("traffic_escape_state","")=="escaping"
			var ordinary_bypass: bool=car.bypass_side!=0 and car.bypass_blend>.7
			if (panic or ordinary_bypass) and not record.escaped:
				record.escaped = true
				record.escape_start=car.position
				record.shift = car.get_meta("traffic_escape_shift",0.0) if panic else car._bypass_shift()
				var at: float = car.route.get_closest_offset(car.position)
				var center: Vector3 = car.route.sample_baked(at+16,true)
				var tangent: Vector3 = car.route.sample_baked(at+17,true)-car.route.sample_baked(at+15,true)
				tangent.y=0; tangent=tangent.normalized()
				if not panic: center+=tangent.cross(Vector3.UP)*float(record.shift)
				var side := Vector3.UP.cross(tangent)
				# Civis com antecipação de ~16 m. Não se injeta reação/rota de fuga.
				if not force_sidewalk:
					for n in (4 if witnesses.is_empty() else 2):
						var point: Vector3 = car.route.sample_baked(at+13+n*3,true)+side*.35
						if not panic: point+=tangent.cross(Vector3.UP)*float(record.shift)
						witnesses.append(person(point,82000+index*100+witnesses.size()))
				if walls.is_empty() and "--with-test-wall" in OS.get_cmdline_user_args(): walls.append(wall_at(center+side*2.8,tangent))
				if not force_sidewalk or fired:
					world.production.state.grant_weapon("pistol")
					world.production.state.equip_weapon("pistol")
					fired = world.gameplay.fire_at(world.player.position+Vector3.BACK*20) or fired
					world.gameplay.clear_wanted()
				print("COMBINED_ESCAPE_START ",prefix," shift=",record.shift," position=",car.position," pedestrians=",witnesses.size())
		for witness in witnesses:
			var actor = witness.actor
			if not is_instance_valid(actor): continue
			var state: Dictionary = director.reactors.get(actor.get_instance_id(),{})
			witness.reacted = witness.reacted or not state.is_empty()
			if not state.is_empty() and float(state.evade_until)>director.clock: witness.dodged=true
			witness.hit = witness.hit or actor.dead or actor.health<100 or actor.has_meta("street_down")
			witness.moved = maxf(witness.moved,flat(actor.position,witness.start))
			witness.sample_clock += dt
			if witness.sample_clock>=1:
				if not state.is_empty() and state.phase=="panic" and flat(actor.position,witness.anchor)<.4:
					witness.stalled += witness.sample_clock
				else: witness.stalled=0.0
				witness.max_stalled=maxf(witness.max_stalled,witness.stalled)
				witness.anchor=actor.position; witness.sample_clock=0.0
			var running_ahead := false
			for record in cars:
				if not is_instance_valid(record.car): continue
				var threat: Dictionary = DANGER.assess(record.car,actor.position,actor.velocity)
				if threat.is_empty(): continue
				if actor.automatic_direction.dot(threat.forward)>.65: running_ahead=true
			witness.forward_clock = witness.forward_clock+dt if running_ahead else 0.0
			witness.max_forward=maxf(witness.max_forward,witness.forward_clock)
		if force_sidewalk and not fired and witnesses.any(func(record):return record.dodged):
			world.production.state.grant_weapon("pistol")
			world.production.state.equip_weapon("pistol")
			fired=world.gameplay.fire_at(world.player.position+Vector3.BACK*20)
			world.gameplay.clear_wanted()
		if not witnesses.is_empty():
			active_clock += dt
			video_clock += dt
			if video_clock>=1.0 and video_frames<50:
				video_clock=0.0
				await capture(prefix+"_video_%03d" % video_frames)
				video_frames+=1
		sample_clock += dt
		if sample_clock>=.5:
			sample_clock=0
			var sample := {"elapsed":active_clock,"cars":[],"people":[]}
			for record in cars:
				if is_instance_valid(record.car): sample.cars.append({"pos":str(record.car.position),"speed":record.car.speed,"health":record.car.health,"state":record.car.get_meta("traffic_escape_state",""),"yield":record.car.get_meta("traffic_yield_state",""),"bypass":record.car.bypass_side,"episode":record.car.traffic_escape._abandon_clock if record.car.traffic_escape!=null else -1,"blocker":str(record.car.blocker),"route_offset":record.car.route_distance,"stuck":record.car.stuck_time,"heading":str(-record.car.global_basis.z)})
			for witness in witnesses:
				if is_instance_valid(witness.actor): sample.people.append({"pos":str(witness.actor.position),"direction":str(witness.actor.automatic_direction),"velocity":str(witness.actor.velocity),"health":witness.actor.health,"down":witness.actor.has_meta("street_down"),"physics":witness.actor.is_physics_processing(),"phase":director.reactors.get(witness.actor.get_instance_id(),{}).get("phase","normal"),"stalled":witness.stalled,"forward":witness.forward_clock})
			telemetry.append(sample)
		if cars.size()==3 and cars.all(func(record):return record.cleared) and active_clock>18: break
	check(fired,prefix+" tiro real durante fuga do trânsito")
	check(cars.size()==3 and cars.all(func(record):return record.cleared),prefix+" fila inteira liberada")
	check(cars.any(func(record):return record.escaped and record.escape_move>8),prefix+" fuga física antes da limpeza")
	if force_sidewalk: check(cars.any(func(record):return record.outside_road),prefix+" deslocamento físico fora do asfalto")
	check(cops.all(func(record):return is_instance_valid(record.car) and flat(record.car.position,record.start)<1),prefix+" viaturas continuaram paradas")
	check(witnesses.size()>=4,prefix+" múltiplos pedestres na cadeia",str(witnesses.size()))
	check(director.stats.vehicle_evades>evades_before,prefix+" aproximação dos carros provocou desvio")
	check(witnesses.any(func(record):return record.dodged),prefix+" pedestre da fixture desvia do veículo")
	var people_results: Array = []
	for witness in witnesses:
		var actor = witness.actor
		check(witness.reacted and witness.moved>3,prefix+" pedestre corre "+str(people_results.size()),str(witness.moved))
		check(not witness.hit,prefix+" pedestre evita impacto "+str(people_results.size()))
		check(witness.max_stalled<3,prefix+" sem prisão persistente na parede "+str(people_results.size()),str(witness.max_stalled))
		check(witness.max_forward<.6,prefix+" sem correr prolongadamente diante do carro "+str(people_results.size()),str(witness.max_forward))
		people_results.append({"reacted":witness.reacted,"dodged":witness.dodged,"hit":witness.hit,"movement":witness.moved,"max_stalled":witness.max_stalled,"max_forward":witness.max_forward})
	await capture(prefix+"_02_fim")
	for record in cops:
		if is_instance_valid(record.car): record.car.queue_free()
	for wall in walls: wall.queue_free()
	for record in cars:
		if is_instance_valid(record.car): record.car.queue_free()
	world.gameplay.clear_wanted()
	var recovery_start: float=director.clock
	var recovery_deadline:=Time.get_ticks_msec()+30000
	while director.clock-recovery_start<16 and Time.get_ticks_msec()<recovery_deadline: await physics_frame
	var recovered:=0
	var pending_recovery: Array=[]
	for witness in witnesses:
		var actor = witness.actor
		var state: Dictionary = director.reactors.get(actor.get_instance_id(),{}) if is_instance_valid(actor) else {}
		var source = director._source(state) if not state.is_empty() else null
		if is_instance_valid(actor) and not actor.dead and state.is_empty() and not actor.controlled_automatically:
			recovered+=1
		elif not is_instance_valid(actor) and witness.removed_healthy:
			print("COMBINED_STREAMING pedestre saudável removido pela população")
		else:
			pending_recovery.append({"valid":is_instance_valid(actor),"phase":state.get("phase","normal"),"source":str(source),"timer":state.get("timer",0)})
		if is_instance_valid(actor): world.people.erase(actor); actor.queue_free()
	check(recovered>0,prefix+" retomada natural observada", "retomados=%d pendentes=%s" % [recovered,str(pending_recovery)])
	var car_results: Array=[]
	for record in cars: car_results.append({"escaped":record.escaped,"shift":record.shift,"moved":record.max_move,"escape_move":record.escape_move,"outside_road":record.outside_road,"removed":record.removed,"retiring":record.retiring,"cleared":record.cleared})
	results.append({"case":prefix,"cars":car_results,"pedestrians":people_results,"recovered":recovered,"pending_recovery":pending_recovery,"evades":director.stats.vehicle_evades-evades_before,"telemetry":telemetry})
	FileAccess.open(folder+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":results},"\t"))
	print("COMBINED_END ",prefix," cars=",car_results," people=",people_results)

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var sidewalk_only:= "--sidewalk-only" in OS.get_cmdline_user_args()
	if sidewalk_only: folder="res://evidence/auditoria-viaria/2026-10-10-fuga-integrada/skate-handover"
	create_timer(300).timeout.connect(func():quit(124))
	DirAccess.make_dir_recursive_absolute(folder)
	root.size=Vector2i(1280,720)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	var deadline:=Time.get_ticks_msec()+90000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if world.session!=null and world.session.ready_for_play: break
	check(world.session!=null and world.session.ready_for_play,"Main real pronta")
	if world.session==null or not world.session.ready_for_play: world.free(); quit(1); return
	check(world.dispatch.router._native_graph()!=null,"backend C# ativo")
	world.player.teleport(Vector3(-324,.08,30))
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.camera.target_size=55
	world.camera.initialized=false
	world.production.region.prepare_collision_at(Vector3(-338,0,15.75))
	director=world.production.civilian_reactions
	await seconds(6)
	if not sidewalk_only: await scenario(1,false)
	await scenario(2,true)
	check(world.production.is_processing() and director.is_physics_processing() and world.dispatch.enabled,"gestores produtivos continuam ativos")
	print("COMBINED_ESCAPE_RESULT checks=",checks," failures=",failures)
	FileAccess.open(folder+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":results},"\t"))
	world.free()
	quit(0 if failures.is_empty() else 1)

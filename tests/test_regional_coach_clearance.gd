extends SceneTree
## Auditoria estática do corredor, separada da interação com o trânsito e das viagens dirigidas.
const F := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const ROUTES := preload("res://runtime/regional/RegionalCoachRoute.gd")
const COACH := preload("res://runtime/regional/RegionalCoach.gd")
var world
var folder := ""
var blocked: Array = []
var checked := 0
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(420).timeout.connect(func(): push_error("COACH_CLEARANCE bounded audit timeout"); quit(3))
	folder=F.output_dir("regional-coach-clearance")
	var snapshot := F.full_snapshot(ROUTES.station("harbor").arrival+Vector3.UP*.12,true)
	snapshot.campaign.aftermath={"call_complete":true}
	var save_path := F.write_fixture(folder,"save.json",snapshot)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true); world.set_meta("menu_save_path",save_path)
	root.add_child(world); current_scene=world
	while world.session==null or not world.session.ready_for_play: await process_frame
	world.player.controlled_automatically=true
	world.player.set_physics_process(false)
	world.player.collision_layer=0
	world.session.weather.set_process(false)
	var coach := COACH.new(); world.add_child(coach)
	coach.collision_layer=0; coach.hide()
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape=coach.shape.shape
	query.collision_mask=1
	var reports: Array = []
	for from in ["harbor","mountain","desert"]:
		for to in ["harbor","mountain","desert"]:
			if from==to: continue
			if "--ice-approach" in OS.get_cmdline_user_args() and to!="mountain": continue
			var plan := ROUTES.plan(world.production,from,to)
			if not plan.get("ok",false): push_error("Missing route "+from+" -> "+to); quit(1); return
			var road: Curve3D=plan.curve
			var length := road.get_baked_length()
			var hits_before := blocked.size()
			var start := maxi(0,floori(length)-90) if "--ice-approach" in OS.get_cmdline_user_args() else 0
			for distance in range(start,ceili(length),1 if start>0 else 3):
				var point := road.sample_baked(minf(distance,length),true)
				var ahead := road.sample_baked(minf(distance+.25,length),true)
				var behind := road.sample_baked(maxf(0,distance-.25),true)
				var tangent := (ahead-behind).normalized()
				var basis := Basis(Vector3.UP,atan2(-tangent.x,-tangent.z))
				world.player.teleport(point+Vector3.UP*.2)
				world.production._update_physical_residency(point)
				for region in world.production.regions.values(): region.prepare_collision_at(point)
				await physics_frame
				if distance==start:
					# Uma auditoria local pode saltar direto entre regiões. Dá às formas de colisão
					# recém-carregadas os mesmos quadros de assentamento do embarque.
					for frame in 3: await physics_frame
				# As curvas da rua aproximam a altura. O piso renderizado da descida norte
				# é curvo, então obtém o apoio real em vez de enterrar o
				# chassi no Y interpolado da rota. Cascos em pé ficam sobre o
				# apoio mais alto sob o comprimento deles, como o motorista nativo faz.
				var support := -INF
				for along in [-coach.half_length,0.0,coach.half_length]:
					var footprint := road.sample_baked(clampf(distance+along,0,length),true)
					var ray := PhysicsRayQueryParameters3D.create(footprint+Vector3.UP*3,footprint-Vector3.UP*2,1)
					var floor_hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
					if floor_hit.is_empty() or floor_hit.normal.y<.65:
						blocked.append({"from":from,"to":to,"distance":distance,"point":str(footprint),"collider":"missing_or_steep_support"})
					else: support=maxf(support,floor_hit.position.y)
				if not is_finite(support): continue
				query.transform=Transform3D(basis,Vector3(point.x,support+coach.body_height*.5+.16,point.z))
				var hits: Array = world.get_world_3d().direct_space_state.intersect_shape(query,4)
				checked+=1
				for hit in hits:
					blocked.append({"from":from,"to":to,"distance":distance,"point":str(point),"collider":str(hit.collider.get_path())})
			print("COACH_CLEARANCE ",from," -> ",to," length=",length," blocked=",blocked.size()-hits_before)
			reports.append({"from":from,"to":to,"length":length,"blocked":blocked.size()-hits_before})
	FileAccess.open(folder+"/clearance.json",FileAccess.WRITE).store_string(JSON.stringify({"checked":checked,"routes":reports,"blocked":blocked},"\t"))
	print("COACH_CLEARANCE_FIRST ",JSON.stringify(blocked.slice(0,30)))
	print("COACH_CLEARANCE_RESULT samples=",checked," blocked=",blocked.size()," evidence=",folder)
	world.free()
	await process_frame
	quit(0 if blocked.is_empty() else 1)

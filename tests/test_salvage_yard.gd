extends SceneTree
const LEDGER := preload("res://world/shared/salvage/SalvageLedger.gd")
const LOCATION := preload("res://world/shared/salvage/SalvageLocation.gd")
var failures: Array[String]=[]
var checks:=0
var captures:=false
var yard: Node2D
var player: Node2D
var world: Node2D
var captured: Dictionary={}
const OUT := "D:/geteco/artifacts/salvage-yard-0910/"

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	create_timer(180).timeout.connect(func(): push_error("SALVAGE_TIMEOUT"); quit(2))
	captures=DisplayServer.get_name()!="headless"
	root.size=Vector2i(1280,900)
	var state:=LEDGER.new()
	for i in 6: check(state.settle("",500)==500,"Daily delivery %d" % i)
	check(state.settle("",500)==0,"Seventh delivery refused")
	var resumed:=LEDGER.new(JSON.parse_string(JSON.stringify(state.data)))
	check(resumed.available()==0,"Save/load cannot refill daily quota")
	resumed.advance(LEDGER.DAY_SECONDS)
	check(resumed.available()==6,"Next gameplay day reopens yard")
	check(resumed.accept({"label":"Test","reward":2400,"duration":10}),"Accept contract")
	var token:=String(resumed.data.contract.token)
	check(not resumed.accept({}),"Only one active contract")
	check(resumed.settle("wrong",500)==500 and not resumed.data.contract.is_empty(),"Wrong car receives ordinary scrap only")
	check(resumed.settle(token,500)==2400 and resumed.data.contract.is_empty(),"Correct target pays once")
	resumed.accept({"label":"Expired","reward":2400,"duration":1})
	resumed.advance(2)
	check(resumed.data.contract.is_empty() and resumed.data.last_result=="expired","Deadline failure")
	for old in [false,true]:
		var position:=LOCATION.center(old)
		check(LOCATION.safe_load_position(position,old)==position+Vector2(0,470),"Load restores outside machinery")
	var path: String="res://world/harbor/HarborGame.tscn" if OS.get_cmdline_user_args().has("--harbor") else "res://legacy/Main.tscn"
	for flag in ["harbor_arrival_seen","harbor_arrival_call_complete","harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(StringName(flag),true)
	world=load(path).instantiate()
	root.add_child(world)
	current_scene=world
	for i in 35: await process_frame
	while world.get("gameplay_ready")!=null and not world.gameplay_ready: await process_frame
	player=world.get_node("Player")
	yard=get_first_node_in_group("chop_shop")
	check(yard!=null,"Production scene has a salvage yard")
	player.set_physics_process(false)
	player.global_position=yard.npc.global_position+Vector2(35,10)
	player.is_control_disabled=false
	player.is_in_dialogue=false
	player.show()
	root.get_node("WantedManager").reset()
	root.get_node("CampaignState").salvage_state.clear()
	for weather in get_nodes_in_group("day_night_manager"):
		weather.is_dynamic_time=false
		weather.time_of_day=.45
		weather.weather_state=0
		weather._update_lighting()
	var camera:=Camera2D.new()
	world.add_child(camera)
	camera.global_position=yard.global_position
	camera.zoom=Vector2.ONE*.88
	camera.make_current()
	await process_frame
	var factory=load("res://world/shared/emergency/ModernTrafficFactory.gd")
	var car: Node2D=factory.spawn_parked_vehicle(world,"SalvageDelivery",yard.to_global(yard.dock),PI*.5,"union_sedan",0,Color("aa4035"))
	car.ensure_presentation()
	var balance: int=player.money
	yard._on_body_entered(car)
	for i in 4: await physics_frame
	check(yard._processing_car==null and player.money==balance,"Spawn/load overlaps never process or pay")
	car.add_to_group("personal_vehicle")
	check(not yard.confirm_delivery(car),"Personal car protected")
	car.remove_from_group("personal_vehicle")
	root.get_node("GameLoading").active=true
	check(not yard.confirm_delivery(car),"Loading blocks delivery")
	root.get_node("GameLoading").active=false
	await shot("01_patio")
	yard.open_panel()
	await shot("02_neco")
	yard._close_panel()
	yard._offered=car
	yard.accept_offer()
	check(not yard.ledger().data.contract.is_empty(),"Real target contract accepted")
	var snapshot: Dictionary=root.get_node("CampaignState").to_save_data()
	root.get_node("CampaignState").restore_from_save(JSON.parse_string(JSON.stringify(snapshot)))
	check(not yard.ledger().data.contract.is_empty(),"Contract survives campaign JSON roundtrip")
	check(yard.confirm_delivery(car),"Explicit parked delivery starts crane")
	check(player.money==balance,"No payment before crushing")
	check(not yard.confirm_delivery(car),"Repeated confirmation cannot duplicate transaction")
	check(root.get_node("SaveManager").save_game("salvage_blocked").get("reason","")=="salvage_busy","Save blocked while vehicle is in the crane")
	while yard.art.animating:
		var phase: String=yard.art.animation_phase
		if not captured.has(phase):
			captured[phase]=true
			await create_timer(.25).timeout
			await shot("03_"+phase)
		await process_frame
	await process_frame
	check(player.money==balance+2400,"Payment happens after crushing")
	check(int(yard.ledger().data.delivered)==1,"One daily delivery recorded")
	check(current_scene==world and not player.is_control_disabled,"Same world and controls restored")
	check(not is_instance_valid(car),"Only delivered vehicle removed")
	check(captured.has("lifting") and captured.has("carrying") and captured.has("dropping") and captured.has("crushing"),"Full physical crane sequence")
	await shot("04_pago")
	await audit_access()
	if OS.get_cmdline_user_args().has("--roundtrip"):
		await save_roundtrip(path)
	print("SALVAGE_RESULT checks=%d failures=%d" % [checks,failures.size()])
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func save_roundtrip(path: String) -> void:
	# SaveManager writes only the unique test slot under redirected APPDATA.
	var saves:=root.get_node("SaveManager")
	var slot: String="qa_neco_%d" % OS.get_process_id()
	yard._offered=yard._choose_target()
	yard.accept_offer()
	var contract: Dictionary=yard.ledger().data.contract
	check(not contract.is_empty(),"A real parked car is offered after delivery")
	if contract.is_empty(): return
	var token:=String(contract.token)
	var remaining:=float(contract.remaining)
	var target: Node2D=yard._target
	var target_id: String=String(target.vehicle_id)
	player.global_position=yard.global_position # Save from the prohibited machinery area.
	var result: Dictionary=saves.save_game(slot)
	check(bool(result.get("success",false)),"Save through the production adapter")
	var loaded: Dictionary=saves.load_game(slot)
	check(bool(loaded.get("success",false)),"Read the isolated saved game")
	check(not LOCATION.YARD.has_point(Vector2(float(loaded.data.player.position[0]),float(loaded.data.player.position[1]))-yard.global_position),"Saved actor relocated to the safe access")
	change_scene_to_file(path)
	await scene_changed
	world=current_scene
	for i in 35: await process_frame
	while world.get("gameplay_ready")!=null and not world.gameplay_ready: await process_frame
	yard=get_first_node_in_group("chop_shop")
	player=world.get_node("Player")
	for i in 10: await process_frame
	yard._ensure_contract_target()
	var restored: Dictionary=yard.ledger().data.contract
	check(not restored.is_empty() and String(restored.get("token",""))==token,"Same contract restored after replacing world")
	check(float(restored.get("remaining",0))>0 and float(restored.get("remaining",0))<=remaining,"Remaining time retained without restarting deadline")
	check(int(yard.ledger().data.delivered)==1,"Daily quota retained after disk load")
	check(is_instance_valid(yard._target) and String(yard._target.vehicle_id)==target_id,"Target vehicle restored")
	check(not yard.art.animating and yard._processing_car==null,"Load never triggers the machinery")
	check(not LOCATION.YARD.has_point(player.global_position-yard.global_position),"Player resumes outside the yard")

func shot(label: String) -> void:
	if not captures: return
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+label+("_harbor" if not yard.legacy else "_legacy")+".png")

func audit_access() -> void:
	var road: PackedVector2Array=yard.access_road().points
	var blocked: Dictionary={}
	var shape:=RectangleShape2D.new()
	shape.size=Vector2(78,38)
	var query:=PhysicsShapeQueryParameters2D.new()
	query.shape=shape
	query.collision_mask=1
	for i in range(road.size()-1):
		for step in range(1,int(road[i].distance_to(road[i+1])/25)):
			var p:=road[i].move_toward(road[i+1],step*25)
			query.transform=Transform2D(road[i].angle_to_point(road[i+1]),p)
			for hit in world.get_world_2d().direct_space_state.intersect_shape(query):
				if hit.collider is StaticBody2D: blocked[str(hit.collider.get_path())]=p
	check(blocked.is_empty(),"Driveable access corridor: "+str(blocked))

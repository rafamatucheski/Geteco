extends SceneTree
const STATE := preload("res://gameplay/mining/jobs/MiningYardJobState.gd")
const JOB := preload("res://gameplay/mining/jobs/MiningYardJob.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
const OPERATION := preload("res://gameplay/mining/MiningOperation.gd")
const LAYOUT := preload("res://world/mining/MiningLayout.gd")
var checks := 0
var failures: Array[String]=[]

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label); push_error(label)

func run() -> void:
	var world:={}
	var wallet:=ECONOMY.new()
	check(JOB.DEPOSIT.grow(-.75).has_point(Vector2(JOB.DESTINATION.x,JOB.DESTINATION.z)),"Relocated job destination lies inside the physical deposit bay")
	check(JOB.DESTINATION.is_equal_approx(LAYOUT.CENTER+Vector3(-13,-28,8.5)),"Job bay follows the intact quarry floor without changing depth")
	check(STATE.validate_wallet(world,wallet.snapshot()),"Old saves remain valid")
	for malformed in [null,7,"invalid",[],{}]:
		check(not STATE.validate_wallet({STATE.KEY:malformed},wallet.snapshot()),"Malformed checkpoint rejected without reading its fields: "+str(malformed))
	check(not STATE.claim(world,wallet).ok,"Unaccepted work cannot pay")
	check(STATE.begin(world),"Accept work")
	check(not STATE.begin(world),"Duplicate acceptance rejected")
	check(not STATE.deliver(world,7,JOB.DESTINATION+Vector3.UP*.58,Vector3.ZERO),"Unrelated rock cannot count")
	check(not STATE.deliver(world,0,JOB.CONTACT,Vector3.ZERO),"Source or invalid altitude cannot count")
	check(STATE.deliver(world,0,JOB.DESTINATION+Vector3(-2,.58,0),Vector3.ZERO),"First valid delivery")
	check(not STATE.deliver(world,0,JOB.DESTINATION+Vector3(-2,.58,0),Vector3.ZERO),"Same load cannot count twice")
	STATE.pause(world)
	check(STATE.data(world).delivered.size()==1 and STATE.data(world).status=="paused","Cancel/death keeps accepted work")
	check(not STATE.deliver(world,1,JOB.DESTINATION+Vector3.UP*.58,Vector3.ZERO),"Paused work cannot count")
	check(not STATE.claim(world,wallet).ok and not STATE.ready_to_claim(world),"Paused partial work cannot pay")
	check(STATE.begin(world),"Resume")
	for id in [1,2]: check(STATE.deliver(world,id,JOB.DESTINATION+Vector3(float(id-1)*2,.58,0),Vector3.ZERO),"Complete delivery "+str(id))
	var restored: Dictionary=JSON.parse_string(JSON.stringify(world))
	check(STATE.valid(restored[STATE.KEY]) and STATE.validate_wallet(restored,wallet.snapshot()),"Partial deliveries survive JSON save roundtrip")
	var full:=ECONOMY.new()
	full.grant_reward("fill_test_wallet",ECONOMY.LIMIT)
	check(not STATE.claim(restored,full).ok and STATE.data(restored).status=="active","Full wallet leaves turn-in pending")
	check(STATE.claim(restored,wallet).ok and wallet.balance==1800,"Exact one-time payment")
	check(not STATE.claim(restored,wallet).ok and wallet.balance==1800,"Replay does not pay again")
	check(STATE.validate_wallet(restored,wallet.snapshot()),"Completion receipt agrees")
	check(not STATE.validate_wallet(world,wallet.snapshot()),"Receipt without completed work rejected")
	check(not STATE.validate_wallet(restored,ECONOMY.new().snapshot()),"Completed work without payment rejected")
	var forged:=STATE.data(restored)
	forged.delivered["0"].position[0]=INF
	check(not STATE.valid(forged),"Non-finite cargo positions rejected")
	check(restored.keys()==[STATE.KEY],"Campaign untouched")
	save_load_contract()
	await physics_contract()
	print("MINING_YARD_JOB checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)

func physics_contract() -> void:
	var stage:=Node3D.new()
	root.add_child(stage)
	var ground:=StaticBody3D.new()
	var shape:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=Vector3(30,1,30)
	shape.shape=box
	ground.position=JOB.DESTINATION-Vector3.UP*.5
	ground.add_child(shape)
	stage.add_child(ground)
	var rock:=OPERATION.create_rock(0)
	rock.position=JOB.DESTINATION+Vector3.UP*2
	stage.add_child(rock)
	await physics_frame
	check(not JOB.deposit_ready(rock),"Airborne load is not a delivery")
	for frame in 180: await physics_frame
	check(JOB.deposit_ready(rock),"Real loose rock supported on static floor is accepted")
	rock.position=JOB.DESTINATION+Vector3.UP*1.5
	rock.rotation=Vector3(.8,.3,.55)
	rock.sleeping=false
	for frame in 180: await physics_frame
	check(JOB.deposit_ready(rock),"Rock resting on its side is still supported by physical convex hull")
	rock.set_meta("mining_carried_by",123)
	check(not JOB.deposit_ready(rock),"Attached load is rejected even inside destination")
	rock.remove_meta("mining_carried_by")
	rock.linear_velocity=Vector3.RIGHT
	check(not JOB.deposit_ready(rock),"Moving load does not count")
	rock.linear_velocity=Vector3.ZERO
	rock.position=JOB.DESTINATION+Vector3(3.8,.58,0)
	check(not JOB.deposit_ready(rock),"Whole rock must fit inside marked bay")
	rock.position=JOB.DESTINATION+Vector3.UP*1.58
	var scoop:=AnimatableBody3D.new()
	scoop.collision_layer=4
	var scoop_shape:=CollisionShape3D.new()
	var scoop_box:=BoxShape3D.new()
	scoop_box.size=Vector3(4,.3,4)
	scoop_shape.shape=scoop_box
	scoop.position=JOB.DESTINATION+Vector3.UP*.85
	scoop.add_child(scoop_shape)
	stage.add_child(scoop)
	for frame in 120: await physics_frame
	check(not JOB.deposit_ready(rock),"Released load resting on machine scoop does not count")
	stage.queue_free()
	await physics_frame
	await uneven_ground_contract()

func uneven_ground_contract() -> void:
	var stage:=Node3D.new()
	root.add_child(stage)
	JOB.GROUND.build_surfaces(stage,Rect2(Vector2(LAYOUT.CENTER.x-21,LAYOUT.CENTER.z+2),Vector2(18,16)))
	var rock:=OPERATION.create_rock(0)
	var point:=Vector2(LAYOUT.CENTER.x-16.0,LAYOUT.CENTER.z+10.6)
	var height:=JOB.GROUND.surface_height(point)
	rock.position=Vector3(point.x,height+.62,point.y)
	stage.add_child(rock)
	for frame in 180: await physics_frame
	var floor_height:=JOB.GROUND.surface_height(Vector2(rock.global_position.x,rock.global_position.z))
	print("MINING_JOB_UNEVEN point=",rock.global_position," floor=",floor_height," rotation=",rock.rotation)
	check(floor_height> -27.98,"fixture rests in the raised part of the actual quarry triangles")
	check(JOB.deposit_ready(rock),"quarry delivery follows actual raised terrain, not a nominal floor plane")
	var world:={}
	STATE.begin(world)
	check(STATE.deliver(world,0,rock.global_position,rock.rotation),"raised physical delivery passes persistent position validation")
	if not STATE.data(world).delivered.has("0"): stage.queue_free(); return
	var record: Dictionary=JSON.parse_string(JSON.stringify(STATE.data(world).delivered["0"]))
	var original:=rock.global_position
	rock.global_position=JOB.DESTINATION+Vector3.UP*.6
	var runtime:=JOB.new()
	stage.add_child(runtime)
	runtime.set_process(false)
	await physics_frame
	runtime._restore_delivery(rock,record)
	check(rock.freeze and rock.global_position.distance_to(original)<.03,"restore admits raised saved cargo using the same physical terrain")
	stage.queue_free()

## Fluxo do card "Limpeza da cava" com save/load de verdade (mundo e carteira em JSON):
## pausar com as três pedras entregues, salvar, carregar, receber direto (sem retomar) e recarregar.
## Sem isto, o pagamento só era provado na memória, nunca depois de restaurar a carteira.
func save_load_contract() -> void:
	var world:={}
	var wallet:=ECONOMY.new()
	check(STATE.begin(world),"save/load: accept")
	for id in STATE.COUNT: check(STATE.deliver(world,id,JOB.DESTINATION+Vector3(float(id-1)*2,.58,0),Vector3.ZERO),"save/load: delivery "+str(id))
	STATE.pause(world)
	var saved_world: Dictionary=JSON.parse_string(JSON.stringify(world))
	var saved_wallet: Dictionary=JSON.parse_string(JSON.stringify(wallet.snapshot()))
	var loaded:=ECONOMY.new()
	check(loaded.restore_snapshot(saved_wallet),"save/load: wallet restores")
	check(STATE.validate_wallet(saved_world,loaded.snapshot()),"save/load: paused full job validates")
	check(STATE.data(saved_world).status=="paused" and STATE.data(saved_world).delivered.size()==STATE.COUNT,"save/load: paused job keeps all three deliveries")
	check(STATE.ready_to_claim(saved_world),"save/load: paused full job offers Receber directly")
	var full:=ECONOMY.new()
	full.grant_reward("fill_test_wallet",ECONOMY.LIMIT)
	check(not STATE.claim(saved_world,full).ok and STATE.data(saved_world).status=="paused","save/load: full wallet keeps paused turn-in pending")
	check(STATE.claim(saved_world,loaded).ok and loaded.balance==STATE.REWARD,"save/load: paused job pays R$ 1.800 once without resuming")
	check(not STATE.claim(saved_world,loaded).ok and loaded.balance==STATE.REWARD,"save/load: paused claim replay does not pay twice")
	check(STATE.data(saved_world).status=="complete","save/load: job completes")
	var final_world: Dictionary=JSON.parse_string(JSON.stringify(saved_world))
	var final_wallet:=ECONOMY.new()
	check(final_wallet.restore_snapshot(JSON.parse_string(JSON.stringify(loaded.snapshot()))),"save/load: paid wallet restores")
	check(STATE.validate_wallet(final_world,final_wallet.snapshot()),"save/load: receipt serra_bruta_clearance survives reload")
	check(not STATE.RECEIPTS.lookup(final_wallet.snapshot(),"reward",STATE.RECEIPT).is_empty(),"save/load: receipt present")
	check(not STATE.ready_to_claim(final_world),"save/load: completed job no longer offers Receber")
	check(not STATE.begin(final_world) and not STATE.claim(final_world,final_wallet).ok and final_wallet.balance==STATE.REWARD,"save/load: completed job cannot restart or pay twice after reload")

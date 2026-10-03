extends SceneTree
const ZOO=preload("res://world/mountain_detail/zoo/MountainZoo.gd")
const GEO=preload("res://world/mountain_detail/zoo/ZooGeometry.gd")
const ACTOR=preload("res://scripts/Actor.gd")
const STATE=preload("res://runtime/GameState.gd")
const TICKETS=preload("res://world/mountain_detail/zoo/ZooTicketState.gd")
class TestGameplay extends Node:
	var health:=100.0
class TestDriving extends Node:
	var occupied:=false
class TestWorld extends Node3D:
	var player=ACTOR.new()
	var gameplay=TestGameplay.new()
	var driving=TestDriving.new()
class TestSession extends Node:
	var state=STATE.new()
	var world=TestWorld.new()
	var ready_for_play:=true
	var modal:=false
	var messages: Array[String]=[]
	func show_message(message: String) -> void: messages.append(message)
var failures: Array[String]=[]
func _initialize() -> void:
	create_timer(90).timeout.connect(func(): push_error("Zoo ticket test timeout"); quit(2))
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error(label)
func frames(n: int) -> void:
	for i in n: await physics_frame
func run() -> void:
	var session:=TestSession.new(); root.add_child(session); root.add_child(session.world)
	session.world.add_child(session.world.gameplay); session.world.add_child(session.world.driving)
	session.world.player.is_player=true; session.world.add_child(session.world.player)
	session.world.player.set_physics_process(false)
	var zoo:=ZOO.new(); zoo.position=ZOO.CENTER; root.add_child(zoo); zoo.session=session
	zoo.set_process(false)
	GEO.solid(zoo,"FixtureGround",Vector3(0,-.1,0),Vector3(100,.2,100))
	session.world.player.teleport(ZOO.CENTER+Vector3(-.7,.08,22))
	await frames(4)
	var admission=zoo.admission
	check(not admission.purchase(),"No purchase without sufficient funds")
	check(not admission.state().active and session.state.economy.balance==0,"Failed payment changes neither ticket nor balance")
	check(session.world.player.test_move(session.world.player.global_transform,Vector3(0,0,-5)),"Unpaid player physically blocked")
	session.state.economy.grant_reward("zoo_ticket_test",90)
	check(admission.purchase(),"Player can buy at gate")
	check(session.state.economy.balance==60,"Exactly $30 deducted")
	check(not admission.purchase() and session.state.economy.balance==60,"Repeated input never double-charges")
	check(not session.world.player.test_move(session.world.player.global_transform,Vector3(0,0,-5)),"Paid player passes the same physical gate")
	session.world.player.teleport(ZOO.CENTER+Vector3(-1,.08,17)); await frames(3)
	check(admission.state().inside,"Visit becomes active after entering")
	var saved: Dictionary=session.state.snapshot()
	check(TICKETS.valid(saved.world.mountain_zoo,saved.economy),"Saved admission is backed by actual payment receipt")
	var restore:=STATE.new()
	check(restore.restore_snapshot(saved),"Full GameState restores paid admission")
	session.state=restore
	check(admission.state().active,"Restored visit does not demand a second charge")
	var forged:=saved.duplicate(true); forged.world.mountain_zoo.receipt="forged"
	check(not STATE.new().restore_snapshot(forged),"Forged unpaid admission cannot be restored")
	session.world.player.teleport(ZOO.CENTER+Vector3(-.7,.08,23)); await frames(3)
	check(not admission.state().active,"Leaving consumes the visit")
	session.world.player.teleport(ZOO.CENTER+Vector3(-.7,.08,22)); await frames(3)
	check(admission.purchase() and session.state.economy.balance==30,"A new visit charges a new receipt")
	# Observe actual visitor movement, queue and payment, without crediting the player's wallet.
	session.world.player.teleport(ZOO.CENTER+Vector3(-5,.08,24))
	for i in 1800:
		await physics_frame
		if admission.npc_sales>=4: break
	check(admission.npc_sales==4 and admission.npc_revenue==120,"Four NPCs queue and pay their own $30 admissions")
	check(session.state.economy.balance==30,"NPC spending never changes player's wallet")
	for visitor in admission.visitors:
		check(visitor.spent==30,"Each visitor paid once")
		check(visitor.wallet==100+int(visitor.actor.identity-650)*10-30,"NPC wallet debited")
	# Exhausted visitor refused by the same payment phase, without opening their collision exception.
	var visitor: Dictionary=admission.visitors[0]
	visitor.actor.remove_collision_exception_with(admission.gate)
	visitor.actor.teleport(ZOO.CENTER+Vector3(.8,.08,22.4))
	visitor.paid=false; visitor.wallet=0; visitor.phase="pay"; visitor.wait=0
	var rejection_queue: Array[Dictionary]=[visitor]
	admission._update_visitor(visitor,rejection_queue,.1)
	check(not visitor.paid and visitor.phase=="depart" and admission.npc_rejected==1,"Unfunded NPC is refused admission")
	check(visitor.actor.test_move(visitor.actor.global_transform,Vector3(0,0,-4)),"Unfunded NPC remains physically blocked")
	# Cached zoo cleanup must remove residents and all player collision exceptions.
	root.remove_child(zoo); await frames(2)
	check(admission.visitors.is_empty(),"Unloading clears all visitor actors")
	root.add_child(zoo); await frames(3)
	check(admission.visitors.size()<=4,"Re-entry has bounded population")
	print("ZOO_TICKETS ","PASS" if failures.is_empty() else str(failures))
	zoo.free(); session.world.free(); session.free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)

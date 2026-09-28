extends SceneTree
const Quest := preload("res://gameplay/urban_v1/TruckersVillageQuest.gd")
const Economy := preload("res://systems/economy/Economy.gd")
class Health extends RefCounted:
	var health := 50.0
	var crime := 0
	func heal(amount):
		if health <= 0 or health >= 100: return false
		health = minf(100,health+amount)
		return true
	func register_crime(amount,_point): crime += amount
class Resident extends Node3D:
	var health := 100.0
	var dead := false
class Village extends Node3D:
	var tonico: Node3D
	func set_part_collected(_id,_value): pass
	func set_repaired(_value): pass
class Manager extends Node:
	signal attacked(actor,source)
	var hostile := false
	var target: Node3D
	func set_hostile(value,source): hostile=value; target=source
class Session extends RefCounted:
	var ready_for_play := true
	var world: Dictionary
	var state: Dictionary
	var controller := {"vehicles":[]}
	var buttons: Array = []
	var modal := false
	var saves := 0
	func show_message(_message): pass
	func save_game(): saves+=1
	func save_block_reason(): return "crime" if world.gameplay.crime>0 else ""
	func _menu(_title): modal=true; buttons.clear()
	func _button(label,action): buttons.append({"label":label,"action":action})
	func close_menu(): modal=false
var failures: Array[String] = []
var checks := 0
func _initialize(): run.call_deferred()
func check(ok: bool,label: String):
	checks+=1
	if not ok: failures.append(label); push_error(label)
func run():
	var player := Node3D.new()
	root.add_child(player)
	player.position=Quest.COOLER_POINT
	var session := Session.new()
	session.world={"player":player,"driving":{"occupied":false,"car":null},"gameplay":Health.new()}
	session.state={"region_id":"harbor","place_id":"","equipped_weapon":"fists","economy":Economy.new()}
	var village := Village.new()
	root.add_child(village)
	village.tonico=Resident.new()
	village.add_child(village.tonico)
	var manager := Manager.new()
	root.add_child(manager)
	var quest := Quest.new()
	root.add_child(quest)
	quest.configure(session,village)
	quest.bind_residents(manager)
	session.state.economy.grant_reward("test_funds",60)
	check(quest.perform("truckers_village_counter") and session.modal and session.buttons.size()==3,"Counter opens explicit buy/rob/back choice")
	session.buttons[0].action.call()
	check(not session.modal and session.world.gameplay.health==75 and session.state.economy.balance==40,"Choosing drink debits20 and heals25")
	check(quest.perform("truckers_village_buy_drink") and session.world.gameplay.health==100 and session.state.economy.balance==20,"Second purchase uses distinct receipt")
	check(not quest.perform("truckers_village_buy_drink") and session.state.economy.balance==20,"Full health never spends money")
	session.world.gameplay.health=95
	check(quest.perform("truckers_village_buy_drink") and session.world.gameplay.health==100,"Healing clamps to maximum")
	session.world.gameplay.health=50
	check(not quest.perform("truckers_village_buy_drink") and session.world.gameplay.health==50,"Insufficient money never heals")
	session.world.gameplay.health=0
	check(not quest.perform("truckers_village_buy_drink") and not quest.perform("truckers_village_rob_register"),"Dead player cannot buy or rob")
	session.world.gameplay.health=50
	player.position+=Vector3(4,0,0)
	check(not quest.perform("truckers_village_rob_register"),"Stale menu cannot rob remotely")
	player.position=Quest.COOLER_POINT
	check(not quest.perform("truckers_village_rob_register"),"Robbery requires an equipped weapon")
	session.state.equipped_weapon="pistol"
	var pre_robbery := quest.snapshot()
	var saves_before := session.saves
	check(quest.perform("truckers_village_rob_register") and session.state.economy.balance==180,"Armed explicit robbery awards register once")
	check(manager.hostile and manager.target==player and session.world.gameplay.crime==30,"Robbery provokes real manager target and reports crime")
	check(session.saves==saves_before,"Crime respects checkpoint restrictions")
	check(not quest.perform("truckers_village_rob_register") and session.state.economy.balance==180,"Repeated robbery cannot duplicate reward")
	check(not quest.perform("truckers_village_buy_drink") and quest.objective().contains("armados"),"Hostility closes sales and supplies HUD objective")
	var hostile_save := quest.snapshot()
	check(quest.restore_snapshot(hostile_save) and manager.hostile,"Restore preserves hostile state and register cooldown")
	quest._physics_process(121)
	check(not manager.hostile and quest.commerce.data.register_cooldown==479,"Hostility expires independently of register replenishment")
	check(not quest.perform("truckers_village_rob_register"),"Empty register stays unavailable after residents calm")
	quest._physics_process(478)
	check(not quest.perform("truckers_village_rob_register"),"Register cooldown is exclusive before deadline")
	quest._physics_process(1)
	check(quest.perform("truckers_village_rob_register") and session.state.economy.balance==360,"Replenished register permits one new cycle")
	check(quest.restore_snapshot(pre_robbery) and quest.commerce.data.robbery_serial==2 and quest.commerce.data.register_cooldown==600,"Wallet reconciles replayed old village marker without reward duplication")
	check(not quest.perform("truckers_village_rob_register") and session.state.economy.balance==360,"Replayed marker cannot bypass cooldown")
	session.world.gameplay.health=0
	quest._physics_process(1)
	check(not manager.hostile and quest.commerce.data.register_cooldown>0,"Player death stops attackers without refilling register")
	session.world.gameplay.health=50
	village.tonico.dead=true
	check(not quest.perform("truckers_village_buy_drink") and not quest.perform("truckers_village_rob_register"),"Dead Tonico cannot trade or be threatened")
	village.tonico.dead=false
	manager.attacked.emit(village.tonico,player)
	check(manager.hostile,"Player attacking a resident also triggers village hostility")
	var invalid := quest.snapshot()
	invalid.commerce.hostility=INF
	check(not quest.restore_snapshot(invalid),"Invalid timer snapshot rejected")
	invalid=quest.snapshot()
	invalid.commerce.drink_serial=-1
	check(not quest.restore_snapshot(invalid),"Invalid receipt counter rejected")
	quest.free()
	manager.free()
	village.free()
	player.free()
	print("TRUCKERS_VILLAGE_COMMERCE checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)

extends SceneTree
## Botão/controlador real da noite com um dublê de fila: nenhum laço físico do motor
## é necessário para provar que um bilhete abandonado não pode despachar uma corrida classificada.
const NIGHT := preload("res://activities/desert_drag/DragNightProgress.gd")
const CONTROLLER := preload("res://activities/desert_drag/DragNightController.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
var checks := 0
var failures: Array[String] = []

class SessionDouble extends Node:
	var ready_for_play := true
	var controller := {"save_invalid":false}
	var state := {"region_id":"desert","place_id":"","world_state":{},"economy":ECONOMY.new()}
	var world := {"gameplay":{"health":100},"driving":{"occupied":false}}
	var modal := false
	var rescue_pending := false
	var arrest_pending := false
	var panel := Control.new()
	var menu_closed: Callable
	var race: Node
	var saves := 0
	var saved_world := {}
	func is_transition_blocked() -> bool: return false
	func _menu(_title: String) -> void: modal=true
	func save_game() -> bool:
		if not race.open_meet.pending.is_empty(): return false
		saves+=1
		saved_world=state.world_state.duplicate(true)
		return true

class QueueDouble extends Node:
	var race: Node
	var pending := ""
	var cancellations := 0
	var ranked_starts := 0
	func cancel_ticket(_notify := true, reason := "cancelled") -> void:
		if pending.is_empty(): return
		cancellations+=1
		race.cancel_waiting_context(reason)
		pending=""
	func dispatch_if_pending() -> void:
		if not pending.is_empty(): ranked_starts+=1

class RaceDouble extends Node3D:
	var session: Node
	var open_meet: Node
	var night_controller: Node
	var active := false
	var pending_context := true
	func can_race(identity: String) -> bool: return identity=="digo"
	func rival_config(_identity: String) -> Dictionary: return {"name":"Digo"}
	func cancel_waiting_context(reason: String) -> void:
		pending_context=false
		night_controller.cancel_attempt(reason)

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks+=1
	print("DRAG_NIGHT_ABANDON ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func _run() -> void:
	var session := SessionDouble.new()
	root.add_child(session)
	session.add_child(session.panel)
	var race := RaceDouble.new()
	root.add_child(race)
	race.session=session
	session.race=race
	var queue := QueueDouble.new()
	race.add_child(queue)
	queue.race=race
	race.open_meet=queue
	var controller := CONTROLLER.new()
	race.add_child(controller)
	race.night_controller=controller
	controller.configure(race)
	check(NIGHT.begin(session.state.world_state,"digo","night_car","desert_faisca","desert_faisca").get("ok",false),"an incomplete night is registered")
	controller._armed=NIGHT.next_pass(session.state.world_state)
	var first_id: int=int(controller._armed.episode_id)
	queue.pending="digo"
	check(controller.open("digo"),"the real night panel opens while its ticket is waiting")
	await process_frame
	check(not controller.panel.buttons.abandon.disabled,"the visible abandon action is available")
	controller.panel.buttons.abandon.pressed.emit()
	check(queue.cancellations==1 and queue.pending.is_empty(),"abandon removes the queued registration")
	check(not race.pending_context and controller._armed.is_empty(),"abandon disarms transient attempt context")
	check(NIGHT.current(session.state.world_state).is_empty(),"abandon clears the durable incomplete night")
	check(session.saves==1 and NIGHT.current(session.saved_world).is_empty(),"the abandoned state is saved after the queue releases its save block")
	queue.dispatch_if_pending()
	check(queue.ranked_starts==0,"an abandoned night cannot dispatch a ranked race later")
	check(NIGHT.data(session.state.world_state).finishes==0 and NIGHT.data(session.state.world_state).wins==0 and session.state.economy.balance==0,"abandon grants no completion, merit or money")
	check(NIGHT.begin(session.state.world_state,"digo","night_car","desert_faisca","desert_faisca").get("ok",false),"another night can be registered")
	controller._armed=NIGHT.next_pass(session.state.world_state)
	check(int(controller._armed.episode_id)>first_id,"abandoned inscription identities are not recycled")
	queue.pending="digo"
	race.pending_context=true
	queue.cancel_ticket(false,"Fila cancelada.")
	check(not NIGHT.current(session.state.world_state).is_empty() and NIGHT.next_pass(session.state.world_state).step==0 and controller._armed.is_empty(),"cancelling only the queue preserves the exact unfinished pass for resumption")
	queue.dispatch_if_pending()
	check(queue.ranked_starts==0,"a cancelled queue cannot dispatch later")
	race.queue_free()
	session.queue_free()
	await process_frame
	print("DRAG_NIGHT_ABANDON_DONE checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

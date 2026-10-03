extends Node3D
## Per-body admission: a paying NPC never unlocks the barrier for an unpaid player.
const ACTOR=preload("res://scripts/Actor.gd")
const GEO=preload("res://world/mountain_detail/zoo/ZooGeometry.gd")
const TICKETS=preload("res://world/mountain_detail/zoo/ZooTicketState.gd")
const PRICE=TICKETS.PRICE
var zoo
var gate: StaticBody3D
var gate_visual: Node3D
var visitors: Array[Dictionary]=[]
var cashier: CharacterBody3D
var npc_revenue:=0
var npc_sales:=0
var npc_rejected:=0
var _spawn_clock:=0.0
var _player_granted:=false
var _initialized:=false
var _last_inside:=false
var _ticket: Dictionary={}
var _state_owner
func _ready() -> void:
	gate=GEO.solid(self,"TicketBarrier",Vector3(0,1.2,20),Vector3(3.9,2.4,.20))
	gate_visual=Node3D.new(); gate_visual.position=Vector3(0,0,20); add_child(gate_visual)
	var g:=GEO.new()
	for x in [-1.5,-.75,0,.75,1.5]: g.part("box",Vector3(x,.75,0),Vector3(.08,1.5,.1),"48584d")
	for y in [.3,1.35]: g.part("box",Vector3(0,y,0),Vector3(3.9,.1,.12),"48584d")
	g.flush(gate_visual)
func state() -> Dictionary:
	if _state_owner==zoo.session.state and not _ticket.is_empty() and is_same(_ticket,zoo.session.state.world_state.get("mountain_zoo")): return _ticket
	_state_owner=zoo.session.state
	var saved: Variant=zoo.session.state.world_state.get("mountain_zoo",{})
	if not TICKETS.valid(saved,zoo.session.state.economy.snapshot()):
		saved=TICKETS.fresh(); zoo.session.state.world_state.mountain_zoo=saved
	_ticket=saved
	return _ticket
func nearest_action() -> Dictionary:
	var session=zoo.session
	if session==null or not session.ready_for_play or session.modal or not session.state.place_id.is_empty() or session.world.driving.occupied or session.world.gameplay.health<=0: return {}
	var local: Vector3=zoo.to_local(session.world.player.global_position)
	if local.z<20 or Vector2(local.x+2.3,local.z-23.5).length()>2.8: return {}
	if state().active: return {}
	return {"id":"zoo_ticket","label":"Pagar ingresso · $%d"%PRICE,"provider":self}
func purchase() -> bool:
	if nearest_action().is_empty(): return false
	var session=zoo.session
	var ticket:=state()
	var serial:=int(ticket.serial)+1
	var receipt:="mountain_zoo_%d"%serial
	if not session.state.spend(PRICE,receipt):
		session.show_message("Ingresso: $%d. Saldo insuficiente."%PRICE); return false
	ticket.serial=serial; ticket.receipt=receipt; ticket.active=true; ticket.inside=false
	session.state.world_state.mountain_zoo=ticket
	_allow_player(true)
	session.show_message("Ingresso pago · $%d"%PRICE)
	return true
func _allow_player(allowed: bool) -> void:
	if not is_instance_valid(zoo.session) or not is_instance_valid(zoo.session.world.player): return
	var player: CharacterBody3D=zoo.session.world.player
	if allowed==_player_granted: return
	_player_granted=allowed
	if allowed: player.add_collision_exception_with(gate)
	else: player.remove_collision_exception_with(gate)
func _physics_process(delta: float) -> void:
	if zoo.session==null or not zoo.session.ready_for_play: return
	var player: CharacterBody3D=zoo.session.world.player
	var p: Vector3=zoo.to_local(player.global_position)
	var near: bool=Vector2(p.x,p.z).length()<65 and zoo.session.state.place_id.is_empty()
	if not near:
		if _initialized: _clear_visitors()
		if _player_granted:
			var ticket:=state(); ticket.active=false; ticket.inside=false
			_allow_player(false)
		return
	if not _initialized: _initialize_staff()
	var ticket:=state()
	var inside:=Geometry2D.is_point_in_polygon(Vector2(p.x,p.z),PackedVector2Array(zoo.BOUNDARY))
	if ticket.active:
		if inside and p.z<19: ticket.inside=true
		if ticket.inside and not inside and p.z>21:
			ticket.active=false; ticket.inside=false
	_allow_player(bool(ticket.active) or inside)
	_last_inside=inside
	_spawn_clock+=delta
	if visitors.size()<4 and _spawn_clock>3:
		_spawn_clock=0; _spawn_visitor(visitors.size())
	var gate_open:=_player_granted and absf(p.z-20)<3 and absf(p.x)<2
	var waiting: Array[Dictionary]=[]
	for visitor in visitors:
		if visitor.phase in ["queue","pay"]: waiting.append(visitor)
	for visitor in visitors:
		_update_visitor(visitor,waiting,delta)
		var at: Vector3=zoo.to_local(visitor.actor.global_position)
		if visitor.paid and absf(at.z-20)<2.8 and absf(at.x)<2: gate_open=true
	gate_visual.position.y=move_toward(gate_visual.position.y,2.5 if gate_open else 0,delta*3)
func _initialize_staff() -> void:
	_initialized=true
	cashier=ACTOR.new(); cashier.name="ZooCashier"; cashier.identity=624
	cashier.controlled_automatically=true
	# The booth's visible base is a closed cabinet, so clerk stands beside it on the ground.
	cashier.position=Vector3(-3.2,.06,21.1); add_child(cashier)
	cashier.set_physics_process(false)
func _spawn_visitor(index: int) -> void:
	var actor:=ACTOR.new(); actor.name="ZooVisitor%d"%index; actor.identity=650+index
	actor.controlled_automatically=true; actor.speed=1.6; actor.position=Vector3(.8,.06,24+index*1.3)
	add_child(actor)
	var note:=MeshInstance3D.new(); var mesh:=BoxMesh.new(); mesh.size=Vector3(.16,.075,.012); note.mesh=mesh
	var mat:=StandardMaterial3D.new(); mat.albedo_color=Color("678356"); note.material_override=mat
	note.position=Vector3(.22,1.08,-.5); actor.add_child(note); note.hide()
	actor.visual.get_child(0).hand_provider=func() -> Array:
		return [null,note.global_position] if note.visible else [null,null]
	visitors.append({"actor":actor,"wallet":100+index*10,"paid":false,"phase":"queue","wait":0.0,"stop":0,"note":note,"spent":0})
func _walk(visitor: Dictionary, target: Vector3) -> bool:
	var actor: CharacterBody3D=visitor.actor
	var direction: Vector3=zoo.to_global(target)-actor.global_position; direction.y=0
	actor.automatic_direction=direction.normalized() if direction.length()>.18 else Vector3.ZERO
	return direction.length()<=.18
func _update_visitor(v: Dictionary, waiting: Array[Dictionary], delta: float) -> void:
	if v.actor.dead:
		v.note.hide(); v.phase="done"; return
	match v.phase:
		"queue":
			var slot:=waiting.find(v)
			if _walk(v,Vector3(-3.2,.06,24+slot*1.5)) and slot==0:
				v.phase="pay"; v.wait=1.8; v.note.show()
		"pay":
			v.actor.automatic_direction=Vector3.ZERO
			v.wait-=delta
			if v.wait<=0:
				v.note.hide()
				if int(v.wallet)<PRICE: npc_rejected+=1; v.phase="depart"; return
				v.wallet-=PRICE; v.spent+=PRICE; npc_revenue+=PRICE; npc_sales+=1
				v.paid=true; v.actor.add_collision_exception_with(gate); v.phase="approach_gate"
		"approach_gate":
			if _walk(v,Vector3(.8,.06,24)): v.phase="enter"
		"enter":
			if _walk(v,Vector3(.8,.06,17)): v.phase="tour"; v.stop=0; v.wait=0.0
		"tour":
			var route: Array[Vector3]=[Vector3(.6,.06,8),Vector3(.6,.06,0),Vector3(.6,.06,-8),Vector3(-.6,.06,0),Vector3(-.6,.06,8),Vector3(-.6,.06,17)]
			if _walk(v,route[int(v.stop)]):
				v.wait+=delta
				if v.wait>4:
					v.wait=0; v.stop+=1
					if v.stop>=route.size(): v.phase="exit"
		"exit":
			if _walk(v,Vector3(-.7,.06,23)):
				v.paid=false; v.actor.remove_collision_exception_with(gate); v.phase="depart"
		"depart":
			if _walk(v,Vector3(3.6,.06,27)): v.phase="done"; v.wait=8.0
		"done":
			v.actor.automatic_direction=Vector3.ZERO; v.wait-=delta
			if v.wait<=0 and not v.actor.dead: v.phase="queue"
func _clear_visitors() -> void:
	for v in visitors:
		if is_instance_valid(v.actor): v.actor.queue_free()
	visitors.clear()
	if is_instance_valid(cashier): cashier.queue_free()
	cashier=null; _initialized=false
func _exit_tree() -> void:
	_allow_player(false)
	_clear_visitors()

extends Node3D
## Hidden exterior relays; the existing region admission owns every transfer.
const STATE := preload("res://runtime/secret_travel/SecretTravelState.gd")
const G := preload("res://world/desert/DesertGeometry.gd")
const SITES := {
	"harbor":{"title":"Harbor · Vila dos Caminhoneiros","point":Vector3(-392,0,72)},
	"mountain":{"title":"Montanha · Passagem de pedra","point":Vector3(737,0,-875)},
	"desert":{"title":"Deserto · Mina desativada","point":Vector3(-1272,0,-1060)},
}
var session
var site: Node3D
var site_id := ""
var _clock := 0.0
var transferring := false
var _curtain: CanvasLayer

func configure(owner_session) -> void:
	session=owner_session
	name="SecretFastTravel"

static func arrival(id: String) -> Vector3:
	return SITES[id].point+Vector3(0,0,2.4)

func _process(delta: float) -> void:
	_clock-=delta
	if _clock>0 or session==null or not session.ready_for_play: return
	_clock=.5
	var id: String=session.state.region_id
	var near: bool=id in SITES and session.state.place_id.is_empty() and session.world.player.global_position.distance_to(SITES[id].point)<105
	if is_instance_valid(site) and (not near or site_id!=id): site.queue_free(); site=null; site_id=""
	if near and not is_instance_valid(site):
		site_id=id
		site=Node3D.new()
		site.name="ConcealedRelay"
		site.position=SITES[id].point
		add_child(site)
		if id=="desert":
			# The abandoned mine relay is recessed among sandstone, screened from
			# the highway to the east. Keep its southern approach and arrival clear.
			var rock:=preload("res://world/desert/DesertSurfaceRocks.gd")
			rock.rock(site,"RelayEastScreen",Vector3(1.0,.88,-.10),Vector3(1.1,1.95,2.2),Color("a88b65"),true)
			rock.rock(site,"RelayWestScreen",Vector3(-1.0,.72,-.30),Vector3(.95,1.6,1.7),Color("b49971"),true)
			rock.rock(site,"RelayRearRock",Vector3(0,.84,-.94),Vector3(1.9,1.9,1.05),Color("af936d"),true)
		# Human-scale weathered service cabinet, dark recess, conduit and latch.
		# No floating label, map reveal, extra lighting or particles.
		G.box(site,"Cabinet",Vector3(0,.68,0),Vector3(.72,1.36,.38),Color("666a5e"),true)
		G.box(site,"Recess",Vector3(0,.92,.195),Vector3(.53,.38,.015),Color("22292a"))
		G.box(site,"Screen",Vector3(-.05,.97,.21),Vector3(.30,.16,.02),Color("809581"))
		G.box(site,"Latch",Vector3(.25,.55,.23),Vector3(.06,.18,.07),Color("8b8270"),true)
		G.box(site,"Conduit",Vector3(-.43,.39,-.09),Vector3(.06,.78,.07),Color("716852"),true)
		for index in 4: G.box(site,"Key",Vector3(-.15+index*.1,.73,.21),Vector3(.055,.045,.025),Color("bbb39d"))

func _near_origin(id: String) -> bool:
	if id not in SITES or session.state.region_id!=id or not session.state.place_id.is_empty() or not is_instance_valid(site) or site.is_queued_for_deletion() or site_id!=id: return false
	var player: Vector3=session.world.player.global_position
	var point: Vector3=SITES[id].point
	if player.z<point.z+.4 or player.distance_to(point+Vector3(0,0,1.1))>=1.6: return false
	var ray:=PhysicsRayQueryParameters3D.create(player+Vector3.UP,point+Vector3(0,.97,.30),1)
	return session.world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _available() -> bool:
	return session!=null and session.ready_for_play and not session.controller.save_invalid and not transferring and not session.modal and not get_tree().paused and not session.is_transition_blocked() and session.world.gameplay.health>0 and not session.world.player.dead and not session.world.player.input_locked and not session.world.driving.occupied and not session.world.driving.is_body_transition_active() and session.world.player.is_on_floor()

func nearest_action() -> Dictionary:
	if not _available() or not _near_origin(session.state.region_id): return {}
	return {"id":"desert","target":"secret_fast_travel","label":"Acessar rede de passagens"}

func _powered() -> bool:
	return session.urban_operations!=null and session.urban_operations.secret_network!=null and session.urban_operations.secret_network.has_power_node("power_drainage")

func _known(id: String) -> bool:
	if id in STATE.data(session.state.world_state).discovered: return true
	return id=="harbor" and session.urban_operations!=null and session.urban_operations.secret_network!=null and session.urban_operations.secret_network.has_route("route_village_house")

func block_reason() -> String:
	if not _powered(): return "Sem energia. Restaure a alimentação da rede subterrânea."
	if session.world.gameplay.stars>0: return "Despiste a polícia antes de viajar."
	if not session.state.campaign.active_id.is_empty(): return "Conclua a missão atual antes de viajar."
	if session.desert.busy() or not session.activities.can_rest(): return "Encerre a atividade atual antes de viajar."
	var reason: String=session.save_block_reason()
	return reason

func perform() -> bool:
	if nearest_action().is_empty(): return false
	var origin: String=session.state.region_id
	if STATE.discover(session.state.world_state,origin): session.save_game()
	var reason:=block_reason()
	if not reason.is_empty(): session.show_message(reason); return true
	session._menu("Rede de passagens")
	for id in SITES:
		if id==origin: continue
		var allowed: bool=_known(id)
		if id=="desert": allowed=allowed and preload("res://world/north_gateway/NorthGatewayPolicy.gd").campaign_completed(session.state.campaign.snapshot())
		session._button(str(SITES[id].title)+( "" if allowed else " · acesso não descoberto"),_select.bind(origin,id))
		var button: Button=session.column.get_child(session.column.get_child_count()-1)
		button.disabled=not allowed
	session._button("Voltar",session.close_menu)
	return true

func _select(origin: String,id: String) -> void:
	session.close_menu()
	if not _available() or not _near_origin(origin) or id==origin or not _known(id): return
	var reason:=block_reason()
	if not reason.is_empty(): session.show_message(reason); return
	transferring=true
	# A curtain hides streaming without bypassing destination collision/admission.
	_curtain=CanvasLayer.new()
	_curtain.layer=95
	var fill:=ColorRect.new()
	fill.color=Color.BLACK
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_curtain.add_child(fill)
	add_child(_curtain)
	if DisplayServer.get_name()=="headless": await get_tree().process_frame
	else: await RenderingServer.frame_post_draw
	var admitted: bool=session.controller.travel(id,arrival(id))
	if admitted:
		while is_instance_valid(session) and session.controller.travel_busy: await get_tree().process_frame
	if is_instance_valid(_curtain): _curtain.queue_free()
	_curtain=null
	transferring=false
	if not admitted: session.show_message("Não foi possível iniciar a viagem.")

func cancel_attempt() -> void:
	# Admitted transfers belong to ProductionWorld; never unlock them prematurely.
	if not transferring and is_instance_valid(_curtain): _curtain.queue_free(); _curtain=null

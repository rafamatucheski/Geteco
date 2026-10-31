extends Node3D
## Reaproveita três pedras reais da pedreira e a hidráulica de carregadeira existente. A consulta
## é limitada a 3 corpos a 5 Hz e para fora da pedreira ou durante transições.
const STATE := preload("res://gameplay/mining/jobs/MiningYardJobState.gd")
const LAYOUT := preload("res://world/mining/MiningLayout.gd")
const GROUND := preload("res://world/mining/MiningExterior.gd")
const CONTACT := LAYOUT.CENTER+Vector3(-21.7,-28,2)
const DESTINATION := LAYOUT.CENTER+Vector3(-13,-28,8.5)
const DEPOSIT := Rect2(Vector2(DESTINATION.x-4.0,DESTINATION.z-3.0),Vector2(8,6))
var session
var operation: Node
var _clock := 0.0
var _carried: Dictionary={}
var _settled: Dictionary={}
var _restored: Dictionary={}
var _markings: Node3D

static func enabled() -> bool:
	return not (OS.is_debug_build() and Engine.get_meta("mining_yard_job_disabled",false))

func configure(owner_session, owner_operation: Node = null) -> void:
	session=owner_session
	operation=owner_operation
	name="MiningYardJob"
	set_process(enabled())

func _available(on_foot := true) -> bool:
	return enabled() and session!=null and session.ready_for_play and session.state.region_id=="desert" and session.state.place_id.is_empty() and not session.modal and not get_tree().paused and not session.is_transition_blocked() and not session.desert.busy() and not session.world.driving.is_body_transition_active() and (not on_foot or not session.world.driving.occupied) and session.world.gameplay.health>0 and not session.world.player.dead and not session.world.player.input_locked

func nearest_action() -> Dictionary:
	if not _available() or session.world.player.global_position.distance_to(CONTACT)>2.6: return {}
	if _contact_actor() == null: return {}
	if STATE.data(session.state.world_state).status=="complete": return {}
	var ray:=PhysicsRayQueryParameters3D.create(session.world.player.global_position+Vector3.UP,CONTACT+Vector3.UP,1)
	if not session.world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return {}
	return {"id":"desert","target":"yard_job","label":"Conversar sobre o serviço da cava"}

func _contact_actor() -> Node3D:
	# Uma estação definida, mantida através do streaming pelo ID da estação. Nunca
	# substitui por um trabalhador distante quando quem fala de verdade está morto ou descarregado.
	for actor in get_tree().get_nodes_in_group("mining_job_contacts"):
		if not is_instance_valid(actor) or actor.get("dead") == true or not actor.is_visible_in_tree(): continue
		if actor.global_position.distance_to(CONTACT) > 4.0: continue
		return actor as Node3D
	return null

func perform(action: Dictionary) -> bool:
	if action.is_empty() or action!=nearest_action(): return false
	var state:=STATE.data(session.state.world_state)
	session._menu("Serra Bruta")
	# Entregas completas valem antes do estado pausado: o operário paga direto.
	if STATE.ready_to_claim(session.state.world_state):
		session._button("Receber R$ 1.800",_claim)
	elif state.status in ["idle","paused"]:
		session._button("Aceitar limpeza da cava · R$ 1.800" if state.status=="idle" else "Retomar limpeza da cava",_begin)
	else:
		session._button("Pausar serviço · manter entregas",_pause)
	session._button("Voltar",session.close_menu)
	return true

func _begin() -> void:
	session.close_menu()
	if nearest_action().is_empty() or not STATE.begin(session.state.world_state): return
	preload("res://runtime/desert/community/DesertCommunityState.gd").track(session.state.world_state,false)
	preload("res://runtime/desert/DesertContractState.gd").track(session.state.world_state,"")
	session.save_game()
	var actor := _contact_actor()
	var binding := preload("res://audio/VoiceActorBinding.gd").resolve(actor, "operário", "gameplay/mining/jobs/MiningYardJob.gd")
	session.show_dialogue([{"speaker":"Operário","message":"Preciso liberar as três pedras marcadas de amarelo. Use a pá da máquina e deixe cada uma dentro da baia branca. Solte a carga e recue: só conto pedra apoiada no chão. Depois volte aqui pelos mil e oitocentos.", "voice_persona":binding.get("persona", ""), "character_id":binding.get("character_id", ""), "voice_section":binding.get("section", ""), "voice_actor":weakref(actor)}])

func _pause() -> void:
	session.close_menu()
	if nearest_action().is_empty(): return
	suspend()
	session.save_game()

func _claim() -> void:
	session.close_menu()
	if nearest_action().is_empty(): return
	var result:=STATE.claim(session.state.world_state,session.state.economy)
	if not result.get("ok",false):
		session.show_message("Libere espaço na carteira para receber pelo serviço.")
		return
	session.save_game()
	session.show_message("Cava liberada. Recebidos R$ 1.800.")

func suspend() -> void:
	if session==null: return
	STATE.pause(session.state.world_state)
	_settled.clear()
	_carried.clear()

func cancel_attempt() -> void:
	suspend()

func save_block_reason() -> String:
	return ""

func objective() -> String:
	if not enabled(): return ""
	var state:=STATE.data(session.state.world_state)
	# Pausado fica fora do HUD de propósito: "pausar" é como o jogador troca o acompanhamento
	# (Água para Santa Lua, história) e este objetivo venceria o da comunidade na lista.
	if state.status!="active": return ""
	if state.delivered.size()==STATE.COUNT: return "Limpeza da cava: volte ao operário para receber R$ 1.800."
	return String(TranslationServer.translate("Limpeza da cava: use a pá e solte as pedras na baia branca (%d/3).")) % state.delivered.size()

func target_position() -> Vector3:
	return CONTACT if STATE.data(session.state.world_state).delivered.size()==STATE.COUNT else DESTINATION

func _process(delta: float) -> void:
	_clock-=delta
	if _clock>0: return
	_clock=.2
	var near: bool=session!=null and session.state.region_id=="desert" and session.state.place_id.is_empty() and session.world.player.global_position.distance_to(DESTINATION)<95
	if is_instance_valid(_markings): _markings.visible=near
	if not near: _settled.clear(); return
	if not is_instance_valid(_markings): _build_markings()
	if not is_instance_valid(operation) and session.mining!=null: operation=session.mining.operation
	if not is_instance_valid(operation): return
	var state:=STATE.data(session.state.world_state)
	for index in mini(STATE.COUNT,operation.rocks.size()):
		var rock: RigidBody3D=operation.rocks[index]
		if not is_instance_valid(rock): continue
		if state.delivered.has(str(index)):
			_restore_delivery(rock,state.delivered[str(index)])
			continue
		if not _available(false) or state.status!="active": _settled.erase(index); continue
		if rock.has_meta("mining_carried_by"):
			var carrier:=instance_from_id(int(rock.get_meta("mining_carried_by")))
			# A restauração da frota preserva arquétipo/controlador, não metadados arbitrários.
			# Exige hidráulica real ocupada segurando este corpo depois de save/reentrada.
			if is_instance_valid(carrier) and carrier is CharacterBody3D and session.world.driving.occupied and session.world.driving.car==carrier:
				var hydraulics: Node=carrier.get_node_or_null("MiningMachine")
				if hydraulics!=null and hydraulics.cargo==rock: _carried[index]=true
			_settled.erase(index)
			continue
		if not _carried.has(index) or not deposit_ready(rock): _settled.erase(index); continue
		_settled[index]=float(_settled.get(index,0.0))+.2
		if _settled[index]<1.5: continue
		if STATE.deliver(session.state.world_state,index,rock.global_position,rock.rotation):
			_accept(rock)
			session.show_message(String(TranslationServer.translate("Pedra depositada · %d/3")) % STATE.data(session.state.world_state).delivered.size())

static func deposit_ready(rock: RigidBody3D) -> bool:
	if rock.freeze or rock.has_meta("mining_carried_by") or rock.linear_velocity.length_squared()>.0225 or rock.angular_velocity.length_squared()>.04: return false
	if not DEPOSIT.grow(-.75).has_point(Vector2(rock.global_position.x,rock.global_position.z)): return false
	if rock.global_position.y< -27.8 or rock.global_position.y> -26.9: return false
	# Uma AABB visual girada tem cantos vazios abaixo da pedra convexa. Mede
	# o próprio casco físico, senão uma pedra deitada de lado parece estar no ar.
	var bottom:=INF
	for child in rock.get_children():
		if child is CollisionShape3D and child.shape is ConvexPolygonShape3D:
			for vertex in child.shape.points: bottom=minf(bottom,(child.global_transform*vertex).y)
	if not is_finite(bottom): return false
	var ray:=PhysicsRayQueryParameters3D.create(rock.global_position,Vector3(rock.global_position.x,bottom-.12,rock.global_position.z),7,[rock.get_rid()])
	var hit:=rock.get_world_3d().direct_space_state.intersect_ray(ray)
	var expected:=GROUND.surface_height(Vector2(rock.global_position.x,rock.global_position.z))
	return not hit.is_empty() and hit.collider is StaticBody3D and not hit.collider is AnimatableBody3D and float(hit.normal.y)>.8 and absf(float(hit.position.y)-expected)<.12 and absf(bottom-float(hit.position.y))<.12

func _accept(rock: RigidBody3D) -> void:
	rock.freeze=true
	rock.linear_velocity=Vector3.ZERO
	rock.angular_velocity=Vector3.ZERO
	rock.remove_meta("mining_stream_suspended")
	rock.set_meta("mining_job_delivered",true)
	_restored[rock.get_instance_id()]=true

func _restore_delivery(rock: RigidBody3D, row: Dictionary) -> void:
	if _restored.has(rock.get_instance_id()): return
	if rock.has_meta("mining_carried_by"): return
	var target:=Transform3D(Basis.from_euler(Vector3(row.rotation[0],row.rotation[1],row.rotation[2])),Vector3(row.position[0],row.position[1],row.position[2]))
	var space:=rock.get_world_3d().direct_space_state
	var floor_ray:=PhysicsRayQueryParameters3D.create(target.origin+Vector3.UP,target.origin-Vector3.UP*2,1,[rock.get_rid()])
	var floor_hit:=space.intersect_ray(floor_ray)
	var expected:=GROUND.surface_height(Vector2(target.origin.x,target.origin.z))
	if floor_hit.is_empty() or absf(float(floor_hit.position.y)-expected)>.12: return
	for child in rock.get_children():
		if not child is CollisionShape3D: continue
		var query:=PhysicsShapeQueryParameters3D.new()
		query.shape=child.shape
		query.transform=(target*child.transform).translated(Vector3.UP*.06)
		query.margin=.001
		query.collision_mask=7
		query.exclude=[rock.get_rid()]
		if not space.intersect_shape(query,1).is_empty(): return
	rock.global_transform=target
	_accept(rock)

func _build_markings() -> void:
	_markings=Node3D.new()
	_markings.name="QuarryJobGroundMarkings"
	add_child(_markings)
	# A pintura não tem colisor, luz, rótulo nem animação por quadro.
	for row in [{"center":DESTINATION,"size":Vector2(8,6),"color":Color("e3ddc8")},{"center":LAYOUT.CENTER+Vector3(-10.5,-28,-3),"size":Vector2(8,3),"color":Color("dcac3b")}]:
		var surface:=SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for axis in 2:
			for side in [-1,1]:
				var center: Vector3=row.center+Vector3(0,0,float(side)*row.size.y*.5) if axis==0 else row.center+Vector3(float(side)*row.size.x*.5,0,0)
				var along:=Vector3.RIGHT if axis==0 else Vector3.BACK
				var across:=Vector3.BACK if axis==0 else Vector3.LEFT
				var length: float=row.size.x if axis==0 else row.size.y
				var steps:=ceili(length/.25)
				for step in steps:
					var a:=center+along*(length*(float(step)/steps-.5))
					var b:=center+along*(length*(float(step+1)/steps-.5))
					for vertex in [a-across*.06,b-across*.06,b+across*.06,a-across*.06,b+across*.06,a+across*.06]:
						var p: Vector3=vertex
						p.y=GROUND.surface_height(Vector2(p.x,p.z))+.03
						surface.add_vertex(p)
		surface.generate_normals()
		var mesh:=MeshInstance3D.new()
		mesh.mesh=surface.commit()
		var material:=StandardMaterial3D.new()
		material.albedo_color=row.color
		material.roughness=1.0
		mesh.material_override=material
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_markings.add_child(mesh)

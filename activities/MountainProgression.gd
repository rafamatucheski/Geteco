extends Node
## Production V1: ContinuousWorld -> MountainPass -> MountainSkiArea / MysteryDirector.
const Definitions := preload("res://activities/ActivityDefinitions.gd")
const Motorsport := preload("res://activities/Motorsport.gd")
const RewardPolicy := preload("res://activities/V1OptionalRewardPolicy.gd")
const COURSES := {
	"ski_primeira_descida":{"name":"Primeira descida","start":Vector2(6600,-3050),"points":[Vector2(6540,-3370),Vector2(6680,-3690),Vector2(6570,-4010),Vector2(6700,-4310)],"reward":260,"bonus":120,"clues":0},
	"ski_slalom_pinhal":{"name":"Slalom do Pinhal","start":Vector2(7000,-3050),"points":[Vector2(7160,-3370),Vector2(6890,-3680),Vector2(7240,-4010),Vector2(6900,-4370),Vector2(7100,-4690)],"reward":480,"bonus":220,"clues":0},
	"ski_pista_da_sombra":{"name":"Pista da Sombra","start":Vector2(7380,-3050),"points":[Vector2(7580,-3400),Vector2(7330,-3740),Vector2(7700,-4120),Vector2(7420,-4510),Vector2(7600,-4780)],"reward":900,"bonus":400,"clues":3}}
const CLUES := ["mountain_expedition_pack","mountain_expedition_journal","mountain_expedition_camera"]
var session
var data := {"version":1,"rental":false,"equipment":false,"rental_serial":0,"best":{},"shadow_announced":false}
var skiing := false
var race = Motorsport.new()
var heading := Vector3.FORWARD
var glide := Vector3.ZERO
var fall_time := 0.0
var turn_stress := 0.0
var shadow: CharacterBody3D
var equipment_visual: Node3D
var gate: Node3D
var status: Label
var _shadow_clock := 0.0
var starts: Dictionary = {}
var course_visuals: Node3D
var lift: Node
var _hud_clock := 0.0
var _gate_target := Vector3(INF, INF, INF)
var _ski_pose: Array = []

func configure(owner_session) -> void:
	session = owner_session
	var saved: Variant = session.state.world_state.get("mountain_progression",{})
	if saved is Dictionary and not saved.is_empty() and not restore_snapshot(saved):
		session.controller.save_invalid = true
		session.show_message("Estado da serra inválido; save original preservado.")
	session.world.player.ski_controller = self
	lift = preload("res://activities/MountainSkiLift.gd").new()
	lift.configure(self)
	add_child(lift)
	course_visuals = preload("res://activities/MountainSkiCourseVisuals.gd").new()
	course_visuals.configure(self)
	session.world.add_child(course_visuals)
	status = Label.new()
	status.position = Vector2(24,156)
	status.add_theme_font_size_override("font_size",20)
	status.add_theme_color_override("font_outline_color", Color("101820"))
	status.add_theme_constant_override("outline_size", 5)
	session.world.hud.add_child(status)
	gate = session.activities._beacon(Vector3.ZERO,Color("74d9ff"),true)
	gate.hide()
	for id in COURSES:
		var beacon: Node3D = session.activities._beacon(Definitions.at(COURSES[id].start,"mountain"),Color("74d9ff"))
		beacon.hide()
		starts[id]=beacon
	session.apply_outfit()

func _open() -> bool:
	var time: float = float(session.state.world_state.get("time",.32))
	if is_instance_valid(session.weather): time = session.weather.time_of_day
	return time >= 8.0/24.0 and time < 18.0/24.0

func clue_count() -> int:
	var found: Array = session.state.economy.snapshot().collectibles
	var total := 0
	for id in CLUES:
		if found.has(id): total += 1
	return total

func stats() -> Dictionary:
	return {"ski_races":data.best.size()}

func show_services() -> void:
	if not _at_counter(): return
	session._menu("Ski")
	if data.rental:
		session._button("Devolver equipamento",func():
			if not _at_counter(): session.close_menu(); return
			_stop(); data.rental=false; data.equipment=false
			session.apply_outfit(); session.close_menu(); _commit())
		if not data.equipment:
			session._button("Retirar skis e bastões",func():
				if not _at_counter(): session.close_menu(); return
				data.equipment=true; session.close_menu(); _commit())
	else:
		session._button("Alugar roupa, skis e bastões · R$ 250",func():
			if not _at_counter() or data.rental: session.close_menu(); return
			session.close_menu()
			if not _open(): session.show_message("Locação: 08:00 às 18:00."); return
			var serial: int = int(data.rental_serial)+1
			if not session.state.economy.spend(250,"ski_rental:%d"%serial): session.show_message("Saldo insuficiente."); return
			data.rental_serial=serial; data.rental=true; data.equipment=true
			session.apply_outfit(); _commit())
	session._button("Fechar",session.close_menu)
	for child in session.column.get_children():
		if child is Button:
			child.grab_focus.call_deferred()
			break

func _at_counter() -> bool:
	if session.state.region_id!="mountain" or session.state.place_id!="ski_lodge" or session.world.gameplay.health<=0 or session.controller.save_invalid or session.world.driving.occupied: return false
	if not is_instance_valid(session.room) or not session.room.interaction_points.has("service"): return false
	return session.world.player.position.distance_to(session.room.interaction_points.service)<1.5

func cancel_attempt() -> void:
	if is_instance_valid(lift): lift.cancel()
	_stop()

func _outside() -> bool:
	return session.state.region_id=="mountain" and session.state.place_id.is_empty() and not session.world.driving.occupied and session.world.gameplay.health>0 and session.state.campaign.active_id.is_empty()

func nearest_action() -> Dictionary:
	if is_instance_valid(lift) and lift.riding: return _action("ski_lift_skip", "Adiantar viagem", session.world.player.position)
	if session==null or session.modal or session.controller.save_invalid or not _outside(): return {}
	if session.world.player.input_locked: return {}
	var point: Vector3 = session.world.player.position
	if race.mode!="": return _action("ski_cancel","Cancelar prova",point)
	if is_instance_valid(lift) and lift.can_board(): return _action("ski_lift", "Teleférico para o cume", point)
	for id in COURSES:
		var start := Definitions.at(COURSES[id].start,"mountain")
		if _flat(point).distance_to(start)<3.0:
			return _action("ski_start:"+id,"Iniciar · "+str(COURSES[id].name),point)
	if skiing: return _action("ski_remove","Retirar skis",point)
	if data.equipment and _on_slope(point): return _action("ski_equip","Colocar skis",point)
	return {}

func _action(id: String, label: String, point: Vector3) -> Dictionary:
	return {"id":id,"target":id,"label":label,"position":point,"range":3.75}

func perform(target: Variant) -> bool:
	var id: String = str(target.get("target","")) if target is Dictionary else str(target)
	if nearest_action().get("target","")!=id: return false
	if id == "ski_lift_skip": lift.skip(); return true
	if id == "ski_lift": return lift.board()
	if id in ["ski_cancel","ski_remove"]: _stop(); return true
	if not data.rental or not data.equipment:
		session.show_message("Alugue a roupa e retire os skis no Summit."); return true
	if id=="ski_equip": _equip(); return true
	if not id.begins_with("ski_start:"): return false
	var course_id := id.trim_prefix("ski_start:")
	var spec: Dictionary = COURSES[course_id]
	if not _open(): session.show_message("Pistas abertas das 08:00 às 18:00."); return true
	if clue_count()<int(spec.clues): session.show_message("Encontre as três pistas da expedição."); return true
	if session.world.player.velocity.length()>70.0/16.0: session.show_message("Pare junto à largada."); return true
	if not session.save_game(true): return false
	_equip()
	heading = Definitions.at(spec.start,"mountain").direction_to(Definitions.at(spec.points[0],"mountain"))
	session.world.player.visual.rotation.y = atan2(-heading.x,-heading.z)
	var points := PackedVector3Array()
	for point in spec.points: points.append(Definitions.at(point,"mountain"))
	if race.begin_race(course_id,Definitions.at(spec.start,"mountain"),points,_flat(session.world.player.position)):
		# V1 is a downhill finish, unlike the reused circuit scorer's return lap.
		race.points.resize(race.points.size()-1)
	return true

func _equip() -> void:
	skiing=true; heading=Vector3.FORWARD; glide=Vector3.ZERO; fall_time=0; turn_stress=0
	session.world.player.visual.rotation.y = 0
	session.state.equip_weapon("fists")
	if not is_instance_valid(equipment_visual):
		equipment_visual=Node3D.new()
		session.world.player.visual.add_child(equipment_visual)
		for side in [-1.0,1.0]:
			var mesh := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size=Vector3(.095,.055,1.72)
			mesh.mesh=box; mesh.position=Vector3(side*.09,.04,0)
			var material := StandardMaterial3D.new()
			material.albedo_color=Color("b84238")
			mesh.material_override=material; equipment_visual.add_child(mesh)
			var pole := MeshInstance3D.new()
			var shaft := CylinderMesh.new()
			shaft.top_radius=.013; shaft.bottom_radius=.013; shaft.height=1.15; shaft.radial_segments=6
			pole.mesh=shaft; pole.position=Vector3(side*.4,.65,.18)
			pole.rotation.x=.2; equipment_visual.add_child(pole)
	equipment_visual.show()
	_build_ski_pose()

func _build_ski_pose() -> void:
	var actor = session.world.player
	if not is_instance_valid(actor.skeleton) or actor.hips < 0: return
	actor._apply_pose(actor._idle_pose)
	var hip: Vector3 = actor.skeleton.get_bone_pose_position(actor.hips)
	hip.y -= .16
	actor.skeleton.set_bone_pose_position(actor.hips,hip)
	for side in ["Left","Right"]:
		var sign_side := -1.0 if side == "Left" else 1.0
		actor._solve_leg(side,actor.visual.to_global(Vector3(sign_side*.09,.07,0)))
		actor._solve_combat_arm(side,Vector3(sign_side*.4,1.02,.06),Basis.IDENTITY,false,sign_side)
	_ski_pose = actor._capture_pose()

func _process(_delta: float) -> void:
	if not skiing or _ski_pose.is_empty() or session.world.gameplay.health <= 0: return
	var actor = session.world.player
	actor._apply_pose(_ski_pose)

func _stop() -> void:
	skiing=false; race.cancel(); glide=Vector3.ZERO; fall_time=0; turn_stress=0
	if is_instance_valid(equipment_visual): equipment_visual.hide()
	if is_instance_valid(gate): gate.hide()
	if is_instance_valid(status): status.text=""
	_gate_target = Vector3(INF, INF, INF)

func motion(delta: float, _walking_direction: Vector3) -> Vector3:
	if not _outside() or session.modal or session.world.player.input_locked: return Vector3.ZERO
	if race.countdown>0 and race.mode!="": return Vector3.ZERO
	fall_time=maxf(0,fall_time-delta)
	if fall_time>0: return Vector3.ZERO
	var axis: Vector2 = get_node("/root/GameInput").movement()
	var brake := maxf(0,axis.y)
	if InputMap.has_action("handbrake") and Input.is_action_pressed("handbrake"): brake=1
	var speed := glide.length()
	var acceleration := 118.0/16.0*maxf(.12,heading.dot(Vector3.FORWARD))+maxf(0,-axis.y)*42.0/16.0
	if get_node("/root/GameInput").sprinting() and speed<115.0/16.0: acceleration+=95.0/16.0
	speed=clampf(speed+(acceleration-(18.0+brake*235.0)/16.0)*delta,0,455.0/16.0)
	heading=heading.rotated(Vector3.UP,-axis.x*lerpf(2.05,.88,speed/(455.0/16.0))*delta).normalized()
	glide=glide.lerp(heading*speed,1.0-exp(-4.8*delta))
	turn_stress=maxf(0,turn_stress-delta*.7)
	if absf(axis.x)>.86 and speed>330.0/16.0: turn_stress+=delta*speed/(300.0/16.0)
	if turn_stress>.8: crash(clampi(roundi(speed*16*.045),8,24)); return Vector3.ZERO
	return glide

func crash(damage: int) -> void:
	if fall_time>0: return
	fall_time=1.15; glide=Vector3.ZERO; turn_stress=0
	session.world.gameplay.damage_player(damage)

func _physics_process(delta: float) -> void:
	if session==null or not session.ready_for_play or session.modal or get_tree().paused: return
	if skiing and (not _outside() or not _on_slope(session.world.player.position)): _stop()
	if skiing:
		for index in session.world.player.get_slide_collision_count():
			var hit: KinematicCollision3D = session.world.player.get_slide_collision(index)
			var impact := maxf(0,glide.dot(-hit.get_normal()))*16.0
			if absf(hit.get_normal().y)<.65 and impact>112: crash(clampi(roundi((impact-80)*.18),6,42)); break
		if session.state.equipped_weapon!="fists": session.state.equip_weapon("fists")
	if race.mode!="":
		race.update(delta,_flat(session.world.player.position),glide,heading,skiing)
		if race.finished: _finish()
		elif race.cancelled: _stop(); session.show_message("Prova cancelada.")
		else:
			_update_gate()
	_hud_clock += delta
	if skiing and _hud_clock >= .1:
		_hud_clock = 0
		var speed_text := "%d km/h" % roundi(glide.length()*3.6)
		if race.mode != "":
			var best := float(data.best.get(race.id, 0))
			status.text = "Largada em %d" % ceili(race.countdown) if race.countdown > 0 else "%s · %.1f s · %d/%d · %s" % [COURSES[race.id].name,race.elapsed,race.gate+1,race.points.size(),speed_text]
			if best > 0: status.text += "\nRecorde: %.2f s" % best
		else:
			status.text = "Ski · "+speed_text
		status.text += "\n%s frear · %s impulso" % [get_node("/root/GameInput").hint("handbrake"),get_node("/root/GameInput").hint("sprint")]
	_shadow_clock+=delta
	if _shadow_clock>=.5:
		_shadow_clock=0
		_refresh_shadow()
		for id in starts:
			var beacon: Node3D = starts[id]
			var point := Definitions.at(COURSES[id].start,"mountain")
			beacon.visible=_outside() and _flat(session.world.player.position).distance_to(point)<100
			if beacon.visible and not beacon.has_meta("grounded"):
				var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*100,point-Vector3.UP*20,1)
				var hit: Dictionary = session.world.get_world_3d().direct_space_state.intersect_ray(query)
				if hit.is_empty(): beacon.hide()
				else: beacon.position=hit.position+Vector3.UP*.05; beacon.set_meta("grounded",true)

func _finish() -> void:
	var spec: Dictionary = COURSES[race.id]
	gate.hide(); status.text=""
	var previous_best: Variant = data.best.get(race.id,null)
	var transactions: Dictionary = session.state.economy.snapshot().transactions
	var settlement: Dictionary = RewardPolicy.ski_settlement(race.id,spec,race.elapsed,previous_best,transactions)
	if not settlement.get("ok",false):
		session.show_message("Resultado inválido; prêmio e recorde preservados.")
		return
	if not RewardPolicy.apply_ski_settlement(session.state.economy,settlement):
		session.show_message("Prêmio indisponível; resultado não registrado.")
		return
	if settlement.record: data.best[race.id]=race.elapsed
	session.activities.refresh_achievements()
	if _commit(): session.show_message("%s · %.2f s · +R$ %d%s"%[spec.name,race.elapsed,int(settlement.amount)," · Novo recorde!" if settlement.record else ""])

func _update_gate() -> void:
	var target: Vector3 = race.target_position()
	if target != _gate_target or not gate.visible:
		var query := PhysicsRayQueryParameters3D.create(target+Vector3.UP*3,target-Vector3.UP*5,1)
		var hit: Dictionary = session.world.get_world_3d().direct_space_state.intersect_ray(query)
		gate.visible = not hit.is_empty()
		if gate.visible:
			gate.position = hit.position + Vector3.UP*.05
			_gate_target = target

func _exit_tree() -> void:
	for node in starts.values():
		if is_instance_valid(node): node.queue_free()
	for node in [status, gate, equipment_visual, course_visuals, shadow]:
		if is_instance_valid(node): node.queue_free()

func on_collectible() -> String:
	var announcement := ""
	if clue_count()>=3 and not data.shadow_announced:
		data.shadow_announced=true
		announcement = "Pista da Sombra aberta. Algo se move na face norte."
	_refresh_shadow()
	return announcement

func _refresh_shadow() -> void:
	var active: bool = _outside() and clue_count()>=3
	var home := Definitions.at(Vector2(7490,-4140),"mountain")
	active=active and _flat(session.world.player.position).distance_to(home)<90
	if not active:
		if is_instance_valid(shadow): shadow.queue_free(); shadow=null
		return
	if is_instance_valid(shadow): return
	var query := PhysicsRayQueryParameters3D.create(home+Vector3.UP*100,home-Vector3.UP*20,1)
	var hit: Dictionary = session.world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return
	var volume := CapsuleShape3D.new()
	volume.radius=.5; volume.height=2.8
	var overlap := PhysicsShapeQueryParameters3D.new()
	overlap.shape=volume
	overlap.transform=Transform3D(Basis.IDENTITY,hit.position+Vector3.UP*1.55)
	overlap.collision_mask=7
	if not session.world.get_world_3d().direct_space_state.intersect_shape(overlap,1).is_empty(): return
	shadow=preload("res://activities/MountainShadow.gd").new()
	shadow.progression=self
	shadow.position=hit.position+Vector3.UP*.1
	session.world.add_child(shadow)

static func _flat(point: Vector3) -> Vector3:
	return Vector3(point.x,0,point.z)

func _on_slope(point: Vector3) -> bool:
	var local := Vector2(point.x,point.z)*16.0-Definitions.MOUNTAIN_OFFSET
	return local.x>=6100 and local.x<=7950 and local.y<=-2910 and local.y>=-4990

func _commit() -> bool:
	session.state.world_state.mountain_progression=snapshot()
	return session.save_game()

func snapshot() -> Dictionary:
	return data.duplicate(true)

func restore_snapshot(saved: Dictionary) -> bool:
	if not validate_snapshot(saved): return false
	data=saved.duplicate(true); data.rental_serial=int(data.rental_serial); _stop()
	return true

static func validate_snapshot(saved: Dictionary) -> bool:
	if saved.get("version")!=1 or not saved.get("rental") is bool or not saved.get("equipment") is bool or not saved.get("shadow_announced") is bool: return false
	if saved.equipment and not saved.rental: return false
	var serial: Variant = saved.get("rental_serial")
	if typeof(serial) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(serial)) or float(serial)<0 or float(serial)>1000000 or float(serial)!=floorf(float(serial)): return false
	if not saved.get("best") is Dictionary: return false
	for id in saved.best:
		var value: Variant = saved.best[id]
		if not COURSES.has(id) or typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or float(value)<=0 or float(value)>600: return false
	return true

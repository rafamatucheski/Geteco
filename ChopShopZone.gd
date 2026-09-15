class_name ChopShopZone
extends Node2D
## Explicit deliveries only: loading and area overlaps never start the crane.
const FINISH := preload("res://world/harbor/ExteriorFinish.gd")
const LOCATION := preload("res://world/shared/salvage/SalvageLocation.gd")
const LEDGER := preload("res://world/shared/salvage/SalvageLedger.gd")
const ART := preload("res://world/shared/salvage/SalvageYard3D.gd")
var legacy := false
var art: Node2D
var npc: Node2D
var dock: Vector2
var _processing_car: Node2D
var _target: Node2D
var _offered: Node2D
var _panel: CanvasLayer
var _status: Label
var _hint: Label
var _hud: CanvasLayer
var _scan_clock := 0.0
var _player: Node2D
var _camera: Camera2D
var _previous_camera: Camera2D
var _last_token := ""
var _current_reward := 0
var _bay_marker: Node2D
var _context_action := ""
var _context_point := Vector2.ZERO
var _feedback_clock := 0.0
var tow_service: Node

func _ready() -> void:
	# A câmera do pátio é fixa; baia e sólidos usam sua pose completa,
	# sem interpolar a criação dos elementos durante o carregamento em etapas.
	physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_to_group("chop_shop")
	art=ART.new()
	art.name="WorkingYard3D"
	add_child(art)
	dock=art.dock_point()
	art.crushed.connect(_finish_delivery)
	npc=preload("res://world/shared/salvage/Neco.gd").new()
	npc.name="Neco"
	npc.position=art.npc_point()
	add_child(npc)
	_build_collisions()
	_build_hud()
	tow_service=preload("res://world/shared/salvage/TowService.gd").new()
	tow_service.name="TowService"
	add_child(tow_service)
	var locator:=preload("res://world/shared/salvage/SalvageLocator.gd").new()
	locator.yard=self
	_hud.add_child(locator)
	for entry in [{"kind":"gate","point":Vector3(6.5,0,12.3)}]:
		var sign:=preload("res://world/shared/salvage/SalvageSign.gd").new()
		sign.kind=entry.kind
		sign.position=art.projected(entry.point)
		add_child(sign)
	_bay_marker=preload("res://world/shared/salvage/SalvageBayMarker.gd").new()
	_bay_marker.name="DeliveryGlow"
	_bay_marker.position=dock
	add_child(_bay_marker)
	_solid(Rect2(art.projected(Vector3(6.5,0,12.3))-Vector2(34,4),Vector2(68,8)))
	if not legacy:
		for wall in _shore_walls(): _solid(wall)
	if not legacy:
		for i in 12:
			var p: Vector2 = [Vector2(-500,-430),Vector2(-320,-465),Vector2(120,-460),Vector2(430,-465),Vector2(510,-410),Vector2(350,430),Vector2(440,430),Vector2(-565,-240),Vector2(-565,40),Vector2(575,-220),Vector2(575,80),Vector2(575,310)][i]
			var tree := preload("res://world/mountain_pass/MountainPine3D.gd").new()
			tree.name = "ExteriorTree%d" % (240+i)
			tree.position = p
			tree.variant_seed = 3 if i % 2 == 0 else 4
			tree.tree_scale = .9 + float(i%3)*.08
			tree.add_to_group("exterior_finish_solid")
			add_child(tree)
		for i in 2:
			FINISH.rock(self,[Vector2(-70,-445),Vector2(285,-430)][i],410+i)
	queue_redraw()

func ledger() -> RefCounted:
	return LEDGER.new(get_node("/root/CampaignState").salvage_state)

func access_road() -> Dictionary:
	return {"points":LOCATION.access(legacy),"width":100.0}

func _draw() -> void:
	FINISH.meadow(self,LOCATION.LAND,901,Color("64724e"))
	var road:=PackedVector2Array()
	for p in LOCATION.access(legacy): road.append(p-position)
	FINISH.trail(self,road,140,Color("65754f"))
	FINISH.trail(self,road,100,Color("8a8269"))
	FINISH.trail(self,road,80,Color("a49a7a"))
	# Two worn tracks follow the existing connected driveway; no new barriers.
	for j in range(road.size()-1):
		var normal := (road[j+1]-road[j]).normalized().orthogonal()*23
		for side in [-1,1]:
			draw_line(road[j]+normal*side,road[j+1]+normal*side,Color("736f5d"),9,true)
	FINISH.aggregate(self,Rect2(-510,-370,1010,55),904)
	FINISH.aggregate(self,Rect2(530,-290,65,585),905)
	if not legacy:
		for wall in _shore_walls():
			draw_rect(wall.grow(3),Color("3c4842"))
			draw_rect(wall,Color("9b9c8c"))
			var length:=maxf(wall.size.x,wall.size.y)
			for step in range(0,int(length),24):
				var point:=wall.position+(Vector2(step,0) if wall.size.x>wall.size.y else Vector2(0,step))
				draw_line(point,point+(Vector2(0,wall.size.y) if wall.size.x>wall.size.y else Vector2(wall.size.x,0)),Color("626e61"),2)

func _shore_walls() -> Array[Rect2]:
	return [Rect2(LOCATION.LAND.position,Vector2(LOCATION.LAND.size.x,12)),Rect2(LOCATION.LAND.position,Vector2(12,LOCATION.LAND.size.y))]

func _solid(rect: Rect2) -> void:
	var body:=StaticBody2D.new()
	body.position=rect.get_center()
	body.collision_layer=1
	body.collision_mask=0
	var collision:=CollisionShape2D.new()
	var shape:=RectangleShape2D.new()
	shape.size=rect.size
	collision.shape=shape
	body.add_child(collision)
	add_child(body)

func _build_collisions() -> void:
	for solid in art.solids:
		var body:=StaticBody2D.new()
		body.name=solid.id
		body.collision_layer=1
		body.collision_mask=0
		body.add_to_group("salvage_obstacle")
		var collision:=CollisionPolygon2D.new()
		collision.polygon=solid.polygon
		body.add_child(collision)
		add_child(body)

func _build_hud() -> void:
	_hud=CanvasLayer.new()
	_hud.layer=26
	add_child(_hud)
	_status=Label.new()
	_status.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_status.offset_left=-234
	_status.offset_right=-25
	_status.offset_top=298
	_status.offset_bottom=344
	_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size",16)
	_status.add_theme_color_override("font_color",Color("f1ce86"))
	_status.add_theme_constant_override("outline_size",5)
	var status_style:=preload("res://ui/GameStyle.gd").panel()
	status_style.content_margin_left=12
	status_style.content_margin_right=12
	status_style.content_margin_top=10
	status_style.content_margin_bottom=10
	_status.add_theme_stylebox_override("normal",status_style)
	_status.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_status)
	_hint=Label.new()
	var key_style:=preload("res://ui/GameStyle.gd").panel()
	key_style.content_margin_left=10
	key_style.content_margin_right=10
	key_style.content_margin_top=5
	key_style.content_margin_bottom=5
	_hint.add_theme_stylebox_override("normal",key_style)
	_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size",18)
	_hint.add_theme_constant_override("outline_size",5)
	_hint.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_hint)

func _active_world() -> bool:
	var loading:=get_node_or_null("/root/GameLoading")
	return not get_tree().paused and (loading==null or not loading.active) and not get_node("/root/SaveManager").has_pending_save()

func _process(delta: float) -> void:
	_player=get_tree().get_first_node_in_group("player") as Node2D
	if _player==null or not _active_world():
		_hud.hide()
		_bay_marker.hide()
		return
	_hud.show()
	var book:=ledger()
	if not is_instance_valid(_processing_car):
		var campaign:=get_parent().get_node_or_null("CobraCampaign")
		var day: int=int(campaign.ledger.data.day) if campaign != null else 0
		book.advance(delta,day)
	var contract: Dictionary=book.data.contract
	if contract.is_empty() and not _last_token.is_empty():
		if String(book.data.last_result) in ["expired","destroyed","interrupted"]:
			_player._show_weapon_notice(_text("NECO: encomenda encerrada. Volte para outro serviço.","NECO: order failed. Come back for another job."))
		if is_instance_valid(_target): _target.remove_meta("salvage_token")
		_target=null
		_last_token=""
	if not contract.is_empty() and not is_instance_valid(_target) and not _last_token.is_empty():
		book.fail_contract("destroyed")
		contract={}
	if not contract.is_empty() and is_instance_valid(_target):
		contract.position=[_target.global_position.x,_target.global_position.y]
		contract.rotation=_target.global_rotation
		if _target.get("health") != null and int(_target.health)<=0:
			book.fail_contract("destroyed")
		elif bool(_player.get("is_dead")) or bool(_player.get("is_arrested")):
			book.fail_contract("interrupted")
	_scan_clock+=delta
	if _scan_clock>=.5:
		_scan_clock=0
		if not contract.is_empty(): _ensure_contract_target()
	var near:=_player.global_position.distance_to(npc.global_position)<90 and _player.visible
	_feedback_clock+=delta
	if _feedback_clock>=.1:
		_feedback_clock=0
		_update_bay_feedback()
	_hint.visible=not _context_action.is_empty() and not is_instance_valid(_panel) and not is_instance_valid(_processing_car) and not bool(_player.get("is_dead")) and not _player.is_in_dialogue
	if _hint.visible:
		_hint.text=get_node("/root/GameInput").hint(_context_action).get_slice(" / ",0)
		_hint.reset_size()
		_hint.position=get_global_transform_with_canvas()*_context_point+Vector2(-_hint.size.x*.5,-52)
	_status.visible=not contract.is_empty()
	if not contract.is_empty():
		_status.text="%s • %d:%02d • $%d" % [contract.label,int(contract.remaining)/60,int(contract.remaining)%60,int(contract.reward)]
	if is_instance_valid(_panel) and (not near or bool(_player.get("is_dead"))): _close_panel()

func _unhandled_input(event: InputEvent) -> void:
	if not _active_world() or _player==null or event.is_echo(): return
	if event.is_action_pressed("ui_cancel") and is_instance_valid(_panel):
		_close_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and not is_instance_valid(_panel) and not is_instance_valid(_processing_car):
		var car:=_nearby_delivery()
		if car!=null and confirm_delivery(car):
			get_viewport().set_input_as_handled()
			return
		if _player.visible and _player.global_position.distance_to(npc.global_position)<90 and not _player.is_in_dialogue:
			open_panel()
			get_viewport().set_input_as_handled()

func _nearby_delivery() -> Node2D:
	if _player==null or not _player.visible or _player.is_in_dialogue or _player.is_dead: return null
	if ledger().available()==0 or get_node("/root/WantedManager").current_stars>0: return null
	var car:=delivery_car()
	if car==null: return null
	var distance:=_player.global_position.distance_to(car.global_position)
	# Beside the car, E delivers; beside Neco, E still opens his jobs.
	if distance<90 and distance<_player.global_position.distance_to(npc.global_position): return car
	return null

func _update_bay_feedback() -> void:
	_context_action=""
	var driven: Node2D=get_node("/root/RegionTravel").controlled_car()
	var actor: Node2D=driven if driven!=null else _player
	_bay_marker.visible=actor.global_position.distance_to(to_global(dock))<1000 and not is_instance_valid(_processing_car) and not is_instance_valid(_panel) and not _player.is_dead and ledger().available()>0
	_bay_marker.ready_for_delivery=false
	if not _bay_marker.visible: return
	if driven!=null:
		if driven.global_position.distance_to(to_global(dock))<52 and driven.velocity.length()<8:
			_context_action="exit_vehicle"
			_context_point=to_local(driven.global_position)
			_bay_marker.ready_for_delivery=true
		return
	var car:=_nearby_delivery()
	if car!=null:
		_context_action="interact"
		_context_point=to_local(car.global_position)
		_bay_marker.ready_for_delivery=true
	elif _player.visible and _player.global_position.distance_to(npc.global_position)<90:
		_context_action="interact"
		_context_point=npc.position

func _on_body_entered(_body: Node) -> void:
	pass # Compatibility: overlaps have no effects, including during load.

func eligible(car: Node2D) -> bool:
	if is_instance_valid(car) and car.get("active_archetype_id") == "porto_rosso" and _reward(car) == 0: return false
	if not is_instance_valid(car) or not car.is_in_group("vehicle"): return false
	if car.has_meta("tow_carried"): return false
	if car.is_in_group("personal_vehicle") or car.is_in_group("mission_vehicle") or car.is_in_group("emergency_vehicle"): return false
	if car.get("is_motorcycle")==true: return false
	if car.get("is_driven_by_player")==true or car.has_meta("vehicle_boarding"): return false
	if car.get("health") != null and int(car.health)<=0: return false
	if car.get("velocity") is Vector2 and car.velocity.length()>8: return false
	return car.has_method("apply_archetype") and car.has_method("configure_as_parked")

func delivery_car() -> Node2D:
	for car in get_tree().get_nodes_in_group("vehicle"):
		if eligible(car) and car.global_position.distance_to(to_global(dock))<52: return car
	return null

func _reward(car: Node) -> int:
	if car.get("active_archetype_id") == "porto_rosso":
		var boss: Dictionary = ledger().data.get("port_boss",{})
		return 50000 if boss.get("status","") == "stolen" else 0
	var book:=ledger()
	if not book.data.contract.is_empty() and String(car.get_meta("salvage_token",""))==String(book.data.contract.token): return int(book.data.contract.reward)
	return 450+roundi(float(car.get("target_length"))*3.0)

func open_panel() -> void:
	if is_instance_valid(_panel) or _player==null: return
	_player.set_dialogue_active(true)
	_panel=CanvasLayer.new()
	_panel.layer=40
	add_child(_panel)
	var shade:=ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color=Color(0,0,0,.35)
	_panel.add_child(shade)
	var center:=CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(center)
	var panel:=PanelContainer.new()
	panel.custom_minimum_size=Vector2(570,0)
	center.add_child(panel)
	var content:=VBoxContainer.new()
	content.add_theme_constant_override("separation",14)
	var scroll:=ScrollContainer.new()
	scroll.custom_minimum_size=Vector2(570,minf(560,get_viewport_rect().size.y-120))
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	scroll.add_child(content)
	content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var title:=Label.new()
	title.text=_text("NECO / FERRO-VELHO","NECO / SALVAGE YARD")
	title.add_theme_font_size_override("font_size",28)
	content.add_child(title)
	var book:=ledger()
	var copy:=Label.new()
	copy.custom_minimum_size.x=520
	copy.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	copy.text=_text("Aqui o barulho não incomoda ninguém. Recebo até seis carros por dia. Estacione na marca e venha acertar comigo. A sua Monaliza fica fora disso.\n\nHoje ainda cabem %d carros. O pagamento sai depois da prensa.","Nobody minds the noise out here. Six cars a day, tops. Park on the mark and come see me. Your Monaliza stays yours.\n\nRoom for %d more cars today. You get paid after the press.") % book.available()
	content.add_child(copy)
	var car:=delivery_car()
	var deliver:=_button(content,_text("Nenhum carro parado na baia","No parked car in the delivery bay"),func(): pass)
	if car != null:
		deliver.text=_text("Entregar %s • receber $%d após esmagar","Deliver %s • $%d after crushing") % [car.display_name,_reward(car)]
		deliver.pressed.connect(func(): confirm_delivery(car))
	deliver.disabled=car==null or book.available()==0 or get_node("/root/WantedManager").current_stars>0
	if get_node("/root/WantedManager").current_stars>0: copy.text+="\n"+_text("Despiste a polícia antes de entregar.","Lose the cops before making a delivery.")
	if book.available()==0: copy.text+="\n"+_text("Pátio lotado. Volte no próximo dia.","Yard is full. Come back tomorrow.")
	if book.data.contract.is_empty():
		_offered=_choose_target()
		if is_instance_valid(_offered) and book.available()>0 and int(book.data.jobs_taken)<3:
			copy.text+="\n\n"+_text("Encomenda especial: preciso de um %s. Você tem 2m30 para roubar o carro marcado e entregar aqui por $2400.","Special order: I need a %s. Steal the marked car and deliver it within 2m30 for $2400.") % _offered.display_name
			_button(content,_text("Aceitar encomenda • iniciar prazo","Accept order • start timer"),accept_offer)
	else:
		copy.text+="\n\n"+_text("Encomenda em andamento: %s. Siga o marcador amarelo.","Active order: %s. Follow the yellow marker.") % book.data.contract.label
		_button(content,_text("Abandonar encomenda","Abandon order"),func(): ledger().fail_contract("abandoned"); _close_panel())
	tow_service.add_offer(content)
	_button(content,_text("Voltar ao pátio","Back to the yard"),_close_panel)
	preload("res://ui/GameStyle.gd").apply(panel)
	content.get_child(content.get_child_count()-1).grab_focus()

func _button(parent: Node, title: String, action: Callable) -> Button:
	var button:=Button.new()
	button.text=title
	button.custom_minimum_size.y=44
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _close_panel() -> void:
	if is_instance_valid(_panel): _panel.queue_free()
	_panel=null
	if is_instance_valid(_player): _player.set_dialogue_active(false)

func _choose_target() -> Node2D:
	var candidates: Array[Node2D]=[]
	for car in get_tree().get_nodes_in_group("modern_parked_vehicle"):
		if car.get("active_archetype_id") == "porto_rosso" or car.has_meta("port_boss_garage_stock"): continue
		if eligible(car) and float(car.target_length)<=95 and String(car.vehicle_id) not in ["towmaster","rescue_pumper","medic_box"] and car.global_position.distance_to(global_position)>900 and not car.has_meta("salvage_token"): candidates.append(car)
	if candidates.is_empty(): return null
	var book:=ledger()
	return candidates[(int(book.data.day)+int(book.data.jobs_taken))%candidates.size()]

func accept_offer() -> void:
	if not eligible(_offered): _close_panel(); return
	var book:=ledger()
	var spec: Dictionary={"vehicle_id":String(_offered.vehicle_id),"label":String(_offered.display_name),"position":[_offered.global_position.x,_offered.global_position.y],"rotation":_offered.global_rotation,"reward":2400,"duration":150.0,"legacy":legacy}
	if book.accept(spec):
		_target=_offered
		_last_token=String(book.data.contract.token)
		_target.set_meta("salvage_token",_last_token)
		_mark_target()
	_close_panel()

func _ensure_contract_target() -> void:
	var contract: Dictionary=ledger().data.contract
	if contract.is_empty() or bool(contract.get("legacy",false))!=legacy: return
	var token:=String(contract.token)
	if is_instance_valid(_target) and String(_target.get_meta("salvage_token",""))==token: return
	var point:=Vector2(float(contract.position[0]),float(contract.position[1]))
	# Reutilize o carro do estacionamento original ao restaurar uma encomenda.
	# O cenário recria esse carro; gerar outro duplicaria o veículo já guinchado.
	if contract.has("source_name"):
		var source:=Vector2(contract.source_position[0],contract.source_position[1])
		for car in get_tree().get_nodes_in_group("modern_parked_vehicle"):
			if String(car.name)==String(contract.source_name) and car.global_position.distance_to(source)<30 and eligible(car):
				car.apply_archetype(String(contract.vehicle_id))
				car.global_position=point
				car.global_rotation=float(contract.rotation)
				car.set_meta("salvage_token",token)
				break
	for car in get_tree().get_nodes_in_group("vehicle"):
		if String(car.get_meta("salvage_token",""))==token or (eligible(car) and String(car.get("vehicle_id"))==String(contract.vehicle_id) and car.global_position.distance_to(point)<30):
			_target=car
			_target.set_meta("salvage_token",token)
			_last_token=token
			_mark_target()
			return
	_target=preload("res://world/shared/emergency/ModernTrafficFactory.gd").spawn_parked_vehicle(get_parent(),"NecoOrder",point,float(contract.rotation),String(contract.vehicle_id),0)
	_target.set_meta("salvage_token",token)
	_last_token=token
	_mark_target()

func _mark_target() -> void:
	if not is_instance_valid(_target) or _target.has_node("NecoOrderMarker"): return
	var marker:=preload("res://world/shared/salvage/SalvageTargetMarker.gd").new()
	marker.name="NecoOrderMarker"
	marker.token=_last_token
	_target.add_child(marker)

func navigation_target() -> Vector2:
	if ledger().data.contract.is_empty(): return Vector2.ZERO
	if is_instance_valid(_target) and _target.has_meta("tow_carried"): return to_global(dock)
	if is_instance_valid(_target) and _target.get("is_driven_by_player")==true: return to_global(dock)
	if is_instance_valid(_target) and _target.global_position.distance_to(to_global(dock))<80: return npc.global_position
	return _target.global_position if is_instance_valid(_target) else Vector2.ZERO

func confirm_delivery(car: Node2D) -> bool:
	if not _active_world() or is_instance_valid(_processing_car) or not eligible(car): return false
	var contract: Dictionary=ledger().data.contract
	if not contract.is_empty() and String(car.get_meta("salvage_token",""))==String(contract.token) and bool(contract.get("tow_required",false)) and not bool(contract.get("tow_loaded",false)):
		if is_instance_valid(_player): _player._show_weapon_notice(_text("Neco pediu este carro no guincho. Carregue na plataforma antes de entregar.","Neco requested this car on the tow truck. Load it onto the flatbed before delivery."))
		return false
	if _player==null or not _player.visible or _player.is_dead: return false
	if _player.global_position.distance_to(npc.global_position)>90 and _player.global_position.distance_to(car.global_position)>90: return false
	if car.global_position.distance_to(to_global(dock))>=52 or ledger().available()==0: return false
	if get_node("/root/WantedManager").current_stars>0: return false
	_close_panel()
	_processing_car=car
	add_to_group("chop_shop_busy")
	_player.set_dialogue_active(true)
	_current_reward=_reward(car)
	car.set_physics_process(false)
	car.set_process(false)
	if car is CollisionObject2D:
		car.set_deferred("collision_layer",0)
		car.set_deferred("collision_mask",0)
	_previous_camera=get_viewport().get_camera_2d()
	_camera=Camera2D.new()
	add_child(_camera)
	_camera.global_position=_previous_camera.get_screen_center_position() if is_instance_valid(_previous_camera) else global_position
	_camera.zoom=_previous_camera.zoom if is_instance_valid(_previous_camera) else Vector2.ONE
	_camera.make_current()
	var move:=create_tween().set_parallel(true)
	move.tween_property(_camera,"global_position",global_position,.55)
	move.tween_property(_camera,"zoom",Vector2.ONE*.95,.55)
	art.play_delivery(car)
	return true

func _finish_delivery() -> void:
	if not is_instance_valid(_processing_car): _unlock_delivery(); return
	var reward: int
	if _processing_car.get("active_archetype_id") == "porto_rosso":
		var state: Dictionary = ledger().data.get("port_boss",{})
		if state.get("status","") == "stolen":
			reward = ledger().settle("",50000)
			if reward == 50000: state.status = "delivered"
	else:
		reward = ledger().settle(String(_processing_car.get_meta("salvage_token","")),_current_reward)
	_processing_car.queue_free()
	_processing_car=null
	if is_instance_valid(_player):
		_player.money+=reward
		_player.report_chop_shop_delivery(reward)
		_player._refresh_weapon_ui()
		_player._show_weapon_notice(_text("NECO PAGOU $%d • %d/6 HOJE","NECO PAID $%d • %d/6 TODAY") % [reward,int(ledger().data.delivered)])
	_unlock_delivery()

func _unlock_delivery() -> void:
	remove_from_group("chop_shop_busy")
	if is_instance_valid(_player): _player.set_dialogue_active(false)
	if is_instance_valid(_previous_camera): _previous_camera.make_current()
	if is_instance_valid(_camera): _camera.queue_free()
	_camera=null

func _exit_tree() -> void:
	_close_panel()
	if is_instance_valid(_player): _player.set_dialogue_active(false)

func _text(pt: String,en: String) -> String:
	return en if TranslationServer.get_locale().begins_with("en") else pt

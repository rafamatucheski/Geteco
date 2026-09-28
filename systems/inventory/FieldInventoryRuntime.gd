extends Node
const GRID := preload("res://systems/inventory/GridInventory.gd")
const BAG := preload("res://systems/inventory/BagVisual.gd")
const PICKUP := preload("res://systems/inventory/PickupPresentation.gd")
const AUDIO := preload("res://gameplay/CombatAudio.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
var session
var ui
var carried: Node3D
var carried_mount: BoneAttachment3D
var pickups: Dictionary = {}
var sources: Array[Dictionary] = []
var clock := 0.0
var context := ""
var shown_kind := ""
var opened_health := 0.0
var last_trunk_access := false
var pickup_voice: AudioStreamPlayer
var pickup_take := 0

func configure(owner_session) -> void:
	session=owner_session
	economy().enable_grid_inventory()
	ui=preload("res://systems/inventory/ui/InventoryPanel.gd").new()
	ui.adapter=self; session.world.hud.add_child(ui)
	for row in [["harbor_fuel","water"],["harbor_fuel","sandwich"],["harbor_hospital","apple"],["harbor_clothing","backpack"],["harbor_ammunation","handbag"],["mountain_cabin","apple"],["ski_lodge","water"],["mountain_outfitters","backpack"]]:
		var definition:=PLACES.get_definition(row[0])
		var offset:=Vector3(-1.3,0,.3) if row[1] in ["water","backpack","apple"] else Vector3(1.3,0,.3)
		sources.append({"key":"supply_"+row[0]+"_"+row[1],"item":row[1],"region":definition.region,"place":"","point":definition.return_position+offset})

func economy(): return session.state.economy

func trunk_access() -> bool:
	return session.personal_car!=null and session.personal_car._available() and session.personal_car._near_trunk() and not session.world.driving.occupied and session.world.gameplay.health>0 and not session.is_transition_blocked()

func can_edit(container: String) -> bool:
	if session.world.gameplay.health<=0 or session.is_transition_blocked(): return false
	return container in ["pockets","storage"] or (container=="trunk" and trunk_access())

func open(at_trunk := false) -> void:
	if session.is_transition_blocked() or session.world.driving.occupied or session.world.gameplay.health<=0: return
	if at_trunk and not trunk_access(): return
	session._menu("Bagagem")
	session.panel.hide()
	session.menu_closed=dismiss
	ui.trunk_visible=at_trunk
	last_trunk_access=trunk_access()
	opened_health=session.world.gameplay.health
	ui.show(); ui.refresh()
	_update_carried()
	if is_instance_valid(carried): carried.set_open(true)
	if at_trunk: session.personal_car._show_trunk_view(economy().personal_loadout())

func close() -> void: session.close_menu()

func dismiss() -> void:
	ui.hide()
	if is_instance_valid(carried): carried.set_open(false)
	session.personal_car._close_trunk_view()

func move(source: String,index: int,target: String,cell := Vector2i(-1,-1)) -> bool:
	if not can_edit(source) or not can_edit(target): _feedback("Aproxime-se do porta-malas para transferir."); return false
	var data: Dictionary=economy().grid_snapshot()
	if index<0 or index>=data[source].size(): return false
	if not GRID.accepts(target,str(data[source][index].id)):
		_feedback("A Monaliza guarda apenas armas e munição."); return false
	var ok: bool = economy().grid_move(source,index,target,cell)
	_changed(ok,"Item movido.","Não há espaço livre nesse formato.")
	return ok

func rotate(source: String,index: int) -> void:
	if not can_edit(source): return
	var data: Dictionary = economy().grid_snapshot()
	if index<0 or index>=data[source].size(): return
	var entry: Dictionary = data[source][index]
	_changed(economy().grid_move(source,index,source,Vector2i(int(entry.x),int(entry.y)),true),"Item girado.","Não há espaço para girar.")

func consume(source: String,index: int) -> bool:
	if not can_edit(source): return false
	var data: Dictionary = economy().grid_snapshot()
	if source not in ["pockets","storage"] or index<0 or index>=data[source].size(): return false
	var id:=str(data[source][index].id)
	var spec:=GRID.spec(id)
	if not spec.has("heal"): return false
	if not session.world.gameplay.heal(float(spec.heal)): _feedback("Sua vida já está cheia."); return false
	# Exact selected stack, rather than consuming a different copy in a pocket.
	data[source][index].amount-=1
	if int(data[source][index].amount)==0: data[source].remove_at(index)
	economy()._data.grid_inventory=data
	economy()._data.inventory[id]-=1
	if economy()._data.inventory[id]==0: economy()._data.inventory.erase(id)
	_changed(true,"Item consumido.","")
	return true

func equip(source: String,index: int,weapon := "") -> void:
	if not session.state.weapons_allowed(): _feedback("Armas guardadas nesta área."); return
	if weapon.is_empty():
		var data: Dictionary = economy().grid_snapshot()
		if source not in ["pockets","storage","trunk"] or index<0 or index>=data[source].size(): return
		weapon=str(data[source][index].id).trim_prefix("weapon:")
		if economy().grid_handbag() and weapon in GRID.LONG: _feedback("Solte a mala para usar a arma longa."); return
		if not can_edit(source) or not economy().grid_equip_weapon(source,index): _feedback("Libere espaço para a arma anterior."); return
	var ok: bool = session.state.equip_weapon(weapon)
	_changed(ok,"Arma equipada.","Arma indisponível enquanto segura a mala.")

func store_weapon(weapon: String,target: String) -> void:
	if not can_edit(target): return
	_changed(economy().grid_store_weapon(weapon,target),"Arma guardada.","Libere espaço para guardar a arma.")

func _feedback(text: String) -> void:
	if ui.visible: ui.say(text)
	else: session.show_message(text)

func _changed(ok: bool,success: String,failure: String) -> void:
	if ok:
		session.save_game()
		ui.refresh(); _update_carried()
	_feedback(success if ok else failure)

func _process(delta: float) -> void:
	if session==null or not session.ready_for_play: return
	clock+=delta
	if clock<.25: return
	clock=0
	if ui.visible and (session.world.gameplay.health<opened_health or session.is_transition_blocked()): close()
	if ui.visible and ui.trunk_visible:
		var access:=trunk_access()
		if access!=last_trunk_access: last_trunk_access=access; ui.refresh()
	_update_carried()
	_refresh_world()

func _update_carried() -> void:
	var kind:=str(economy()._data.grid_inventory.bag)
	if shown_kind!=kind:
		if is_instance_valid(carried): carried.queue_free()
		if is_instance_valid(carried_mount): carried_mount.queue_free()
		carried_mount=null
		carried=null; shown_kind=kind
		if not kind.is_empty():
			carried=BAG.new(); carried.kind=kind; session.world.player.visual.add_child(carried)
			carried.actor_space=session.world.player.visual
			if kind=="backpack":
				var skeleton: Skeleton3D=session.world.player.skeleton
				var bone: int=skeleton.find_bone("Spine") if skeleton!=null else -1
				if bone>=0:
					carried_mount=BoneAttachment3D.new(); carried_mount.name="BackpackAttachment"; carried_mount.bone_idx=bone
					skeleton.add_child(carried_mount)
					var space:=Node3D.new(); space.name="BackpackRestSpace"
					space.transform=skeleton.get_bone_global_rest(bone).affine_inverse()*skeleton.global_transform.affine_inverse()*session.world.player.visual.global_transform
					carried_mount.add_child(space); carried.reparent(space,false); carried.carry_space=space
				carried.rotation.y=PI
			carried.position=carried.rest_position()
			carried.set_worn(true)
	if is_instance_valid(carried): carried.visible=session.world.player.visible and not session.world.driving.occupied

func _ground_point(point: Vector3, bag_space := false) -> Vector3:
	var player: CharacterBody3D = session.world.player
	var ray:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*1.5,point-Vector3.UP*3,1,[player.get_rid()])
	var space: PhysicsDirectSpaceState3D = session.world.get_world_3d().direct_space_state
	var hit: Dictionary = space.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y<.8 or absf(float(hit.position.y)-player.global_position.y)>1.1: return Vector3.INF
	var floor_point: Vector3 = hit.position+Vector3.UP*.025
	if bag_space:
		# Includes the widest bag's full rotation and the maximum bob height.
		var shape:=BoxShape3D.new(); shape.size=Vector3(.8,.8,.8)
		var query:=PhysicsShapeQueryParameters3D.new(); query.shape=shape; query.transform.origin=floor_point+Vector3.UP*.41
		query.collision_mask=7; query.exclude=[player.get_rid()]
		if not space.intersect_shape(query,1).is_empty(): return Vector3.INF
	return floor_point

func drop_bag() -> bool:
	if session.world.driving.occupied or session.is_transition_blocked() or session.world.gameplay.health<=0: return false
	var player: Node3D = session.world.player
	var forward: Vector3 = -player.visual.global_basis.z
	var point:=Vector3.INF
	for direction in [forward,forward.rotated(Vector3.UP,PI*.5),forward.rotated(Vector3.UP,-PI*.5)]:
		point=_ground_point(player.global_position+direction*1.15,true)
		if point.is_finite(): break
	if not point.is_finite(): _feedback("Não há espaço no chão para a bagagem."); return false
	var uid: int = economy().grid_drop_bag(session.state.region_id,session.state.place_id,point)
	if uid<0: return false
	_refresh_world()
	_changed(true,"Bagagem no chão. O conteúdo foi preservado.","")
	return true

func _place_migrated_bag(data: Dictionary) -> void:
	if session.is_transition_blocked() or session.world.driving.occupied: return
	for drop in data.ground:
		if not drop.get("pending",false): continue
		for i in 16:
			var direction:=Vector3.FORWARD.rotated(Vector3.UP,float(i)*TAU/8.0)
			var point:=_ground_point(session.world.player.global_position+direction*(1.4+floorf(i/8.0)),true)
			if not point.is_finite(): continue
			drop.position=[point.x,point.y,point.z]; drop.region=session.state.region_id; drop.place=session.state.place_id
			drop.erase("pending"); session.save_game()
			session.show_message("Itens do save antigo estão na mala ao seu lado.")
			return
		return

func _refresh_world() -> void:
	var data: Dictionary = economy()._data.grid_inventory
	_place_migrated_bag(data)
	var wanted: Dictionary = {}
	var position: Vector3 = session.world.player.global_position
	for row in sources:
		if row.region!=session.state.region_id or row.place!=session.state.place_id or row.key in data.claimed or position.distance_squared_to(row.point)>6400: continue
		wanted[row.key]=row
	for row in data.ground:
		if row.get("pending",false): continue
		var point:=Vector3(float(row.position[0]),float(row.position[1]),float(row.position[2]))
		if row.region!=session.state.region_id or row.place!=session.state.place_id or position.distance_squared_to(point)>6400: continue
		var key: String = "drop_"+str(row.uid)
		wanted[key]={"key":key,"item":row.bag,"point":point,"uid":int(row.uid)}
	for key in pickups.keys():
		if not wanted.has(key): pickups[key].node.queue_free(); pickups.erase(key)
	for key in wanted:
		if pickups.has(key): continue
		var row: Dictionary = wanted[key].duplicate(true)
		var point: Vector3 = row.point
		if not row.has("uid"):
			point=_ground_point(point,row.item in ["backpack","handbag"])
			if not point.is_finite(): continue
		var node := PICKUP.new()
		var model: Node3D
		if row.item in ["backpack","handbag"]:
			model=BAG.new(); model.kind=row.item
			var body:=StaticBody3D.new(); body.name="PickupBody"; body.collision_layer=1; body.collision_mask=0
			var shape:=BoxShape3D.new(); shape.size=BAG.pickup_size(row.item)
			# A fixed envelope contains the rotating visual at every angle.
			var width := Vector2(shape.size.x,shape.size.z).length()
			shape.size = Vector3(width,shape.size.y+.14,width)
			var collision:=CollisionShape3D.new(); collision.name="CollisionShape3D"; collision.shape=shape; collision.position=Vector3(0,shape.size.y*.5,0)
			body.add_child(collision); node.add_child(body)
		else: model=_food(str(row.item))
		node.configure(model,str(row.item))
		session.world.add_child(node); node.global_position=point
		row.node=node; pickups[key]=row

func _food(item: String) -> Node3D:
	var node:=Node3D.new()
	var mesh:=MeshInstance3D.new()
	var material:=StandardMaterial3D.new(); material.roughness=.8
	if item=="apple":
		var sphere:=SphereMesh.new(); sphere.radius=.11; sphere.height=.20; sphere.radial_segments=12; sphere.rings=6; mesh.mesh=sphere
		material.albedo_color=Color("b85b45"); mesh.position.y=.11
	elif item=="water":
		var bottle:=CylinderMesh.new(); bottle.top_radius=.055; bottle.bottom_radius=.075; bottle.height=.29; bottle.radial_segments=12; mesh.mesh=bottle
		material.albedo_color=Color("79a9bb"); mesh.position.y=.15
	else:
		var box:=BoxMesh.new(); box.size=Vector3(.23,.10,.18); mesh.mesh=box; mesh.position.y=.055; material.albedo_color=Color("d7b574")
	mesh.material_override=material; node.add_child(mesh)
	return node

func nearest_action() -> Dictionary:
	if session.modal or session.world.driving.occupied or session.is_transition_blocked(): return {}
	var best:=1.7
	var result: Dictionary = {}
	for key in pickups:
		var row: Dictionary = pickups[key]
		var distance: float = session.world.player.global_position.distance_to(row.node.global_position)
		if distance>=best: continue
		var excluded: Array[RID]=[session.world.player.get_rid()]
		var body:=row.node.get_node_or_null("PickupBody") as StaticBody3D
		if body!=null: excluded.append(body.get_rid())
		var ray:=PhysicsRayQueryParameters3D.create(session.world.player.global_position+Vector3.UP*.5,row.node.global_position+Vector3.UP*.25,1,excluded)
		if not session.world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
		best=distance; result={"id":"field_inventory","target":key,"label":"Pegar "+str(GRID.spec(row.item).label)}
	return result

func perform(key: String) -> bool:
	if nearest_action().get("target","")!=key: return false
	var row: Dictionary = pickups[key]
	var ok:=false
	if row.has("uid"): ok=economy().grid_recover_bag(int(row.uid))
	elif row.item in ["backpack","handbag"]: ok=economy().grid_equip_bag(row.item)
	else: ok=economy().grant_item(row.item)
	if ok and not row.has("uid"): economy().grid_claim(key)
	if ok:
		# Detach from the active registry immediately; its short visual tail owns
		# itself until freed. Failed grants never animate or play a reward.
		pickups.erase(key)
		row.node.collect()
		if not is_instance_valid(pickup_voice):
			pickup_voice=AudioStreamPlayer.new(); pickup_voice.name="PickupRewardAudio"
			pickup_voice.bus=AUDIO.SFX_BUS_NAME; pickup_voice.volume_db=-3.0
			add_child(pickup_voice)
		pickup_voice.stream=AUDIO.wav("reward_pickup_%d.wav" % pickup_take)
		pickup_take=(pickup_take+1)%3
		pickup_voice.play()
		_refresh_world()
	_changed(ok,"Item recolhido.","Sem espaço. Solte a bagagem atual para pegar outra." if row.item in ["backpack","handbag"] else "Sem espaço no inventário.")
	return true

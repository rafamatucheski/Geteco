extends Node3D
const PICKUP := preload("res://systems/inventory/PickupPresentation.gd")
## Native room adapter; geometry remains authored in original metre coordinates.
var definition: Dictionary
var model: Node3D
var solid_bodies: Array[StaticBody3D] = []
var solid_bounds: Array[AABB] = []
var vault_pivot: Node3D
var vault_bodies: Array[StaticBody3D] = []
var reward_visual: Node3D
## Verdadeiro em lugares que animam a própria arma (ex.: esconderijo da Vértice);
## o resto das recompensas do lugar continua com a apresentação de coleta.
var own_weapon_presentation := false
var reward_points: Array[Dictionary] = []
var interaction_points: Dictionary = {}
var spawn_position: Vector3:
	get: return to_global(definition.spawn)
var exit_position: Vector3:
	get: return to_global(definition.exit)
var camera_target: Vector3:
	get: return to_global(definition.camera_target)
var camera_size: float:
	get: return definition.camera_size
var active := true
func _ready() -> void:
	name = definition.id
	var resource = load(definition.model)
	model = resource.instantiate() if resource is PackedScene else resource.new()
	for property in model.get_property_list():
		if property.name in ["variant","variant_index"]: model.set(property.name,definition.variant)
	add_child(model)
	# Per-room worlds/suns from old projected render must never light other regions.
	for child in model.find_children("*","",true,false):
		if child is WorldEnvironment or child is DirectionalLight3D:
			child.get_parent().remove_child(child)
			child.free()
	var footprints = model.get("footprints")
	if footprints is Array:
		for entry in footprints: _rect_solid(entry.id,entry.rect)
	var solid_rects = model.get("solid_rects")
	if solid_rects is Dictionary:
		for id in solid_rects: _rect_solid(id,solid_rects[id])
	var rectangles = model.get("solids")
	if rectangles is Array:
		for i in rectangles.size(): _rect_solid("AuthorSolid%d"%i,rectangles[i])
	if definition.id == "harbor_bank": _classify_bank()
	var groups := {}
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		var id := str(mesh.get_meta("interior_solid_id",""))
		if id.is_empty(): continue
		var bounds: AABB = (global_transform.affine_inverse()*mesh.global_transform)*mesh.get_aabb()
		if bounds.position.y > 2.1 or bounds.end.y < .06: continue
		if groups.has(id): groups[id] = groups[id].merge(bounds)
		else: groups[id] = bounds
	for id in groups:
		var bounds: AABB = groups[id]
		bounds.size.y = maxf(.15,bounds.end.y)
		bounds.position.y = 0
		_box_solid(id,bounds)
	var size: Vector2 = definition.size
	_box_solid("Floor",AABB(Vector3(-size.x*.5,-.22,-size.y*.5),Vector3(size.x,.2,size.y)),false)
	if str(definition.id).begins_with("mountain_cabin"):
		for wall in [Rect2(-7,-4.75,14,.3),Rect2(-7,-4.6,.3,9.2),Rect2(6.7,-4.6,.3,9.2),Rect2(-7,4.45,5,.3),Rect2(2,4.45,5,.3)]: _rect_solid("LogWall",wall)
	if definition.id == "lumberjack_shelter": _bunkhouse_solids()
	if definition.id == "harbor_hospital": model.set_door_amount(1.0)
	_special_solids()
	if definition.id == "port_boss_garage":
		_box_solid("OriginalAccessRampFloor",AABB(Vector3(-3,-.14,7.65),Vector3(6,.12,3.3)),false)
	# Front cutaway uses the same original silhouette; physical bounds stay full.
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		var bounds: AABB = (global_transform.affine_inverse()*mesh.global_transform)*mesh.get_aabb()
		if mesh.mesh is BoxMesh and bounds.position.z > size.y*.5-.9 and bounds.size.y > 2.2:
			mesh.mesh = mesh.mesh.duplicate()
			mesh.mesh.size.y = .3
			mesh.position.y = .15
	# Authored overhead structures cut away from the fixed gameplay camera.
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		var bounds: AABB = (global_transform.affine_inverse()*mesh.global_transform)*mesh.get_aabb()
		if definition.id == "harbor_police" and mesh.mesh is BoxMesh and absf(bounds.get_center().z-.5)<.05 and bounds.size.x>6.9 and bounds.size.x<7.1 and bounds.size.y>2.2:
			# Original holding-area front partition hides Ferreira completely; cutaway only.
			mesh.mesh = mesh.mesh.duplicate()
			mesh.mesh.size.y = 1.0
			mesh.position.y = .5
		if definition.id == "harbor_police" and bounds.position.z > 6.8 and bounds.position.y > 1.9: mesh.hide()
		if definition.id == "harbor_fire_station" and bounds.position.z > 9.5 and bounds.position.y > 3.4: mesh.hide()
		if definition.id == "lumberjack_shelter" and bounds.position.y > 2.8 and bounds.size.x > 8: mesh.hide()
		if definition.id == "ski_lodge" and mesh.get_meta("interior_solid_id","") == &"ChangingRooms":
			if bounds.position.y > 2.0: mesh.hide()
			elif mesh.mesh is BoxMesh and bounds.size.y > 1.9:
				mesh.mesh = mesh.mesh.duplicate()
				mesh.mesh.size.y = 1.1
				mesh.position.y = .55
			elif mesh.mesh is CylinderMesh and bounds.size.y > 1.9:
				mesh.mesh = mesh.mesh.duplicate()
				mesh.mesh.height = 1.1
				mesh.position.y = .55
	interaction_points["service"] = to_global(definition.spawn+Vector3(0,0,-1))
	if definition.get("service", "") == "residence":
		for station in model.station_points:
			var point: Vector2 = model.station_points[station]
			interaction_points[station] = to_global(Vector3(point.x,0,point.y))
	if definition.id in ["harbor_ammunation", "mountain_gunshop"]:
		# The service target belongs to the customer side of Vance's counter.
		# Spawn-relative placement left it in the middle of the shop instead.
		interaction_points["service"] = to_global(Vector3(1.7 if definition.id == "mountain_gunshop" else 0.0, 0, -.9))
	for npc in definition.get("npcs",[]): interaction_points[npc.id] = to_global(npc.local_position)
	_install_reward()
func _rect_solid(id: String, rect: Rect2) -> void:
	_box_solid(id,AABB(Vector3(rect.position.x,0,rect.position.y),Vector3(rect.size.x,2,rect.size.y)))
func _box_solid(id: String,bounds: AABB,obstacle := true) -> void:
	var body := StaticBody3D.new()
	body.name = id
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("interior_solid_id",id)
	body.set_meta("bounds",bounds)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = bounds.size
	collision.shape = box
	collision.position = bounds.get_center()
	body.add_child(collision)
	add_child(body)
	solid_bodies.append(body)
	if obstacle: solid_bounds.append(bounds)
func _bunkhouse_solids() -> void:
	for bounds in [Rect2(-5,-4.8,10,.2),Rect2(-5.1,-4.7,.2,9.4),Rect2(4.9,-4.7,.2,9.4),Rect2(-5,4.7,10,.2),Rect2(-1.85,-4.12,3.7,1.15),Rect2(-1.2,-.27,2.4,1.24),Rect2(-1.15,-.8,2.3,.4),Rect2(-1.15,1.1,2.3,.4),Rect2(-4.35,2.35,1.2,1.3),Rect2(3,2.55,1.2,1.3)]: _rect_solid("BunkhouseSolid",bounds)
	for side in [-1,1]:
		for row in 2: _rect_solid("Bunk",Rect2(side*3.75-.62,-3.67+row*2.8,1.24,2.34))
func is_floor_clear(point: Vector3,radius := .32) -> bool:
	for bounds in solid_bounds:
		if Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z).grow(radius).has_point(Vector2(point.x,point.z)): return false
	return true
func _install_reward() -> void:
	var rewards: Array = definition.get("rewards",[])
	if rewards.is_empty() and not definition.get("reward",{}).is_empty(): rewards = [definition.reward]
	for item in rewards:
		var local: Vector3 = item.get("local_position",definition.spawn+Vector3(.8,0,0))
		if not is_floor_clear(local): local = definition.spawn+Vector3(-.8,0,0)
		if not is_floor_clear(local): continue
		var pickup_presentation: bool = not (own_weapon_presentation and item.kind == "weapon")
		var visual: Node3D = PICKUP.new() if pickup_presentation else Node3D.new()
		visual.name = str(item.id)
		visual.position = local
		add_child(visual)
		# Com apresentação de coleta, o modelo fica dentro de `art` (que gira e flutua);
		# `PickupPresentation.lift` (.09) já eleva `art`, então a peça desce esse tanto.
		var art: Node3D = Node3D.new() if pickup_presentation else visual
		var lift := .09 if pickup_presentation else 0.0
		if item.kind == "weapon":
			var weapon := Node3D.new()
			weapon.rotation.z = PI*.5
			weapon.position.y = .25-lift
			art.add_child(weapon)
			preload("res://assets/regions/source/scripts/player/ArsenalWeapon3D.gd").build(weapon,item.item)
		else:
			var mesh := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(.32,.2,.22)
			mesh.mesh = box
			mesh.position.y = .2-lift
			var surface := StandardMaterial3D.new()
			surface.albedo_color = Color("b79655")
			mesh.material_override = surface
			art.add_child(mesh)
		if pickup_presentation: visual.call("configure",art,str(item.get("item",item.kind)))
		var data: Dictionary = item.duplicate(true)
		data["reward"] = item.duplicate(true)
		data["position"] = to_global(local)
		data["visual"] = visual
		reward_points.append(data)
		if reward_visual == null: reward_visual = visual
## `animate` só na coleta de verdade (absorção de 0,25 s da V1); reconciliar recibos
## ao carregar continua escondendo na hora.
func set_reward_available(available: bool,id: String = "",animate := false) -> void:
	for point in reward_points:
		if id.is_empty() or point.id == id:
			var visual: Node3D = point.visual
			if not is_instance_valid(visual): continue
			if visual.has_method("set_available"): visual.call("set_available",available,animate)
			else: visual.visible = available
func set_active(value: bool) -> void:
	active = value
	visible = value
	process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED

func _classify_bank() -> void:
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		var label := str(mesh.name)
		if label == "Floor" or label.begins_with("Tile_") or label.begins_with("Cornice") or label.begins_with("Lamp") or label == "VaultLintel": continue
		mesh.set_meta("interior_solid_id",label)
	_rect_solid("BankFrontBoundary",Rect2(-7,5,14,.12))

func _special_solids() -> void:
	if definition.id in ["harbor_ammunation","mountain_gunshop"]:
		var solids := {"NorthWall":Rect2(-7.25,-5.25,14.5,.5),"WestWall":Rect2(-7.25,-5.25,.5,10.5),"EastWall":Rect2(6.75,-5.25,.5,10.5),"SouthWall":Rect2(-7.25,4.75,14.5,.5),"ServiceCounter":Rect2(-2.6,-2.8,5.2,1.2),"ArmorDisplay":Rect2(-6.35,-1.05,1.7,3.05),"ExplosivesDisplay":Rect2(4.65,-1.05,1.7,3.05),"LeftStock":Rect2(-6.05,2.2,1.1,1.6),"RightStock":Rect2(4.95,2.2,1.1,1.6),"StaffOnly":Rect2(-6.8,-4.85,13.6,1.7)}
		if definition.id == "mountain_gunshop":
			solids.ServiceCounter.position.x += 1.7
			solids.ArmorDisplay.position.x += 2.6
			solids.LeftStock.position.x += 2.6
			solids.WoodStove = Rect2(-6.15,1.225,1,.975)
		for id in solids: _rect_solid(id,solids[id])
	elif definition.id == "cemetery_keeper":
		for rect in [Rect2(-4.65,-3.7,9.3,.22),Rect2(-4.7,-3.7,.22,7.4),Rect2(4.48,-3.7,.22,7.4),Rect2(-4.65,3.5,9.3,.22),Rect2(-4.17,-3.3,3.25,1.02),Rect2(2.1,-3.23,1.8,2.6),Rect2(1.24,-2.95,.68,.7),Rect2(-4.15,-.97,.8,.85),Rect2(-3.8,.85,1.5,2.15),Rect2(3.2,.75,.95,1.65),Rect2(2.305,-.555,.51,.37),Rect2(1.6275,3.2175,1.045,.065)]: _rect_solid("KeeperFurniture",rect)
	elif definition.id == "harbor_sewer":
		for rect in [Rect2(-130,-118,460,18),Rect2(-130,134,460,18),Rect2(-130,-118,18,270),Rect2(312,-118,18,270),Rect2(112,-100,54,77),Rect2(112,23,54,111),Rect2(212,-56,72,45),Rect2(208,100,65,24),Rect2(-98,32,33,46),Rect2(72,97,10,10),Rect2(286,107,10,10),Rect2(-100,-85,396,10),Rect2(285,-80,10,70)]:
			_rect_solid("SewerSolid",Rect2((rect.position-Vector2(100,17))*.05,rect.size*.05))
	elif definition.id == "mountain_mystery_cave":
		var outline: Array[Vector2] = model.FLOOR_OUTLINE
		for i in range(outline.size()-1):
			var delta := outline[i+1]-outline[i]
			var center := (outline[i+1]+outline[i])*.5
			_box_solid("CaveContour",AABB(Vector3(-.9,0,-delta.length()*.5),Vector3(1.8,3,delta.length())))
			var body: StaticBody3D = solid_bodies[-1]
			body.position = Vector3(center.x,0,center.y)
			body.rotation.y = atan2(delta.x,delta.y)
			solid_bounds.pop_back() # Rotated contour is tested by native physics, not axis approximation.
		_rect_solid("CaveExitThreshold",Rect2(-1,5.6,2,.2))

func set_vault_open(amount: float) -> void:
	if definition.id != "harbor_bank": return
	if not is_instance_valid(vault_pivot):
		vault_pivot = Node3D.new()
		vault_pivot.name = "OriginalVaultHinge"
		vault_pivot.position = Vector3(-1.1,0,-3.2)
		add_child(vault_pivot)
		for mesh in model.find_children("*","MeshInstance3D",true,false):
			if _is_vault_door_part(str(mesh.name)): mesh.reparent(vault_pivot,true)
		for body in solid_bodies:
			if _is_vault_door_part(str(body.get_meta("interior_solid_id",""))): vault_bodies.append(body)
	vault_pivot.rotation.y = -PI*.65*clampf(amount,0,1)
	for body in vault_bodies: body.collision_layer = 0 if amount >= .95 else 1
func _is_vault_door_part(label: String) -> bool:
	return label.begins_with("VaultDoor") or label.begins_with("DoorBolt") or label.begins_with("Wheel") or label.begins_with("Spoke")

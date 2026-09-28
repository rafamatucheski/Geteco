extends Node
## Two residents per home, created on first approach. Only one home's pair is
## active at a time; all other rigs and bodies sleep behind their closed roofs.
const RESIDENT := preload("res://gameplay/urban_v1/TruckersVillageResident.gd")
var manager
var homes
var quest
var pairs: Dictionary = {}
var saved_health: Dictionary = {}
var active_house := -1
var _scan := 0.0

func configure(owner_manager, home_geometry, owner_quest) -> void:
	manager=owner_manager
	homes=home_geometry
	quest=owner_quest
	if not homes.house_entered.is_connected(_entered): homes.house_entered.connect(_entered)

func _entered(index: int) -> void:
	house_entered(index,manager.session.world.player.global_position)

func _process(delta: float) -> void:
	_scan-=delta
	if _scan>0: return
	_scan=.25
	if manager.session==null or not manager.session.ready_for_play or not manager.region_active:
		_activate(-1)
		return
	var point: Vector3 = manager.session.world.player.global_position
	var index: int = homes.house_at(point)
	if index==0 and homes.get_meta("secret_house_authorized",false): index=-1
	if index<0:
		var distance := 14.0
		for i in homes.homes.size():
			var candidate: float = point.distance_to(homes.homes[i].entry)
			if candidate<distance: distance=candidate; index=i
	_activate(index)

func _ensure(index: int) -> void:
	if pairs.has(index) or index<0 or index>=homes.homes.size(): return
	var anchors: Array = homes.occupant_anchors(index)
	var actors: Array = []
	var health: Array = saved_health.get(str(index),[90.0,90.0])
	for slot in 2:
		var actor = RESIDENT.new()
		actor.configure({"id":"village_home_%d_resident_%d"%[index,slot],"variant":(index+slot)%4,"position":anchors[slot]+Vector3.UP*.04,"stationary":true,"weapon":"shotgun"},manager.session.world.gameplay)
		add_child(actor)
		actor.attacked.connect(manager._on_attacked)
		actor.health=float(health[slot])
		if actor.health<=0:
			actor.health=1
			actor.receive_damage(1)
		actor.set_hostile(manager.hostile,manager.target)
		actors.append(actor)
	pairs[index]=actors

func _activate(index: int) -> void:
	if index>=0: _ensure(index)
	if index==active_house: return
	active_house=index
	for id in pairs:
		for actor in pairs[id]: actor.set_active(id==index and manager.region_active)

func house_entered(index: int, point: Vector3) -> bool:
	if manager.session==null or not manager.session.ready_for_play or not manager.region_active: return false
	if manager.session.world.gameplay.health<=0 or manager.session.world.driving.occupied: return false
	# A stale door signal or arbitrary identifier cannot aggro a distant home.
	if index<0 or index>=homes.homes.size() or homes.house_at(point)!=index: return false
	if index==0 and homes.get_meta("secret_house_authorized",false): return false
	if manager.session.world.player.global_position.distance_to(point)>.5: return false
	_activate(index)
	for actor in pairs.get(index,[]):
		if not actor.dead and actor.health>0 and actor.global_position.distance_to(point)<=8:
			if quest.commerce.data.hostility<=0:
				manager.session.show_message("Sai da minha casa! Vou chamar o pessoal!")
			quest.trigger_conflict(manager.session.world.player)
			for neighbour in manager.residents:
				if is_instance_valid(neighbour) and not neighbour.dead:
					neighbour.respond_to_house(homes.homes[index].entry)
			return true
	return false

func set_hostile(value: bool, source: Node3D) -> void:
	for actors in pairs.values():
		for actor in actors: actor.set_hostile(value,source)

func snapshot() -> Dictionary:
	var records := saved_health.duplicate(true)
	for id in pairs:
		records[str(id)]=[pairs[id][0].health,pairs[id][1].health]
	return {"version":1,"health":records}

func restore_snapshot(data: Dictionary) -> bool:
	if not validate_snapshot(data): return false
	saved_health=data.health.duplicate(true)
	# Rebuild on next approach instead of reviving a fallen rig in-place.
	for actors in pairs.values():
		for actor in actors: actor.free()
	pairs.clear()
	active_house=-1
	return true

static func validate_snapshot(data: Dictionary) -> bool:
	if data.get("version")!=1 or not data.get("health") is Dictionary or data.health.size()>6: return false
	for id in data.health:
		if id not in ["0","1","2","3","4","5"]: return false
		var pair: Variant = data.health[id]
		if not pair is Array or pair.size()!=2: return false
		for health in pair:
			if typeof(health) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(health)) or health<0 or health>90: return false
	return true

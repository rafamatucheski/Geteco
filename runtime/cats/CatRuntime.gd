extends Node
## Owns a bounded set of discoveries/residents; the residence owns all save data.
const LOCATIONS = preload("res://runtime/cats/CatLocations.gd")
const CAT = preload("res://runtime/cats/HouseCat.gd")
const FURNITURE = preload("res://runtime/cats/CatFurniture.gd")
const AUDIO = preload("res://runtime/cats/CatAudio.gd")
const PLACES = preload("res://world/places/PlaceCatalog.gd")
const LAYOUT = preload("res://runtime/cats/CatHomeLayout.gd")
var session
var discoveries: Array[Dictionary] = []
var cats: Dictionary = {}
var residents: Array[CharacterBody3D] = []
var furniture: Array[Node3D] = []
var furniture_points: Array[Dictionary] = []
var home_points: Array[Vector3] = []
var _clock := 0.0
var _context := ""
var _home_id := ""
var _home_definition := {}
var _epoch := 0
var _probe := CapsuleShape3D.new()
var collect_audio: AudioStreamPlayer

func configure(owner_session) -> void:
	session = owner_session
	discoveries = LOCATIONS.definitions()
	_probe.radius = .26
	_probe.height = .56
	collect_audio = AudioStreamPlayer.new()
	collect_audio.stream = AUDIO.make_collect()
	collect_audio.volume_db = -10
	add_child(collect_audio)

func can_animate() -> bool:
	return session != null and session.ready_for_play and not session.is_transition_blocked() and not get_tree().paused

func _process(delta: float) -> void:
	_clock -= delta
	if _clock > 0 or not can_animate(): return
	_clock = .35
	refresh()

func refresh() -> void:
	if session == null or not session.ready_for_play: return
	var home = session.activities.residence
	if not home.cats_unlocked() or session.state.region_id != "harbor":
		_clear_discoveries()
		_clear_home()
		return
	_refresh_discoveries()
	var supplies: Dictionary = home.cat_furniture()
	if home.cat_count() == 0 and int(supplies.bed)+int(supplies.ball)+int(supplies.scratcher) == 0:
		_clear_home()
		return
	var id: String = home.data.active_home
	if id != _home_id:
		_home_id = id
		_home_definition = PLACES.get_definition(id)
	var indoors: bool = session.state.place_id == id and is_instance_valid(session.room)
	var rooftop: bool = session.service_roofs != null and session.service_roofs.is_active()
	var exterior: Vector3 = _home_definition.exterior_position
	var at_home: bool = (indoors or (session.state.place_id.is_empty() and session.world.player.global_position.distance_to(exterior) < 32)) and not rooftop
	if not at_home:
		_clear_home()
		return
	var context := id+":"+str(indoors)+":"+str(home.adopted_cats())+":"+str(home.cat_furniture())
	if indoors: context += ":"+str(session.room.get_instance_id())
	if context != _context:
		_clear_home()
		_context = context
		_rebuild_home(indoors,context,_epoch)

func _rebuild_home(indoors: bool, context: String, epoch: int) -> void:
	# Retired collision shapes must leave the physics world before admission.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if epoch != _epoch or context != _context or not is_inside_tree(): return
	if indoors and (not is_instance_valid(session.room) or session.state.place_id != _home_id): return
	_build_home(indoors)

func _refresh_discoveries() -> void:
	var point: Vector3 = session.world.player.global_position
	var adopted: Array[String] = session.activities.residence.adopted_cats()
	var on_roof: bool = session.service_roofs != null and session.service_roofs.is_active()
	for row in discoveries:
		var visible_context: bool = session.state.place_id.is_empty() or (on_roof and row.get("roof","") == session.service_roofs.definition.get("id",""))
		var wanted: bool = row.id not in adopted and visible_context and point.distance_to(row.point) < (85.0 if cats.has(row.id) else 65.0)
		if not wanted:
			if cats.has(row.id): cats[row.id].queue_free(); cats.erase(row.id)
			continue
		if cats.has(row.id): continue
		var origin: Vector3 = row.point
		# A roof is rendered before its traversable upper floor is opened. Its
		# authored datum is stable; ground discoveries require streamed support.
		if not row.has("roof"):
			origin = floor_point(origin)
			if not origin.is_finite() or not point_clear(origin,.40): continue
		var cat = CAT.new()
		cat.configure(row.id,row.index,false,self)
		session.world.add_child(cat)
		cat.global_position = origin
		cat.set_activity("sit")
		cats[row.id] = cat

func nearest_action() -> Dictionary:
	if not _can_adopt(): return {}
	var nearest_cat: CharacterBody3D
	var distance := 1.45
	for cat in cats.values():
		if not is_instance_valid(cat): continue
		var next: float = session.world.player.global_position.distance_to(cat.global_position)
		if next < distance and _visible_reach(cat): nearest_cat = cat; distance = next
	return {} if nearest_cat == null else {"id":"cat_adopt","target":nearest_cat.cat_id,"label":"Adotar gato"}

func _can_adopt() -> bool:
	return session != null and session.ready_for_play and session.state.region_id == "harbor" and session.activities.residence.cats_unlocked() and not session.modal and not session.controller.save_invalid and not session.is_transition_blocked() and not session.world.driving.occupied and not session.world.player.input_locked and session.world.gameplay.health > 0 and not session.rescue_pending and not session.arrest_pending

func _visible_reach(cat: CharacterBody3D) -> bool:
	var from: Vector3 = session.world.player.global_position+Vector3.UP*.35
	var to: Vector3 = cat.global_position+Vector3.UP*.25
	var query := PhysicsRayQueryParameters3D.create(from,to,1)
	return session.world.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func perform(id: String) -> bool:
	var action := nearest_action()
	if action.get("target","") != id or not cats.has(id): return false
	if not session.activities.residence.adopt_cat(id): return false
	cats[id].queue_free()
	cats.erase(id)
	collect_audio.play()
	session.activities._commit()
	session.show_message("%d/10 gatos adotados"%session.activities.residence.cat_count())
	_context = ""
	return true

func floor_point(point: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.28,point-Vector3.UP*.38,1)
	var hit: Dictionary = session.world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.y < .85: return Vector3.INF
	return hit.position+Vector3.UP*.025

func point_clear(point: Vector3, radius := .26) -> bool:
	_probe.radius = radius
	_probe.height = maxf(.56,radius*2)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _probe
	query.transform.origin = point+Vector3.UP*(_probe.height*.5+.025)
	query.collision_mask = 1
	return session.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _build_home(indoors: bool) -> void:
	var home = session.activities.residence
	var definition: Dictionary = _home_definition
	var origin: Vector3 = session.room.global_position if indoors else definition.exterior_position
	var frame: Basis = session.room.global_basis if indoors else Basis(Vector3.UP,float(definition.get("editor_rotation",0)))
	# Explicit floor candidates, then real support/body queries. No actor is
	# placed on top of a cabinet and no random navigation crosses a solid.
	for z in range(-4,5) if indoors else range(5,8):
		for x in range(-6,7) if indoors else range(-3,4):
			var point := origin+frame*Vector3(x*.95,0,z*.9)
			if indoors and _station_clearance(point)<1.0: continue
			var grounded := floor_point(point)
			if grounded.is_finite() and point_clear(grounded,.40): home_points.append(grounded)
	if indoors: _build_furniture()
	var chosen: Array[Vector3] = []
	for id in home.adopted_cats():
		var index: int = int(id.trim_prefix("cat_"))-1
		var point := Vector3.INF
		# Spread personalities through the free space without blocking the door.
		for offset in home_points.size():
			var candidate: Vector3 = home_points[(index*7+offset)%home_points.size()]
			var spaced := true
			for prop in furniture:
				var footprint: Vector2 = prop.get_meta("footprint",Vector2.ONE)
				var local: Vector3 = prop.to_local(candidate)
				if Rect2(-footprint*.5,footprint).grow(.40).has_point(Vector2(local.x,local.z)): spaced = false; break
			for used in chosen:
				if candidate.distance_to(used)<.65: spaced = false; break
			if spaced and point_clear(candidate): point=candidate; break
		if not point.is_finite(): continue
		chosen.append(point)
		var cat = CAT.new()
		cat.configure(id,index,true,self)
		session.world.add_child(cat)
		cat.global_position = point
		residents.append(cat)

func _station_clearance(point: Vector3) -> float:
	var distance := INF
	for station in session.room.interaction_points.values(): distance = minf(distance,point.distance_to(station))
	return distance

func _build_furniture() -> void:
	var owned: Dictionary = session.activities.residence.cat_furniture()
	var corridors: Array[Vector3] = LAYOUT.protected_paths(session.room)
	var candidates: Array[Vector3] = []
	for z in range(-10,11):
		for x in range(-14,15):
			var point: Vector3 = session.room.to_global(Vector3(x*.45,0,z*.45))
			if _station_clearance(point)<1.1 or not session.room.is_floor_clear(Vector3(x*.45,0,z*.45),.48): continue
			var grounded := floor_point(point)
			if grounded.is_finite() and point_clear(grounded,.48): candidates.append(grounded)
	var footprints: Array[Rect2] = []
	var approaches: Array[Rect2] = []
	for kind in ["bed","scratcher","ball"]:
		for _index in int(owned.get(kind,0)):
			for point in candidates:
				var footprint: Vector2 = {"bed":Vector2(.94,.82),"scratcher":Vector2(.52,.52),"ball":Vector2(.20,.20)}[kind]
				var rectangle := Rect2(Vector2(point.x,point.z)-footprint*.5,footprint)
				var approach_rect := Rect2(Vector2(point.x-.29,point.z-.92),Vector2(.58,.77))
				var protected_rect := rectangle.grow(.40)
				var blocks_corridor := false
				for sample in corridors:
					if protected_rect.has_point(Vector2(sample.x,sample.z)): blocks_corridor = true; break
				if blocks_corridor: continue
				var free := true
				for index in footprints.size():
					if rectangle.grow(.08).intersects(footprints[index]) or rectangle.intersects(approaches[index]) or approach_rect.intersects(footprints[index]): free=false; break
				if not free: continue
				# Reserve both the prop and its front approach on clear floor.
				var access := point+Vector3(0,0,-.78)
				if not floor_point(access).is_finite() or not point_clear(access,.30): continue
				var prop: Node3D = FURNITURE.create(kind)
				session.world.add_child(prop)
				prop.global_position = point
				furniture.append(prop)
				furniture_points.append({"kind":kind,"point":point+Vector3(prop.get_meta("use_position",Vector3.ZERO)),"access":access,"prop":prop,"activity":str(prop.get_meta("use_activity","play"))})
				footprints.append(rectangle)
				approaches.append(approach_rect)
				break

func choose_activity(cat: CharacterBody3D) -> void:
	if home_points.is_empty(): cat.rest=3.0; return
	# A cat only chooses an unoccupied prop with a clear swept path.
	if not furniture_points.is_empty() and cat.rng.randf()<.65:
		for offset in furniture_points.size():
			var row: Dictionary = furniture_points[(cat.coat+offset)%furniture_points.size()]
			var occupied := false
			for other in residents:
				if other != cat and is_instance_valid(other) and other.toy == row.prop: occupied = true; break
			if occupied: continue
			var target: Vector3 = row.point
			if _walk_clear(cat,target):
				cat.walk_to(target,row.activity,row.prop)
			elif _walk_clear(cat,row.access) and row.kind == "bed":
				cat.walk_to(row.access,"sit",row.prop)
				cat.use_after_approach = target
			else: continue
			return
	for _attempt in 12:
		var target: Vector3 = home_points[cat.rng.randi_range(0,home_points.size()-1)]
		var distance: float = cat.global_position.distance_to(target)
		if distance > 3.5 or distance < .45 or not _walk_clear(cat,target): continue
		cat.walk_to(target,"sit" if cat.rng.randf()<.6 else "play")
		return
	cat.set_activity("sit")
	cat.toy = null
	cat.rest = cat.rng.randf_range(1,3)

func _walk_clear(cat: CharacterBody3D, target: Vector3) -> bool:
	if not point_clear(target): return false
	var movement := target-cat.global_position
	movement.y = 0
	var start: Transform3D = cat.global_transform
	if movement.length_squared() > .001: start.basis = Basis(Vector3.UP,atan2(-movement.x,-movement.z))
	start.origin.y += .04
	if cat.test_move(start,movement): return false
	for part in range(1,5):
		if not floor_point(cat.global_position.lerp(target,part/4.0)).is_finite(): return false
	return true

func _clear_discoveries() -> void:
	for cat in cats.values():
		if is_instance_valid(cat): cat.queue_free()
	cats.clear()

func _clear_home() -> void:
	_epoch += 1
	for cat in residents:
		if is_instance_valid(cat): cat.queue_free()
	for prop in furniture:
		if is_instance_valid(prop): prop.queue_free()
	residents.clear()
	furniture.clear()
	furniture_points.clear()
	home_points.clear()
	_context = ""

func _exit_tree() -> void:
	_clear_discoveries()
	_clear_home()

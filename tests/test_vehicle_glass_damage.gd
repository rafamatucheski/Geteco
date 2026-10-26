extends SceneTree
const VEHICLE := preload("res://scripts/Vehicle.gd")
const GLASS := preload("res://gameplay/vehicle_effects/VehicleGlassDamage.gd")
const INTERIOR := preload("res://gameplay/VehicleInterior.gd")
class Combat extends "res://gameplay/Gameplay.gd":
	func _ready() -> void: set_process(false); set_physics_process(false)
	func _damage(_actor: Object, _amount: float, _source: Node, _continuous: bool = false) -> void: pass
	func _play_stream(_stream: AudioStream, _point: Vector3, _volume: float, _pitch: float = 1.0, _reach: float = 0.0) -> void: pass
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	print(("PASS " if value else "FAIL ")+label)
	if not value: failures += 1
func car_at(id: String, point: Vector3) -> CharacterBody3D:
	var car := VEHICLE.new()
	car.archetype = id
	root.add_child(car)
	car.set_physics_process(false)
	car.position = point
	return car
func glass_count(car: Node3D) -> int:
	var count := 0
	for part: MeshInstance3D in car.visual.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null or not part.is_visible_in_tree(): continue
		for surface in part.mesh.get_surface_count():
			if GLASS._hidden(part,surface) or not INTERIOR._is_glass(part,surface,part.get_active_material(surface)): continue
			count += GLASS._indices(INTERIOR.contact_arrays(part.mesh,surface)).size()/3
	return count
func paint_area(car: Node3D) -> float:
	var area := 0.0
	for part: MeshInstance3D in car.visual.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null or not part.is_visible_in_tree(): continue
		for surface in part.mesh.get_surface_count():
			if preload("res://runtime/VehicleSurfaceRoles.gd").key(part,surface).get_slice("#",0) != "paint": continue
			var arrays := INTERIOR.contact_arrays(part.mesh,surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices := GLASS._indices(arrays)
			for i in range(0,indices.size()-2,3):
				var a := part.to_global(vertices[indices[i]])
				var b := part.to_global(vertices[indices[i+1]])
				var c := part.to_global(vertices[indices[i+2]])
				area += (b-a).cross(c-a).length()*.5
	return area
func ray_for(car: Node3D, axis: int) -> Array:
	var owner := GLASS.owner_for(car,true)
	for part: MeshInstance3D in car.visual.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null: continue
		for surface in part.mesh.get_surface_count():
			if GLASS._hidden(part,surface) or not INTERIOR._is_glass(part,surface,part.get_active_material(surface)): continue
			var arrays := INTERIOR.contact_arrays(part.mesh,surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices := GLASS._indices(arrays)
			for i in range(0,indices.size()-2,3):
				var point: Vector3 = (points[indices[i]]+points[indices[i+1]]+points[indices[i+2]])/3.0
				var world_point := part.to_global(point)
				var normal := Vector3.LEFT if axis == 0 else Vector3.FORWARD
				var from := world_point + normal*5.0
				var to := world_point - normal*5.0
				var hit: Dictionary = owner.contact(from,to)
				if not hit.is_empty() and hit.glass: return [from,to]
	return []
func rain_count(car: Node3D) -> int:
	var geometry: Dictionary = preload("res://gameplay/vehicle_effects/VehicleWindshieldRain.gd").geometry_for(car)
	return geometry.glass.surface_get_array_len(0) if not geometry.is_empty() else 0
func glass_area(car: Node3D) -> float:
	var area := 0.0
	for part: MeshInstance3D in car.visual.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null: continue
		for surface in part.mesh.get_surface_count():
			if not GLASS._hidden(part,surface) and INTERIOR._is_glass(part,surface,part.get_active_material(surface)):
				area += surface_area(INTERIOR.contact_arrays(part.mesh,surface),part.global_transform)
	return area
func surface_area(arrays: Array, transform := Transform3D.IDENTITY) -> float:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices := GLASS._indices(arrays)
	var area := 0.0
	for i in range(0,indices.size()-2,3):
		var a: Vector3 = transform * vertices[indices[i]]
		var b: Vector3 = transform * vertices[indices[i+1]]
		var c: Vector3 = transform * vertices[indices[i+2]]
		area += (b-a).cross(c-a).length()*.5
	return area
func rain_area(car: Node3D) -> float:
	var geometry: Dictionary = preload("res://gameplay/vehicle_effects/VehicleWindshieldRain.gd").geometry_for(car)
	return surface_area(geometry.glass.surface_get_arrays(0)) if not geometry.is_empty() else 0.0
func opening_at(car: Node3D, point: Vector3, direction: Vector3, rain := false) -> bool:
	if not point.is_finite(): return false
	var from := point-direction*.08
	var to := point+direction*.08
	if not rain: return GLASS.owner_for(car).contact(from,to).is_empty()
	var geometry: Dictionary = preload("res://gameplay/vehicle_effects/VehicleWindshieldRain.gd").geometry_for(car)
	if geometry.is_empty(): return true
	var arrays: Array = geometry.glass.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices := GLASS._indices(arrays)
	from = car.to_local(from)
	to = car.to_local(to)
	for i in range(0,indices.size()-2,3):
		if Geometry3D.segment_intersects_triangle(from,to,vertices[indices[i]],vertices[indices[i+1]],vertices[indices[i+2]]) != null: return false
	return true
func run() -> void:
	var combat := Combat.new()
	root.add_child(combat)
	for id in ["union_sedan","monaliza","police_cruiser","courier_van"]:
		var car := car_at(id,Vector3.ZERO)
		var twin := car_at(id,Vector3(24,0,0))
		twin.finish_doors()
		for tick in 3: await physics_frame
		var original := glass_count(twin)
		var paint := paint_area(twin)
		var original_rain := rain_count(twin)
		var ray := ray_for(car,0)
		check(not ray.is_empty(),id+" exposes reachable side glazing")
		if ray.is_empty(): car.free(); twin.free(); continue
		var physical := PhysicsRayQueryParameters3D.create(ray[0],ray[1],4)
		var hit := car.get_world_3d().direct_space_state.intersect_ray(physical)
		if hit.is_empty() or hit.collider != car: print("GLASS_PHYSICS ",id," from=",ray[0]," to=",ray[1]," hit=",hit," car=",car.global_position)
		check(not hit.is_empty() and hit.collider == car,id+" shot hits production vehicle collider")
		combat._damage_bullet(car,25.0,null,ray[0],ray[1])
		check(car.door_presentation.ready_for_boarding or car.door_presentation.coupe_ready,id+" resolves pending door topology before breaking glass")
		# Rachadura (26/10): os primeiros tiros só marcam o vidro; o BREAK_HITS-ésimo derruba o painel.
		check(glass_count(car) == original and not car.find_children(GLASS.CRACK_NAME,"Decal",true,false).is_empty(),id+" first shot cracks the pane without removing glazing")
		var side_point: Vector3 = GLASS.owner_for(car).contact(ray[0],ray[1]).get("point",Vector3.INF)
		for i in GLASS.BREAK_HITS - 1: combat._damage_bullet(car,25.0,null,ray[0],ray[1])
		var broken := glass_count(car)
		# Fragmentos de borda acrescentam triângulos: a remoção se mede por área e passagem do tiro.
		check(glass_area(car) < glass_area(twin) and glass_area(car) > 0 and opening_at(car,side_point,(ray[1]-ray[0]).normalized()),id+" opens struck pane while preserving other glazing and edge fragments")
		check(is_equal_approx(paint_area(car),paint),id+" preserves all painted geometry")
		check(glass_count(twin) == original and twin.snapshot_glass().is_empty(),id+" does not modify shared twin")
		check(rain_area(car) < rain_area(twin) and rain_count(twin) == original_rain and opening_at(car,side_point,(ray[1]-ray[0]).normalized(),true),id+" rain overlay leaves the opening empty and preserves the shared twin")
		car.animate_driver_door(-1,true,.01)
		await create_timer(.03).timeout
		check(glass_count(car) == broken,id+" opening a door preserves its broken window")
		var saved: Array = car.snapshot_glass()
		check(saved.size() == GLASS.BREAK_HITS and GLASS.valid_records(saved),id+" snapshots each valid glass strike")
		combat._damage_bullet(car,25.0,null,Vector3(0,.4,-8),Vector3(0,.4,8))
		check(car.snapshot_glass().size() == GLASS.BREAK_HITS,id+" hood or tire shot cannot shatter a window")
		car.body_dents.impact(18.0,Vector3(.6,.6,-car.half_length))
		car.body_dents._rebuild()
		car.finish_doors()
		check(glass_count(car) == broken,id+" damage and door preparation preserve broken glazing")
		car.restore_glass(saved)
		check(glass_count(car) == broken,id+" restore replays glass damage without repairing it")
		car.repair()
		check(glass_count(car) == original and car.snapshot_glass().is_empty(),id+" repair restores glazing and clears records")
		var front := ray_for(car,2)
		check(not front.is_empty(),id+" exposes reachable windshield")
		if not front.is_empty():
			var front_point: Vector3 = GLASS.owner_for(car).contact(front[0],front[1]).get("point",Vector3.INF)
			for i in GLASS.BREAK_HITS: combat._damage_bullet(car,25.0,null,front[0],front[1])
			check(glass_area(car) < glass_area(twin) and opening_at(car,front_point,(front[1]-front[0]).normalized()),id+" windshield opens after repeated hits")
			car.repair()
			combat._police_rounds.append({"point":front[0],"direction":(front[1]-front[0]).normalized(),"speed":1200.0,"distance":0.0,"range":20.0,
				"damage":25.0,"data":preload("res://gameplay/WeaponCatalog.gd").get_weapon("pistol"),"source":weakref(twin),"rid":twin.get_rid(),"visual":{},"blocked":{}})
			combat._advance_police_rounds(1.0/60.0)
			check(car.snapshot_glass().size() == 1 and combat._police_rounds.is_empty(),id+" swept police projectile strikes glass beyond hull entry")
		car.free()
		twin.free()
	combat.free()
	print("VEHICLE_GLASS_DAMAGE checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

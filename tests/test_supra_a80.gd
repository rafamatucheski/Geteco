extends SceneTree
## Real fleet assembly, supported lights, wheel arches and tuning semantics.
const CARS := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
const ADAPTER := preload("res://gameplay/desert_cars/DesertCarAdapter.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	print("SUPRA ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func _triangles(model: Node3D,key: String) -> Array:
	var result: Array = []
	for part: MeshInstance3D in model.get_children():
		if part.material_override.resource_name!=key or part.has_meta("wheel_center"): continue
		var faces := part.mesh.get_faces()
		for i in range(0,faces.size(),3):
			result.append([part.transform*faces[i],part.transform*faces[i+1],part.transform*faces[i+2]])
	return result

func run() -> void:
	var spec := FLEET.spec("supra_a80")
	check(not spec.is_empty() and spec.label=="Toyota Supra A80","Supra registered in production fleet")
	check(spec.get("reward_only",false) and spec.get("race_only",false),"honour prize is not available in ordinary vehicle shop")
	check(spec.gears.size()==6 and spec.drivetrain=="rwd" and spec.factory_turbo,"A80 retains six-speed twin-turbo RWD identity")
	var model := FLEET.create("supra_a80")
	var wheels := {}
	var triangle_count := 0
	var bounds := AABB()
	var lights := 0
	for part: MeshInstance3D in model.get_children():
		triangle_count += part.mesh.get_faces().size()/3
		bounds = bounds.merge(part.transform*part.mesh.get_aabb())
		if part.has_meta("wheel_center"): wheels[part.get_meta("wheel_center")]=true
		if part.material_override.resource_name=="headlight":
			lights += 1
			check(absf(part.mesh.get_aabb().get_center().x)>.25,"front light mount remains on its own side")
	check(wheels.size()==4,"exactly four independently animated wheel pivots")
	check(lights==2,"two headlight assemblies use shared equipment")
	check(model.get_child_count()<=32 and triangle_count<=16000,"bounded model batches and triangles: %d / %d"%[model.get_child_count(),triangle_count])
	check(bounds.size.x<2.12 and bounds.size.z<4.66 and bounds.end.y<1.37,"mirrors, spoiler and body keep authored A80 proportions")
	var hull := _triangles(model,"paint")
	var uncovered := 0
	var detached := 0
	for key in ["headlight","tail"]:
		var outward := Vector3.UP if key=="headlight" else Vector3.BACK
		for tri: Array in _triangles(model,key):
			var center: Vector3 = (tri[0]+tri[1]+tri[2])/3.0
			var origin := center+outward*.10
			var nearest := INF
			for skin: Array in hull:
				var hit: Variant = Geometry3D.ray_intersects_triangle(origin,-outward,skin[0],skin[1],skin[2])
				if hit is Vector3: nearest=minf(nearest,origin.distance_to(hit))
			if not is_finite(nearest): uncovered+=1
			elif nearest<.1005 or nearest>.133: detached+=1
	check(uncovered==0 and detached==0,"headlight and circular tail lenses sit on body: %d unsupported, %d buried/detached"%[uncovered,detached])
	for center: Vector3 in wheels:
		var blocked := false
		for tri: Array in hull:
			var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3(signf(center.x)*1.1,center.y+.13,center.z),Vector3(-signf(center.x),0,0),tri[0],tri[1],tri[2])
			if hit is Vector3 and absf(hit.x)>.70: blocked=true; break
		check(not blocked,"open wheel arch at "+str(center))
	model.free()
	var car := VEHICLE.new()
	car.archetype="supra_a80"
	car.vehicle_id="supra_contract"
	car.paint_color=Color("e5e3db")
	root.add_child(car)
	car.set_physics_process(false)
	check(car.wheels.size()==4 and car._paint.materials.size()>0,"production vehicle retains animated wheels and repaintable body")
	check(car.get_meta("desert_car_id","")=="supra_a80" and car.get_node_or_null("DesertCarAudio")!=null,"actual Supra drivetrain and engine audio attach")
	car.finish_doors()
	check(not car.door_layout(-1).is_empty() and not car.door_layout(1).is_empty(),"both Supra doors use real boarding apertures")
	car.controlled=true
	var equipment: Node = car.ensure_equipment(root)
	check(equipment.lamps.size()==2 and equipment.lens_materials.size()==2,"real equipment builds exactly two separate projectors")
	equipment.headlights_on=true
	equipment._refresh()
	check(equipment.lamps.all(func(entry): return entry.lamp.visible),"driver's Supra headlights illuminate the road")
	equipment.broken_left=true
	equipment._refresh()
	check(equipment.lens_materials.any(func(entry): return entry.side<0 and not entry.material.emission_enabled) and equipment.lens_materials.any(func(entry): return entry.side>0 and entry.material.emission_enabled),"damage extinguishes only the left headlamp")
	car.brake_input=true
	equipment._refresh()
	check(not equipment.tail_materials.is_empty() and equipment.tail_materials.all(func(material): return material.emission_enabled and material.emission_energy_multiplier>2),"the four round rear lamps act as real brake lights")
	var parts := {"engine":"race_cam","turbo":"turbo_large","tires":"drag_tires","paint":"paint_rosso","wheels":"wheels_bronze"}
	var upgraded := TUNING.tuned_spec("supra_a80",parts)
	check(upgraded.torque_nm>spec.torque_nm and upgraded.traction>spec.traction,"real tuning improves the reward car's own power and grip")
	ADAPTER.attach(car,parts)
	check(car.get_meta("desert_parts")==parts and car.get_meta("desert_car_id")=="supra_a80","equipment reapply preserves owned parts and car identity")
	car.free()
	print("SUPRA_DONE checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)

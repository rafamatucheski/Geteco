extends SceneTree
## Custo de VehicleGlassDamage.reapply depois de um amassado (malha nova), com N tiros no vidro:
## caminho antigo (um _remove_panel por registro) × em lote (24/10). Confere que os dois deixam o mesmo vidro.
## Uso: --script res://tests/measure/measure_glass_reapply.gd
const VEHICLE := preload("res://scripts/Vehicle.gd")
const GLASS := preload("res://gameplay/vehicle_effects/VehicleGlassDamage.gd")
const INTERIOR := preload("res://gameplay/VehicleInterior.gd")
func _initialize() -> void: run.call_deferred()
func glass_signature(car: Node3D) -> Array:
	var out := []
	for part: MeshInstance3D in car.visual.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null or not part.is_visible_in_tree(): continue
		for surface in part.mesh.get_surface_count():
			if GLASS._hidden(part,surface) or not INTERIOR._is_glass(part,surface,part.get_active_material(surface)): continue
			out.append(GLASS._indices(INTERIOR.contact_arrays(part.mesh,surface)).size())
	return out
func shots(car: Node3D, owner: Node) -> int:
	var made := 0
	for part: MeshInstance3D in car.visual.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null: continue
		for surface in part.mesh.get_surface_count():
			if GLASS._hidden(part,surface) or not INTERIOR._is_glass(part,surface,part.get_active_material(surface)): continue
			var arrays := INTERIOR.contact_arrays(part.mesh,surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices := GLASS._indices(arrays)
			var step := 3
			for i in range(0,indices.size()-2,step):
				var center := part.to_global((points[indices[i]]+points[indices[i+1]]+points[indices[i+2]])/3.0)
				for normal in [Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK]:
					if not owner.shoot(center+normal*5.0,center-normal*5.0).is_empty(): made += 1; break
	return made
func reapply_ms(car: Node3D, owner: Node, batch: bool) -> float:
	# Simula a malha nova do amassado: cada peça volta à malha base e o reapply refaz os furos.
	for part in owner._parts.keys():
		if is_instance_valid(part): part.mesh = owner._parts[part].base
	GLASS.batch_reapply = batch
	var began := Time.get_ticks_usec()
	owner.reapply()
	return (Time.get_ticks_usec()-began)/1000.0
func run() -> void:
	for id in ["union_sedan","monaliza","police_cruiser","courier_van","sedan_classic","lumber_pickup_4x4"]:
		var car := VEHICLE.new(); car.archetype = id
		root.add_child(car); car.set_physics_process(false)
		for i in 3: await physics_frame
		var owner: Node = GLASS.owner_for(car,true)
		var n := shots(car,owner)
		var old_ms := reapply_ms(car,owner,false); var old_sig := glass_signature(car)
		var new_ms := reapply_ms(car,owner,true); var new_sig := glass_signature(car)
		var old2 := reapply_ms(car,owner,false); var new2 := reapply_ms(car,owner,true)
		print("GLASS_REAPPLY %s tiros=%d registros=%d antigo_ms=%.2f/%.2f lote_ms=%.2f/%.2f igual=%s" % [id,n,owner.records.size(),old_ms,old2,new_ms,new2,str(old_sig==new_sig)])
		car.free()
	quit()

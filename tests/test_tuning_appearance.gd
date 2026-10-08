extends SceneTree
const VEHICLE := preload("res://scripts/Vehicle.gd")
const ADAPTER := preload("res://gameplay/desert_cars/DesertCarAdapter.gd")
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
const CATALOG := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func run() -> void:
	var ids: Array = CATALOG.IDS.duplicate()
	ids.append_array(["sport_coupe","porto_rosso","sedan_classic"])
	for id in ids:
		var car := VEHICLE.new()
		car.archetype = id
		car.vehicle_id = "appearance_test_"+id
		car.paint_color = Color("923a35")
		root.add_child(car)
		car.set_physics_process(false)
		var untouched := VEHICLE.new()
		untouched.archetype = id
		untouched.paint_color = Color("e4e1d6")
		root.add_child(untouched)
		untouched.set_physics_process(false)
		var factory_roughness: float = car._paint.materials[0].roughness
		var factory_metallic: float = car._paint.materials[0].metallic
		var parts := {"paint":"paint_ocean","finish":"finish_matte","wheels":"wheels_bronze"}
		ADAPTER.attach(car,parts)
		var appearance: RefCounted = car.get_meta("tuning_appearance")
		check(not appearance._rims.is_empty(),id+" rim selection")
		check(appearance._rims.all(func(m): return m.albedo_color == Color("a58450")),id+" bronze rims")
		check(car._paint.materials[0].albedo_color == Color("285968"),id+" paint")
		check(is_equal_approx(car._paint.materials[0].roughness,.88),id+" matte")
		check(untouched._paint.materials[0].albedo_color == Color("e4e1d6"),id+" no shared material mutation")
		check(car.paint_color == Color("923a35"),id+" factory colour retained for removal/save")
		car.paint_color = Color("923a35")
		check(car._paint.materials[0].albedo_color == Color("285968"),id+" late restore of factory paint preserves installed override")
		car.restore_health(car.max_health*.5)
		check(car._paint.materials[0].detail_enabled and is_equal_approx(car._paint.materials[0].roughness,.88),id+" damage preserves matte and adds scratches")
		ADAPTER.attach(car,parts)
		check(is_equal_approx(car.health/car.max_health,.5) and car._paint.materials[0].detail_enabled,id+" cosmetics do not heal or remove scratches")
		car.restore_health(car.max_health)
		var before: Dictionary = TUNING.tuned_spec(id)
		var after: Dictionary = TUNING.tuned_spec(id,parts)
		# The existing tuning loop normalises integer durability to float even for
		# a neutral part. Compare physical values, not Dictionary variant types.
		for field in ["torque_nm","acceleration","mass","durability","final_drive","max_speed","traction","dirt_grip","turn_speed","low_response","redline","street_cap_mps"]:
			check(is_equal_approx(float(before[field]),float(after[field])),id+" cosmetic preserves "+field)
		car._ensure_door_presentation()
		ADAPTER.attach(car,{"paint":"paint_pearl","finish":"finish_gloss"})
		check(car._paint.materials[0].albedo_color == Color("e4e1d6"),id+" repaint after doors built")
		ADAPTER.attach(car,{})
		check(car._paint.materials[0].albedo_color == Color("923a35"),id+" removal restores factory paint")
		check(is_equal_approx(car._paint.materials[0].roughness,factory_roughness) and is_equal_approx(car._paint.materials[0].metallic,factory_metallic),id+" removal restores material finish")
		for i in appearance._rims.size(): check(appearance._rims[i].albedo_color == appearance._rim_defaults[i],id+" removal restores rim")
		car.free()
		untouched.free()
		await process_frame
	print("TUNING_APPEARANCE checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

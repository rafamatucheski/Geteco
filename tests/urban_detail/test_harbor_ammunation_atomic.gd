extends SceneTree

## Guards the productive V1 Ammu-Nation address as one atomic contract:
## catalog/access/return, streamed facade selection and displaced frontage name.

const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const REGION := preload("res://world/regions/NativeRegion.gd")
const SIGNAGE := preload("res://world/urban_detail/UrbanSignage.gd")
const EXPECTED_SOURCE := Vector2(1550, 140)

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if value:
		return
	failures.append(label)
	push_error("FAIL: " + label)

func run() -> void:
	var definition: Dictionary = CATALOG.get_definition("harbor_ammunation")
	var expected_exterior := CATALOG._at(EXPECTED_SOURCE, "harbor")
	check(not definition.is_empty(), "Ammu-Nation exists in PlaceCatalog")
	check(definition.get("exterior_position", Vector3.INF).is_equal_approx(expected_exterior), "Catalog exterior is productive NorthFrontage2")
	check(definition.get("entry_position", Vector3.INF).is_equal_approx(expected_exterior + Vector3(0, 0, 130.0 / 16.0)), "Entry derives from the same productive facade")
	check(definition.get("return_position", Vector3.INF).is_equal_approx(definition.entry_position + Vector3(0, 0, 1)), "Return derives from the same entry")
	check(SIGNAGE.extract_proper_name("NorthFrontage1") == "Foundry Flats", "Displaced NorthFrontage1 keeps Foundry Flats")
	check(SIGNAGE.extract_proper_name("NorthFrontage2") == "Ammu-Nation", "NorthFrontage2 carries Ammu-Nation name")

	var access := {}
	for point in CATALOG.access_points():
		if point.place_id == "harbor_ammunation":
			access = point
			break
	check(not access.is_empty(), "Ammu-Nation access is published")
	if not access.is_empty():
		check(access.position.is_equal_approx(definition.entry_position), "Published access matches catalog entry")
		check(access.return_position.is_equal_approx(definition.return_position), "Published return matches catalog return")

	var region: Node3D = REGION.build_region("harbor", expected_exterior)
	root.add_child(region)
	for _frame in 6:
		await process_frame
		await physics_frame
	var ammu := region.find_child("NorthFrontage2", true, false)
	var foundry := region.find_child("NorthFrontage1", true, false)
	check(ammu != null, "NorthFrontage2 streams at the catalog location")
	check(foundry != null, "NorthFrontage1 remains present beside Ammu-Nation")
	if ammu != null:
		check(str(ammu.get_script().resource_path).ends_with("AmmunationFacade3D.gd"), "NorthFrontage2 uses the authored Ammu-Nation facade")
		check(str(ammu.get_meta("place_id", "")) == "harbor_ammunation", "Streamed facade metadata targets Ammu-Nation interior/catalog")
		check((ammu.get_meta("entry_position", Vector3.INF) as Vector3).is_equal_approx(definition.entry_position), "Streamed facade metadata keeps the catalog entry")
		check((ammu.get_meta("return_position", Vector3.INF) as Vector3).is_equal_approx(definition.return_position), "Streamed facade metadata keeps the catalog return")
	if foundry != null:
		check(not str(foundry.get_script().resource_path).ends_with("AmmunationFacade3D.gd"), "NorthFrontage1 no longer selects the Ammu-Nation facade")

	print("HARBOR_AMMUNATION_ATOMIC_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", 14, failures.size()])
	region.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

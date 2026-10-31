extends SceneTree
## Uma arma comprada precisa ser o mesmo objeto mostrado na loja, incluindo as
## peças de recarga e o cano usado para encaixar acessórios. Sem cena/save de jogo.
const MODELS = preload("res://gameplay/ArsenalWeapon3D.gd")
const SHOP = preload("res://assets/regions/source/guns/ammunation/AmmunationArt.gd")
const LEGACY = preload("res://assets/regions/source/scripts/player/ArsenalWeapon3D.gd")
const CATALOG = preload("res://gameplay/WeaponCatalog.gd")
const CUSTOM = preload("res://gameplay/WeaponCustomization.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func describe(node: Node3D) -> Dictionary:
	var bounds := AABB()
	var initialized := false
	var triangles := 0
	var surfaces := 0
	for part in node.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null: continue
		var transform: Transform3D = node.global_transform.affine_inverse() * part.global_transform
		var box: AABB = transform * part.mesh.get_aabb()
		bounds = bounds.merge(box) if initialized else box
		initialized = true
		for index in part.mesh.get_surface_count():
			surfaces += 1
			var arrays: Array = part.mesh.surface_get_arrays(index)
			var indices = arrays[Mesh.ARRAY_INDEX]
			var vertices = arrays[Mesh.ARRAY_VERTEX]
			triangles += int(indices.size() / 3) if indices != null and not indices.is_empty() else int(vertices.size() / 3)
	return {"bounds": bounds, "triangles": triangles, "surfaces": surfaces}
func colors(node: Node3D) -> Array:
	var values: Array = []
	for part in node.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null: continue
		for index in part.mesh.get_surface_count():
			var material: Material = part.get_active_material(index)
			if material is StandardMaterial3D: values.append(material.albedo_color)
	return values
func run() -> void:
	for id in CATALOG.ORDER:
		if id == "fists": continue
		var held := Node3D.new()
		var shown := Node3D.new()
		var repeat := Node3D.new()
		var old_entry := Node3D.new()
		for model in [held, shown, repeat, old_entry]: root.add_child(model)
		var muzzle: Vector3 = MODELS.build(held, id)
		SHOP.item(shown, id)
		SHOP.item(repeat, id)
		var legacy_muzzle: Vector3 = LEGACY.build(old_entry, id)
		var expected := describe(held)
		for model in [shown, repeat, old_entry]:
			var actual := describe(model)
			check(actual.triangles == expected.triangles, "%s keeps geometry in display/cache/legacy" % id)
			check(actual.surfaces == expected.surfaces, "%s keeps surfaces in display/cache/legacy" % id)
			var a: AABB = actual.bounds
			var b: AABB = expected.bounds
			check(a.position.is_equal_approx(b.position) and a.size.is_equal_approx(b.size), "%s keeps proportions in display/cache/legacy" % id)
		check((shown.get_meta("weapon_muzzle", Vector3.INF) as Vector3).is_equal_approx(muzzle), "%s display accessory origin matches equipped" % id)
		check(legacy_muzzle.is_equal_approx(muzzle), "%s source entry accessory origin matches equipped" % id)
		for label in ["Slide", "Pump", "ReloadCylinder", "BreakActionBarrels", "CurvedMagazine", "LoadedRocket"]:
			if held.find_child(label, true, false) != null:
				check(shown.find_child(label, true, false) != null and repeat.find_child(label, true, false) != null, "%s preserves animated %s through store cache" % [id, label])
		if CUSTOM.supports(id, "chrome"):
			var original := colors(held)
			var cached_original := colors(repeat)
			CUSTOM.fit(shown, id, {id: {"owned": false, "installed": false, "owned_parts": ["chrome"], "parts": {"finish": "chrome"}}}, muzzle)
			check(colors(held) == original, "%s preview finish leaves equipped material unchanged" % id)
			check(colors(repeat) == cached_original, "%s preview finish leaves another cached copy unchanged" % id)
		for model in [held, shown, repeat, old_entry]: model.free()
	print("WEAPON_MODEL_CONSISTENCY checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)

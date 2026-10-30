extends RefCounted
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
## Per-instance material finishes and bounded mesh kits; no frame processing. The saved
## parts own the override, while Vehicle.paint_color retains its original colour.
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
const VISUAL_KIT_SLOTS := ["spoiler","skirts","front_lip","diffuser"]
# Exact PassengerDesign / sport-coupe alloy palettes. Rotor greys #667177 and
# #53585a deliberately remain in the fixed surface of the mixed wheel batch.
const VERTEX_ALLOY_COLORS := [Color("aab6bc"),Color("9eaeb7"),Color("ba9865"),Color("bdad87"),Color("d9e2df"),Color("a47c51"),Color("abb6be"),Color("c1a36d"),Color("c4c8c9"),Color("b9c4c3"),Color("dfd5b2"),Color("b4b6b7"),Color("9caeb9"),Color("bebcb0"),Color("c7ac77"),Color("b8c2c6"),Color("adb9c1"),Color("b5b8a7"),Color("b7babc")]
var _painter: RefCounted
var _body_defaults: Array = []
var _rims: Array[StandardMaterial3D] = []
var _rim_defaults: Array[Color] = []
var _rim_vertex_defaults: Array[bool] = []
var _active_finish := {}
var _kits: RefCounted

func bind(model: Node3D, painter: RefCounted) -> void:
	_painter = painter
	for material in painter.materials:
		_body_defaults.append([material,material.roughness,material.metallic,material.clearcoat_enabled,material.detail_enabled])
	var copies := {}
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if not mesh.has_meta("wheel_center") or mesh.mesh == null: continue
		_split_vertex_alloy(mesh)
		if mesh.material_override != null:
			var material := mesh.material_override as StandardMaterial3D
			if _is_rim(material): mesh.material_override = _local_rim(material,copies)
		else:
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(surface) as StandardMaterial3D
				if _is_rim(material): mesh.set_surface_override_material(surface,_local_rim(material,copies))
	_kits = preload("res://gameplay/desert_cars/TuningBodyKits.gd").new()
	_kits.bind(model,painter)

func _is_rim(material: StandardMaterial3D) -> bool:
	if material == null or material.emission_enabled: return false
	var role := material.resource_name.to_lower()
	for excluded in ["brake","rotor","caliper","rubber","tire","wheel_fixed"]:
		if excluded in role: return false
	if role in ["wheel_alloy","alloy","rim","wheel_rim","rim_metal","wheel_metal"]: return true
	# A frota refeita em 21/10 chama o aro de "detail" dentro da malha da roda (só malhas com
	# wheel_center chegam aqui, então o "detail" da carroceria não entra). A cópia é por instância.
	if role == "detail": return true
	# Only unlabelled legacy exports need the material-property fallback.
	return role.is_empty() and material.metallic > .35 and material.roughness < .6 and material.albedo_color.v > .30

func _local_rim(material: StandardMaterial3D, copies: Dictionary) -> StandardMaterial3D:
	if not copies.has(material):
		var copy := material.duplicate() as StandardMaterial3D
		copies[material] = copy
		_rims.append(copy)
		_rim_defaults.append(material.albedo_color)
		_rim_vertex_defaults.append(material.vertex_color_use_as_albedo)
	return copies[material]

## The authored sport coupe batches rubber, rotor and forged spokes into one
## vertex-coloured `wheel` surface. Give its bright alloy triangles their own
## instance material rather than tinting the tyre along with the rim.
func _split_vertex_alloy(part: MeshInstance3D) -> void:
	if part.material_override != null: return
	var source := part.mesh
	var replacement := ArrayMesh.new()
	var split := false
	for surface in source.get_surface_count():
		var material := part.get_active_material(surface) as StandardMaterial3D
		var arrays := MESH_ARRAYS.arrays_of(source,surface)
		if material == null or material.resource_name != "wheel" or not material.vertex_color_use_as_albedo or arrays[Mesh.ARRAY_COLOR] == null:
			replacement.add_surface_from_arrays(source.surface_get_primitive_type(surface),arrays)
			replacement.surface_set_material(replacement.get_surface_count()-1,material)
			continue
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			for i in colors.size(): indices.append(i)
		var alloy := PackedInt32Array()
		var remaining := PackedInt32Array()
		for i in range(0,indices.size(),3):
			var bright := true
			for j in 3:
				if not _authored_alloy_color(colors[indices[i+j]]): bright = false
			for j in 3:
				if bright: alloy.append(indices[i+j])
				else: remaining.append(indices[i+j])
		if alloy.is_empty() or remaining.is_empty():
			replacement.add_surface_from_arrays(source.surface_get_primitive_type(surface),arrays)
			replacement.surface_set_material(replacement.get_surface_count()-1,material)
			continue
		split = true
		var unchanged: Array = arrays.duplicate()
		unchanged[Mesh.ARRAY_INDEX] = remaining
		replacement.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,unchanged)
		var fixed_material := material.duplicate() as StandardMaterial3D
		fixed_material.resource_name = "wheel_fixed"
		replacement.surface_set_material(replacement.get_surface_count()-1,fixed_material)
		var recoloured: Array = arrays.duplicate()
		recoloured[Mesh.ARRAY_INDEX] = alloy
		replacement.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,recoloured)
		var alloy_material := material.duplicate() as StandardMaterial3D
		alloy_material.resource_name = "wheel_alloy"
		alloy_material.set_meta("tuning_isolated_alloy",true)
		replacement.surface_set_material(replacement.get_surface_count()-1,alloy_material)
	if split: part.mesh = replacement

func _authored_alloy_color(color: Color) -> bool:
	for authored: Color in VERTEX_ALLOY_COLORS:
		if absf(color.r-authored.r)<.012 and absf(color.g-authored.g)<.012 and absf(color.b-authored.b)<.012: return true
	return false

func apply(parts: Dictionary, original_paint: Color) -> void:
	var clean := TUNING.clean_parts(parts)
	var paint: Dictionary = TUNING.PARTS.get(clean.get("paint",""),{})
	var finish: Dictionary = TUNING.PARTS.get(clean.get("finish",""),{})
	_active_finish = finish
	var wheels: Dictionary = TUNING.PARTS.get(clean.get("wheels",""),{})
	_painter.apply(Color(str(paint.body_color)) if paint.has("body_color") else original_paint)
	for row in _body_defaults:
		var material: StandardMaterial3D = row[0]
		material.roughness = float(finish.get("body_roughness",row[1]))
		material.metallic = float(finish.get("body_metallic",row[2]))
		material.clearcoat_enabled = bool(row[3]) if finish.is_empty() else str(clean.finish) == "finish_gloss"
		material.detail_enabled = bool(row[4]) if finish.is_empty() and paint.is_empty() else false
	for i in _rims.size():
		_rims[i].albedo_color = Color(str(wheels.wheel_color)) if wheels.has("wheel_color") else _rim_defaults[i]
		# Only the explicitly separated bright alloy surface has no tyre/rotor
		# shading baked into its colours. Other fleet batches must retain theirs.
		_rims[i].vertex_color_use_as_albedo = false if wheels.has("wheel_color") and _rims[i].get_meta("tuning_isolated_alloy",false) else _rim_vertex_defaults[i]
	if _kits != null:
		_kits.apply(clean,TUNING.PARTS,Color(str(paint.body_color)) if paint.has("body_color") else original_paint)

func damage_base(material: StandardMaterial3D, fallback: Dictionary) -> Dictionary:
	# Wear remains on top of the purchased finish, including after a cold load.
	# Factory values are retained independently so removing a finish is reversible.
	for row in _body_defaults:
		if row[0] != material: continue
		var base := fallback.duplicate()
		base.roughness = float(_active_finish.get("body_roughness",row[1]))
		base.metallic = float(_active_finish.get("body_metallic",row[2]))
		base.clearcoat = bool(row[3]) if _active_finish.is_empty() else float(_active_finish.body_roughness) < .3
		return base
	return fallback

static func apply_vehicle(car: CharacterBody3D, parts: Dictionary) -> void:
	# Peça visual comprada antes de o carro perder a compatibilidade (ex.: aerofólio sobre
	# asa de fábrica) continua no inventário, mas não é montada.
	var archetype := str(car.get("archetype"))
	if not archetype.is_empty():
		parts = parts.duplicate()
		for slot in parts.keys():
			if slot in VISUAL_KIT_SLOTS and not TUNING.compatible(str(parts[slot]),archetype): parts.erase(slot)
	var has_style := parts.has("paint") or parts.has("finish") or parts.has("wheels") or parts.has("spoiler") or parts.has("sunroof") or parts.has("taillights") or parts.has("wheel_model") or parts.has("wheel_size") or parts.has("skirts") or parts.has("front_lip") or parts.has("diffuser")
	if not has_style and not car.has_meta("tuning_appearance"): return
	# Restaura a sombra real antes de kits/teto varrerem ou substituírem o Body.
	if car.has_method("invalidate_shadow_proxy"): car.invalidate_shadow_proxy()
	var appearance: RefCounted = car.get_meta("tuning_appearance") if car.has_meta("tuning_appearance") else null
	if appearance == null:
		appearance = load("res://gameplay/desert_cars/TuningAppearance.gd").new()
		appearance.bind(car.visual,car._paint)
		car.set_meta("tuning_appearance",appearance)
	appearance.apply(parts,car.paint_color)
	if is_instance_valid(car.damage_look): car.damage_look.refresh_paint_finish()

## Presentation-only workshop preview; the session owns purchase and persistence.
static func preview_vehicle(car: CharacterBody3D, parts: Dictionary) -> void:
	apply_vehicle(car,parts)
	var adapter: Script = load("res://gameplay/desert_cars/DesertCarAdapter.gd")
	var spec := TUNING.tuned_spec(adapter.profile_of(car),parts)
	spec["installed_parts"] = TUNING.clean_parts(parts)
	adapter._apply_neon(car,spec)

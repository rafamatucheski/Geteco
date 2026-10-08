extends RefCounted
## Per-instance material finishes; no mesh changes or frame processing. The saved
## parts own the override, while Vehicle.paint_color retains its original colour.
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
var _painter: RefCounted
var _body_defaults: Array = []
var _rims: Array[StandardMaterial3D] = []
var _rim_defaults: Array[Color] = []
var _active_finish := {}

func bind(model: Node3D, painter: RefCounted) -> void:
	_painter = painter
	for material in painter.materials:
		_body_defaults.append([material,material.roughness,material.metallic,material.clearcoat_enabled,material.detail_enabled])
	var copies := {}
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if not mesh.has_meta("wheel_center") or mesh.mesh == null: continue
		if mesh.material_override != null:
			var material := mesh.material_override as StandardMaterial3D
			if _is_rim(material): mesh.material_override = _local_rim(material,copies)
		else:
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(surface) as StandardMaterial3D
				if _is_rim(material): mesh.set_surface_override_material(surface,_local_rim(material,copies))

func _is_rim(material: StandardMaterial3D) -> bool:
	if material == null or material.emission_enabled: return false
	# Legacy wheels have no semantic material name: only metal within a tagged
	# wheel is eligible, never rubber, brake darkness, glass or body paint.
	if material.resource_name == "wheel_alloy": return true
	return material.resource_name != "paint" and material.metallic > .35 and material.roughness < .6 and material.albedo_color.v > .30

func _local_rim(material: StandardMaterial3D, copies: Dictionary) -> StandardMaterial3D:
	if not copies.has(material):
		var copy := material.duplicate() as StandardMaterial3D
		copies[material] = copy
		_rims.append(copy)
		_rim_defaults.append(material.albedo_color)
	return copies[material]

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
	var has_style := parts.has("paint") or parts.has("finish") or parts.has("wheels")
	if not has_style and not car.has_meta("tuning_appearance"): return
	var appearance: RefCounted = car.get_meta("tuning_appearance") if car.has_meta("tuning_appearance") else null
	if appearance == null:
		appearance = load("res://gameplay/desert_cars/TuningAppearance.gd").new()
		appearance.bind(car.visual,car._paint)
		car.set_meta("tuning_appearance",appearance)
	appearance.apply(parts,car.paint_color)
	if is_instance_valid(car.damage_look): car.damage_look.refresh_paint_finish()

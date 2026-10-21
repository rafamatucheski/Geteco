extends RefCounted
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
## Per-instance, event-driven geometry. Shared fleet meshes are never mutated.
const WHEEL := preload("res://gameplay/desert_cars/TuningWheelKit.gd")
const ROOF := preload("res://gameplay/desert_cars/TuningSunroof.gd")
var model: Node3D
var wheels: Array = []
var tails: Array = []
var roof: RefCounted
var spoiler: Node3D
var _wheel_signature := ""
var _spoiler_style := ""
var _tail_signature := ""

func bind(source: Node3D, painter: RefCounted) -> void:
	model = source
	roof = ROOF.new()
	roof.bind(source,painter)
	var groups := {}
	var local_tails := {}
	var vehicle: Node = model.get_parent()
	var equipment: Node = vehicle.get("equipment") if vehicle is CharacterBody3D else null
	for part: MeshInstance3D in source.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null: continue
		if part.has_meta("wheel_center") and part.get_meta("wheel_spins",true):
			var center: Vector3 = part.get_meta("wheel_center")
			if not groups.has(center): groups[center] = {"center":center,"parts":[],"radius":0.0,"width":0.0,"kit":null}
			groups[center].parts.append(part)
			var box := part.mesh.get_aabb()
			groups[center].radius = maxf(groups[center].radius,maxf(box.size.y,box.size.z)*.5)
			groups[center].width = maxf(groups[center].width,box.size.x)
		for surface in part.mesh.get_surface_count():
			var material := part.get_active_material(surface) as StandardMaterial3D
			if material == null: continue
			var key := str(part.get_meta("coupe_damage_material_key",""))
			for meta_key in part.get_meta_list():
				if str(meta_key).ends_with("surface_material_keys"):
					var keys: Array = part.get_meta(meta_key)
					if surface < keys.size(): key = str(keys[surface])
			if key != "tail" and material.resource_name != "tail": continue
			var instance := material
			# VehicleEquipment already owns its tail instances and must keep them.
			if equipment == null:
				if not local_tails.has(material): local_tails[material] = material.duplicate()
				instance = local_tails[material]
				if part.material_override != null: part.material_override = instance
				else: part.set_surface_override_material(surface,instance)
				if vehicle is CharacterBody3D and vehicle.get("tail_material") == material: vehicle.set("tail_material",instance)
			if not tails.any(func(row): return row.material == instance):
				var default_color: Color = instance.albedo_color
				if equipment != null:
					var tail_index: int = equipment.tail_materials.find(instance)
					if tail_index >= 0: default_color = equipment._tail_colors[tail_index]
				tails.append({"material":instance,"part":part,"surface":surface,"color":default_color,"emission":instance.emission})
	for group in groups.values(): wheels.append(group)

func apply(parts: Dictionary, catalog: Dictionary, paint: Color) -> void:
	var wheel_part: Dictionary = catalog.get(parts.get("wheel_model",""),{})
	var size_part: Dictionary = catalog.get(parts.get("wheel_size",""),{})
	var color_part: Dictionary = catalog.get(parts.get("wheels",""),{})
	var signature := str(parts.get("wheel_model",""))+":"+str(parts.get("wheel_size",""))
	if signature != _wheel_signature:
		_wheel_signature = signature
		for group in wheels:
			if is_instance_valid(group.kit): group.kit.free()
			group.kit = null
			var changed := not wheel_part.is_empty() or not size_part.is_empty()
			for part in group.parts: part.visible = not changed
			if not changed: continue
			var kit := WHEEL.build(str(wheel_part.get("wheel_design","five_spoke")),float(group.radius),Color(str(color_part.get("wheel_color","bfc7c8"))),clampf(float(group.width),.15,.45),float(size_part.get("rim_ratio",.70)))
			var parent: Node3D = group.parts[0].get_parent()
			parent.add_child(kit)
			# Driving wheels are already reparented to a pivot at their centre.
			kit.position = Vector3.ZERO if parent != model else group.center
			group.kit = kit
	for group in wheels:
		if is_instance_valid(group.kit): group.kit.get_meta("alloy_material").albedo_color = Color(str(color_part.get("wheel_color","bfc7c8")))
	_apply_tails(catalog.get(parts.get("taillights",""),{}))
	roof.apply(str(catalog.get(parts.get("sunroof",""),{}).get("sunroof_style","")))
	_apply_spoiler(str(catalog.get(parts.get("spoiler",""),{}).get("spoiler_style","")),paint)

func _apply_tails(part: Dictionary) -> void:
	var signature := str(part.get("tail_color",""))
	var vehicle: Node = model.get_parent()
	var equipment: Node = vehicle.get("equipment") if vehicle is CharacterBody3D else null
	var rebound := false
	# Equipment is attached lazily on boarding and owns another local material
	# instance. Follow that instance so removal restores the original lens too.
	for row in tails:
		if not is_instance_valid(row.part): continue
		var current: Material = row.part.get_active_material(row.surface)
		if current != row.material and current is StandardMaterial3D:
			row.material = current
			rebound = true
	if signature == _tail_signature and not rebound: return
	_tail_signature = signature
	for row in tails:
		var color: Color = row.color if part.is_empty() else Color(signature)
		row.material.albedo_color = color
		# Preserve functional brake emission: lens tint changes, brake remains red.
		if equipment != null:
			var index: int = equipment.tail_materials.find(row.material)
			if index >= 0: equipment._tail_colors[index] = color
			equipment._tail_state = -1
		else: row.material.emission = row.emission

func _apply_spoiler(style: String, paint: Color) -> void:
	if style == _spoiler_style:
		if is_instance_valid(spoiler): spoiler.get_meta("paint_material").albedo_color = paint
		return
	_spoiler_style = style
	if is_instance_valid(spoiler): spoiler.free()
	spoiler = null
	if style.is_empty(): return
	var bounds := AABB()
	var first := true
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null or part.has_meta("wheel_center"): continue
		var box: AABB = ROOF.relative_transform(part,model)*part.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	var cabin: Dictionary = model.get_meta("vehicle_interior_spec",{})
	var z := bounds.end.z-.15
	var y := float(cabin.get("belt",bounds.size.y*.60))+.06
	# A hatch carries its spoiler along the rear roof edge, a saloon on its boot.
	var rear := float(cabin.get("rear_top",0.0))
	if rear > bounds.end.z*.53:
		z = rear-.04
		y = float(cabin.get("roof",bounds.end.y))+.04
	var measured := _mount_height(z)
	if measured > -INF: y = measured+.006
	spoiler = Node3D.new()
	spoiler.name = "TuningSpoiler"
	model.add_child(spoiler)
	var material := WHEEL.material(paint,.30,.42)
	spoiler.set_meta("paint_material",material)
	var width := bounds.size.x*.78
	var height := .19 if style == "sport" else .035
	for side in [-1.0,1.0]: _box(spoiler,Vector3(side*width*.30,y+height*.5,z),Vector3(.055,maxf(.03,height),.10),material)
	_box(spoiler,Vector3(0,y+height,z),Vector3(width,.045,.21 if style == "sport" else .12),material)
	if style == "sport":
		for side in [-1.0,1.0]: _box(spoiler,Vector3(side*width*.5,y+height+.025,z),Vector3(.025,.11,.24),material)

func _mount_height(z: float) -> float:
	var highest := -INF
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null or part.has_meta("wheel_center"): continue
		var xf := ROOF.relative_transform(part,model)
		for surface in part.mesh.get_surface_count():
			var material := part.get_active_material(surface) as StandardMaterial3D
			if material == null or material.resource_name not in ["paint","roof_paint"]: continue
			var arrays := MESH_ARRAYS.arrays_of(part.mesh,surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for i in range(0,count,3):
				var a: Vector3 = xf*vertices[indices[i] if not indices.is_empty() else i]
				var b: Vector3 = xf*vertices[indices[i+1] if not indices.is_empty() else i+1]
				var c: Vector3 = xf*vertices[indices[i+2] if not indices.is_empty() else i+2]
				var denom := (b.z-c.z)*(a.x-c.x)+(c.x-b.x)*(a.z-c.z)
				if absf(denom) < .00001: continue
				var u := ((b.z-c.z)*(-c.x)+(c.x-b.x)*(z-c.z))/denom
				var v := ((c.z-a.z)*(-c.x)+(a.x-c.x)*(z-c.z))/denom
				if u >= 0 and v >= 0 and u+v <= 1:
					highest = maxf(highest,u*a.y+v*b.y+(1.0-u-v)*c.y)
	return highest

static func _box(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> void:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = at
	part.material_override = material
	parent.add_child(part)

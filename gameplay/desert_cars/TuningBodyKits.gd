extends RefCounted
## Per-instance, event-driven geometry. Shared fleet meshes are never mutated.
const WHEEL := preload("res://gameplay/desert_cars/TuningWheelKit.gd")
const ROOF := preload("res://gameplay/desert_cars/TuningSunroof.gd")
const AERO := preload("res://gameplay/desert_cars/TuningAeroKit.gd")
const AERO_STYLE_KEYS := {"skirts":"skirt_style","front_lip":"lip_style","diffuser":"diffuser_style"}
var model: Node3D
var wheels: Array = []
var tails: Array = []
var roof: RefCounted
var aero: RefCounted
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
	aero = AERO.new()
	aero.bind(source,wheels,tails,painter)

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
	for slot in AERO_STYLE_KEYS:
		aero.apply(slot,str(catalog.get(parts.get(slot,""),{}).get(AERO_STYLE_KEYS[slot],"")),paint)

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
	# Posição lida no perfil real da lata: tampa do porta-malas ou borda do teto.
	var mount: Dictionary = aero.spoiler_mount()
	if mount.is_empty(): return
	var z := float(mount.z)
	var y := float(mount.y)+.006
	var hatch := bool(mount.hatch)
	spoiler = Node3D.new()
	spoiler.name = "TuningSpoiler"
	if float(mount.rear) < 0.0: spoiler.rotation.y = PI
	model.add_child(spoiler)
	var material := WHEEL.material(paint,.30,.42)
	spoiler.set_meta("paint_material",material)
	var width := float(mount.half_width)*2.0*(.92 if hatch else .88)
	if style == "ducktail":
		_ducktail(spoiler,width*1.04,y,z,material)
		return
	if style == "gt":
		# Asa de pista: pescoço alto, perfil mais fundo e placas laterais grandes.
		# Na borda do teto o pescoço é mais curto, como nos hatches de rali.
		var lift := .18 if hatch else .30
		for side in [-1.0,1.0]:
			_box(spoiler,Vector3(side*width*.28,y+lift*.5,z-.02),Vector3(.04,lift,.14),material)
		var wing := _box(spoiler,Vector3(0,y+lift+.02,z+.02),Vector3(width*1.06,.04,.30),material)
		wing.rotation.x = -.10
		for side in [-1.0,1.0]: _box(spoiler,Vector3(side*width*.53,y+lift+.01,z+.02),Vector3(.018,.20,.36),material)
		return
	var height := (.09 if hatch else .19) if style == "sport" else .035
	for side in [-1.0,1.0]: _box(spoiler,Vector3(side*width*.30,y+height*.5,z),Vector3(.055,maxf(.03,height),.10),material)
	_box(spoiler,Vector3(0,y+height,z),Vector3(width,.045,.21 if style == "sport" else .12),material)
	if style == "sport":
		for side in [-1.0,1.0]: _box(spoiler,Vector3(side*width*.5,y+height+.025,z),Vector3(.025,.11,.24),material)

## Rabo de pato: cunha contínua sobre a borda da tampa, levantando na ponta de trás.
static func _ducktail(parent: Node3D, width: float, y: float, z: float, material: Material) -> void:
	var profile := [Vector2(z-.20,y-.004),Vector2(z+.03,y-.004),Vector2(z+.045,y+.075),Vector2(z+.01,y+.06)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := width*.5
	var stations := [[-half,.55],[-half+.08,1.0],[half-.08,1.0],[half,.55]]
	var inside := Vector3(0,y+.02,z-.05)
	var rings: Array = []
	for station in stations:
		var ring: Array = []
		# As pontas baixam a lâmina sem mexer na base, que segue na tampa.
		for p: Vector2 in profile: ring.append(Vector3(float(station[0]),y+(p.y-y)*float(station[1]),p.x))
		rings.append(ring)
	for s in rings.size()-1:
		for i in profile.size():
			var j := (i+1)%profile.size()
			AERO._quad(st,rings[s][i],rings[s][j],rings[s+1][j],rings[s+1][i],inside,0)
	for ring in [rings[0],rings[rings.size()-1]]:
		for i in range(1,ring.size()-1): AERO._triangle(st,ring[0],ring[i],ring[i+1],inside)
	AERO._commit(parent,st,material)

static func _box(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = at
	part.material_override = material
	parent.add_child(part)
	return part

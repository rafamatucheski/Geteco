extends "res://prototypes/living_cast/CoupeDamageModel.gd"

const PREPARED_GEOMETRY := preload("res://prototypes/living_cast/BossMusclePreparedGeometry.scn")
const MATERIAL_KEY_META := &"boss_muscle_material_key"
const SURFACE_KEYS_META := &"boss_muscle_surface_material_keys"
const EXPECTED_PREPARED_GEOMETRY_SIGNATURE := 3943922188
const EXPECTED_PREPARED_CONTRACT_VERSION := 2
const EXPECTED_PREPARED_MESHES := 10
const EXPECTED_PREPARED_TRIANGLES := 26582

func _ready() -> void:
	if get_child_count()==0:
		var cache:=preload("res://cars/VehicleGeometryCache.gd")
		if not cache.restore(self):
			build()
			cache.capture(self)
	super._ready()

## Ironback V8: original long-hood, rear-cabin fastback. Uses the shared mesh
## damage/material contracts, but none of the coupe's shell or lamp geometry.
func width_at(z: float) -> float:
	return 0.94-0.10*pow(absf(z)/2.46,8)+0.055*exp(-pow((z-1.35)/0.65,2))

func top_at(x_ratio: float,z: float) -> float:
	return 0.83+0.07*(1-x_ratio*x_ratio)-0.05*pow(absf(z)/2.46,6)

func arch_bottom(z: float) -> float:
	var bottom := 0.25
	for axle in [-1.50,1.35]:
		var gap := absf(z-axle)
		if gap<0.405: bottom=maxf(bottom,0.36+sqrt(0.405*0.405-gap*gap))
	return bottom

func build_shell() -> void:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in 64:
		var a_z := lerpf(-2.46,2.46,float(j)/64)
		var b_z := lerpf(-2.46,2.46,float(j+1)/64)
		for i in 12:
			var a_x := lerpf(-1,1,float(i)/12)
			var b_x := lerpf(-1,1,float(i+1)/12)
			var a := Vector3(a_x*width_at(a_z),top_at(a_x,a_z),a_z)
			var b := Vector3(a_x*width_at(b_z),top_at(a_x,b_z),b_z)
			var c := Vector3(b_x*width_at(b_z),top_at(b_x,b_z),b_z)
			var d := Vector3(b_x*width_at(a_z),top_at(b_x,a_z),a_z)
			for vertex in [a,c,b,a,d,c]: surface_tool.add_vertex(vertex)
		for side in [-1.0,1.0]:
			var a := Vector3(side*width_at(a_z),top_at(side,a_z),a_z)
			var b := Vector3(side*width_at(b_z),top_at(side,b_z),b_z)
			var c := Vector3(side*width_at(b_z),arch_bottom(b_z),b_z)
			var d := Vector3(side*width_at(a_z),arch_bottom(a_z),a_z)
			for vertex in ([a,b,c,a,c,d] if side<0 else [a,c,b,a,d,c]): surface_tool.add_vertex(vertex)
	surface_tool.generate_normals()
	mesh_node(surface_tool.commit(),Vector3.ZERO,paint)
	for z in [-2.46,2.46]:
		var half := width_at(z)
		var points: Array[Vector3] = [Vector3(-half,.25,z),Vector3(half,.25,z),Vector3(half,.79,z),Vector3(-half,.79,z)]
		if z>0: points.reverse()
		surface(points,paint)

func build() -> void:
	if get_child_count()!=0:
		push_error("BossMuscleModel.build refused duplicate geometry")
		return
	# Geometry is the exact post-clearance/post-batching result of
	# build_procedural_source(). Materials stay unique per live vehicle so paint,
	# lamp damage, charring and repair never leak between instances.
	paint=mat("paint","49252d",.42,.24)
	mat("rubber","15191a",0,.92)
	mat("trim","272c2d",.35,.4)
	mat("bronze","a17c4b",.72,.27)
	var glass:=mat("glass","22343e",.38,.16)
	glass.cull_mode=BaseMaterial3D.CULL_DISABLED
	mat("headlight","ede5cc",.1,.2,.5)
	mat("tail","c53f34",.1,.2,.6)
	mat("rotor","6b6a62",.6,.5)
	var template:=PREPARED_GEOMETRY.instantiate() as Node3D
	assert(template != null)
	# A failed/interrupted bake must never replace the authored car. The builder
	# only publishes this contract after exact triangle/material validation.
	if not _prepared_template_is_acceptable(template):
		template.free()
		set_meta("boss_muscle_geometry_source",&"procedural_fallback")
		build_procedural_source()
		return
	set_meta("vehicle_wheel_clearance_signature",int(template.get_meta("vehicle_wheel_clearance_signature",0)))
	set_meta("boss_muscle_prepared_geometry_signature",int(template.get_meta("boss_muscle_prepared_geometry_signature",0)))
	set_meta("boss_muscle_geometry_source",&"prepared")
	for child in template.get_children():
		_clear_owner(child)
		template.remove_child(child)
		add_child(child)
		_bind_materials(child)
	template.free()

func _prepared_template_is_acceptable(template: Node3D) -> bool:
	if int(template.get_meta("boss_muscle_prepared_contract_version",0))!=EXPECTED_PREPARED_CONTRACT_VERSION:
		return false
	if int(template.get_meta("boss_muscle_prepared_geometry_signature",0))!=EXPECTED_PREPARED_GEOMETRY_SIGNATURE:
		return false
	if int(template.get_meta("boss_muscle_prepared_meshes",0))!=EXPECTED_PREPARED_MESHES:
		return false
	if int(template.get_meta("boss_muscle_prepared_triangles",0))!=EXPECTED_PREPARED_TRIANGLES:
		return false
	var meshes:=0
	var wheels:=0
	var lamps:=0
	var damage_bodies:=0
	var static_groups:=0
	for child in template.get_children():
		var part:=child as MeshInstance3D
		if part==null or part.mesh==null:
			return false
		meshes+=1
		var surface_keys:PackedStringArray=part.get_meta(SURFACE_KEYS_META,PackedStringArray())
		if surface_keys.is_empty() or surface_keys.size()!=part.mesh.get_surface_count():
			return false
		for key in surface_keys:
			if not materials.has(StringName(key)):
				return false
		if String(part.name).begins_with("BossMuscle_wheel_"):
			if not part.has_meta("wheel_center") or not bool(part.get_meta("wheel_spins",false)):
				return false
			wheels+=1
		elif String(part.name).begins_with("BossMuscle_lamp_"):
			if absf(part.position.x)<0.4 or absf(part.position.z)<2.4:
				return false
			lamps+=1
		elif bool(part.get_meta("boss_muscle_damage_body",false)):
			if part.mesh.get_surface_count()!=1:
				return false
			damage_bodies+=1
		elif part.name==&"BossMuscle_static_misc":
			static_groups+=1
	return meshes==EXPECTED_PREPARED_MESHES and wheels==4 and lamps==4 and damage_bodies==1 and static_groups==1

func _bind_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var part:=node as MeshInstance3D
		var surface_keys:PackedStringArray=part.get_meta(SURFACE_KEYS_META,PackedStringArray())
		assert(surface_keys.size()==part.mesh.get_surface_count())
		if _all_same_surface_key(surface_keys):
			var material_key:=StringName(surface_keys[0])
			assert(materials.has(material_key))
			part.material_override=materials[material_key]
		else:
			for surface_index in surface_keys.size():
				var material_key:=StringName(surface_keys[surface_index])
				assert(materials.has(material_key))
				part.set_surface_override_material(surface_index,materials[material_key])
	for child in node.get_children():
		_bind_materials(child)

func _all_same_surface_key(surface_keys: PackedStringArray) -> bool:
	if surface_keys.is_empty():
		return false
	for material_key in surface_keys:
		if material_key!=surface_keys[0]:
			return false
	return true

func _clear_owner(node: Node) -> void:
	node.owner=null
	for child in node.get_children():
		_clear_owner(child)

## Kept as the reproducible authored source for
## tests/build_boss_muscle_prepared_geometry.gd.
func build_procedural_source() -> void:
	paint=mat("paint","49252d",.42,.24)
	var rubber:=mat("rubber","15191a",0,.92)
	var trim:=mat("trim","272c2d",.35,.4)
	var bronze:=mat("bronze","a17c4b",.72,.27)
	var glass:=mat("glass","22343e",.38,.16)
	glass.cull_mode=BaseMaterial3D.CULL_DISABLED
	var lens:=mat("headlight","ede5cc",.1,.2,.5)
	var tail:=mat("tail","c53f34",.1,.2,.6)
	build_shell()
	box(Vector3(0,.24,0),Vector3(1.72,.09,4.30),rubber)
	# Cabin sits behind the long hood; broad flat roof and sloping rear glass.
	surface([Vector3(-.66,1.32,-.10),Vector3(.66,1.32,-.10),Vector3(.65,1.32,.84),Vector3(-.65,1.32,.84)],paint)
	surface([Vector3(-.78,.9,-.62),Vector3(.78,.9,-.62),Vector3(.66,1.32,-.10),Vector3(-.66,1.32,-.10)],glass)
	surface([Vector3(-.65,1.32,.84),Vector3(.65,1.32,.84),Vector3(.82,.91,1.83),Vector3(-.82,.91,1.83)],glass)
	for side in [-1.0,1.0]:
		var a:=Vector3(side*.78,.90,-.62)
		var b:=Vector3(side*.66,1.32,-.10)
		var c:=Vector3(side*.65,1.32,.84)
		var d:=Vector3(side*.87,.91,1.45)
		surface([a,b,c,d],glass)
		tube([a,b,c,d,a],.026,paint)
		surface([c,d,Vector3(side*.94,.87,1.99),Vector3(side*.82,.91,1.83)],paint)
		tube([Vector3(side*.69,1.32,.51),Vector3(side*.84,.9,.7)],.02,trim)
		box(Vector3(side*.951,.72,.68),Vector3(.025,.026,.17),bronze)
		box(Vector3(side*.93,.91,-.49),Vector3(.22,.08,.16),paint)
		tube([Vector3(side*.945,.81,-.58),Vector3(side*.944,.32,-.47),Vector3(side*.973,.32,.99),Vector3(side*.97,.83,1.08)],.006,trim)
		# Narrow rectangular headlight signatures, not round eye-like lenses.
		box(Vector3(side*.61,.80,-2.465),Vector3(.42,.055,.023),lens)
		box(Vector3(side*.59,.49,-2.47),Vector3(.25,.035,.02),bronze)
		box(Vector3(side*.55,.72,2.465),Vector3(.48,.065,.025),tail)
		box(Vector3(side*.96,.32,0),Vector3(.055,.07,1.92),trim)
		for wheel_z in [-1.50,1.35]:
			var start:=get_child_count()
			var center:=Vector3(side*.94,.36,wheel_z)
			var tire:=cylinder(center,.355,.24,rubber)
			tire.rotation.z=PI/2
			var rim:=cylinder(Vector3(side*1.065,.36,wheel_z),.255,.024,trim)
			rim.rotation.z=PI/2
			var rotor:=cylinder(Vector3(side*1.078,.36,wheel_z),.20,.012,mat("rotor","6b6a62",.6,.5))
			rotor.rotation.z=PI/2
			for spoke in 5:
				var angle:=float(spoke)*TAU/5
				tube([Vector3(side*1.09,.36+cos(angle)*.045,wheel_z+sin(angle)*.045),Vector3(side*1.09,.36+cos(angle+.1)*.24,wheel_z+sin(angle+.1)*.24)],.028,bronze)
			var hub:=cylinder(Vector3(side*1.10,.36,wheel_z),.06,.022,bronze)
			hub.rotation.z=PI/2
			for index in range(start,get_child_count()):
				get_child(index).set_meta("wheel_center",center)
				get_child(index).set_meta("wheel_spins",true)
	# Deep grille, chin spoiler, twin hood creases and restrained bronze pinlines.
	box(Vector3(0,.66,-2.473),Vector3(1.50,.19,.035),rubber)
	for i in 5: box(Vector3(0,.595+i*.032,-2.495),Vector3(1.43,.012,.018),trim)
	box(Vector3(0,.29,-2.47),Vector3(1.79,.075,.12),trim)
	for side in [-1.0,1.0]:
		tube([Vector3(side*.36,.894,-2.19),Vector3(side*.34,.935,-1.4),Vector3(side*.41,.919,-.71)],.009,bronze)
		box(Vector3(side*.59,.29,2.48),Vector3(.18,.12,.12),trim)
	box(Vector3(0,.87,2.18),Vector3(1.76,.045,.15),trim)

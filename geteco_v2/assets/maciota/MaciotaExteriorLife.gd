extends RefCounted
## Static, collision-free dressing for Maciota's authored street facade.
## The existing shell and piers remain the only ground-level solids.

const KIT := preload("res://world/city_look/CityPropKit.gd")
const CITY_MATERIALS := preload("res://world/city_look/CityLookMaterials.gd")
const FONT := preload("res://assets/Barlow.ttf")

const IRON := Color("202d31")
const STEEL := Color("52666a")
const BRASS := Color("d6a74d")
const CREAM := Color("dfd4bd")


static func build(facade: Node3D) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	_build_static_geometry(tool)
	tool.generate_normals()
	var detail := MeshInstance3D.new()
	detail.name = "MaciotaExteriorDetails"
	detail.mesh = tool.commit()
	detail.material_override = KIT.material()
	detail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	facade.add_child(detail)
	_build_name(facade)
	_build_work_lamps(facade)


static func _build_static_geometry(t: SurfaceTool) -> void:
	var face := 7.8125
	# Heavy charcoal frame, inset workshop bay and a continuous brass datum.
	KIT.box(t, Vector3(-2.0, 3.79, face + .075), Vector3(5.92, .74, .19), IRON)
	KIT.box(t, Vector3(-2.0, 4.17, face + .14), Vector3(5.72, .065, .21), BRASS)
	KIT.box(t, Vector3(-2.0, 3.39, face + .14), Vector3(5.72, .05, .16), BRASS)
	for x in [-5.02, 1.02]:
		KIT.box(t, Vector3(x, 1.68, face + .06), Vector3(.14, 3.28, .2), IRON)
		KIT.box(t, Vector3(x, 1.68, face + .17), Vector3(.045, 3.15, .045), BRASS)
		KIT.box(t, Vector3(x, 4.60, face - .33), Vector3(.19, .24, .68), IRON)
	# The original shell remains the physical back of the bay. A parked project
	# car and lift are seen in shadow; the roller is gathered above the opening.
	KIT.box(t, Vector3(-2.0, 1.59, 6.833), Vector3(5.68, 3.0, .045), Color("263539"))
	for x in [-4.36, .36]:
		KIT.box(t, Vector3(x, 1.39, 6.94), Vector3(.19, 2.55, .11), Color("6f8587"))
		KIT.box(t, Vector3(x, 2.71, 6.96), Vector3(.31, .09, .18), BRASS)
	KIT.box(t, Vector3(-2.0, .42, 6.95), Vector3(3.7, .17, .17), Color("171f22"))
	KIT.box(t, Vector3(-2.0, .76, 7.01), Vector3(3.31, .56, .17), Color("57534c"))
	KIT.box(t, Vector3(-2.0, 1.16, 6.995), Vector3(1.82, .29, .13), Color("364a4d"))
	KIT.box(t, Vector3(-2.0, 1.32, 7.04), Vector3(1.55, .025, .035), Color("9ca6a1"))
	for x in [-3.12, -.88]:
		KIT.box(t, Vector3(x, .49, 7.105), Vector3(.48, .22, .075), Color("151b1c"))
	for rib in 4:
		var y := 2.94 + float(rib) * .056
		KIT.box(t, Vector3(-2.0, y, 7.59), Vector3(5.65, .022, .045), Color("617579"))
	KIT.box(t, Vector3(-2.0, 3.13, 7.35), Vector3(5.85, .29, .45), STEEL)
	for x in [-4.55, .55]:
		KIT.box(t, Vector3(x, 3.13, 7.63), Vector3(.18, .38, .15), IRON)
	# Shallow steel awning and exposed braces frame the approach without
	# entering the car or pedestrian clearance at ground level.
	KIT.box(t, Vector3(-2.0, 3.43, 8.06), Vector3(6.55, .10, .65), IRON)
	KIT.box(t, Vector3(-2.0, 3.48, 8.38), Vector3(6.55, .055, .055), BRASS)
	for x in [-5.12, 1.12]:
		KIT.box(t, Vector3(x, 3.22, 8.04), Vector3(.09, .46, .53), STEEL)
	# Individually authored roofline: stepped parapet, long skylight ribs,
	# industrial extraction duct and a compact service exhaust.
	KIT.box(t, Vector3(-2.0, 4.77, 7.58), Vector3(8.04, .42, .30), IRON)
	KIT.box(t, Vector3(-2.0, 5.02, 7.62), Vector3(8.04, .055, .33), BRASS)
	for x in [-4.84, -3.36, -1.88, -.40, 1.08]:
		KIT.box(t, Vector3(x, 4.60, 4.48), Vector3(.085, .12, 5.9), STEEL)
	for z in [3.24, 4.54, 5.84]:
		KIT.box(t, Vector3(-1.88, 4.72, z), Vector3(5.9, .20, .065), Color("809398"))
	KIT.box(t, Vector3(-4.61, 4.95, 3.18), Vector3(.68, .70, .76), STEEL)
	KIT.box(t, Vector3(-4.61, 5.32, 3.18), Vector3(.79, .065, .88), IRON)
	KIT.cylinder(t, Vector3(-4.61, 5.32, 3.18), .18, .53, Color("617579"), 8)
	KIT.cylinder(t, Vector3(-4.61, 5.85, 3.18), .26, .055, IRON, 8)
	# Overhead utilities and a weathered masonry band on the front piers.
	for x in [-5.49, 1.49]:
		for y in [.64, 1.38, 2.12, 2.86]:
			KIT.box(t, Vector3(x, y, face + .015), Vector3(.79, .025, .022), Color("819196"))
		KIT.box(t, Vector3(x, 4.06, 7.96), Vector3(.12, .13, .45), IRON)
	# Paint and old oil live flush with the apron; neither changes collision.
	for x in [-3.64, -.36]:
		KIT.box(t, Vector3(x, .013, 8.48), Vector3(.11, .018, 1.03), BRASS)
	for index in 5:
		KIT.box(t, Vector3(-4.68 + float(index) * .34, .014, 8.03), Vector3(.16, .019, .46), Color("9b793a"), -.40)
	KIT.box(t, Vector3(-1.97, .012, 8.91), Vector3(1.12, .016, .36), Color("343a38"), .12)
	KIT.box(t, Vector3(-.78, .011, 8.80), Vector3(.53, .014, .17), Color("3a403b"), -.23)


static func _build_name(facade: Node3D) -> void:
	var label := Label3D.new()
	label.name = "MaciotaName"
	label.text = "MACIOTA"
	label.font = FONT
	label.font_size = 128
	label.pixel_size = .0066
	label.position = Vector3(-2.0, 3.80, 7.985)
	label.modulate = CREAM
	label.outline_size = 10
	label.outline_modulate = IRON
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.set_meta("neon_color", CREAM)
	label.add_to_group(&"city_neon_label")
	facade.add_child(label)


static func _build_work_lamps(facade: Node3D) -> void:
	var lens_mesh := BoxMesh.new()
	lens_mesh.size = Vector3(.31, .15, .12)
	for x in [-5.45, 1.45]:
		var lens := MeshInstance3D.new()
		lens.name = "MaciotaWorkLampLeft" if x < 0.0 else "MaciotaWorkLampRight"
		lens.mesh = lens_mesh
		lens.position = Vector3(x, 3.04, 8.14)
		lens.material_override = CITY_MATERIALS.lamp_head()
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		facade.add_child(lens)

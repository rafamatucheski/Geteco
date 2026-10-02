extends Node3D
## Static workshop salvage yard. Solids are local to each object; paths stay open.
const KIT := preload("res://world/city_look/CityPropKit.gd")
const RUST := Color("80513a")
const STEEL := Color("4b5150")
const PAINT := Color("677b79")

func _ready() -> void:
	name = "GarageBackyard"
	_car()
	_parts()
	_bins()
	_oil()

func _tool() -> SurfaceTool:
	var t := SurfaceTool.new()
	t.begin(Mesh.PRIMITIVE_TRIANGLES)
	t.set_smooth_group(-1)
	return t

func _finish(t: SurfaceTool, label: String, at: Vector3, yaw: float, bounds: AABB) -> void:
	t.generate_normals()
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = t.commit()
	visual.material_override = KIT.material()
	visual.position = at
	visual.rotation.y = yaw
	add_child(visual)
	if bounds.size == Vector3.ZERO: return
	var solid := StaticBody3D.new()
	solid.name = label + "Solid"
	solid.collision_layer = 1
	solid.collision_mask = 0
	solid.set_meta("interior_solid_id",label)
	solid.position = at
	solid.rotation.y = yaw
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = bounds.size
	collider.shape = shape
	collider.position = bounds.get_center()
	solid.add_child(collider)
	add_child(solid)

func _car() -> void:
	var t := _tool()
	# Wheels, bonnet and one door have been removed. The cabin remains recognisable.
	KIT.box(t,Vector3(0,.47,0),Vector3(1.68,.16,4.05),STEEL)
	KIT.box(t,Vector3(0,.63,.18),Vector3(1.58,.16,2.5),Color("343b39"))
	for x in [-.79,.79]:
		KIT.box(t,Vector3(x,.70,-1.24),Vector3(.18,.45,1.5),PAINT)
		KIT.box(t,Vector3(x,.79,1.46),Vector3(.18,.60,1.16),PAINT)
		KIT.box(t,Vector3(x,.63,.12),Vector3(.13,.20,1.2),RUST)
		for z in [-.70,.86]:
			KIT.box(t,Vector3(x*.88,1.22,z),Vector3(.095,.75,.09),PAINT)
	KIT.box(t,Vector3(0,1.61,.10),Vector3(1.54,.10,1.7),PAINT)
	KIT.box(t,Vector3(0,1.671,.14),Vector3(.53,.017,.8),RUST,.12)
	KIT.box(t,Vector3(0,1.02,1.55),Vector3(1.57,.12,.98),PAINT)
	KIT.box(t,Vector3(.79,.94,.12),Vector3(.12,.50,1.25),PAINT)
	for x in [-.41,.41]:
		KIT.box(t,Vector3(x,.85,.30),Vector3(.53,.22,.57),Color("4f4237"))
		KIT.box(t,Vector3(x,1.04,.59),Vector3(.53,.48,.15),Color("4f4237"))
	KIT.box(t,Vector3(0,1.10,-.57),Vector3(1.36,.16,.25),Color("303936"))
	# Open engine bay, ribbed block, radiator and exposed front crossmember.
	KIT.box(t,Vector3(0,.71,-1.35),Vector3(.65,.39,.84),Color("353d3c"))
	for z in [-1.64,-1.48,-1.32,-1.16,-1.0]:
		KIT.box(t,Vector3(0,.94,z),Vector3(.67,.055,.065),Color("9b9d8e"))
	KIT.box(t,Vector3(0,.79,-1.87),Vector3(1.20,.39,.10),STEEL)
	for x in [-.48,-.24,0,.24,.48]:
		KIT.box(t,Vector3(x,.79,-1.935),Vector3(.028,.30,.018),Color("252c2b"))
	for z in [-2.04,2.04]:
		KIT.box(t,Vector3(0,.59,z),Vector3(1.77,.10,.09),Color("89938e"))
	for x in [-.59,.59]:
		KIT.box(t,Vector3(x,.87,2.055),Vector3(.28,.13,.035),Color("7e3027"))
	# Four visible stands keep the stripped shell off the ground.
	for x in [-.57,.57]:
		for z in [-1.18,1.20]:
			KIT.box(t,Vector3(x,.12,z),Vector3(.48,.17,.45),Color("b0aaa0"))
			KIT.box(t,Vector3(x,.31,z),Vector3(.32,.23,.32),Color("7e847d"))
	_finish(t,"StrippedCar",Vector3(-2,.04,-1.9),PI/2,AABB(Vector3(-.89,0,-2.1),Vector3(1.78,1.7,4.2)))

func _parts() -> void:
	var t := _tool()
	# Slatted pallet with used engine, brake discs and detached sheet metal.
	for z in [-.45,.45]: KIT.box(t,Vector3(0,.12,z),Vector3(1.5,.16,.14),Color("63503c"))
	for i in 6: KIT.box(t,Vector3(-.65+i*.26,.24,0),Vector3(.21,.10,1.2),Color("897054"))
	KIT.box(t,Vector3(-.20,.55,0),Vector3(.66,.52,.72),STEEL)
	for z in [-.28,-.12,.04,.20]: KIT.box(t,Vector3(-.2,.84,z),Vector3(.69,.08,.075),Color("a29b85"))
	KIT.cylinder(t,Vector3(.5,.3,.23),.20,.16,RUST,16)
	KIT.cylinder(t,Vector3(.5,.46,.23),.10,.04,STEEL,12)
	KIT.box(t,Vector3(.58,.59,-.34),Vector3(.08,.58,.53),Color("746754"),.16)
	_finish(t,"SalvagePallet",Vector3(-5,.04,.24),0,AABB(Vector3(-.76,0,-.61),Vector3(1.52,.94,1.22)))
	var panels := _tool()
	KIT.box(panels,Vector3(0,.58,0),Vector3(1.35,1.12,.12),PAINT)
	KIT.box(panels,Vector3(0,.69,-.075),Vector3(.85,.56,.035),Color("566563"))
	KIT.box(panels,Vector3(.38,.27,-.08),Vector3(.36,.29,.025),RUST)
	KIT.box(panels,Vector3(.82,.42,-.03),Vector3(.12,.75,.66),STEEL)
	_finish(panels,"DetachedPanels",Vector3(-2.25,.04,.93),0,AABB(Vector3(-.68,0,-.38),Vector3(1.57,1.18,.77)))
	var tires := _tool()
	for i in 3: _tire(tires,Vector3(0,.16+i*.23,0))
	_finish(tires,"UsedTires",Vector3(.73,.04,.38),0,AABB(Vector3(-.40,0,-.40),Vector3(.80,.85,.80)))

func _tire(t: SurfaceTool, at: Vector3) -> void:
	for i in 20:
		var a := TAU*float(i)/20
		var b := TAU*float(i+1)/20
		for j in 6:
			var vertices: Array[Vector3] = []
			for pair in [[a,j],[b,j],[b,j+1],[a,j+1]]:
				var angle: float = TAU*float(pair[1])/6
				var r := .28+.11*cos(angle)
				vertices.append(at+Vector3(cos(pair[0])*r,sin(angle)*.12,sin(pair[0])*r))
			t.set_color(Color("242a28") if i%2 else Color("343936"))
			for index in [0,1,2,0,2,3]: t.add_vertex(vertices[index])

func _bins() -> void:
	for i in 3:
		var t := _tool()
		var c: Color = [Color("56685a"),Color("7b6047"),Color("52616b")][i]
		KIT.cylinder(t,Vector3(0,.06,0),.32,.90,c,16,.35)
		for y in [.12,.36,.77,.97]: KIT.cylinder(t,Vector3(0,y,0),.355,.04,STEEL,16)
		KIT.cylinder(t,Vector3(0,1.01,0),.36,.065,Color("858b80"),16,.31)
		KIT.box(t,Vector3(0,1.10,0),Vector3(.16,.07,.065),STEEL)
		for x in [-.37,.37]: KIT.box(t,Vector3(x,.78,0),Vector3(.06,.13,.16),STEEL)
		for k in 4:
			KIT.box(t,Vector3(-.16+k*.095,.56,-.32),Vector3(.035,.53,.025),c.darkened(.19))
		_finish(t,"SalvageBin%d"%i,Vector3(4.05+i*.89,.04,.45-float(i%2)*.17),float(i)*.22,AABB(Vector3(-.41,0,-.37),Vector3(.82,1.16,.74)))

func _oil() -> void:
	var materials := preload("res://world/city_look/CityLookMaterials.gd")
	var surface := materials.ground_decal("garage_used_oil",materials.alpha_blob("garage_used_oil",.38),Color(.055,.047,.032,.82))
	for entry in [[Vector3(-2,.058,-1.9),Vector2(4.7,2.8)],[Vector3(-4.65,.058,-.65),Vector2(1.35,.9)],[Vector3(1.35,.058,-1.2),Vector2(.85,.55)]]:
		var stain := MeshInstance3D.new()
		stain.name="OilStain"
		var plane := PlaneMesh.new()
		plane.size=entry[1]
		stain.mesh=plane
		stain.position=entry[0]
		stain.rotation.y=.23
		stain.material_override=surface
		stain.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(stain)

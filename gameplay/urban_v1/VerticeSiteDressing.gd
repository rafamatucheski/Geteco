extends Node3D
## Static working detail for Vértice, authored in company-local metres.
## Central cargo islands leave the truck loop, patrol and dock lanes unobstructed.
var solids: Array[StaticBody3D] = []
var placements: Array[Dictionary] = []
var roof_parts: Array[Node3D] = []
var _materials := {}
var _batches := {}
var _roof: Node3D
var _fixed: Node3D

func _ready() -> void:
	name = "VerticeWorkingDetail"
	_fixed = Node3D.new()
	_fixed.name = "SiteDetails"
	add_child(_fixed)
	_roof = Node3D.new()
	_roof.name = "RestShelterRoof"
	add_child(_roof)
	roof_parts.append(_roof)
	_cargo_islands()
	_perimeter_work()
	_employee_court()
	_office_details()
	_storage_details()
	_packing_stations()
	_flush()

func set_cutaway(active: bool) -> void:
	for roof in roof_parts: roof.visible = not active

func set_region_active(active: bool) -> void:
	visible = active
	for body in solids: body.collision_layer = 1 if active else 0

func _cargo_islands() -> void:
	_bay(Vector2(-17.5,45.5),Vector2(15,7))
	_bay(Vector2(5,47.5),Vector2(10,5))
	for row in [Vector3(-23,.03,44),Vector3(-19,.03,44),Vector3(-15,.03,47.2),Vector3(2,.03,47),Vector3(6.5,.03,47.6)]:
		_cargo(row,2.25 if row.x < 0 else 1.8)
	_empty_pallets(Vector3(-23,.03,47.5),5)
	_empty_pallets(Vector3(-19,.03,47.5),4)
	_pallet_jack(Vector3(-12,.03,44.5))
	_reel(Vector3(9,.03,47.2),.6)
	for p in [Vector2(-24.5,42.5),Vector2(-10.5,48.5),Vector2(.5,45.5)]: _cone(p)
	# Corner stripes and tire scuffs mark handling space without explanatory text.
	for x in [-25.0,-10.0,0.0,10.0]:
		_box(Vector3(x,.043,44),Vector3(.1,.015,2),"yellow")
	for x in [-30.0,-27.5,12.0]:
		_box(Vector3(x,.038,44),Vector3(.15,.01,6),"scuff")

func _bay(center: Vector2, size: Vector2) -> void:
	for side in [-1.0,1.0]:
		_box(Vector3(center.x+side*size.x*.5,.043,center.y),Vector3(.1,.014,size.y),"yellow")
		_box(Vector3(center.x,.043,center.y+side*size.y*.5),Vector3(size.x,.014,.1),"yellow")

func _pallet(at: Vector3, width := 2.4, depth := 1.9) -> void:
	for x in [-width*.4,0.0,width*.4]:
		_box(at+Vector3(x,.11,0),Vector3(.18,.2,depth),"wood_dark")
	for z in [-.8,-.4,0.0,.4,.8]:
		_box(at+Vector3(0,.23,z*depth/1.9),Vector3(width,.09,.25),"wood")

func _cargo(at: Vector3, height: float) -> void:
	_pallet(at)
	var carton_height := (height-.3)*.5
	for row in 2:
		for x in [-.55,.55]:
			for z in [-.43,.43]:
				var p := at+Vector3(x,.28+carton_height*(row+.5),z)
				_box(p,Vector3(1.02,carton_height-.025,.82),"carton" if row==0 else "paper")
				_box(p+Vector3(0,carton_height*.5,.001),Vector3(.11,.015,.81),"tape")
				_box(p+Vector3(0,0,.416),Vector3(.11,carton_height-.03,.016),"tape")
				_box(p+Vector3(.29,.1,.427),Vector3(.18,.13,.015),"label")
	for x in [-.87,.87]:
		_box(at+Vector3(x,height*.5+.14,.91),Vector3(.045,height-.2,.025),"strap")
		_box(at+Vector3(x,height+.02,0),Vector3(.045,.03,1.84),"strap")
	_solid("PalletizedFreight",at+Vector3(0,height*.5,0),Vector3(2.4,height,1.9))

func _empty_pallets(at: Vector3, count: int) -> void:
	for level in count: _pallet(at+Vector3(0,level*.27,0),2.2,1.7)
	_solid("EmptyPalletStack",at+Vector3(0,count*.27*.5,0),Vector3(2.2,count*.27,1.7))

func _pallet_jack(at: Vector3) -> void:
	for x in [-.33,.33]:
		_box(at+Vector3(x,.16,.6),Vector3(.2,.22,1.65),"ochre")
		_cylinder(at+Vector3(x,.1,1.23),.1,.16,"rubber",Vector3(0,0,PI*.5))
	_box(at+Vector3(0,.28,-.18),Vector3(.85,.32,.55),"ochre")
	_cylinder(at+Vector3(0,.23,-.4),.23,.18,"rubber",Vector3(0,0,PI*.5))
	_box(at+Vector3(0,.89,-.5),Vector3(.07,1.2,.07),"steel",Vector3(-.15,0,0))
	for x in [-.23,.23]: _box(at+Vector3(x,1.45,-.6),Vector3(.065,.37,.065),"rubber")
	_box(at+Vector3(0,1.65,-.6),Vector3(.52,.065,.065),"rubber")
	_solid("HandPalletJack",at+Vector3(0,.8,.36),Vector3(.9,1.6,2.2))

func _cone(p: Vector2) -> void:
	var at := Vector3(p.x,.03,p.y)
	_box(at+Vector3(0,.04,0),Vector3(.42,.08,.42),"rubber")
	_cylinder(at+Vector3(0,.36,0),.18,.6,"orange",Vector3.ZERO,.045)
	_cylinder(at+Vector3(0,.43,0),.126,.11,"label",Vector3.ZERO,.1)
	_solid("SafetyCone",at+Vector3(0,.34,0),Vector3(.42,.68,.42))

func _perimeter_work() -> void:
	# Guard patrol is x=-43; vehicles run x=-37. Keep this strip west of -45.
	for z in [5.0,10.0,17.0,22.0]: _cargo(Vector3(-46.6,.03,z),1.6 if z<15 else 2.15)
	_reel(Vector3(-46.7,.03,31),.82)
	_reel(Vector3(-46.7,.03,35),.67)
	_empty_pallets(Vector3(-46.6,.03,43),5)
	for z in [65.5,73.0]: _dumpster(Vector3(-46.5,.03,z))
	# East-side utility plant sits beyond the x44 patrol, clear of office access.
	for z in [5.0,8.0,11.0]: _drum(Vector3(47.4,.03,z),"teal")
	var bench := Vector3(47.5,.03,17)
	_box(bench+Vector3(0,.9,0),Vector3(2.1,.15,4),"steel")
	for z in [-1.7,1.7]: _box(bench+Vector3(0,.45,z),Vector3(1.8,.9,.16),"steel")
	_box(bench+Vector3(0,1.18,-.8),Vector3(.9,.4,1),"red")
	for z in [-1.0,-.65]: _box(bench+Vector3(-.46,1.18,z),Vector3(.03,.06,.2),"chrome")
	_cylinder(bench+Vector3(.2,1.2,1.1),.21,.5,"dark",Vector3(PI*.5,0,0))
	_solid("MaintenanceWorkbench",bench+Vector3(0,.75,0),Vector3(2.1,1.5,4))
	for z in [15.7,17.7]:
		_box(Vector3(49.1,1.3,z),Vector3(.12,2.6,1.6),"steel")
		for y in [.7,1.2,1.7]: _box(Vector3(49, y,z),Vector3(.09,.04,1.25),"chrome")
		_solid("ToolBoard",Vector3(49.1,1.3,z),Vector3(.12,2.6,1.6))
	# Back strip remains behind the guard's z=-24 perimeter walk.
	for x in [3.0,9.0,15.0]: _cargo(Vector3(x,.03,-27),1.5)
	# Two parking bays remain empty for real drivable employee vehicles.
	for x in [-37.0,-31.0]:
		_box(Vector3(x,.13,71),Vector3(2.4,.26,.35),"concrete")
		_solid("ParkingWheelStop",Vector3(x,.13,71),Vector3(2.4,.26,.35))
	for x in [-38.0,-36.5,-35.0]:
		for z in [73.2,74.3]: _cylinder(Vector3(x,.5,z),.04,1,"steel")
		_box(Vector3(x,1,73.75),Vector3(.08,.08,1.18),"steel")
		_solid("CycleStand",Vector3(x,.5,73.75),Vector3(.12,1,1.2))

func _drum(at: Vector3, key: String) -> void:
	_cylinder(at+Vector3(0,.62,0),.47,1.22,key)
	for y in [.1,.34,.89,1.18]: _cylinder(at+Vector3(0,y,0),.485,.055,"steel")
	_cylinder(at+Vector3(.19,1.26,0),.055,.025,"dark")
	_solid("SteelDrum",at+Vector3(0,.63,0),Vector3(.98,1.26,.98))

func _reel(at: Vector3, radius: float) -> void:
	_cylinder(at+Vector3(0,radius,0),radius*.64,1.15,"dark",Vector3(PI*.5,0,0))
	for z in [-.65,.65]:
		_cylinder(at+Vector3(0,radius,z),radius,.13,"wood",Vector3(PI*.5,0,0))
		_cylinder(at+Vector3(0,radius,z*1.12),.13,.025,"dark",Vector3(PI*.5,0,0))
	for z in [-.42,-.21,0.0,.21,.42]: _cylinder(at+Vector3(0,radius,z),radius*.66,.045,"rubber",Vector3(PI*.5,0,0))
	_solid("CableReel",at+Vector3(0,radius,0),Vector3(radius*2,radius*2,1.45))

func _dumpster(at: Vector3) -> void:
	_box(at+Vector3(0,.95,0),Vector3(2.2,1.6,3.6),"green")
	for z in [-.91,.91]: _box(at+Vector3(0,1.82,z),Vector3(2.3,.13,1.75),"dark")
	for x in [-1.11,1.11]:
		for z in [-1.2,-.3,.6,1.3]: _box(at+Vector3(x,.95,z),Vector3(.055,1.35,.07),"steel")
	for x in [-.85,.85]:
		for z in [-1.35,1.35]: _cylinder(at+Vector3(x,.16,z),.16,.13,"rubber",Vector3(0,0,PI*.5))
	_solid("WasteContainer",at+Vector3(0,.98,0),Vector3(2.3,1.96,3.6))

func _employee_court() -> void:
	_box(Vector3(31,.04,71.7),Vector3(13,.025,9),"concrete")
	for x in [25.0,37.0]:
		for z in [68.0,75.5]:
			_box(Vector3(x,1.6,z),Vector3(.12,3.2,.12),"teal")
			_solid("RestShelterPost",Vector3(x,1.6,z),Vector3(.12,3.2,.12))
	_box(Vector3(31,3.3,71.75),Vector3(12.8,.15,8.3),"teal",Vector3(.045,0,0),_roof)
	for x in range(25,38): _box(Vector3(x,3.4,71.75),Vector3(.045,.055,8.3),"steel",Vector3(.045,0,0),_roof)
	_solid("RestShelterRoof",Vector3(31,3.3,71.75),Vector3(12.8,.15,8.3))
	for x in [27.5,33.2]:
		_picnic_table(Vector3(x,.03,71))
	_box(Vector3(36,1.0,74.4),Vector3(1.2,2,1.0),"teal")
	_box(Vector3(36,1.18,73.88),Vector3(.89,1.25,.035),"dark")
	for x in [35.8,36.15]:
		for y in [.83,1.2,1.57]: _box(Vector3(x,y,73.85),Vector3(.18,.2,.025),"paper")
	_solid("RefreshmentMachine",Vector3(36,1,74.4),Vector3(1.2,2,1))
	_planter(Vector3(24,.03,74.5))
	_planter(Vector3(39,.03,74.5))

func _picnic_table(at: Vector3) -> void:
	for x in [-.36,0.0,.36]: _box(at+Vector3(x,.82,0),Vector3(.32,.09,2.6),"wood")
	for z in [-.9,.9]: _box(at+Vector3(0,.4,z),Vector3(.75,.8,.13),"teal")
	_solid("BreakTable",at+Vector3(0,.43,0),Vector3(1.1,.86,2.6))
	for x in [-1.0,1.0]:
		_box(at+Vector3(x,.48,0),Vector3(.48,.09,2.6),"wood")
		for z in [-.9,.9]: _box(at+Vector3(x,.23,z),Vector3(.12,.46,.12),"teal")
		_solid("BreakBench",at+Vector3(x,.27,0),Vector3(.48,.54,2.6))
	for z in [-.6,.5]: _cylinder(at+Vector3(.1,.94,z),.055,.16,"label")

func _planter(at: Vector3) -> void:
	_box(at+Vector3(0,.32,0),Vector3(.9,.64,.9),"concrete")
	_box(at+Vector3(0,.65,0),Vector3(.75,.045,.75),"soil")
	for dx in [-.23,0.0,.23]:
		_cylinder(at+Vector3(dx,1.13,0),.16,.97,"green",Vector3(0,0,dx),.03)
	_solid("Planter",at+Vector3(0,.76,0),Vector3(.9,1.52,.9))

func _office_details() -> void:
	# A compact kitchenette in the unused west office bay; x35 walk stays open.
	_box(Vector3(29.3,.49,17),Vector3(1.6,.98,4.2),"cream")
	_box(Vector3(29.3,1.02,17),Vector3(1.7,.09,4.3),"dark")
	for z in [15.5,16.6,17.7,18.5]:
		_box(Vector3(30.12,.48,z),Vector3(.025,.79,.88),"wood")
		_box(Vector3(30.15,.78,z),Vector3(.05,.035,.26),"chrome")
	_box(Vector3(29.3,1.08,18),Vector3(1.05,.035,.8),"chrome")
	_box(Vector3(29.3,1.1,18),Vector3(.83,.028,.58),"dark")
	_cylinder(Vector3(28.93,1.3,18),.035,.4,"chrome")
	_box(Vector3(29.1,1.5,18),Vector3(.36,.055,.06),"chrome")
	_box(Vector3(29.2,1.29,15.5),Vector3(.55,.43,.55),"red")
	_cylinder(Vector3(29.35,1.15,16.1),.09,.18,"label")
	_solid("KitchenetteCounter",Vector3(29.3,.8,17),Vector3(1.7,1.6,4.3))
	_box(Vector3(29.3,1.02,20.7),Vector3(1.3,2.04,1.25),"cream")
	_box(Vector3(29.96,1.42,20.7),Vector3(.035,.025,1.2),"steel")
	_box(Vector3(30,1.16,20.2),Vector3(.06,.45,.06),"chrome")
	_solid("StaffRefrigerator",Vector3(29.3,1.02,20.7),Vector3(1.35,2.04,1.25))
	_planter(Vector3(32,.04,26.5))
	# Small props remain inside the existing furniture's physical envelope.
	for z in [14.0,21.0]:
		_box(Vector3(40.2,.86,z+.1),Vector3(.43,.09,.5),"paper")
		_box(Vector3(40.2,.91,z+.1),Vector3(.38,.015,.45),"label")
		_cylinder(Vector3(38.5,.93,z+.25),.085,.2,"teal")
		_box(Vector3(40.35,.94,z-.45),Vector3(.42,.25,.3),"dark")
	for z in [10.9,22.8]:
		_box(Vector3(41.8,1.9,z),Vector3(.12,1.1,2.0),"wood")
		for dz in [-.6,0.0,.6]: _box(Vector3(41.72,1.91,z+dz),Vector3(.025,.65,.41),"paper")
		_solid("NoticeBoard",Vector3(41.8,1.9,z),Vector3(.12,1.1,2))

func _storage_details() -> void:
	# Wrap and shipping-label detail uses existing rack collision envelopes.
	for x in [-19.0,-7.0,7.0,19.0]:
		for z in [-13.0,-4.0]:
			for dx in [-2.0,0.0,2.0]:
				for y in [1.04,2.91]:
					_box(Vector3(x+dx,y,z+.919),Vector3(1.48,.025,.016),"wood_dark")
					_box(Vector3(x+dx-.37,y+.24,z+.929),Vector3(.28,.19,.012),"label")
					_box(Vector3(x+dx+.38,y,z+.935),Vector3(.045,1.04,.016),"strap")
	for x in [-23.0,-15.0]:
		_box(Vector3(x+.85,1.84,-17.5),Vector3(.75,.18,.65),"paper")
		_box(Vector3(x+.85,1.94,-17.5),Vector3(.63,.02,.52),"label")
		_cylinder(Vector3(x-.8,1.9,-17.45),.15,.18,"yellow")
		_box(Vector3(x,1.82,-17.2),Vector3(.4,.07,.24),"dark")
	# Emergency equipment goes on already solid wall/piers, not in walking lanes.
	for x in [-25.0,25.0]:
		_cylinder(Vector3(x,1.0,17.56),.14,.55,"red")
		_box(Vector3(x,1.35,17.56),Vector3(.2,.12,.2),"dark")
		_solid("FireExtinguisher",Vector3(x,1.1,17.56),Vector3(.3,.75,.3))
	# No props in the hatch reserve x[-25,-20], z[-16,-10].

func _packing_stations() -> void:
	# Two recognisable packing islands in the otherwise empty receiving hall.
	# Reserved footprint each: x=center±2.1, z6.8..9.2. Cross-aisle is z12;
	# central/side lanes x0, ±12 and x24 remain continuous and unobstructed.
	for x in [-19.0,19.0]:
		var bench := Vector3(x-.55,0,7.45)
		_box(bench+Vector3(0,1.02,0),Vector3(2.8,.12,1.1),"wood")
		for dx in [-1.22,1.22]:
			for dz in [-.43,.43]: _box(bench+Vector3(dx,.49,dz),Vector3(.1,.98,.1),"teal")
		_box(bench+Vector3(0,.3,0),Vector3(2.6,.08,.95),"steel")
		_box(bench+Vector3(-.75,.57,0),Vector3(.85,.45,.65),"paper")
		# Scale: weighing plate, stem, angled readout and small control keys.
		_box(bench+Vector3(-.65,1.17,.03),Vector3(.85,.18,.78),"steel")
		_box(bench+Vector3(-.65,1.28,.03),Vector3(.81,.055,.74),"chrome")
		_box(bench+Vector3(-.91,1.46,-.42),Vector3(.07,.78,.07),"steel")
		_box(bench+Vector3(-.91,1.85,-.39),Vector3(.52,.29,.13),"dark")
		_box(bench+Vector3(-.91,1.88,-.315),Vector3(.4,.12,.022),"green")
		# Label printer with output sheet, a tape gun and rolls of wrapping film.
		_box(bench+Vector3(.36,1.27,-.08),Vector3(.53,.38,.5),"cream")
		_box(bench+Vector3(.36,1.22,.178),Vector3(.35,.07,.022),"dark")
		_box(bench+Vector3(.36,1.16,.33),Vector3(.27,.017,.36),"label")
		for dx in [.87,1.13]:
			_cylinder(bench+Vector3(dx,1.2,-.23),.105,.23,"tape")
			_cylinder(bench+Vector3(dx,1.322,-.23),.045,.008,"wood_dark")
		_box(bench+Vector3(.96,1.17,.26),Vector3(.21,.2,.24),"red")
		_solid("PackingStationBench",bench+Vector3(0,.99,0),Vector3(2.8,1.98,1.1))
		# Short roller bed joins the station to its cart; each roller has relief.
		var conveyor := Vector3(x-.55,0,8.73)
		for side in [-1.0,1.0]:
			_box(conveyor+Vector3(0,.89,side*.29),Vector3(2.75,.13,.06),"teal")
			_box(conveyor+Vector3(side*1.1,.43,0),Vector3(.12,.86,.5),"steel")
		for index in 12:
			_cylinder(conveyor+Vector3(-1.2+index*.22,.89,0),.065,.53,"chrome",Vector3(PI*.5,0,0))
		_box(conveyor+Vector3(-.2,1.17,0),Vector3(.65,.46,.49),"carton")
		_box(conveyor+Vector3(-.2,1.405,0),Vector3(.1,.02,.49),"tape")
		_solid("PackingRollerBed",conveyor+Vector3(0,.72,0),Vector3(2.75,1.44,.65))
		# Four-wheel cage trolley carrying differently sized outbound parcels.
		var cart := Vector3(x+1.35,0,8.15)
		_box(cart+Vector3(0,.22,0),Vector3(1.05,.13,1.8),"teal")
		for dx in [-.44,.44]:
			for dz in [-.73,.73]:
				_cylinder(cart+Vector3(dx,.12,dz),.12,.09,"rubber",Vector3(0,0,PI*.5))
			_box(cart+Vector3(dx,.86,-.82),Vector3(.06,1.25,.06),"steel")
		_box(cart+Vector3(0,1.49,-.82),Vector3(.94,.06,.06),"steel")
		for dz in [-.43,.43]:
			_box(cart+Vector3(0,.68,dz),Vector3(.91,.83,.72),"carton")
			_box(cart+Vector3(0,1.101,dz),Vector3(.11,.018,.72),"tape")
		_box(cart+Vector3(0,1.34,.25),Vector3(.72,.47,.68),"paper")
		_box(cart+Vector3(0,1.58,.25),Vector3(.11,.02,.68),"tape")
		_solid("PackingParcelTrolley",cart+Vector3(0,.8,0),Vector3(1.05,1.6,1.8))
		_bay(Vector2(x,8),Vector2(4.2,2.4))

func _material(key: String) -> Material:
	if _materials.has(key): return _materials[key]
	var palette := {"wood":"a68660","wood_dark":"725c43","carton":"af9876","paper":"d0bd98","tape":"c3ad80","label":"e5dfcb","strap":"303c3b","teal":"365e60","steel":"6c7978","chrome":"a7b3af","ochre":"c29d45","orange":"c17c35","rubber":"252c2c","dark":"394746","scuff":"555d58","yellow":"c9b674","concrete":"959b91","red":"9e493d","green":"607561","cream":"c5c4ad","soil":"555443"}
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(palette.get(key,"ffffff"))
	material.roughness = .88
	if key in ["steel","chrome","teal","red"]:
		material.metallic = .3
		material.roughness = .55
	_materials[key] = material
	return material

func _box(at: Vector3, size: Vector3, key: String, angles := Vector3.ZERO, group: Node3D = null) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_append(mesh,at,key,angles,group)

func _cylinder(at: Vector3, radius: float, height: float, key: String, angles := Vector3.ZERO, top_radius := -1.0) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = top_radius if top_radius>=0 else radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 1
	_append(mesh,at,key,angles,null)

func _append(mesh: Mesh, at: Vector3, material_key: String, angles: Vector3, group: Node3D) -> void:
	if group == null: group = _fixed
	var key := "%s:%s"%[group.get_instance_id(),material_key]
	if not _batches.has(key):
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = {"surface":builder,"group":group,"material":_material(material_key)}
	var surface: SurfaceTool = _batches[key].surface
	surface.append_from(mesh,0,Transform3D(Basis.from_euler(angles),at))

func _solid(id: String, at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = id+str(solids.size())
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("interior_solid_id","vertice_detail/"+body.name)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	solids.append(body)
	placements.append({"id":id,"center":at,"size":size})

func _flush() -> void:
	for key in _batches:
		var row: Dictionary = _batches[key]
		var instance := MeshInstance3D.new()
		instance.name = "WorkingDetailBatch"
		instance.mesh = row.surface.commit()
		instance.material_override = row.material
		row.group.add_child(instance)
	_batches.clear()

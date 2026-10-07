extends Node3D
## Static parts and work-in-progress bays. Shared textured finishes and merged
## geometry keep the clutter independent of the worker's per-frame routine.
const G := preload("res://world/desert/DesertGeometry.gd")
const MATERIALS := preload("res://world/desert/DesertTownMaterials.gd")
const FINISH := preload("res://world/places/ShopInteriorMaterials.gd")
const CITY := preload("res://world/city_look/CityLookMaterials.gd")
const SALVAGE := preload("res://assets/maciota/GarageBackyard.gd")
var solid_inventory: Array[Dictionary] = []

func _ready() -> void:
	name="DigoYardDetails"
	_project_bay()
	_rear_storage()
	_mobile_tools()
	_grime()
	MATERIALS.batch_visuals(self)

func _project_bay() -> void:
	var yard := SALVAGE.new()
	yard.position=Vector3(-9,0,3)
	yard.name="SecondProjectBay"
	add_child(yard)
	# Reuse the fully modelled stripped shell, its four stands, engine pallet
	# and detached panels, but move both meshes AND solids of the scrap bins.
	for child in yard.get_children():
		if str(child.name).begins_with("SalvageBin"):
			var index := int(str(child.name).trim_prefix("SalvageBin").left(1))
			child.position=Vector3(-4+float(index)*1.2,.04,-7)
		if child is MeshInstance3D and child.material_override is StandardMaterial3D and child.material_override.vertex_color_use_as_albedo:
			var mat: StandardMaterial3D=child.material_override.duplicate()
			mat.albedo_texture=FINISH.texture("metal")
			mat.uv1_triplanar=true
			mat.uv1_world_triplanar=true
			mat.uv1_scale=Vector3.ONE*2.5
			mat.roughness=.91
			child.material_override=mat
	# Low wheeled jack, hydraulic piston and long handle visibly support a
	# project awaiting wheels. One solid reserves the complete jack footprint.
	_solid("HydraulicJack",Vector3(-10,.60,-.32),Vector3(.65,1.20,1.58))
	_box("JackBase",Vector3(-10,.13,-.5),Vector3(.50,.15,1.10),"metal",Color("9c4835"))
	for side in [-1.0,1.0]:
		var arm := _box("JackLiftArm",Vector3(-10+side*.15,.28,-.52),Vector3(.07,.12,.70),"metal",Color("a25338"))
		arm.rotation.x=-.2
		var wheel := G.cylinder(self,"JackCaster",Vector3(-10+side*.30,.12,-.13),.11,.09,Color("353936"))
		wheel.rotation.z=PI*.5
	_beam(Vector3(-10,.21,-.06),Vector3(-10,1.15,.40),.035,Color("454d49"))
	# Wheels set out for the next job, within a reserved low rack.
	_solid("WheelRack",Vector3(-12.8,.6,6),Vector3(3.7,1.2,.82))
	for x in [-14.55,-11.05]: _box("WheelRackPost",Vector3(x,.6,6),Vector3(.06,1.2,.65),"metal",Color("565c54"))
	for y in [.12,1.15]: _box("WheelRackRail",Vector3(-12.8,y,6),Vector3(3.7,.08,.70),"metal",Color("72664c"))
	for index in 5:
		var x := -14.2+float(index)*.7
		var tyre := G.cylinder(self,"RackTyre",Vector3(x,.64,6),.39,.26,Color("242927"))
		tyre.rotation.x=PI*.5
		var rim := G.cylinder(self,"RackRim",Vector3(x,.64,5.855),.235,.03,Color("8b9590"))
		rim.rotation.x=PI*.5

func _rear_storage() -> void:
	# An open metal frame reads as a workshop, without a high wall concealing
	# Dante/Digo through the user's diagonal exterior camera.
	for x in [-9.5,-5.0,-.5]:
		_solid("PartsRack",Vector3(x,1.18,9.2),Vector3(3.6,2.36,1.05))
		for side in [-1.0,1.0]:
			_box("RackUpright",Vector3(x+side*1.72,1.18,9.2),Vector3(.065,2.36,1.05),"metal",Color("56635d"))
		for tier in 4:
			var y := .10+float(tier)*.68
			_box("RackShelf",Vector3(x,y,9.2),Vector3(3.6,.07,1.05),"wood",Color("877254"))
			for item in 4:
				var xx: float=float(x)-1.2+float(item)*.8
				if (tier+item)%3==0:
					G.cylinder(self,"PaintTin",Vector3(xx,y+.19,9.05),.13,.32,Color("7a8c76"))
				else:
					_box("PartsCarton",Vector3(xx,y+.22,9.15),Vector3(.60,.38,.68),"wood",Color("9c8462"))
					_box("CartonTape",Vector3(xx,y+.42,9.15),Vector3(.08,.013,.67),"cloth",Color("c1ad83"))
	# A second substantial bench carries real mechanical shapes at working
	# height, while the west service aisle and customer parking stay free.
	_solid("EngineBench",Vector3(6.4,.52,6.1),Vector3(5.2,1.04,1.20))
	for x in [4.05,8.75]:
		for z in [5.63,6.57]: _box("BenchLeg",Vector3(x,.49,z),Vector3(.11,.98,.11),"metal",Color("56625b"))
	_box("EngineBenchTop",Vector3(6.4,1.015,6.1),Vector3(5.2,.09,1.20),"wood",Color("8e7052"))
	for i in 2:
		var x := 4.8+float(i)*2.6
		_box("EngineBlock",Vector3(x,1.38,6.1),Vector3(1.05,.65,.68),"metal",Color("5b6564"))
		for rib in 6: _box("EngineCoolingRib",Vector3(x-.44+float(rib)*.175,1.70,6.1),Vector3(.065,.055,.77),"metal",Color("8a9892"))
		G.cylinder(self,"EnginePulley",Vector3(x,1.38,5.715),.22,.06,Color("535c59")).rotation.x=PI*.5
	_box("OilyCloth",Vector3(6.3,1.08,5.87),Vector3(.45,.02,.4),"cloth",Color("746143"))
	_solid("OilDrum",Vector3(12,.48,7.6),Vector3(.85,.96,.85))
	G.cylinder(self,"OilDrumBody",Vector3(12,.48,7.6),.41,.96,Color("8a5f43"))
	for y in [.10,.47,.88]: G.cylinder(self,"OilDrumBand",Vector3(12,y,7.6),.425,.045,Color("493d32"))
	_beam(Vector3(12,.96,7.6),Vector3(12,1.26,7.6),.05,Color("737b70"))
	_beam(Vector3(12,1.26,7.6),Vector3(12.32,1.26,7.6),.05,Color("737b70"))

func _mobile_tools() -> void:
	_solid("MobileToolCart",Vector3(-7.1,.47,-6),Vector3(1.2,.94,.65))
	for y in [.18,.72]: _box("ToolCartTray",Vector3(-7.1,y,-6),Vector3(1.1,.075,.58),"metal",Color("945345"))
	for x in [-7.60,-6.6]:
		_box("ToolCartUpright",Vector3(x,.45,-6),Vector3(.06,.75,.58),"metal",Color("7e4237"))
		for z in [-6.23,-5.77]: G.cylinder(self,"CartCaster",Vector3(x,.07,z),.07,.07,Color("292e2c")).rotation.z=PI*.5
	for i in 5: _box("CartSocket",Vector3(-7.45+float(i)*.17,.80,-6.03),Vector3(.05,.10,.07),"metal",Color("9ca8a2"))
	# Coiled hoses lie against the compressor, never across the worker route.
	var hose := Node3D.new()
	hose.name="CoiledAirHose"
	hose.position=Vector3(3.1,.07,2.4)
	add_child(hose)
	for loop in 3:
		for segment in 18:
			var a := TAU*float(segment)/18
			var b := TAU*float(segment+1)/18
			var radius := .38+float(loop)*.065
			_beam(hose.position+Vector3(cos(a)*radius,0,sin(a)*radius),hose.position+Vector3(cos(b)*radius,0,sin(b)*radius),.018,Color("393f35"))
	# Small tins, rags and bolts remain on their work surfaces; ordinary foot
	# traffic never receives an invisible ankle-height barrier from litter.
	for i in 8:
		var x := -5.6+float(i)*.31
		G.cylinder(self,"BenchSocket",Vector3(x,1.06,2.18),.026,.065,Color("9aa39d"))
	for i in 3: _box("UsedRag",Vector3(-3.65+float(i)*.14,1.04,2.25),Vector3(.15,.014,.23),"cloth",Color("665c49"))

func _grime() -> void:
	var texture := CITY.alpha_blob("desert_digo_oil",.42)
	var mat := CITY.ground_decal("desert_digo_oil",texture,Color(.10,.075,.044,.78))
	for row in [[Vector3(0,.052,0),Vector2(3.4,4.4)],[Vector3(-10,.051,1.0),Vector2(5.5,3.4)],[Vector3(5,.049,5.4),Vector2(2.8,1.2)],[Vector3(-5,.048,2),Vector2(3.8,1.6)]]:
		var stain := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size=row[1]
		stain.mesh=plane
		stain.position=row[0]
		stain.material_override=mat
		stain.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(stain)
	for x in [-.78,.78,5.2,6.8]:
		for i in 5:
			var mark := _box("TyreScuff",Vector3(x,.048,-8.6+float(i)*.56),Vector3(.14,.005,.34),"rubber",Color("4e4c40"))
			mark.rotation.y=.05*sin(float(i))

func _box(id: String, at: Vector3, size: Vector3, kind: String, color: Color) -> MeshInstance3D:
	var node := G.box(self,id,at,size,color)
	node.material_override=FINISH.material(kind,color)
	return node

func _solid(id: String, at: Vector3, size: Vector3) -> void:
	var holder := Node3D.new()
	holder.name=id+"Volume"
	holder.position=at
	G.collision(holder,size)
	holder.set_meta("interior_solid_id",id)
	add_child(holder)
	solid_inventory.append({"id":id,"bounds":AABB(at-size*.5,size)})

func _beam(a: Vector3, b: Vector3, width: float, color: Color) -> void:
	var node := G.cylinder(self,"ServiceDetail",(a+b)*.5,width*.5,a.distance_to(b),color)
	node.basis=Basis(Quaternion(Vector3.UP,(b-a).normalized()))

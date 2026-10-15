extends RefCounted
const G := preload("res://world/desert/DesertGeometry.gd")
const DETAILS := preload("res://world/desert/DesertTownDetails.gd")
const TRUCK_DETAILS := preload("res://world/desert/DesertTruckDetails.gd")
const BITREM := preload("res://world/desert/DesertBitremModel.gd")
const MATERIALS := preload("res://world/desert/DesertTownMaterials.gd")

static func _box(parent: Node3D,id: String,at: Vector3,size: Vector3,color: Color,solid := false) -> MeshInstance3D:
	var result := G.box(parent,id,at,size,color,solid)
	# Duplicate Godot node names may be rewritten; finish selection must keep the authored identity.
	result.set_meta("desert_part_id",id)
	return result

## Posto Miragem pintado (PaintedFacadeKit, estilo posto-deserto): a fachada inteira
## vira imagem e a caixa de colisão do kit substitui as paredes. O vão da casca 3D
## era um recuo sólido (sem interior), então não há entrada de verdade para casar.
const PAINTED_FUEL := "posto-deserto"

static func _painted_fuel(data: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name=str(data.id)
	root.position=data.position
	var size: Vector3=data.size
	var wall_h: float=PaintedFacadeKit.natural_size(PAINTED_FUEL).y
	PaintedFacadeKit.build(root,PAINTED_FUEL,Vector3(size.x,wall_h,size.z),root,NAN,{"snow":false})
	# Faixa laranja do topo da pintura recebe o nome próprio do posto.
	G.sign_name(root,str(data.name),Vector3(0,wall_h*.89,size.z*.5+.06),48)
	var details := Node3D.new()
	details.name="AuthoredTownDetails"
	root.add_child(details)
	DETAILS._fuel_shop(details,size)
	MATERIALS.batch_visuals(details)
	return root

static func building(data: Dictionary) -> Node3D:
	if data.kind=="fuel" and PaintedFacadeKit.enabled() and FileAccess.file_exists(PaintedFacadeKit.ROOT+PAINTED_FUEL+"/style.json"):
		return _painted_fuel(data)
	var root := Node3D.new()
	root.name=str(data.id)
	root.position=data.position
	if data.kind in ["diner","shop"]: root.rotation.y=PI
	var size: Vector3=data.size
	var wall: Color=data.color
	var entry_width := 5.4 if data.kind=="workshop" else 2.4
	# Split front wall at the actual usable doorway. Transfer interiors retain the compact marker.
	_box(root,"RearWall",Vector3(0,size.y*.5,-size.z*.5),Vector3(size.x,size.y,.4),wall,true)
	for side in [-1.0,1.0]:
		_box(root,"SideWall",Vector3(side*size.x*.5,size.y*.5,0),Vector3(.4,size.y,size.z),wall,true)
		var segment := (size.x-entry_width)*.5
		_box(root,"FrontWall",Vector3(side*(entry_width*.5+segment*.5),size.y*.5,size.z*.5),Vector3(segment,size.y,.4),wall,true)
	_box(root,"DoorLintel",Vector3(0,size.y-.45,size.z*.5),Vector3(entry_width,.9,.45),wall)
	_box(root,"DoorRecess",Vector3(0,1.2,size.z*.5-.35),Vector3(entry_width,2.4,.12),Color("3d4948"),true)
	_box(root,"RoofSlab",Vector3(0,size.y+.12,0),Vector3(size.x+.6,.24,size.z+.6),Color("a59176"))
	for side in [-1.0,1.0]:
		_box(root,"Parapet",Vector3(side*(size.x*.5+.1),size.y+.35,0),Vector3(.22,.55,size.z+.6),wall)
	_box(root,"ParapetFront",Vector3(0,size.y+.35,size.z*.5+.2),Vector3(size.x+.6,.55,.22),wall)
	_box(root,"Foundation",Vector3(0,.08,0),Vector3(size.x+.7,.16,size.z+.7),Color("9b8b72"))
	# Flat adobe/stucco masses, deep window reveals, modest awnings and rooftop cooling units.
	for side in [-1.0,1.0]:
		if data.kind=="workshop": continue
		_box(root,"WindowFrame",Vector3(side*size.x*.30,1.65,size.z*.5+.23),Vector3(2.4,1.4,.14),Color("e1caa3"))
		_box(root,"WindowGlass",Vector3(side*size.x*.30,1.65,size.z*.5+.32),Vector3(2.1,1.12,.05),Color("46595a"))
		_box(root,"WindowShade",Vector3(side*size.x*.30,2.48,size.z*.5+.7),Vector3(2.8,.14,1.25),Color("8d604a"))
	_box(root,"CoolingUnit",Vector3(size.x*.28,size.y+.6,-size.z*.24),Vector3(1.4,.8,1.3),Color("9b9b88"))
	var sign_height := size.y+.46 if data.kind=="bank" else size.y-.65
	_box(root,"SignBacking",Vector3(0,sign_height,size.z*.5+.31),Vector3(minf(size.x-2,10),.95,.18),Color("66574a"))
	G.sign_name(root,str(data.name),Vector3(0,sign_height+.01,size.z*.5+.42),48)
	if data.kind=="bank":
		for side in [-1.0,1.0]:
			_box(root,"PorticoColumn",Vector3(side*2.1,1.7,size.z*.5+1.65),Vector3(.55,3.4,.55),Color("d7c09c"),true)
		_box(root,"Portico",Vector3(0,3.5,size.z*.5+1.1),Vector3(6.2,.28,3),Color("b59065"))
		_box(root,"CopperBand",Vector3(0,size.y+.55,size.z*.5+.26),Vector3(size.x+.6,.18,.2),Color("85603d"))
	elif data.kind=="workshop":
		for x in [-8.0,8.0]:
			_box(root,"Shutter",Vector3(x,1.6,size.z*.5+.25),Vector3(4.5,3.2,.16),Color("696e64"))
			for y in range(1,12): _box(root,"ShutterRib",Vector3(x,float(y)*.25,size.z*.5+.35),Vector3(4.45,.04,.035),Color("484d46"))
		for i in 3:
			G.cylinder(root,"TireStack",Vector3(size.x*.5+1.5,.32+float(i)*.42,3),.62,.38,Color("272723"),true)
	elif data.kind=="motel":
		for i in 6:
			var x := -14.0+float(i)*5.5
			_box(root,"MotelDoor",Vector3(x,1.12,size.z*.5+.26),Vector3(1.1,2.2,.09),Color("796652"))
		_box(root,"CoveredWalk",Vector3(0,2.8,size.z*.5+1.3),Vector3(size.x,.15,2.8),Color("a87956"))
	DETAILS.finish_shell(root,data)
	root.add_child(DETAILS.building(data))
	MATERIALS.batch_visuals(root)
	return root

static func bitrem(color: Color) -> Node3D:
	return BITREM.build(color)

static func truck_stop(include_trucks := true) -> Node3D:
	var root := Node3D.new()
	root.name="MiragemTruckStop"
	var canopy := Vector3(10,0,4)
	for x in [-5.0,5.0]:
		_box(root,"PumpIsland",canopy+Vector3(x,.1,0),Vector3(1.7,.2,2.4),Color("b2a58b"),true)
		_box(root,"Pump",canopy+Vector3(x,1.1,0),Vector3(.85,2,1),Color("9b5c43"),true)
		_box(root,"PumpDisplay",canopy+Vector3(x,1.6,.51),Vector3(.64,.35,.04),Color("283736"))
	for i in 4:
		if include_trucks:
			var truck := bitrem([Color("a75339"),Color("718787"),Color("d2b676"),Color("76634e")][i])
			truck.position=Vector3(-26-float(i)*6.4,0,3)
			root.add_child(truck)
		_box(root,"ParkingLine",Vector3(-29.2-float(i)*6.4,.02,3),Vector3(.1,.02,29),Color("c1b695"))
	root.add_child(TRUCK_DETAILS.truck_stop())
	MATERIALS.batch_visuals(root)
	return root

static func cactus(height: float) -> Node3D:
	var root := Node3D.new()
	root.name="Saguaro"
	G.cylinder(root,"Stem",Vector3(0,height*.5,0),.18,height,Color("647052"),height>2.2)
	for side in [-1.0,1.0]:
		var arm := G.cylinder(root,"Arm",Vector3(side*.35,height*.53,0),.11,.7,Color("6c7454"))
		arm.rotation.z=PI*.5
		G.cylinder(root,"Tip",Vector3(side*.66,height*.67,0),.115,height*.29,Color("6c7454"))
	return root

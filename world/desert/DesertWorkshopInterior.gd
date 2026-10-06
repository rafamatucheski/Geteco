extends Node3D
## Digo has a wide central vehicle bay, west tools and east tuning desk.
const G := preload("res://world/desert/DesertGeometry.gd")
var variant := 0
func _ready() -> void:
	G.room_box(self,"ConcreteFloor",Vector3(0,-.035,0),Vector3(25,.05,18),Color("888476"),false)
	G.room_box(self,"RearWall",Vector3(0,2.3,-8.9),Vector3(25,4.6,.22),Color("b5a281"))
	for side in [-1.0,1.0]:
		G.room_box(self,"SideWall%s"%side,Vector3(side*12.4,2.3,0),Vector3(.22,4.6,18),Color("b5a281"))
		G.room_box(self,"FrontWall%s"%side,Vector3(side*7.55,2.3,8.9),Vector3(9.7,4.6,.22),Color("b5a281"))
	G.room_box(self,"Workbench",Vector3(-9.7,.65,-5.4),Vector3(4.1,1.3,1.2),Color("6b715e"))
	G.room_box(self,"ToolChest",Vector3(-10.4,.6,-2.1),Vector3(1.8,1.2,1),Color("9b503b"))
	for i in 5: G.room_box(self,"Drawer%d"%i,Vector3(-10.4,.22+float(i)*.19,-1.58),Vector3(1.65,.04,.07),Color("b3aba0"),false)
	G.room_box(self,"TuningDesk",Vector3(8.4,.65,0),Vector3(3.2,1.3,1.5),Color("a17e52"))
	G.room_box(self,"Computer",Vector3(8.4,1.64,-.18),Vector3(.75,.64,.25),Color("354344"))
	G.room_box(self,"DeskChair",Vector3(8.4,.45,-2),Vector3(.75,.9,.75),Color("52594d"))
	for side in [-1.0,1.0]:
		G.room_box(self,"LiftPost%s"%side,Vector3(side*2.1,1.8,-3.5),Vector3(.48,3.6,.65),Color("ae653f"))
		G.room_box(self,"LiftFoot%s"%side,Vector3(side*2.1,.08,-3.5),Vector3(.9,.16,1.1),Color("665b48"))
	# Ground-level rails do not silently lift the actor onto a prop.
	for x in [-1.4,1.4]: G.room_box(self,"BayPaint",Vector3(x,.003,-3),Vector3(.07,.01,8.5),Color("d3bf85"),false)
	for i in 3:
		var shelf_id := "PartsShelf%d"%i
		G.room_box(self,shelf_id,Vector3(5+float(i)*2.1,1.1,-7.9),Vector3(1.8,2.2,.9),Color("6e6d5c"))
		for tier in 3: G.room_box(self,"PartsCrate",Vector3(5+float(i)*2.1,.45+float(tier)*.65,-7.75),Vector3(1.5,.42,.65),Color("af976d"),false)
	for z in [-4.0,3.0]:
		G.room_box(self,"RoofTruss",Vector3(0,4.3,z),Vector3(24,.24,.22),Color("68634e"),false)
		var lamp := OmniLight3D.new()
		lamp.position=Vector3(0,3.5,z)
		lamp.light_color=Color("ffe4bf")
		lamp.light_energy=1.0
		lamp.omni_range=11
		lamp.shadow_enabled=false
		add_child(lamp)
	preload("res://world/desert/DesertInteriorFinish.gd").apply(self,false)

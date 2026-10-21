extends RefCounted
## A compact physical pumping station in existing Santa Lua reserved ground.
## Streamed with its terrain chunk; no lights, actors, animation or per-frame work.
const G := preload("res://world/desert/DesertGeometry.gd")
const ORIGIN := Vector3(-543,0,-444)
const RADIO := ORIGIN+Vector3(0,0,1.55)
const PUMP := ORIGIN+Vector3(1.6,0,0)
const VALVE := ORIGIN+Vector3(-2.6,0,1.3)
const GROUP := "desert_community_site"

static func build_chunk(parent: Node3D, rect: Rect2) -> Node3D:
	if not rect.has_point(Vector2(ORIGIN.x,ORIGIN.z)): return null
	var site:=Node3D.new()
	site.name="SantaLuaCooperative"
	site.position=ORIGIN
	parent.add_child(site)
	site.add_to_group(GROUP)
	G.box(site,"PumpBase",Vector3(0,.14,0),Vector3(1.7,.28,1.15),Color("998e79"),true)
	G.box(site,"PumpHousing",Vector3(0,.55,0),Vector3(1.25,.56,.82),Color("657c76"),true)
	G.box(site,"Radio",Vector3(.29,.97,.18),Vector3(.38,.28,.24),Color("535b50"),true)
	G.box(site,"RadioGrille",Vector3(.29,.98,.31),Vector3(.23,.12,.02),Color("272e2b"))
	G.cylinder(site,"Antenna",Vector3(.45,1.35,.18),.018,.54,Color("969e96"))
	for x in [-.08,.0,.08]: G.box(site,"RadioSpeaker",Vector3(.28+x,.98,.325),Vector3(.012,.1,.01),Color("8a9282"))
	G.box(site,"PipeFromTower",Vector3(-2.65,.27,-.8),Vector3(.18,.18,1.9),Color("687a73"),true)
	G.box(site,"TowerSupplyExtension",Vector3(-2.65,.27,-3.9),Vector3(.18,.18,4.4),Color("687a73"),true)
	G.box(site,"TowerOutletElbow",Vector3(-3.475,.27,-6),Vector3(1.83,.18,.18),Color("687a73"),true)
	G.box(site,"PipeToPump",Vector3(-1.42,.27,0),Vector3(2.5,.18,.18),Color("687a73"),true)
	G.box(site,"ValveStem",Vector3(-2.65,.67,0),Vector3(.16,.84,.16),Color("687a73"),true)
	var valve:=G.cylinder(site,"ValveWheel",Vector3(-2.65,1.12,0),.27,.065,Color("954d3e"),true)
	valve.rotation.x=PI*.5
	var repaired:=Node3D.new()
	repaired.name="InstalledCoupling"
	site.add_child(repaired)
	G.cylinder(repaired,"NewCoupling",Vector3(.82,.43,0),.2,.43,Color("acae9e"),true).rotation.z=PI*.5
	G.box(site,"IrrigationLine",Vector3(5,.11,0),Vector3(8.2,.1,.1),Color("59665b"))
	var wet:=Node3D.new()
	wet.name="RestoredWater"
	site.add_child(wet)
	for row in 2:
		var z: float=-.85-float(row)*1.55
		G.box(site,"GardenBed",Vector3(7,.035,z),Vector3(5.8,.065,1.05),Color("a88d61"))
		G.box(wet,"DampSoil",Vector3(7,.072,z),Vector3(5.75,.012,1.0),Color("67573b"))
		G.box(wet,"IrrigationWater",Vector3(7,.081,z+.32),Vector3(5.65,.018,.13),Color("789da3"))
		for plant in 7:
			var at:=Vector3(4.6+float(plant)*.79,.19,z-.08)
			G.box(site,"YoungPlant",at,Vector3(.19,.23,.31),Color("737b45"))
			G.box(site,"YoungPlantLeaf",at+Vector3(0,.06,0),Vector3(.37,.1,.12),Color("7d8750"))
	set_step(site,0)
	return site

static func set_step(site: Node3D, step: int) -> void:
	if int(site.get_meta("community_step",-1))==step: return
	site.set_meta("community_step",step)
	var coupling: Node3D=site.get_node("InstalledCoupling")
	coupling.visible=step>=3
	# Disable the hidden replacement's physical shape too.
	for shape in coupling.find_children("*","CollisionShape3D",true,false): shape.set_deferred("disabled",step<3)
	(site.get_node("RestoredWater") as Node3D).visible=step>=4

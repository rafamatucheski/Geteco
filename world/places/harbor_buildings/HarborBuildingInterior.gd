extends Node3D
## Eight authored floor plans. Solid IDs cover the entire furniture footprint.
const MATERIALS = preload("res://world/places/ShopInteriorMaterials.gd")
var variant := 0
var width := 14.0
var depth := 11.0
var serial := 0

func _ready() -> void:
	if variant>=4: width=11; depth=14
	_shell()
	_stairs()
	match variant:
		0: _customs_reception()
		1: _customs_offices()
		2: _customs_accounts()
		3: _customs_staff()
		4: _apartment_day()
		5: _apartment_night()
		6: _apartment_studio()
		7: _apartment_library()
	set_process(false)
	set_physics_process(false)

func box(at: Vector3,size: Vector3,color: String,solid: String="",kind: String="wood") -> MeshInstance3D:
	var node:=MeshInstance3D.new()
	serial+=1
	node.name=(solid if not solid.is_empty() else "Detail")+str(serial)
	var mesh:=BoxMesh.new()
	mesh.size=size
	node.mesh=mesh
	node.position=at
	node.material_override=MATERIALS.material(kind,Color(color))
	if not solid.is_empty(): node.set_meta("interior_solid_id",solid)
	add_child(node)
	return node

func _shell() -> void:
	var plaster:="b7b4a6" if variant<4 else "c3b59b"
	box(Vector3(0,-.045,0),Vector3(width,.05,depth),"7e817b" if variant<4 else "8b6646","","stone" if variant<4 else "wood")
	box(Vector3(0,1.45,-depth*.5+.12),Vector3(width,2.9,.24),plaster,"BackWall","stone")
	for sign in [-1,1]:
		box(Vector3(sign*(width*.5-.12),1.45,0),Vector3(.24,2.9,depth),plaster,"SideWall%d"%sign,"stone")
		# Camera-facing wall stays physically full-height under its visual cutaway.
		box(Vector3(sign*(width*.25+.55),1.45,depth*.5-.12),Vector3(width*.5-1.1,2.9,.24),plaster,"FrontWall%d"%sign,"stone")
		box(Vector3(sign*(width*.5-.26),.09,0),Vector3(.06,.18,depth-.4),"534c40")
		box(Vector3(sign*(width*.25+.48),.52,-.8),Vector3(width*.5-1.35,1.04,.18),plaster,"Partition%d"%sign,"stone")
		box(Vector3(sign*width*.29,1.9,-depth*.5+.25),Vector3(1.8,1.12,.07),"283d45","","metal")
		for edge in [-1,1]:
			box(Vector3(sign*width*.29+edge*.94,1.9,-depth*.5+.31),Vector3(.08,1.28,.12),"554d40")
		box(Vector3(sign*width*.29,1.9,-depth*.5+.34),Vector3(.06,1.15,.1),"88755c")
		box(Vector3(sign*width*.29,1.28,-depth*.5+.35),Vector3(2,.10,.30),"88755c")
	# Entrance and central circulation stay clear on every floor.
	box(Vector3(0,.008,depth*.5-1.6),Vector3(1.8,.02,1.15),"494e45","","cloth")

func _stairs() -> void:
	var x:=-width*.5+1.45
	for step in 7:
		var h:=.16*(step+1)
		box(Vector3(x,h*.5,.2-step*.25),Vector3(1.8,h,.26),"726e64","Stair%d"%step,"stone")
	for sign in [-1,1]:
		box(Vector3(x+sign*1.0,.85,-.55),Vector3(.08,1.7,2.1),"474b47","StairRail%d"%sign,"metal")
	# Deep landing/recess communicates a stairwell; transfer is explicit at its foot.
	box(Vector3(x,1.3,-1.6),Vector3(1.9,2.6,.12),"373e3b","StairBack","stone")

func _desk(at: Vector3,id: String,computer:=true) -> void:
	box(at+Vector3(0,.73,0),Vector3(1.8,.12,.85),"795a3e",id)
	for sign in [-1,1]: box(at+Vector3(sign*.7,.34,0),Vector3(.15,.68,.65),"5b6261",id,"metal")
	if computer:
		box(at+Vector3(.18,1.10,-.17),Vector3(.65,.42,.08),"27383d",id,"metal")
		box(at+Vector3(.18,.84,-.17),Vector3(.08,.2,.08),"414946",id,"metal")
		box(at+Vector3(.15,.815,.21),Vector3(.53,.025,.20),"343a3c",id,"metal")
	box(at+Vector3(-.57,.84,.12),Vector3(.32,.045,.35),"d5ceaf",id,"cloth")
	_chair(at+Vector3(0,0,.95),id+"Chair","435c60")

func _chair(at: Vector3,id: String,color: String) -> void:
	box(at+Vector3(0,.47,0),Vector3(.52,.12,.52),color,id,"cloth")
	box(at+Vector3(0,.82,.22),Vector3(.52,.6,.12),color,id,"cloth")
	for x in [-.2,.2]:
		for z in [-.2,.2]: box(at+Vector3(x,.22,z),Vector3(.065,.44,.065),"4d514b",id,"metal")

func _shelf(at: Vector3,id: String,archive:=false) -> void:
	box(at+Vector3(0,1.03,-.24),Vector3(1.5,2.06,.08),"624d38",id)
	for sign in [-1,1]: box(at+Vector3(sign*.73,1.03,0),Vector3(.09,2.06,.55),"624d38",id)
	for level in 4:
		var y:=.14+level*.49
		box(at+Vector3(0,y,0),Vector3(1.5,.07,.55),"977951",id)
		for item in 5:
			box(at+Vector3(-.56+item*.27,y+.19,0),Vector3(.20,.31,.35),["7c4a37","637572","b4a578","4f5865","8b725a"][(item+level+variant)%5],id,"cloth")
	if archive: box(at+Vector3(0,2.16,0),Vector3(1.1,.18,.5),"a49b83",id)

func _sofa(at: Vector3,id: String,color: String) -> void:
	box(at+Vector3(0,.25,0),Vector3(2.25,.4,.88),"544432",id)
	box(at+Vector3(0,.53,0),Vector3(1.9,.22,.78),color,id,"cloth")
	box(at+Vector3(0,.83,-.34),Vector3(2.1,.68,.20),color,id,"cloth")
	for sign in [-1,1]: box(at+Vector3(sign*1.02,.65,0),Vector3(.24,.54,.95),color,id,"cloth")

func _table(at: Vector3,id: String,size: Vector2) -> void:
	box(at+Vector3(0,.76,0),Vector3(size.x,.10,size.y),"9d7d50",id)
	for x in [-1,1]:
		for z in [-1,1]: box(at+Vector3(x*(size.x*.5-.13),.36,z*(size.y*.5-.13)),Vector3(.10,.72,.10),"655039",id)

func _bed(at: Vector3,id: String,color: String) -> void:
	box(at+Vector3(0,.21,0),Vector3(1.55,.38,2.2),"745b43",id)
	box(at+Vector3(0,.47,0),Vector3(1.5,.20,2.12),"d8d3bc",id,"cloth")
	box(at+Vector3(0,.60,.32),Vector3(1.53,.09,1.40),color,id,"cloth")
	box(at+Vector3(0,.68,-1.03),Vector3(1.65,1.18,.12),"73533d",id)
	box(at+Vector3(0,.62,-.70),Vector3(1.12,.16,.42),"e8ddc1",id,"cloth")

func _kitchen(at: Vector3,id: String) -> void:
	box(at+Vector3(0,.44,0),Vector3(2.8,.88,.65),"859181",id)
	box(at+Vector3(0,.91,0),Vector3(2.9,.10,.72),"d1cbb9",id,"stone")
	box(at+Vector3(-.8,.973,0),Vector3(.64,.035,.46),"6b858b",id,"metal")
	box(at+Vector3(.7,.974,0),Vector3(.7,.035,.48),"303839",id,"metal")
	for x in [-1,0,1]: box(at+Vector3(x*.8,.64,.35),Vector3(.25,.035,.035),"a8aba2",id,"metal")
	box(at+Vector3(0,1.98,-.08),Vector3(2.8,.7,.42),"b6ae92",id)

func _customs_reception() -> void:
	_desk(Vector3(3.3,0,2.25),"Reception")
	_sofa(Vector3(3.3,0,4.2),"Waiting","61716a")
	_desk(Vector3(-3.7,0,-3.2),"Agent")
	_shelf(Vector3(2.8,0,-4.85),"ArchiveA",true)
	_shelf(Vector3(4.65,0,-4.85),"ArchiveB",true)
	_table(Vector3(3.5,0,-2.5),"Dispatch",Vector2(2.1,1.05))

func _customs_offices() -> void:
	_table(Vector3(3.6,0,-3.0),"Conference",Vector2(2.5,1.25))
	for i in 2: _chair(Vector3(2.9+i*1.35,0,-1.75),"ConferenceChair%d"%i,"5d685d")
	_desk(Vector3(-3.4,0,-3.2),"Director")
	_shelf(Vector3(-5.7,0,-4.8),"DirectorLibrary")
	_desk(Vector3(2.4,0,2.4),"Analyst")
	_shelf(Vector3(5.4,0,3.4),"FrontFiles",true)

func _apartment_day() -> void:
	_kitchen(Vector3(3,0,-6.35),"Kitchen")
	box(Vector3(4.65,.95,-4.75),Vector3(.72,1.9,.8),"d5d2bf","Fridge","metal")
	_table(Vector3(-3.2,0,-4.35),"Dining",Vector2(1.55,1.15))
	for sign in [-1,1]: _chair(Vector3(-3.2+sign*.45,0,-3.35),"DiningChair%d"%sign,"9a8060")
	_sofa(Vector3(3.25,0,1.45),"LivingSofa","8b684e")
	_table(Vector3(3.25,0,3.25),"LivingTable",Vector2(1.25,.7))
	_shelf(Vector3(3.8,0,5.7),"LivingBooks")

func _apartment_night() -> void:
	box(Vector3(0,.6,-4.65),Vector3(.18,1.2,4.2),"c3b59b","BedroomDivider","stone")
	_bed(Vector3(-3.0,0,-4.65),"MainBed","7d6159")
	_bed(Vector3(2.7,0,-4.85),"SecondBed","677b83")
	box(Vector3(-4.75,1.02,-2.4),Vector3(.55,2.04,1.3),"765e48","Wardrobe")
	_desk(Vector3(2.8,0,4.2),"Study",false)
	# Bathroom has a separate side entrance, with body-height fixtures.
	box(Vector3(2.0,.56,1.45),Vector3(.18,1.12,2.1),"c0c7bc","BathroomPartition","stone")
	box(Vector3(4.4,.42,.15),Vector3(1.2,.84,.65),"cfdbd6","Sink","stone")
	box(Vector3(4.5,.30,2.1),Vector3(.65,.6,.85),"e0ded2","Toilet","stone")
	box(Vector3(4.5,.84,1.8),Vector3(.66,.63,.25),"e0ded2","Toilet","stone")

func _customs_accounts() -> void:
	_desk(Vector3(-3.2,0,-3.1),"AccountsWest")
	_desk(Vector3(3.2,0,-3.1),"AccountsEast")
	_shelf(Vector3(-5.6,0,-4.85),"Ledgers",true)
	_shelf(Vector3(5.6,0,-4.85),"Contracts",true)
	_table(Vector3(3.5,0,2.2),"Plans",Vector2(2.6,1.2))
	for i in 3: box(Vector3(2.8+i*.65,.84,2.2),Vector3(.50,.05,.65),"d4cfb6","Plans","cloth")
	_chair(Vector3(3.5,0,3.5),"PlansChair","767052")
	box(Vector3(5.7,.57,3.4),Vector3(.85,1.14,.8),"666f70","Copier","metal")
	box(Vector3(5.7,1.2,3.4),Vector3(.9,.13,.85),"bcbfb2","Copier","metal")

func _customs_staff() -> void:
	_kitchen(Vector3(3.5,0,-4.85),"StaffKitchen")
	_table(Vector3(3.6,0,-2.8),"Lunch",Vector2(2.0,.9))
	for i in 2: _chair(Vector3(3.05+i*1.1,0,-1.8),"LunchChair%d"%i,"70806b")
	for i in 3: box(Vector3(-4.8+i*.9,1.0,-4.9),Vector3(.78,2.0,.7),"74877e","Locker%d"%i,"metal")
	_sofa(Vector3(3.5,0,1.5),"StaffSofa","997655")
	_table(Vector3(3.5,0,3.15),"StaffCoffee",Vector2(1.2,.65))
	_shelf(Vector3(5.7,0,3.8),"StaffBooks")

func _apartment_studio() -> void:
	_kitchen(Vector3(-2.8,0,-6.35),"StudioKitchen")
	_bed(Vector3(3,0,-4.7),"StudioBed","73815b")
	box(Vector3(0,.55,-4.8),Vector3(.18,1.1,3.8),"b3b09a","StudioPartition","stone")
	_sofa(Vector3(3.15,0,1.5),"StudioSofa","736889")
	_desk(Vector3(3.2,0,4.65),"StudioWork")
	_table(Vector3(-2.8,0,-3.9),"StudioDining",Vector2(1.4,.8))
	_chair(Vector3(-2.8,0,-2.9),"StudioDiningChair","8f795f")

func _apartment_library() -> void:
	for i in 3: _shelf(Vector3(-3.8+i*1.85,0,-6.35),"Library%d"%i)
	_table(Vector3(-2.6,0,-3.6),"Reading",Vector2(1.8,1.0))
	_chair(Vector3(-2.6,0,-2.6),"ReadingChair","6e806d")
	_bed(Vector3(3.1,0,-4.5),"GuestBed","a8865b")
	_sofa(Vector3(3.1,0,1.55),"LibrarySofa","647777")
	_table(Vector3(3.1,0,3.4),"LibraryCoffee",Vector2(1.2,.65))
	_desk(Vector3(3.2,0,5.0),"Writing",false)

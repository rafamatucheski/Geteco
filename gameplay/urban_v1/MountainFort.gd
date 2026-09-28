extends Node3D
## Ante-sala do forte militar sob a área de esqui da serra (primeira etapa).
##
## O lugar é interior nativo: o adaptador (MountainFortPlace) cuida de viagem, câmera e
## save. A sala é montada para a operação militar futura: as barricadas de sacos de
## areia e o gaveteiro-cofre formam cobertura física, e a porta blindada ao norte segue
## selada até o combate tático ser desenhado (docs/fort-operation-plan.md).
const SPAWN_POINT := Vector3(0,0,5.2)
const EXIT_POINT := Vector3(0,0,6.1)
const ROOM_BOUNDS := Rect2(-10,-25.3,20,32.4)
const HALL_FLOOR_Z := -9.1
## Coberturas da sala de operações: a IA dos soldados lê esta mesma lista para gerar
## os pontos de abrigo (lados e pontas), então cenário e tática não divergem.
const HALL_COVERS := [
	{"id":"barrier_w1","pos":Vector2(-5.5,-11.5),"size":Vector2(3.6,.8),"kind":"barrier"},
	{"id":"barrier_e1","pos":Vector2(5.5,-11.5),"size":Vector2(3.6,.8),"kind":"barrier"},
	{"id":"crates_c","pos":Vector2(0,-14.5),"size":Vector2(2.6,1.4),"kind":"crates"},
	{"id":"barrier_w2","pos":Vector2(-7.0,-17.5),"size":Vector2(3.0,.8),"kind":"barrier"},
	{"id":"barrier_e2","pos":Vector2(7.0,-17.5),"size":Vector2(3.0,.8),"kind":"barrier"},
	{"id":"crates_w3","pos":Vector2(-2.6,-20.4),"size":Vector2(2.2,1.2),"kind":"crates"},
	{"id":"crates_e3","pos":Vector2(2.6,-20.4),"size":Vector2(2.2,1.2),"kind":"crates"},
]
const COVER_HEIGHT := 1.8
const CAMERA_POSTS := [Vector3(-9.0,3.1,-24.7),Vector3(9.0,3.1,-24.7)]
const BEACON_POSTS := [Vector3(-3.0,3.0,-24.8),Vector3(3.0,3.0,-24.8)]
const REINFORCEMENT_DOORS := [Vector3(-5.2,0,-24.3),Vector3(3.6,0,-24.3)]
const LIFT_POINT := Vector3(-8.6,.04,-22.5)
const COMMAND_DESK := Vector3(0,0,-23.4)
const DOOR_TERMINAL := Vector3(-4.2,.04,-3.6)
var blast_leaves: Array[Node3D] = []
var lift_leaves: Array[Node3D] = []
var blast_body: StaticBody3D
var blast_open := false
var beacons: Array[OmniLight3D] = []
var camera_heads: Array[Node3D] = []
var reinforcement_leaves: Array[Node3D] = []
var solids: Array[StaticBody3D] = []
var floor_body: StaticBody3D
var roof_parts: Array[Node3D] = []
var facade_parts: Array[Node3D] = []
var lights: Array[OmniLight3D] = []
var active := true
var _cutaway := true
var _fixed: Node3D
var _roof: Node3D
var _front: Node3D
var _materials := {}
var _batches := {}

func _ready() -> void:
	name = "MountainFort"
	_fixed = _group("RoomAndFurniture")
	_roof = _group("CeilingCutaway")
	_front = _group("FrontWallCutaway")
	roof_parts.append(_roof)
	facade_parts.append(_front)
	_shell()
	_blast_door()
	_mountain_map()
	_guard_post()
	_armory_cage()
	_barricades()
	_supplies()
	_services()
	_exit_door()
	_operations_hall()
	_commit()
	set_cutaway(_cutaway)
	set_active(active)

func set_active(value: bool) -> void:
	active = value
	visible = value
	for body in solids: body.collision_layer = 1 if value else 0
	if is_instance_valid(blast_body) and blast_open: blast_body.collision_layer = 0
	if is_instance_valid(floor_body): floor_body.collision_layer = 1 if value else 0
	for light in lights: light.visible = value
	set_process(false)
	set_physics_process(false)

func set_cutaway(value: bool) -> void:
	_cutaway = value
	for part in roof_parts: part.visible = not value
	for part in facade_parts: part.visible = not value

func _group(id: String) -> Node3D:
	var group := Node3D.new()
	group.name = id
	add_child(group)
	return group

func _shell() -> void:
	var length := 32.4
	_box(Vector3(0,-.12,HALL_FLOOR_Z),Vector3(20.4,.24,length),"floor")
	floor_body = _solid("Floor",Vector3(0,-.12,HALL_FLOOR_Z),Vector3(20.4,.24,length),false)
	floor_body.set_meta("interior_floor",true)
	for spec in [["WestWall",Vector3(-10,1.8,HALL_FLOOR_Z),Vector3(.3,3.6,length-.1)],
		["EastWall",Vector3(10,1.8,HALL_FLOOR_Z),Vector3(.3,3.6,length-.1)],
		["HallBackWall",Vector3(0,1.8,-25.15),Vector3(20,3.6,.3)],
		# Parede entre a ante-sala e a sala de operações, com o vão da porta blindada.
		["AnteNorthWallWest",Vector3(-6.4,1.8,-7),Vector3(7.2,3.6,.3)],
		["AnteNorthWallEast",Vector3(6.4,1.8,-7),Vector3(7.2,3.6,.3)],
		["AnteLintel",Vector3(0,3.5,-7),Vector3(5.6,.2,.3)]]:
		_box(spec[1],spec[2],"concrete")
		_solid(spec[0],spec[1],spec[2])
	_box(Vector3(0,1.8,7),Vector3(20,3.6,.3),"concrete",_front)
	_solid("FrontWall",Vector3(0,1.8,7),Vector3(20,3.6,.3))
	_box(Vector3(0,3.66,HALL_FLOOR_Z),Vector3(20.2,.18,length-.2),"concrete",_roof)
	for x in [-9.8,9.8]:
		_box(Vector3(x,.5,HALL_FLOOR_Z),Vector3(.04,.95,length-.4),"wall_band")
	_box(Vector3(0,.5,-24.98),Vector3(19.6,.95,.04),"wall_band")
	for x in [-8,-4,4,8]: _box(Vector3(x,1.9,-24.97),Vector3(.05,3.3,.04),"seam")
	# Linhas amarelas no piso conduzem da entrada à porta blindada, com o corredor
	# central livre entre as barricadas.
	for x in [-1.9,1.9]: _box(Vector3(x,.012,-2.0),Vector3(.14,.012,10.0),"hazard")
	for z in [-6.2,6.2]: _box(Vector3(0,.012,z),Vector3(19.2,.012,.10),"paint")
	for x in [-6,-3,3,6]:
		_box(Vector3(x,3.4,0),Vector3(.3,.24,14),"steel",_roof)
		_box(Vector3(x,3.4,-16),Vector3(.3,.24,17),"steel",_roof)

func _blast_door() -> void:
	# Porta blindada em duas folhas que correm para dentro da parede quando o terminal do
	# posto de guarda a libera. O colisor único do vão some junto.
	var at := Vector3(0,0,-6.82)
	_box(at+Vector3(0,3.3,.02),Vector3(5.8,.3,.3),"frame")
	for x in [-2.9,2.9]: _box(at+Vector3(x,1.6,.02),Vector3(.3,3.2,.3),"frame")
	blast_body = _solid("BlastDoor",Vector3(0,1.6,-6.9),Vector3(5.6,3.2,.3))
	for side in [-1.0,1.0]:
		var leaf := Node3D.new()
		leaf.name = "BlastLeaf"+("West" if side<0 else "East")
		add_child(leaf)
		blast_leaves.append(leaf)
		_node_box(leaf,at+Vector3(side*1.4,1.55,.16),Vector3(2.8,3.0,.14),"steel")
		for index in 8:
			_node_box(leaf,at+Vector3(side*(.3+float(index)*.32),.25,.24),Vector3(.2,.34,.03),"hazard" if index%2 else "dark",Vector3(0,0,.5))
		_node_cylinder(leaf,at+Vector3(side*.5,1.55,.28),.52,.08,"steel",Vector3(PI*.5,0,0))
		for spoke in 2: _node_box(leaf,at+Vector3(side*.5,1.55,.34),Vector3(.7,.07,.05),"steel",Vector3(0,0,PI*.5*float(spoke)))
	for x in [-2.5,2.5]: _cylinder(at+Vector3(x,3.0,.22),.22,.08,"red_lamp",Vector3(PI*.5,0,0))
	for x in [-3.1,3.1]: _box(at+Vector3(x,.5,.38),Vector3(.10,1.0,.7),"steel")
	# Terminal do posto de guarda que libera a porta (mesa do posto, lado leste).
	_box(Vector3(-4.2,.95,-3.95),Vector3(.5,.3,.14),"dark")
	_box(Vector3(-4.2,.96,-3.87),Vector3(.42,.22,.02),"screen")

func set_blast_open(open: bool,animate := false) -> void:
	blast_open = open
	if is_instance_valid(blast_body): blast_body.collision_layer = 0 if open or not active else 1
	for index in blast_leaves.size():
		var target := (2.7 if index == 1 else -2.7) if open else 0.0
		if animate:
			create_tween().tween_property(blast_leaves[index],"position:x",target,1.8).set_trans(Tween.TRANS_SINE)
		else:
			blast_leaves[index].position.x = target

func set_alarm_visual(on: bool) -> void:
	for beacon in beacons:
		beacon.visible = on

func open_reinforcement_doors(open: bool) -> void:
	for index in reinforcement_leaves.size():
		var side := -1.0 if index%2 == 0 else 1.0
		create_tween().tween_property(reinforcement_leaves[index],"position:x",side*1.05 if open else 0.0,.9)

func _mountain_map() -> void:
	# Mapa de relevo da serra: curvas, teleférica e o lodge marcados sem texto.
	var board := Vector3(-6.2,2.0,-6.8)
	_box(board,Vector3(5.2,2.7,.08),"wood")
	_box(board+Vector3(0,0,.05),Vector3(4.9,2.4,.02),"paper")
	for index in 6:
		var y := -.9+float(index)*.36
		_box(board+Vector3(0,y,.07),Vector3(4.4-abs(y)*.5,.03,.01),"contour",Vector3(0,0,.06*float(index%3-1)))
	_box(board+Vector3(-.6,-.1,.075),Vector3(3.2,.05,.01),"blue",Vector3(0,0,.7))
	_box(board+Vector3(.7,.1,.075),Vector3(2.4,.04,.01),"red",Vector3(0,0,-.5))
	for spec in [Vector3(.72,.72,0),Vector3(-1.1,-.6,0),Vector3(1.6,-.5,0)]:
		_cylinder(board+spec+Vector3(0,0,.09),.16,.04,"red_lamp",Vector3(PI*.5,0,0))
	_box(board+Vector3(1.3,.72,.08),Vector3(.5,.32,.012),"paper",null,Vector3(0,0,.1))

func _guard_post() -> void:
	# Posto de guarda: mesa com monitores acesos, rádio e cadeira caída.
	_solid("GuardDesk",Vector3(-6.2,.6,-3.6),Vector3(3.2,1.2,1.1))
	_box(Vector3(-6.2,1.06,-3.6),Vector3(3.2,.12,1.1),"wood")
	for x in [-7.65,-4.75]:
		for z in [-4.05,-3.15]: _box(Vector3(x,.5,z),Vector3(.1,1.0,.1),"steel")
	_box(Vector3(-6.2,.35,-3.6),Vector3(3.0,.08,.95),"steel")
	for x in [-7.0,-6.2,-5.4]:
		_box(Vector3(x,1.5,-3.85),Vector3(.62,.44,.06),"dark")
		_box(Vector3(x,1.5,-3.81),Vector3(.54,.36,.02),"screen")
		_box(Vector3(x,1.2,-3.85),Vector3(.10,.14,.10),"steel")
	_box(Vector3(-4.95,1.2,-3.5),Vector3(.55,.26,.4),"camo")
	_cylinder(Vector3(-4.8,1.5,-3.5),.03,.5,"steel",Vector3(0,0,-.2))
	_box(Vector3(-6.7,1.145,-3.2),Vector3(.5,.02,.36),"paper",null,Vector3(0,.2,0))
	_cylinder(Vector3(-5.6,1.16,-3.25),.13,.12,"ceramic")
	_solid("GuardChair",Vector3(-6.1,.45,-2.4),Vector3(.6,.9,.6))
	_box(Vector3(-6.1,.45,-2.4),Vector3(.55,.08,.55),"steel")
	_box(Vector3(-6.1,.85,-2.15),Vector3(.55,.7,.07),"steel")
	_cylinder(Vector3(-6.1,.22,-2.4),.06,.44,"steel")

func _armory_cage() -> void:
	# Jaula de armas: postes e tela, racks vazios e caixas de munição fechadas.
	for x in [5.4,6.9,8.4,9.4]:
		for z in [-5.6,-1.4]: _box(Vector3(x,1.35,z),Vector3(.08,2.7,.08),"steel")
	for z in [-5.6,-1.4]:
		for y in [.25,1.35,2.45]: _box(Vector3(7.4,y,z),Vector3(4.1,.05,.05),"steel")
		for x in [5.9,6.4,6.9,7.4,7.9,8.4,8.9]: _box(Vector3(x,1.35,z),Vector3(.02,2.6,.02),"wire")
	_solid("CageFront",Vector3(7.4,1.3,-1.4),Vector3(4.1,2.6,.14))
	_solid("CageBack",Vector3(7.4,1.3,-5.6),Vector3(4.1,2.6,.14))
	for x in [6.2,7.4,8.6]:
		_box(Vector3(x,1.4,-5.42),Vector3(.9,.06,.18),"steel")
		_box(Vector3(x,.9,-5.42),Vector3(.9,.06,.18),"steel")
		for slot in 4: _box(Vector3(x-.32+float(slot)*.21,1.15,-5.36),Vector3(.05,.5,.05),"dark")
	_solid("AmmoStacks",Vector3(9.0,.42,-3.5),Vector3(1.4,.84,2.8))
	for z in [-4.5,-3.5,-2.5]:
		_box(Vector3(9.0,.22,z),Vector3(1.3,.42,.8),"camo")
		_box(Vector3(9.0,.62,z),Vector3(1.2,.36,.72),"camo",null,Vector3(0,.06,0))
		_box(Vector3(8.36,.42,z),Vector3(.04,.16,.5),"hazard")

func _barricades() -> void:
	# Sacos de areia em degraus formam duas chicanes de cobertura diante da porta.
	for spec in [[Vector3(-3.6,0,-1.0),4.6],[Vector3(3.6,0,-2.8),4.6],[Vector3(-3.4,0,2.4),3.6],[Vector3(3.4,0,1.0),3.6]]:
		var origin: Vector3 = spec[0]
		var length: float = spec[1]
		_solid("Sandbags",origin+Vector3(0,.5,0),Vector3(length,1.0,.9))
		for row in 3:
			var count := int(length/.62)-row
			for index in count:
				var x := -length*.5+.4+float(index)*.62+float(row)*.31
				_box(origin+Vector3(x,.16+float(row)*.28,0),Vector3(.58,.26,.56),"sand",null,Vector3(0,.05*float((index+row)%3-1),0))

func _supplies() -> void:
	_solid("RationCrates",Vector3(-8.6,.55,3.0),Vector3(1.6,1.1,2.0))
	for z in [2.4,3.6]:
		_box(Vector3(-8.6,.32,z),Vector3(1.5,.62,1.0),"wood")
		_box(Vector3(-8.5,.85,z),Vector3(1.2,.44,.9),"wood",null,Vector3(0,.15,0))
	_box(Vector3(-8.05,.32,3.0),Vector3(.04,.2,.6),"hazard")
	_solid("FuelDrums",Vector3(8.2,.5,3.6),Vector3(1.9,1.0,.9))
	for x in [7.6,8.4,9.0]: _cylinder(Vector3(x,.5,3.6),.6,1.0,"camo")
	for x in [7.6,8.4,9.0]:
		for y in [.2,.8]: _cylinder(Vector3(x,y,3.6),.63,.06,"steel")

func _services() -> void:
	# Calhas de cabos e dutos no teto; três luminárias frias e uma câmera de vigilância.
	for x in [-1.2,1.2]:
		_cylinder(Vector3(x,3.28,0),.22,13.6,"steel",Vector3(PI*.5,0,0),_roof)
	_box(Vector3(-7.5,3.3,0),Vector3(.5,.1,13.6),"dark",_roof)
	for spec in [[Vector3(-4.0,3.2,-2.5),Color("dfe8e4"),8.0,1.4],[Vector3(4.0,3.2,-2.5),Color("dfe8e4"),8.0,1.4],
		[Vector3(0,3.2,3.6),Color("e6dfc8"),8.0,1.1],[Vector3(0,2.9,-6.0),Color("d47862"),5.5,.9]]:
		var point: Vector3 = spec[0]
		_box(point+Vector3(0,.06,0),Vector3(.24,.09,1.4),"steel",_roof)
		_box(point,Vector3(.18,.06,1.28),"lamp",_roof)
		var light := OmniLight3D.new()
		light.position = point-Vector3.UP*.15
		light.light_color = spec[1]
		light.light_energy = spec[3]
		light.omni_range = spec[2]
		light.shadow_enabled = false
		add_child(light)
		lights.append(light)
	_box(Vector3(9.5,3.0,5.5),Vector3(.3,.3,.55),"dark",_roof,Vector3(.4,-.6,0))
	_cylinder(Vector3(9.3,3.4,5.5),.05,.4,"steel",Vector3.ZERO,_roof)

func _exit_door() -> void:
	# Porta circular do cofre: o retorno ao túnel. Fica na parede sul, sob o corte.
	_solid("ExitVault",Vector3(0,1.4,6.8),Vector3(2.4,2.8,.4),true)
	_cylinder(Vector3(0,1.5,6.72),2.0,.3,"steel",Vector3(PI*.5,0,0))
	_cylinder(Vector3(0,1.5,6.56),1.5,.1,"frame",Vector3(PI*.5,0,0))
	for spoke in 3: _box(Vector3(0,1.5,6.48),Vector3(1.0,.09,.06),"steel",Vector3(0,0,PI*float(spoke)/3.0))
	for index in 14:
		var angle := TAU*float(index)/14.0
		_box(Vector3(cos(angle)*1.08,1.5+sin(angle)*1.08,6.5),Vector3(.26,.2,.1),"hazard" if index%2 else "dark",Vector3(0,0,angle))
	_box(Vector3(0,3.4,6.3),Vector3(2.6,.1,1.0),"steel",_roof)

func _operations_hall() -> void:
	# Sala de operações: barreiras e caixas de altura de peito formam abrigo real; a
	# mesa de comando, a área do saque e as duas portas de reforço ficam ao fundo.
	for cover in HALL_COVERS:
		var at := Vector3(cover.pos.x,0,cover.pos.y)
		var size := Vector3(cover.size.x,COVER_HEIGHT,cover.size.y)
		_solid(cover.id,at+Vector3(0,size.y*.5,0),size)
		if cover.kind == "barrier":
			_box(at+Vector3(0,size.y*.5,0),size,"concrete")
			_box(at+Vector3(0,.12,0),Vector3(size.x+.1,.24,size.z+.14),"wall_band")
			for index in 4: _box(at+Vector3(-size.x*.5+.45+float(index)*(size.x-.9)/3.0,size.y*.55,size.z*.5+.01),Vector3(.05,size.y*.8,.02),"seam")
			_box(at+Vector3(0,size.y*.5,size.z*.5+.012),Vector3(size.x*.96,.16,.02),"hazard")
		else:
			for tier in 2:
				_box(at+Vector3(-.02*float(tier),.45+float(tier)*.9,0),Vector3(size.x-.1*float(tier),.88,size.z-.05),"wood",null,Vector3(0,.04*float(tier),0))
				_box(at+Vector3(0,.45+float(tier)*.9,size.z*.5),Vector3(size.x-.06,.06,.03),"wood_dark")
			_box(at+Vector3(size.x*.3,1.6,size.z*.35),Vector3(.5,.02,.36),"paper",null,Vector3(0,.3,0))
	# Faixas de piso e setas de avanço.
	for x in [-8.6,8.6]: _box(Vector3(x,.012,-16),Vector3(.12,.012,17),"paint")
	for z in [-9.5,-15.5,-21.5]: _box(Vector3(0,.012,z),Vector3(.5,.012,.9),"hazard")
	# Mesa de comando com monitores acesos.
	_solid("CommandDesk",COMMAND_DESK+Vector3(0,.55,0),Vector3(7.0,1.1,.9))
	_box(COMMAND_DESK+Vector3(0,1.02,0),Vector3(7.0,.12,.9),"wood")
	_box(COMMAND_DESK+Vector3(0,.45,0),Vector3(6.8,.9,.7),"frame")
	for x in [-2.6,-1.3,0.0,1.3,2.6]:
		_box(COMMAND_DESK+Vector3(x,1.55,-.2),Vector3(.9,.55,.06),"dark")
		_box(COMMAND_DESK+Vector3(x,1.55,-.16),Vector3(.8,.46,.02),"screen")
		_box(COMMAND_DESK+Vector3(x,1.15,-.2),Vector3(.12,.16,.1),"steel")
	# Área do saque: armário de aço, caixas e sacos junto à parede leste.
	var stash := Vector3(8.4,0,-23.0)
	_solid("StashLocker",stash+Vector3(0,1.0,-1.5),Vector3(3.2,2.0,.6))
	_box(stash+Vector3(0,1.0,-1.5),Vector3(3.2,2.0,.6),"frame")
	for x in [-1.05,0.0,1.05]: _box(stash+Vector3(x,1.0,-1.19),Vector3(.9,1.8,.03),"steel")
	_solid("StashCrates",stash+Vector3(1.2,.5,.6),Vector3(1.4,1.0,1.4))
	_box(stash+Vector3(1.2,.5,.6),Vector3(1.4,1.0,1.4),"camo")
	_box(stash+Vector3(1.2,.5,1.32),Vector3(1.3,.12,.03),"hazard")
	_box(Vector3(8.4,.012,-23.8),Vector3(3.4,.012,2.2),"hazard")
	# Portas de reforço na parede do fundo, cada uma com duas folhas nodais.
	for door in REINFORCEMENT_DOORS:
		_box(Vector3(door.x,1.5,-24.94),Vector3(2.6,3.0,.06),"dark")
		_box(Vector3(door.x,3.05,-24.9),Vector3(2.8,.16,.12),"frame")
		for side in [-1.0,1.0]:
			var leaf := Node3D.new()
			leaf.name = "ReinforcementLeaf"
			add_child(leaf)
			reinforcement_leaves.append(leaf)
			_node_box(leaf,Vector3(door.x+side*.65,1.45,-24.86),Vector3(1.28,2.9,.1),"steel")
			_node_box(leaf,Vector3(door.x+side*.65,.35,-24.8),Vector3(1.2,.3,.03),"hazard")
	_service_lift()
	# Câmeras de vigilância (cabeças giratórias) e giroflex do alarme.
	for post in CAMERA_POSTS:
		var head := Node3D.new()
		head.name = "SecurityCamera"
		head.position = post
		add_child(head)
		_node_box(head,Vector3.ZERO,Vector3(.3,.28,.6),"dark")
		_node_cylinder(head,Vector3(0,0,.32),.16,.1,"steel",Vector3(PI*.5,0,0),10)
		_node_cylinder(head,Vector3(0,.2,-.05),.05,.24,"steel")
		camera_heads.append(head)
	for post in BEACON_POSTS:
		_box(post,Vector3(.36,.4,.2),"dark")
		_box(post+Vector3(0,0,.13),Vector3(.24,.28,.06),"red_lamp")
		var beacon := OmniLight3D.new()
		beacon.position = post+Vector3(0,-.3,1.2)
		beacon.light_color = Color("e0392b")
		beacon.light_energy = 2.6
		beacon.omni_range = 9.0
		beacon.shadow_enabled = false
		beacon.visible = false
		add_child(beacon)
		beacons.append(beacon)
	# Iluminação fria da sala.
	for spec in [[Vector3(-4.5,3.2,-12.0),Color("dfe8e4"),9.0,1.3],[Vector3(4.5,3.2,-12.0),Color("dfe8e4"),9.0,1.3],
		[Vector3(0,3.2,-18.5),Color("e6dfc8"),10.0,1.3]]:
		var point: Vector3 = spec[0]
		_box(point+Vector3(0,.06,0),Vector3(.24,.09,1.4),"steel",_roof)
		_box(point,Vector3(.18,.06,1.28),"lamp",_roof)
		var light := OmniLight3D.new()
		light.position = point-Vector3.UP*.15
		light.light_color = spec[1]
		light.light_energy = spec[3]
		light.omni_range = spec[2]
		light.shadow_enabled = false
		add_child(light)
		lights.append(light)

func _service_lift() -> void:
	# Elevador de carga que sobe pela montanha até a saída secreta no esqui.
	var at := Vector3(-8.6,0,-24.72)
	_solid("ServiceLift",at+Vector3(0,1.5,-.05),Vector3(2.3,3.0,.5))
	_box(at+Vector3(0,1.6,0),Vector3(2.5,3.2,.2),"frame")
	_box(at+Vector3(0,3.3,.05),Vector3(2.7,.24,.3),"steel")
	for side in [-1.0,1.0]:
		var leaf := Node3D.new()
		leaf.name = "LiftLeaf"
		add_child(leaf)
		lift_leaves.append(leaf)
		_node_box(leaf,at+Vector3(side*.55,1.45,.16),Vector3(1.05,2.8,.08),"steel")
		for bar in 4: _node_box(leaf,at+Vector3(side*.55,.4+float(bar)*.65,.22),Vector3(1.0,.05,.04),"dark")
	# Seta de subida em amarelo sobre o vão e faixa de perigo no piso.
	for side in [-1.0,1.0]: _box(at+Vector3(side*.3,3.0,.22),Vector3(.7,.09,.03),"hazard",Vector3(0,0,-side*.7))
	_box(at+Vector3(0,2.72,.22),Vector3(.09,.5,.03),"hazard")
	_box(Vector3(-8.6,.012,-23.4),Vector3(2.3,.012,1.2),"hazard")
	_box(Vector3(-8.6,.014,-23.4),Vector3(2.1,.012,1.0),"floor")
	_cylinder(at+Vector3(1.5,1.6,.2),.18,.06,"screen",Vector3(PI*.5,0,0))

func set_lift_open(open: bool,animate := true) -> void:
	for index in lift_leaves.size():
		var target := (-.9 if index == 0 else .9) if open else 0.0
		if animate: create_tween().tween_property(lift_leaves[index],"position:x",target,.9)
		else: lift_leaves[index].position.x = target

func _node_box(parent: Node3D,at: Vector3,size: Vector3,key: String,angles := Vector3.ZERO) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var display := MeshInstance3D.new()
	display.mesh = mesh
	display.material_override = _material(key)
	display.position = at
	display.rotation = angles
	parent.add_child(display)

func _node_cylinder(parent: Node3D,at: Vector3,diameter: float,height: float,key: String,angles := Vector3.ZERO,segments := 12) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = diameter*.5
	mesh.bottom_radius = diameter*.5
	mesh.height = height
	mesh.radial_segments = segments
	var display := MeshInstance3D.new()
	display.mesh = mesh
	display.material_override = _material(key)
	display.position = at
	display.rotation = angles
	parent.add_child(display)

func _material(key: String) -> Material:
	if _materials.has(key): return _materials[key]
	var colors := {"floor":"5a5f55","concrete":"7c7e74","wall_band":"4d564d","seam":"51574e","steel":"5f6862",
		"dark":"242a28","frame":"353d39","hazard":"c79f3a","paint":"a8a48a","wood":"6f5c43","paper":"c7bd91",
		"contour":"6d5f45","blue":"4a7080","red":"a8433a","camo":"4f5c45","sand":"a39469","wire":"7a827c",
		"screen":"7fbf9a","lamp":"e7dcc3","red_lamp":"c9483a","ceramic":"a2a68d","wood_dark":"4f4130"}
	var result := StandardMaterial3D.new()
	result.albedo_color = Color(colors[key])
	result.roughness = .9
	if key in ["steel","frame","wire"]:
		result.metallic = .5
		result.roughness = .5
	if key in ["lamp","screen","red_lamp"]:
		result.emission_enabled = true
		result.emission = result.albedo_color
		result.emission_energy_multiplier = .8 if key != "lamp" else .4
	_materials[key] = result
	return result

## O quarto argumento aceita o grupo (teto/parede frontal) ou já os ângulos.
func _box(at: Vector3,size: Vector3,key: String,extra: Variant = null,angles := Vector3.ZERO) -> void:
	var group: Node3D = null
	if extra is Vector3: angles = extra
	elif extra is Node3D: group = extra
	var mesh := BoxMesh.new()
	mesh.size = size
	_append(mesh,Transform3D(Basis.from_euler(angles),at),key,group)

func _cylinder(at: Vector3,diameter: float,height: float,key: String,angles := Vector3.ZERO,group: Node3D = null) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = diameter*.5
	mesh.bottom_radius = diameter*.5
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 1
	_append(mesh,Transform3D(Basis.from_euler(angles),at),key,group if group != null else _fixed)

func _append(mesh: Mesh,transform: Transform3D,key: String,group: Node3D) -> void:
	if group == null: group = _fixed
	var batch_key := str(group.get_instance_id())+":"+key
	if not _batches.has(batch_key):
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[batch_key] = {"builder":builder,"group":group,"material":_material(key)}
	_batches[batch_key].builder.append_from(mesh,0,transform)

func _solid(id: String,at: Vector3,size: Vector3,obstacle := true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = id+"Solid"
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("interior_solid_id","mountain_fort/"+id)
	body.set_meta("bounds",AABB(at-size*.5,size))
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	if obstacle: solids.append(body)
	return body

func _commit() -> void:
	for batch in _batches.values():
		var display := MeshInstance3D.new()
		display.name = "StaticDetailBatch"
		display.mesh = batch.builder.commit()
		display.material_override = batch.material
		batch.group.add_child(display)
	_batches.clear()

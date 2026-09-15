extends "res://world/harbor/events/BankClerkModel.gd"
## Articulated hands carry actual props throughout the street encounter.
var gesture := "idle"
var carrying_bag := false
var bag: Node3D
var phone: Node3D

func _ready() -> void:
	super._ready()
	bag = Node3D.new()
	bag.name = "LeatherSatchel"
	forearms[0].add_child(bag)
	bag.position = Vector3(0,-.39,.02)
	DETAIL.piece(bag,Vector3(.29,.23,.11),Vector3.ZERO,Color("8c593c"),true)
	DETAIL.piece(bag,Vector3(.27,.085,.12),Vector3(0,.07,.01),Color("704530"),true)
	DETAIL.piece(bag,Vector3(.032,.045,.014),Vector3(0,.04,.067),Color("c4ac75"))
	for side in [-1,1]:
		DETAIL.piece(bag,Vector3(.022,.12,.025),Vector3(side*.085,.16,0),Color("5e3929"))
	DETAIL.piece(bag,Vector3(.18,.025,.025),Vector3(0,.22,0),Color("5e3929"))
	phone = Node3D.new()
	phone.name = "Phone"
	forearms[1].add_child(phone)
	phone.position = Vector3(0,-.285,.045)
	DETAIL.piece(phone,Vector3(.065,.13,.018),Vector3.ZERO,Color("262b32"))
	DETAIL.piece(phone,Vector3(.053,.105,.004),Vector3(0,0,.012),Color("81a9b6"))
	phone.hide()

func _process(delta: float) -> void:
	super._process(delta)
	if not is_instance_valid(bag): return
	bag.visible = carrying_bag
	phone.visible = gesture == "call"
	var left := Vector3(0,0,-.045)
	var right := Vector3(0,0,.045)
	var elbow := -.10
	match gesture:
		"threaten", "handover":
			right = Vector3(-.85 + sin(clock*2.5)*.10,0,-.18)
			elbow = -.6
		"hands_up":
			left = Vector3(-1.0,0,-.55)
			right = Vector3(-1.0,0,.55)
			elbow = -1.35
		"call":
			right = Vector3(-.5,0,.25)
			elbow = -2.25
		"arrested":
			left = Vector3(.30,0,.08)
			right = Vector3(.30,0,-.08)
			elbow = -.6
	if not walking:
		limbs[1].rotation = limbs[1].rotation.lerp(left,minf(1,delta*6))
		limbs[3].rotation = limbs[3].rotation.lerp(right,minf(1,delta*6))
	forearms[1].rotation.x = elbow
	if gesture in ["hands_up", "arrested"]: forearms[0].rotation.x = elbow

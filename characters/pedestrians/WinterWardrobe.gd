extends RefCounted
const PART = preload("res://characters/pedestrians/CitizenDetails.gd")
const APPEARANCE = preload("res://characters/pedestrians/CitizenAppearance.gd")
const SKINS := [Color("d2a180"),Color("936448"),Color("edc1a2"),Color("b88160")]
const HAIRS := [Color("302824"),Color("695044"),Color("9c784a"),Color("99948a")]

static func light_viewport(viewport: SubViewport) -> void:
	var lighting := WorldEnvironment.new()
	lighting.name="PersonAmbientLight"
	lighting.environment=Environment.new()
	lighting.environment.background_mode=Environment.BG_COLOR
	lighting.environment.background_color=Color(0,0,0,0)
	lighting.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	lighting.environment.ambient_light_color=Color("becbdc")
	lighting.environment.ambient_light_energy=.65
	viewport.add_child(lighting)

static func build(model: Node3D, winter := true) -> void:
	var variant: int = posmod(model.appearance_variant, 12)
	var female: bool = model.appearance_female
	var skin: Color = SKINS[variant%4]
	var hair: Color = HAIRS[(variant/3)%4]
	var coat: Color = model.coat_color
	var boots := Color("2c3036")
	var width := [.98,1.10,.92,1.04][variant%4] as float
	model.scale = Vector3(width,[1.0,.96,1.05,.93][variant%4],1)
	# As peças de roupa sobrepõem as articulações para não separar os membros.
	for side in [-1,1]:
		var leg := Node3D.new()
		leg.position = Vector3(side*.115,.78,0)
		model.add_child(leg)
		model.limbs.append(leg)
		PART.piece(leg,Vector3(.185,.64,.21),Vector3(0,-.31,0),Color("344353"))
		PART.piece(leg,Vector3(.195,.18,.29),Vector3(0,-.69,.035),boots)
		var arm := Node3D.new()
		arm.position = Vector3(side*.255,1.35,0)
		model.add_child(arm)
		model.limbs.append(arm)
		PART.piece(arm,Vector3(.175,.46,.21),Vector3(0,-.20,0),coat)
		PART.piece(arm,Vector3(.125,.13,.145),Vector3(0,-.47,.018),boots if winter else skin)
		PART.piece(arm,Vector3(.18,.035,.215),Vector3(0,-.39,0),coat.darkened(.25))
	var torso := MeshInstance3D.new()
	torso.name = "Coat"
	torso.mesh = APPEARANCE.tailored_body(female,false)
	torso.scale = Vector3(1.27,1.43,1.18)
	torso.position.y = 1.09
	torso.material_override = StandardMaterial3D.new()
	torso.material_override.albedo_color = coat
	model.add_child(torso)
	PART.piece(model,Vector3(.39,.08,.31),Vector3(0,.79,0),boots)
	PART.piece(model,Vector3(.13,.20,.13),Vector3(0,1.48,0),skin,true).name="Neck"
	var head := Node3D.new()
	head.name="Head"
	head.position.y=1.62
	head.rotation.y=PI # Cabelos compartilhados têm frente -Z; moradores usam +Z.
	model.add_child(head)
	PART.piece(head,Vector3(.30,.32,.285),Vector3.ZERO,skin,true)
	for side in [-1,1]:
		PART.piece(head,Vector3(.04,.075,.045),Vector3(side*.15,-.02,0),skin,true)
		PART.piece(head,Vector3(.029,.017,.02),Vector3(side*.06,.01,-.142),Color("292b2e"))
		PART.piece(head,Vector3(.045,.013,.022),Vector3(side*.06,.041,-.14),hair)
	PART.piece(head,Vector3(.04,.052,.048),Vector3(0,-.025,-.15),skin,true)
	PART.piece(head,Vector3(.052,.011,.017),Vector3(0,-.079,-.135),skin.darkened(.35))
	var style: int = [2,3,6,7][variant%4] if female else [0,1,5,7][variant%4]
	var hat := variant%3
	APPEARANCE.build_hair(head,style,hair,winter and hat!=2 or model.role=="bus_driver")
	if winter and hat==0:
		PART.piece(head,Vector3(.34,.17,.32),Vector3(0,.13,.015),coat.darkened(.3),true).name="WoolHat"
		PART.piece(head,Vector3(.34,.04,.325),Vector3(0,.08,.015),coat.lightened(.15))
	elif winter and hat==1:
		for side in [-1,1]: PART.piece(head,Vector3(.075,.28,.24),Vector3(side*.17,.015,.04),coat.lightened(.1),true)
		PART.piece(head,Vector3(.37,.14,.32),Vector3(0,.17,.035),coat.lightened(.1),true).name="Hood"
		PART.piece(head,Vector3(.36,.27,.10),Vector3(0,.025,.15),coat)
	elif winter:
		for side in [-1,1]: PART.piece(head,Vector3(.072,.09,.09),Vector3(side*.165,.015,0),Color("d0c6b0"),true)
	if winter:
		var scarf: Color = [Color("b4734c"),Color("a6b7ad"),Color("805968"),Color("bba568")][variant%4]
		PART.piece(model,Vector3(.32,.09,.29),Vector3(0,1.42,.025),scarf)
		PART.piece(model,Vector3(.085,.29,.04),Vector3(.10,1.26,.19),scarf)
		if variant%2==0:
			for y in [1.0,1.15,1.29]: PART.piece(model,Vector3(.39,.018,.025),Vector3(0,y,.185),coat.darkened(.18))
		model.breath=PART.piece(model,Vector3(.12,.08,.18),Vector3(0,1.53,.38),Color(.8,.9,1,.14),true)
		model.breath.material_override.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	PART.piece(model,Vector3(.018,.55,.024),Vector3(0,1.12,.19),Color("bdc4c4"))
	for side in [-1,1]: PART.piece(model,Vector3(.13,.12,.025),Vector3(side*.12,.96,.19),coat.darkened(.2))
	if model.role=="bus_driver":
		PART.piece(model,Vector3(.065,.09,.022),Vector3(.10,1.26,.205),Color("efeee1")).name="DriverID"
		PART.piece(model,Vector3(.032,.17,.025),Vector3(0,1.29,.215),Color("26384c"))
		for side in [-1,1]: PART.piece(model,Vector3(.10,.025,.08),Vector3(side*.19,1.39,0),Color("c7b77e"))
		if not winter:
			PART.piece(head,Vector3(.33,.11,.30),Vector3(0,.14,0),Color("283d59"))
			PART.piece(head,Vector3(.24,.022,.13),Vector3(0,.09,-.17),Color("283d59"))
	elif model.role=="truck_driver":
		for side in [-1,1]: PART.piece(model,Vector3(.045,.45,.03),Vector3(side*.14,1.14,.20),Color("e1d79b"))
		PART.piece(model,Vector3(.41,.036,.03),Vector3(0,1.01,.20),Color("e1d79b")).name="ReflectiveBand"
	elif model.role in ["logger","ranger"]:
		PART.piece(model,Vector3(.085,.14,.06),Vector3(-.16,1.30,.20),boots)
		PART.piece(model,Vector3(.013,.13,.013),Vector3(-.18,1.42,.20),boots)
	elif variant%2==1:
		PART.piece(model,Vector3(.32,.37,.14),Vector3(0,1.10,-.24),coat.darkened(.25)).name="Backpack"
	model.set_meta("winter_outfit",winter)
	model.set_meta("wardrobe_role",model.role)
	model.set_meta("headwear_variant",hat)

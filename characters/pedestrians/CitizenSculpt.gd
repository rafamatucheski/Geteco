extends RefCounted
const GEO := preload("res://characters/pedestrians/CitizenGeometry.gd")

static func build(actor: Node) -> void:
	var identity := int(actor.get_meta("appearance_variant",0))
	var female := bool(actor.get_meta("appearance_female",false))
	var skin: Color = actor.skin_color
	var cloth: Color = actor.shirt_color
	if int(actor.archetype) in [1,2,6,7]:
		cloth = Color.from_hsv(cloth.h,cloth.s*.65,cloth.v*.85)
	var head: Node3D = actor.head_node
	# Replace the spherical base and block beard; retain authored hats and props.
	for part in head.get_children():
		if part is MeshInstance3D and (part.name == "BaseHair" or part.position.is_zero_approx() or part.position.is_equal_approx(Vector3(0,-.09,-.08))):
			part.free()
		elif part is MeshInstance3D and part.position.y > .07:
			part.scale.x *= .84
			part.scale.z *= .84
	var face := GEO.new()
	var jaw := .080 if female else .094
	jaw *= .94 + (identity % 3)*.04
	var cheek := .124+(identity%5)*.004
	var nose_width := .017+(identity%3)*.003
	var chin := .044
	if actor.body_type==2:
		jaw+=.023
		chin=.064
		cheek=maxf(cheek,.139)
	elif actor.body_type==1:
		jaw*=.85
		chin=.036
	elif identity%3==1:
		jaw+=.012
		chin=.056
	face.loft([Vector4(-.155,chin,.052,-.023),Vector4(-.13,jaw*.83,.069,-.018),Vector4(-.075,jaw,.091,-.004),Vector4(.008,cheek,.108,.008),Vector4(.075,cheek*.98,.108,.015),Vector4(.135,.109,.093,.022),Vector4(.178,.052,.055,.023),Vector4(.184,.002,.002,.023)],skin)
	# Actual nose bridge, restrained eyelids and inset eyes rather than stickers.
	face.loft([Vector4(-.047,nose_width,.017,-.121),Vector4(-.03,nose_width,.026+(identity%3)*.003,-.126),Vector4(.04,.012,.009,-.102)],skin,8)
	var lip := skin.darkened(.31).lerp(Color("915956"),.18)
	face.oval(Vector3(.059,.009,.013),Vector3(0,-.082,-.101),lip)
	face.oval(Vector3(.051,.010,.010),Vector3(0,-.097,-.094),skin.darkened(.12))
	for side in [-1,1]:
		var eye_x: float = side*(.050+(identity%3)*.002)
		face.oval(Vector3(.050,.022,.012),Vector3(eye_x,.016,-.100),skin.darkened(.35))
		face.oval(Vector3(.037,.015,.011),Vector3(eye_x,.015,-.107),Color("c8bcaa"))
		face.oval(Vector3(.016,.015,.007),Vector3(eye_x,.015,-.113),Color("34332d"))
		face.oval(Vector3(.048,.009,.014),Vector3(eye_x,.039,-.101),actor.hair_color.darkened(.25),Vector3(0,0,side*.10))
		face.oval(Vector3(.031,.065,.037),Vector3(side*(cheek+.003),-.007,.012),skin)
		face.oval(Vector3(.010,.037,.020),Vector3(side*(cheek+.014),-.008,-.002),skin.darkened(.2))
	face.finish(head,"CitizenFace",.86)
	_build_beard(actor,jaw,chin)
	var neck := GEO.new()
	neck.loft([Vector4(-.29,.068,.064,.01),Vector4(-.21,.065,.061,.01),Vector4(-.12,.053,.054,.01)],skin,12)
	neck.finish(head,"Neck")
	_build_hair(actor)
	# Tailored silhouette with a continuous shoulder into the sleeve.
	var shell: MeshInstance3D = actor.torso_node.get_node("BodyShell")
	for part in actor.torso_node.get_children():
		if part is MeshInstance3D and part.mesh is BoxMesh:
			if part.mesh.size.is_equal_approx(Vector3(.12,.26,.03)) or part.mesh.size.is_equal_approx(Vector3(.04,.22,.035)): part.free()
	var torso := GEO.new()
	var waist := .145 if female else .158
	torso.loft([Vector4(-.24,.152,.123,0),Vector4(-.19,.16,.133,0),Vector4(-.03,waist,.132,0),Vector4(.13,.184,.139,0),Vector4(.185,.19,.122,.002),Vector4(.238,.083,.075,.007)],cloth,16,0,TAU,.025)
	torso.loft([Vector4(.205,.077,.074,.007),Vector4(.247,.075,.071,.007)],cloth.darkened(.23),12)
	if actor.has_tie:
		torso.panel([Vector3(-.042,.20,-.099),Vector3(.042,.20,-.099),Vector3(.04,.125,-.146),Vector3(-.04,.125,-.146)],Color("d9d5c8"))
		torso.panel([Vector3(-.04,.125,-.146),Vector3(.04,.125,-.146),Vector3(.037,-.14,-.142),Vector3(-.037,-.14,-.142)],Color("d9d5c8"))
		torso.panel([Vector3(-.012,.12,-.151),Vector3(.012,.12,-.151),Vector3(.015,-.084,-.15),Vector3(0,-.108,-.15),Vector3(-.015,-.084,-.15)],Color("6d3532"))
		for side in [-1,1]:
			torso.panel([Vector3(side*.08,.20,-.101),Vector3(side*.12,.09,-.116),Vector3(side*.037,-.03,-.149),Vector3(side*.026,.125,-.151)],cloth.lightened(.12))
	torso.box(Vector3(.017,.30,.012),Vector3(0,-.015,-.135),cloth.darkened(.18))
	if identity%4 == 0 and not actor.has_tie:
		torso.box(Vector3(.072,.30,.012),Vector3(0,.012,-.138),cloth.darkened(.43))
		for side in [-1,1]: torso.box(Vector3(.013,.31,.014),Vector3(side*.044,.012,-.143),cloth.lightened(.07))
	elif identity%4 == 3 and not actor.has_tie:
		torso.loft([Vector4(-.29,.164,.128,0),Vector4(-.20,.16,.13,0)],cloth)
		torso.box(Vector3(.12,.024,.015),Vector3(0,.13,-.137),cloth.darkened(.25))
	for i in 4: torso.oval(Vector3(.010,.010,.008),Vector3(0,.10-i*.072,-.145),Color("aea99c"))
	if identity%3 != 1:
		torso.box(Vector3(.065,.065,.010),Vector3(-.094,.056,-.133),cloth.darkened(.08))
		torso.box(Vector3(.068,.009,.012),Vector3(-.094,.091,-.14),cloth.lightened(.09))
	for side in [-1,1]:
		torso.oval(Vector3(.080,.074,.022),Vector3(side*.064,.197,-.078),cloth.lightened(.10),Vector3(0,0,side*-.42))
	var garment := torso.finish(actor.torso_node,"TailoredCloth")
	shell.mesh=garment.mesh
	shell.material_override=garment.material_override
	garment.free()
	var pelvis := GEO.new()
	pelvis.loft([Vector4(-.31,.125,.105,0),Vector4(-.23,.158,.121,0),Vector4(-.205,.156,.12,0)],actor.pants_color)
	pelvis.loft([Vector4(-.228,.16,.123,0),Vector4(-.202,.158,.123,0)],Color("3b3430"))
	pelvis.box(Vector3(.039,.027,.013),Vector3(0,-.214,-.127),Color("9b9380"))
	pelvis.finish(actor.torso_node,"Waist")
	preload("res://characters/pedestrians/CitizenMorphology.gd").deform_torso(actor.torso_node,int(actor.body_type))
	for side in 2:
		var upper: Node3D = actor.left_upper_arm if side == 0 else actor.right_upper_arm
		var lower: Node3D = actor.left_lower_arm if side == 0 else actor.right_lower_arm
		# Bring the shoulder socket into the body surface, including slim builds.
		upper.position.x = (-1 if side == 0 else 1)*(.174*actor.torso_node.scale.x+.022*upper.scale.x)
		var sleeve := GEO.new()
		sleeve.loft([Vector4(-.224,.046,.047,0),Vector4(-.19,.052,.052,0),Vector4(-.07,.059,.060,0),Vector4(.009,.057,.059,0),Vector4(.025,.029,.035,0)],cloth,12)
		sleeve.oval(Vector3(.113,.074,.118),Vector3(0,.002,0),cloth)
		for child in upper.get_children():
			if child is MeshInstance3D: child.free()
		sleeve.finish(upper,"Sleeve")
		# Preserve carried objects, only replacing the original limb/hand/cap.
		var arm_color: Color = lower.get_child(0).material_override.albedo_color
		for i in 3: lower.get_child(0).free()
		for prop in lower.get_children():
			if prop is MeshInstance3D and prop.mesh is CylinderMesh:
				if side==0 and actor.has_coffee_cup and prop.mesh.height<.1: prop.name="HeldCoffee"
				if side==1 and actor.has_walking_stick and prop.mesh.height>.5: prop.name="WalkingStick"
		var forearm := GEO.new()
		forearm.loft([Vector4(-.184,.031,.034,0),Vector4(-.15,.039,.040,0),Vector4(-.05,.045,.046,0),Vector4(.012,.043,.044,0)],arm_color,12)
		if arm_color != skin:
			forearm.loft([Vector4(-.181,.033,.036,0),Vector4(-.16,.037,.039,0)],cloth.darkened(.18),12)
			forearm.oval(Vector3(.009,.009,.006),Vector3(0,-.169,-.04),Color("959080"))
		forearm.oval(Vector3(.058,.080,.043),Vector3(0,-.215,-.005),skin)
		forearm.oval(Vector3(.024,.045,.029),Vector3((1 if side==0 else -1)*.026,-.205,-.008),skin,Vector3(0,0,(1 if side==0 else -1)*.3))
		forearm.finish(lower,"Palm")
		var thigh: Node3D = actor.left_upper_leg if side==0 else actor.right_upper_leg
		var shin: Node3D = actor.left_lower_leg if side==0 else actor.right_lower_leg
		for child in thigh.get_children():
			if child is MeshInstance3D: child.free()
		var leg := GEO.new()
		var thigh_radius := .081 if actor.body_type==2 else .064 if actor.body_type==1 else .071
		leg.loft([Vector4(-.289,.052,.057,0),Vector4(-.20,thigh_radius*.85,.064,0),Vector4(-.04,thigh_radius,.073,0),Vector4(.025,thigh_radius*.94,.068,0)],actor.pants_color,12)
		leg.finish(thigh,"TrouserThigh").scale.y = .32/.28
		shin.position.y = -.32
		var shin_color: Color = shin.get_child(0).material_override.albedo_color
		for child in shin.get_children(): child.free()
		var calf := GEO.new()
		calf.loft([Vector4(-.26,.039,.042,0),Vector4(-.19,.042,.048,.002),Vector4(-.09,.054,.057,.004),Vector4(.013,.055,.057,0)],shin_color,12)
		calf.finish(shin,"TrouserCalf").scale.y = .29/.26
		var foot := Node3D.new()
		foot.name="GaitFoot"
		foot.position=Vector3(0,-.29,0)
		shin.add_child(foot)
		var shoe := GEO.new()
		var shoe_color: Color = actor.shoe_color
		shoe.oval(Vector3(.092,.058,.171),Vector3(0,.003,-.034),shoe_color)
		shoe.box(Vector3(.087,.012,.156),Vector3(0,-.0265,-.027),shoe_color.darkened(.3))
		shoe.box(Vector3(.076,.015,.045),Vector3(0,-.022,.032),shoe_color.darkened(.35))
		for i in 3: shoe.box(Vector3(.044,.006,.008),Vector3(0,.029,-.032-i*.014),shoe_color.lightened(.17))
		shoe.finish(foot,"Footwear",.65)
	actor.set_meta("citizen_dressed",true)
	actor.set_meta("rig_tailored",true)
	actor.set_meta("detail_role","civilian")
	actor.set_meta("outfit_variant",identity%4)

static func _build_beard(actor: Node, jaw: float, chin: float) -> void:
	var style := int(actor.get_meta("beard_style",2 if actor.has_beard else 0))
	if not actor.has_beard or style==0: return
	var beard:=GEO.new()
	var color: Color=actor.hair_color.darkened(.08)
	if style==1: color=actor.skin_color.lerp(color,.45)
	if style in [1,2,3]:
		var length := .005 if style==1 else .015 if style==2 else .070
		beard.loft([Vector4(-.155-length,chin*.9,.056,-.026),Vector4(-.14-length*.45,jaw*.82,.077,-.022),Vector4(-.092,jaw*1.05,.098,-.008),Vector4(-.055,jaw*1.08,.098,-.002)],color,12,PI*.5,PI)
		# Sideburns close the jaw contour without painting the back of the neck.
		for side in [-1,1]:
			beard.oval(Vector3(.024,.09,.041),Vector3(side*jaw,.0,-.001),color,Vector3(0,0,side*-.20))
	elif style==4:
		beard.loft([Vector4(-.193,.023,.016,-.059),Vector4(-.153,.043,.028,-.061),Vector4(-.112,.035,.015,-.089)],color,10)
	if style!=1:
		for side in [-1,1]:
			beard.oval(Vector3(.050 if style==5 else .045,.021,.021),Vector3(side*.023,-.063,-.115),color,Vector3(0,0,side*-.16))
	beard.finish(actor.head_node,"FacialHair",1.0)

static func _build_hair(actor: Node) -> void:
	var hair := GEO.new()
	var color: Color = actor.hair_color
	var style := int(actor.get_meta("hair_style",0))
	var covered: bool = actor.has_cap or actor.has_beanie or actor.has_fur_hood or actor.has_ranger_hat or actor.has_cowboy_hat
	# Scalp sections leave the forehead open; side/back locks close the hairline.
	if not covered:
		hair.scalp(color)
		for i in 7:
			if style==7: continue
			var x := (i-3)*.032
			var sweep := .035 if style in [1,2,6] else -.012
			hair.lock(Vector3(x*.8,.171,.022),Vector3(x+sweep,.17,-.098),Vector3(x+sweep*.5,.10+(i%3)*.008,-.101),.022,color.lightened((i%3)*.018))
	for side in [-1,1]:
		if style in [2,6]:
			hair.oval(Vector3(.065,.24 if style==2 else .37,.17),Vector3(side*.121,-.012 if style==2 else -.068,.037),color)
		for i in 4:
			if style==5 and side==-1: continue
			var z := -.025+i*.036
			var end_y := -.12 if style==2 else (-.23 if style==6 else -.04)
			if covered: end_y = maxf(end_y,-.09)
			hair.lock(Vector3(side*.098,.135,z),Vector3(side*.15,.025,z+.014),Vector3(side*.119,end_y,z+.02),.038 if style in [2,6] else .025,color)
	for i in 6:
		var x := (i-2.5)*.039
		hair.lock(Vector3(x,.15,.073),Vector3(x,.036,.137),Vector3(x,-.24 if style==6 else -.09,.10),.026,color)
	if style==3:
		hair.lock(Vector3(0,.04,.115),Vector3(.02,-.01,.24),Vector3(.025,-.30,.18),.066,color)
	if style==4 and not covered:
		for i in 5: hair.lock(Vector3(0,.16,-.085+i*.043),Vector3(.006,.24,-.07+i*.043),Vector3(.007,.19,-.05+i*.043),.025,color)
	if style==7 and not covered:
		for i in 12:
			var a := i*TAU/12
			hair.oval(Vector3(.068,.059,.070),Vector3(sin(a)*.092,.159,cos(a)*.073+.023),color.lightened((i%3)*.018),Vector3(.2,a,.15))
	hair.finish(actor.head_node,"HairStyle",1.0)

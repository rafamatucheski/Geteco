extends RefCounted
## Authored silhouettes share grip coordinates with their family, not scaled copies.
const GEO = preload("res://gameplay/WeaponPresentation3D.gd")
const FINISH = preload("res://gameplay/WeaponFinish3D.gd")
const IDS := ["pistol_suppressed", "smg_compact", "smg_tactical", "shotgun_auto"]

static func build(root: Node3D, id: String) -> Vector3:
	var steel := GEO._mat(Color("56616b"), .65, .42)
	var dark := GEO._mat(Color("252c30"), .45, .55)
	var rubber := GEO._mat(Color("171d20"), 0, .84)
	var olive := GEO._mat(Color("515746"), .05, .74)
	var muzzle := Vector3.ZERO
	if id == "pistol_suppressed":
		GEO.build(root,"pistol")
		GEO._cylinder(root,"IntegralSuppressor",Vector3(0,.055,-.225),.024,.15,dark,Vector3(90,0,0))
		GEO._cylinder(root,"SuppressorBore",Vector3(0,.055,-.301),.008,.002,rubber,Vector3(90,0,0))
		muzzle = Vector3(0,.055,-.302)
	elif id == "shotgun_auto":
		GEO._section_box(root,"Receiver",Vector3(0,.015,-.025),Vector3(.050,.067,.235),dark,.008)
		GEO._stock_profile(root,"SyntheticStock",PackedVector2Array([Vector2(.27,-.085),Vector2(.27,.025),Vector2(.15,.028),Vector2(.09,.018),Vector2(.045,-.025),Vector2(.045,-.065),Vector2(.085,-.071),Vector2(.14,-.015),Vector2(.20,-.035)]),.048,olive)
		GEO._box(root,"ButtPad",Vector3(0,-.03,.273),Vector3(.051,.12,.016),rubber)
		GEO._cylinder(root,"Barrel",Vector3(0,.035,-.355),.018,.47,steel,Vector3(90,0,0))
		GEO._cylinder(root,"MagazineTube",Vector3(0,-.012,-.32),.017,.37,dark,Vector3(90,0,0))
		GEO._section_box(root,"FixedForeEnd",Vector3(0,-.018,-.20),Vector3(.057,.050,.17),olive,.009)
		GEO._box(root,"EjectionPort",Vector3(.026,.025,-.035),Vector3(.002,.025,.07),rubber)
		var bolt := Node3D.new()
		bolt.name = "Slide"
		root.add_child(bolt)
		GEO._box(bolt,"BoltHandle",Vector3(.04,.024,-.055),Vector3(.03,.012,.016),steel)
		GEO._box(root,"FrontSight",Vector3(0,.063,-.55),Vector3(.012,.027,.018),dark)
		GEO._trigger_guard(root,Vector3(0,-.034,.015),dark)
		muzzle = Vector3(0,.035,-.591)
		GEO._cylinder(root,"Bore",muzzle,.011,.002,rubber,Vector3(90,0,0))
	else:
		var compact := id == "smg_compact"
		var front := -.25 if compact else -.41
		GEO._section_box(root,"Receiver",Vector3(0,.012,-.055),Vector3(.052,.075,.22),dark,.008)
		GEO._section_box(root,"FiringGrip",Vector3(0,-.05,.03),Vector3(.035,.095,.05),rubber,.005)
		GEO._section_box(root,"ForeEnd",Vector3(0,-.011,-.15),Vector3(.054,.052,.10 if compact else .15),rubber if compact else olive,.008)
		GEO._cylinder(root,"Barrel",Vector3(0,.015,(front-.17)*.5),.015,absf(front+.17),steel,Vector3(90,0,0))
		GEO._cylinder(root,"Bore",Vector3(0,.015,front-.002),.007,.002,rubber,Vector3(90,0,0))
		# Detachable magazine remains a separate node for the real reload animation.
		var mag := Node3D.new()
		mag.name = "CurvedMagazine"
		root.add_child(mag)
		GEO._profile(mag,"MagazineBody",PackedVector2Array([Vector2(-.04,-.03),Vector2(-.085,-.03),Vector2(-.10,-.16),Vector2(-.055,-.17)]),.028,dark)
		GEO._trigger_guard(root,Vector3(0,-.035,-.015),dark)
		GEO._box(root,"EjectionPort",Vector3(.027,.02,-.03),Vector3(.002,.025,.054),rubber)
		var bolt := Node3D.new()
		bolt.name = "Slide"
		root.add_child(bolt)
		GEO._box(bolt,"ChargingHandle",Vector3(.038,.026,-.04),Vector3(.025,.012,.017),steel)
		if compact:
			# Short folding stock: the shoulder endpoint stays compatible with the SMG rig.
			for x in [-.019,.019]: GEO._cylinder(root,"FoldingStock",Vector3(x,.03,.12),.004,.13,steel,Vector3(90,0,0))
			GEO._box(root,"StockPlate",Vector3(0,.005,.19),Vector3(.044,.075,.01),dark)
			GEO._box(root,"TopChargingBlock",Vector3(0,.064,-.025),Vector3(.032,.026,.03),steel)
		else:
			GEO._profile(root,"SolidStock",PackedVector2Array([Vector2(.06,.041),Vector2(.19,.042),Vector2(.19,-.045),Vector2(.16,-.045),Vector2(.11,.005),Vector2(.06,.005)]),.044,olive)
			GEO._box(root,"StockPad",Vector3(0,0,.193),Vector3(.048,.09,.012),rubber)
			GEO._box(root,"TopRail",Vector3(0,.057,-.065),Vector3(.03,.014,.18),steel)
			for z in [-.21,-.185,-.16]: GEO._box(root,"ForeEndVent",Vector3(0,.012,z),Vector3(.056,.014,.009),rubber)
		GEO._box(root,"FrontSight",Vector3(0,.047,front+.025),Vector3(.014,.028,.017),dark)
		GEO._box(root,"RearSight",Vector3(0,.064,.035),Vector3(.03,.014,.018),steel)
		muzzle = Vector3(0,.015,front-.003)
	FINISH.apply(root,id,muzzle)
	return muzzle

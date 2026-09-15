extends RefCounted
## Identidade visual independente da rotina e do papel de combate.
const PART = preload("res://characters/pedestrians/CitizenDetails.gd")
const HAIR_NAMES := ["curto", "franja lateral", "chanel", "rabo de cavalo", "moicano", "raspado lateral", "comprido", "cacheado"]

static func prepare(actor: Node) -> void:
	var variant: int = actor.appearance_seed if actor.appearance_seed >= 0 else randi_range(0, 65535)
	actor.set_meta("appearance_variant", variant)
	var female: bool = actor.appearance_gender == 2 or (actor.appearance_gender == 0 and variant % 2 == 1)
	actor.set_meta("appearance_female", female)
	var styles := [2,3,6,7,1] if female else [0,1,4,5,7]
	var hair: int = actor.hair_style_override if actor.hair_style_override >= 0 else styles[(variant / 2) % styles.size()]
	actor.set_meta("hair_style", posmod(hair, HAIR_NAMES.size()))
	if female: actor.has_beard = false
	var beard: int = actor.beard_style_override
	if beard < 0:
		beard = (2 + posmod(variant / 3,4)) if actor.has_beard else posmod(variant / 2,6)
	if female: beard = 0
	actor.set_meta("beard_style",beard)
	actor.has_beard = beard > 0
	# Parte da população usa o cabelo exposto: bonés não devem uniformizar a rua.
	if actor.archetype in [0,1,2,6,7] and variant % 3 != 0:
		actor.has_cap = false
		actor.has_beanie = false
	if actor.hair_style_override >= 0 and actor.archetype in [0,1,2,4,5,6,7]:
		actor.has_cap = false
		actor.has_beanie = false

static func apply(actor: Node) -> void:
	var variant := int(actor.get_meta("appearance_variant", 0))
	var female := bool(actor.get_meta("appearance_female", false))
	var heavy: bool = actor.body_type == 2
	var torso: MeshInstance3D = actor.torso_node.get_node("BodyShell")
	torso.mesh = tailored_body(female, heavy)
	PART.piece(actor.torso_node,Vector3(.29,.10,.245),Vector3(0,-.245,0),actor.pants_color).name="Pelvis"
	actor.head_node.scale.x *= .96 + (variant%5)*.015
	# O pescoço sobrepõe cabeça e gola, inclusive no biotipo baixo e na corrida.
	var neck := PART.piece(actor.head_node, Vector3(.115,.22,.12), Vector3(0,-.19,.012), actor.skin_color, true)
	neck.name = "Neck"
	var old_hair: Node3D = actor.head_node.get_node("BaseHair")
	old_hair.hide()
	var style := int(actor.get_meta("hair_style",0))
	var covered: bool = actor.has_cap or actor.has_beanie or actor.has_fur_hood or actor.has_ranger_hat or actor.has_cowboy_hat
	build_hair(actor.head_node, style, actor.hair_color, covered)
	# Muda a linha de gola e a barra; ambos os gêneros usam roupas cotidianas.
	var cloth: Color = actor.shirt_color
	var outfit := variant % 4
	if outfit == 0:
		for side in [-1,1]:
			PART.piece(actor.torso_node,Vector3(.05,.31,.025),Vector3(side*.085,.0,-.18),cloth.darkened(.3)).rotation.z=side*.17
	elif outfit == 1:
		PART.piece(actor.torso_node,Vector3(.30,.045,.025),Vector3(0,.055,-.179),cloth.lightened(.23))
	elif outfit == 2:
		PART.piece(actor.torso_node,Vector3(.28,.022,.025),Vector3(0,-.17,-.168),cloth.darkened(.24))
	if female and outfit == 3 and not actor.is_gangster:
		var hem := PART.piece(actor.torso_node, Vector3.ONE, Vector3(0,-.22,0),cloth.darkened(.12))
		hem.name = "TunicHem"
		var mesh := CylinderMesh.new()
		mesh.top_radius = .16
		mesh.bottom_radius = .19
		mesh.height = .19
		mesh.radial_segments = 10
		hem.mesh = mesh
		hem.scale.z = .8
	actor.set_meta("outfit_variant",outfit)

static func tailored_body(female: bool, heavy: bool) -> ArrayMesh:
	# Seções chanfradas dão volume à barriga sem criar uma esfera sobreposta.
	var hip := .164 if female else .148
	var waist := .133 if female else .155
	if heavy: waist = .175
	var shoulder := .173 if female else .185
	var rings := [Vector3(hip,-.23,.132),Vector3(waist,-.06,.156 if heavy else .138),Vector3(shoulder,.135,.148),Vector3(shoulder,.18,.13),Vector3(.095,.235,.09)]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sections: Array[PackedVector3Array] = []
	for ring in rings:
		var points := PackedVector3Array()
		for corner in [Vector2(-.7,-1),Vector2(.7,-1),Vector2(1,-.65),Vector2(1,.65),Vector2(.7,1),Vector2(-.7,1),Vector2(-1,.65),Vector2(-1,-.65)]:
			points.append(Vector3(corner.x*ring.x,ring.y,corner.y*ring.z))
		sections.append(points)
	for row in sections.size()-1:
		for i in 8:
			var j := (i+1)%8
			for point in [sections[row][i],sections[row][j],sections[row+1][i],sections[row][j],sections[row+1][j],sections[row+1][i]]:
				surface.add_vertex(point)
	for i in range(1,7):
		for point in [sections[0][0],sections[0][i],sections[0][i+1],sections[4][0],sections[4][i+1],sections[4][i]]: surface.add_vertex(point)
	surface.generate_normals()
	return surface.commit()

static func build_hair(head: Node3D, style: int, color: Color, covered := false) -> void:
	var hair := Node3D.new()
	hair.name = "HairStyle"
	head.add_child(hair)
	var crown := PART.piece(hair,Vector3(.345,.15,.32),Vector3(0,.115,.025),color,true)
	if covered: crown.hide()
	if style == 4 and not covered:
		crown.hide()
		PART.piece(hair,Vector3(.34,.105,.32),Vector3(0,.10,.02),color.darkened(.15),true)
		for i in 6:
			var tuft := PART.piece(hair,Vector3(.10,.12,.075),Vector3(0,.18+sin(i/5.0*PI)*.04,-.11+i*.05),color)
			tuft.rotation.x = -.25 + i*.10
	elif style in [0,1,5] and not covered:
		for i in 4:
			var fringe := PART.piece(hair,Vector3(.095,.075,.12),Vector3(-.105+i*.067,.15,-.075),color.lightened(.025*i),true)
			fringe.rotation.z = -.25 if style != 0 else 0
		if style == 5:
			crown.scale.x *= .82
	elif style == 2:
		for side in [-1,1]: PART.piece(hair,Vector3(.07,.265,.22),Vector3(side*.145,-.015,.035),color,true)
		PART.piece(hair,Vector3(.29,.23,.10),Vector3(0,-.025,.14),color,true)
	elif style == 3:
		PART.piece(hair,Vector3(.105,.10,.12),Vector3(0,.055,.19),color,true)
		PART.piece(hair,Vector3(.09,.29,.11),Vector3(0,-.07,.22),color,true).rotation.x=-.15
		PART.piece(hair,Vector3(.10,.024,.10),Vector3(0,.03,.2),Color("879a73"))
	elif style == 6:
		for side in [-1,1]: PART.piece(hair,Vector3(.075,.38,.13),Vector3(side*.15,-.06,.045),color,true)
		PART.piece(hair,Vector3(.29,.38,.09),Vector3(0,-.07,.15),color,true)
	elif style == 7 and not covered:
		for i in 9:
			var angle := i*TAU/9
			PART.piece(hair,Vector3(.125,.12,.13),Vector3(cos(angle)*.125,.145,sin(angle)*.105+.015),color.lightened(.025*(i%3)),true)

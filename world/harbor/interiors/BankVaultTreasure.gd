extends RefCounted
## Cada conjunto é uma coleta única: notas com cintas e barras guardadas em bandejas.
const PART = preload("res://world/shared/pedestrians/CitizenDetails.gd")

static func build(parent: Node3D, point: Vector3, variant: int) -> Node3D:
	var pile := Node3D.new()
	pile.name="VaultCash%d"%variant
	parent.add_child(pile)
	pile.position=point
	PART.piece(pile,Vector3(1.35,.08,.85),Vector3(0,.06,0),Color("3a4844"))
	for row in 2:
		for column in 3:
			for level in (3 if column==1 else 2):
				var bundle := Node3D.new()
				pile.add_child(bundle)
				bundle.position=Vector3(-.43+column*.40,.145+level*.10,-.19+row*.36)
				bundle.rotation.y=(column-row+variant)*.055
				PART.piece(bundle,Vector3(.34,.085,.25),Vector3.ZERO,Color("8da68a"))
				PART.piece(bundle,Vector3(.31,.008,.22),Vector3(0,.047,0),Color("c2d1ab"))
				for edge in [-1,1]:
					for line in 3:
						PART.piece(bundle,Vector3(.33,.005,.004),Vector3(0,-.025+line*.021,edge*.126),Color("d2d5b8"))
				PART.piece(bundle,Vector3(.06,.09,.258),Vector3.ZERO,Color("d7bd87"))
				PART.piece(bundle,Vector3(.06,.009,.11),Vector3(.10,.052,0),Color("55765c"))
	# Ouro ao lado das notas, pertencente ao mesmo conjunto recolhível.
	for i in 3:
		var bar := PART.piece(pile,Vector3(.27,.12,.15),Vector3(-.40+i*.38,.16,.50),Color("d6a438"))
		bar.material_override.metallic=.7
		bar.material_override.roughness=.25
		PART.piece(pile,Vector3(.19,.012,.085),Vector3(-.40+i*.38,.225,.50),Color("f1d67d"))
	return pile

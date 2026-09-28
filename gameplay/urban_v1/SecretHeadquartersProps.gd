extends RefCounted
## Static corner equipment; each group has full-footprint collision.

static func build(stage) -> void:
	var generator: Vector3 = stage.HQ_CENTER+Vector3(-5.1,0,5.55)
	stage._solid("OldGenerator",generator+Vector3(0,.64,0),Vector3(2.1,1.28,1.35))
	stage._box(generator+Vector3(0,.13,0),Vector3(2.1,.24,1.35),"303a39")
	stage._box(generator+Vector3(.23,.68,0),Vector3(1.43,.91,1.14),"5b674f")
	stage._cylinder(generator+Vector3(-.64,.65,0),.37,.73,"696d65",Vector3(0,0,PI*.5),12)
	stage._box(generator+Vector3(-.02,1.16,0),Vector3(.96,.18,.90),"4b4437")
	for x in [-.32,-.12,.08,.28,.48,.68]:
		stage._box(generator+Vector3(x,.74,.58),Vector3(.045,.53,.045),"292d2a")
	stage._box(generator+Vector3(.60,.43,.58),Vector3(.48,.23,.04),"777063")
	stage._cylinder(generator+Vector3(.60,.45,.63),.065,.055,"9f513f",Vector3(PI*.5,0,0),10)
	stage._pipe(generator+Vector3(.68,1.02,-.40),generator+Vector3(.68,1.78,-.40),.07,"6f6657")
	var cot: Vector3 = stage.HQ_CENTER+Vector3(5.0,0,4.75)
	stage._solid("FieldCot",cot+Vector3(0,.38,0),Vector3(1.18,.76,2.38))
	stage._box(cot+Vector3(0,.57,0),Vector3(1.06,.15,2.16),"68755d")
	for side in [-1.0,1.0]:
		stage._box(cot+Vector3(side*.55,.51,0),Vector3(.07,.08,2.32),"696d65")
		for z in [-.9,.9]:
			stage._box(cot+Vector3(side*.46,.26,z),Vector3(.07,.50,.07),"777063",Vector3(0,0,side*.16))
	stage._box(cot+Vector3(0,.72,-.69),Vector3(.72,.17,.42),"999889")
	stage._box(cot+Vector3(0,.69,.50),Vector3(1.04,.09,.83),"704f42")
	for z in [.19,.39,.59,.79]:
		stage._box(cot+Vector3(0,.742,z),Vector3(1.02,.01,.028),"796a4e")

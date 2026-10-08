extends RefCounted
## Fixed discoveries in Harbor; one low, accessible service rooftop introduces them.
const ROOFS = preload("res://world/places/harbor_buildings/HarborServiceRoofCatalog.gd")

static func definitions() -> Array[Dictionary]:
	var roof := ROOFS.find("harbor_ammunation")
	var rooftop: Vector3 = roof.exterior_position + Vector3(1.1,float(roof.roof_height)+.025,2.8).rotated(Vector3.UP,float(roof.exterior_rotation))
	return [
		{"id":"cat_01","index":0,"point":rooftop,"roof":"harbor_ammunation","site":"rooftop"},
		{"id":"cat_02","index":1,"point":Vector3(-48,.02,128),"site":"cemetery_back"},
		{"id":"cat_03","index":2,"point":Vector3(-283,.02,108),"site":"truckers_outskirts"},
		{"id":"cat_04","index":3,"point":Vector3(-305,.02,-48),"site":"industrial_edge"},
		{"id":"cat_05","index":4,"point":Vector3(311,.02,-139),"site":"lighthouse_approach"},
		{"id":"cat_06","index":5,"point":Vector3(316,.02,-50),"site":"canal_bank"},
		{"id":"cat_07","index":6,"point":Vector3(350,.02,357),"site":"port_backlot"},
		{"id":"cat_08","index":7,"point":Vector3(220,.02,150),"site":"quayside_edge"},
		{"id":"cat_09","index":8,"point":Vector3(-76,.02,38),"site":"west_scrub"},
		{"id":"cat_10","index":9,"point":Vector3(383,.02,-101),"site":"north_outskirts"},
	]

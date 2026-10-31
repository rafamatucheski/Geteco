extends RefCounted
## Todas as posições são pixels da V1 locais ao MountainPass, não coordenadas de interior projetadas.
const OFFSET := Vector2(4300,-4960)
const RADIUS := 220.0/16.0 # Actual controller radius; ignores larger/smaller Area2D art radii.
const SOURCES := [
	{"id":"logging_camp","point":Vector2(6440,580),"source":"MountainPass.gd:LoggingCamp/CampfireHeatSource"},
	{"id":"summit_camp","point":Vector2(6370,-2780),"source":"MountainPass.gd:AltitudeOutpostBunker/SummitCampfire"},
	{"id":"smuggler_camp","point":Vector2(5655,-990),"source":"MountainSceneryBuilder.gd:SecretMountainLake/SmugglerCampsite/fire_pit"},
	# Último Abrigo: a V1 punha o aquecedor em shop_position+(0,65), no meio do caminho 2,3 m à
	# frente da porta pintada; quem chegava de viés parava nele e não entrava (auditoria de 30/10).
	# Fica 4,5 m ao lado, junto à quina da fachada, ainda bem dentro do RADIUS da loja.
	{"id":"outfitters_heater","point":Vector2(6052,708),"source":"MountainExpedition.gd:shop_position+(0,65)"},
	{"id":"patrol_shelter","point":Vector2(6610,-1250),"source":"MountainSettlement.gd:PatrolShelter3D"},
	{"id":"transit_village","point":Vector2(7650,-1553),"source":"MountainTransitVillageLayout.gd:HEAT_SOURCE"},
	{"id":"resort_brazier","point":Vector2(7310,-2700),"source":"ResortPromenade.gd:_build_fire_brazier"},
	# Pista da Forja da Serra (V2, 17/10/2026): brasa da fornalha e fogueira do Mestre Aurélio.
	{"id":"blade_forge","point":Vector2(7100,-982.4),"source":"MountainForge.gd:HEARTH"},
	{"id":"hermit_camp","point":Vector2(6941.6,-8505.6),"source":"ForgeHermitCabin.gd:FIRE"},
	# Refúgio da Serra (26/10): fogueira em frente ao abrigo; MountainRefuge.world_point(FIRE) × 16 − OFFSET.
	{"id":"mountain_refuge","point":Vector2(7901.6,-3030.4),"source":"MountainRefuge.gd:FIRE"},
]
static func to_world(point: Vector2) -> Vector3:
	point = (point+OFFSET)/16.0
	return Vector3(point.x,0,point.y)
static func nearest(point: Vector3) -> Dictionary:
	# Ten immutable positions: no scene-tree traversal or resources per frame.
	var best := RADIUS*RADIUS
	var found: Dictionary = {}
	for source in SOURCES:
		var at := to_world(source.point)
		var distance := Vector2(at.x-point.x,at.z-point.z).length_squared()
		if distance < best and absf(point.y-at.y)<2.5:
			best = distance
			found = source
	return found
static func sheltered(point: Vector3) -> bool:
	if point.y < -.5 or point.y > 3: return false
	var original := Vector2(point.x,point.z)*16.0-OFFSET
	# O MountainPass configura o túnel original como 850x150.
	if Rect2(4950,325,850,150).has_point(original): return true
	# Original aircraft interior floor bounds, already authored in metres.
	var plane := to_world(Vector2(5450,-1150))
	return Rect2(-1.37,-13,2.74,22.4).has_point(Vector2(point.x-plane.x,point.z-plane.z))

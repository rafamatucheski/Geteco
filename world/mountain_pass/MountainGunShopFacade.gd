extends "res://world/shared/ammunation/AmmunationBranchView.gd"
var entrance: BuildingEntrance
func _ready() -> void:
	z_as_relative = false
	z_index = 4
	build_view(preload("res://world/shared/ammunation/AmmunationFacade3D.gd"),12.0,22.0,Vector3(0,1.8,0))
	_build_parking()
	add_solid(Rect2(-4.2,-2.2,8.4,4.4),"GunShopStructure")
	for side in [-1.0,1.0]:
		add_solid(Rect2(side*3.8-0.15,2.65,0.30,0.30),"PorchPost")

func _build_parking() -> void:
	var lot := Node2D.new()
	lot.name = "AmmunationParking"
	lot.z_as_relative = false
	lot.z_index = 1
	add_child(lot)
	var paving := Polygon2D.new()
	paving.polygon = PackedVector2Array([Vector2(-148,62),Vector2(148,62),Vector2(148,205),Vector2(-148,205)])
	paving.color = Color("555753")
	lot.add_child(paving)
	preload("res://world/mountain_pass/MountainGroundMaterials.gd").apply(paving,"asphalt")
	for x in [-132.0,-88.0,44.0,88.0,132.0]:
		var stripe := Line2D.new()
		stripe.width = 1.6
		stripe.default_color = Color("c6c4a5")
		stripe.points = PackedVector2Array([Vector2(x,83),Vector2(x,131)])
		lot.add_child(stripe)
	var walk := Polygon2D.new()
	walk.color = Color("9b9b89")
	walk.polygon = PackedVector2Array([Vector2(-22,54),Vector2(22,54),Vector2(22,145),Vector2(-22,145)])
	lot.add_child(walk)
	for x in [-110.0,66.0,110.0]:
		var stop := Polygon2D.new()
		stop.color = Color("b8ad7d")
		stop.position = Vector2(x,87)
		stop.polygon = PackedVector2Array([Vector2(-14,-2),Vector2(14,-2),Vector2(14,2),Vector2(-14,2)])
		lot.add_child(stop)
func install_entrance(manager: Node2D) -> void:
	if is_instance_valid(entrance): return
	entrance = preload("res://scripts/entrances/BuildingEntrance.tscn").instantiate()
	entrance.name = "AmmuNationEntrance"
	entrance.position = project_floor(Vector2(0,3.2))
	entrance.display_name = "AMMU-NATION — ARMAS E MUNIÇÃO"
	entrance.entrance_kind = BuildingEntrance.EntranceKind.SHOP
	entrance.destination_id = &"ammunation"
	add_child(entrance)
	# BuildingEntrance.tscn's own $InteractionArea keeps collision_mask=3 (no
	# player bit) so it can be reused for vehicle-only or mixed doors without
	# forcing pedestrian detection everywhere; Harbor's procedural doors patch
	# this per-door in HarborEntrance.gd (role-based). This shop is a
	# pedestrian-only entrance (BuildingEntrance.EntranceKind.SHOP, no vehicle
	# ever needs to trigger it), so the fix is local to this one door instead
	# of touching the shared scene's default or every other entrance kind.
	entrance.get_node("InteractionArea").collision_mask = 4
	entrance.get_node("Facade").hide()
	entrance.get_node("Prompt").modulate.a = 0.0
	manager.register_exterior_entrance(entrance,&"ammunation",to_global(project_floor(Vector2(0,4.5))))
	bind_entrance(entrance,manager.ammunation_interior)

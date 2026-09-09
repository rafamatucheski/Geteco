extends "res://district/mountain_pass/MountainStaticModelView.gd"
var entrance: BuildingEntrance
func _ready() -> void:
	z_as_relative = false
	z_index = 4
	build_view(preload("res://district/mountain_pass/art/review_0908/MountainGunShop3D.gd"),12.0,22.0,Vector3(0,1.8,0))
	add_solid(Rect2(-4.2,-2.2,8.4,4.4),"GunShopStructure")
	for side in [-1.0,1.0]:
		add_solid(Rect2(side*3.8-0.15,2.65,0.30,0.30),"PorchPost")
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
	manager.register_exterior_entrance(entrance,&"ammunation",to_global(project_floor(Vector2(0,4.5))))

extends SceneTree
const IDS = ["american_dump_truck","american_tanker_truck","boxrunner","cargo_flatbed_truck","medic_box","police_cruiser","police_suv","rescue_pumper","snow_plow_truck","towmaster","police_transport","armored_truck"]
func _initialize() -> void:
	var all := {}
	for id in IDS:
		var model: Node3D = preload("res://runtime/FleetCatalog.gd").create(id)
		var entries := []
		for p: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			var m := p.get_active_material(0) as StandardMaterial3D
			var metadata := {}
			for k in p.get_meta_list(): metadata[k]=str(p.get_meta(k))
			entries.append({"name":str(model.get_path_to(p)),"type":p.mesh.get_class(),"tri":p.mesh.get_faces().size()/3,"pos":str(p.position),"box":str(p.transform*p.get_aabb()),"material":m.resource_name if m else "", "color":m.albedo_color.to_html() if m else "", "meta":metadata,"visible":p.visible})
		all[id] = {"spec":preload("res://runtime/FleetCatalog.gd").spec(id),"parts":entries}
		model.free()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence/fleet-redesign-20261011/service"))
	var file := FileAccess.open("res://evidence/fleet-redesign-20261011/service/inventory.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(all,"\t"))
	print("Service inventory exported")
	quit()

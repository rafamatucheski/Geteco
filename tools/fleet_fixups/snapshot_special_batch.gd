extends SceneTree
const FLEET=preload("res://runtime/FleetCatalog.gd")
const MESH=preload("res://tools/fleet_fixups/FleetBatchMesh.gd")
const IDS=["desert_faisca","desert_coyote","desert_siroco","desert_bison","desert_mirage","desert_faisca_rally","desert_coyote_drag","desert_mirage_gt","rauhz_focus_mk1","supra_a80","jessica_jetta_gli","digo_amarok_2014","digo_gol_1993","cobra_boss_ironback"]
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var inventory := {}
	for id: String in IDS:
		var model: Node3D=FLEET.create(id)
		root.add_child(model)
		await process_frame
		model.set_script(null)
		var info: Dictionary=MESH.counts(model)
		info["spec"]=FLEET.spec(id)
		info["parts"]=[]
		for node in model.find_children("*","MeshInstance3D",true,false):
			var metadata := {}
			for key in node.get_meta_list(): metadata[key]=node.get_meta(key)
			info.parts.append({"name":node.name,"metadata":metadata,"bounds":node.transform*node.get_aabb()})
		var file := "res://evidence/fleet-redesign-20261011/special/original/"+id+".scn"
		info["path"]=file
		info["save_status"]=MESH.save_model(model,file)
		inventory[id]=info
		print("SPECIAL_SOURCE ",id," ",info.meshes," / ",info.triangles)
		model.free()
	var out:=FileAccess.open("res://evidence/fleet-redesign-20261011/special/original-inventory.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(inventory,"\t"))
	quit()

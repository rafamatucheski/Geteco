extends SceneTree
const MESH=preload("res://tools/fleet_fixups/FleetBatchMesh.gd")
const DESIGN=preload("res://tools/fleet_fixups/SpecialFleetDesign.gd")
const IDS=preload("res://tools/fleet_fixups/snapshot_special_batch.gd").IDS
const PROFILES={"desert_faisca":"orbita_micro","desert_coyote":"muscle_classic","desert_siroco":"union_sedan","desert_bison":"vale_crossover","desert_mirage":"porto_rosso","desert_faisca_rally":"monaliza","desert_coyote_drag":"cobra_v8","desert_mirage_gt":"vertice_midengine","rauhz_focus_mk1":"sport_estate","supra_a80":"monaliza","jessica_jetta_gli":"sport_estate","digo_amarok_2014":"vale_crossover","digo_gol_1993":"orbita_micro","cobra_boss_ironback":"cobra_v8"}
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var folder := "res://evidence/fleet-redesign-20261011/special"
	var inventory: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+"/original-inventory.json"))
	var production: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+"/production.json")) if FileAccess.file_exists(folder+"/production.json") else {}
	var selected: Array=[]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ids="): selected=Array(arg.trim_prefix("--ids=").split(","))
	for id: String in IDS:
		if not selected.is_empty() and id not in selected: continue
		var model := (load(folder+"/original/"+id+".scn") as PackedScene).instantiate() as Node3D
		var spec: Dictionary=inventory[id].spec
		for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			if part.has_meta("wheel_center") or part.mesh==null: continue
			part.mesh=preload("res://tools/fleet_fixups/SpecialMeshReduction.gd").reduce(part.mesh,.35)
			part.set_meta("batch_ratio",1.0)
		var design := DESIGN.new()
		design.target_id=id
		design.apply(model,PROFILES[id],spec)
		if id in ["digo_gol_1993","jessica_jetta_gli"]: design.split_front_lenses(model)
		var baked: Node3D=MESH.bake(model,1.0,id)
		var destination := "res://assets/fleet/redesigned/"+id+".scn"
		var info: Dictionary=MESH.counts(baked)
		info["before"]={"meshes":inventory[id].meshes,"surfaces":inventory[id].surfaces,"triangles":inventory[id].triangles}
		info["destination"]=destination
		info["status"]=MESH.save_model(baked,destination)
		if id in ["digo_gol_1993","jessica_jetta_gli"]: info["headlight_fix"]="Two lenses occupied one legacy surface and bound only one projector. Offline split preserves triangles/materials and restores independent left/right equipment bindings."
		production[id]=info
		print("SPECIAL_BAKED ",id," ",info)
		baked.free()
		model.free()
	var file := FileAccess.open(folder+"/production.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(production,"\t"))
	quit()

extends SceneTree
const DATA := preload("res://world/editing/WorldEditData.gd")
const REGION := preload("res://world/editing/EditableDesertRegion.gd")
const UI := preload("res://addons/geteco_world_editor/WorldEditor.gd")
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func run() -> void:
	var official := DATA.disk_hash()
	var doc := DATA.empty_document()
	check(DATA.validate_document(doc).is_empty(),"Three regions accepted")
	var old := {"version":1,"regions":{"harbor":{},"mountain":{}}}
	check(DATA.validate_document(old).is_empty(),"Old two-region saves remain valid")
	var prop := DATA.new_entity("prop",Vector2(-390,-940))
	prop.id = "new/desert_editor_test"
	doc.regions.desert[prop.id] = prop
	var file := "res://.godot/desert_editor_test_%d.json"%OS.get_process_id()
	check(DATA.save_document(doc,DATA.disk_hash(file),file).is_empty(),"Save three-region document")
	var reloaded := DATA.read_document(file)
	check(reloaded.error.is_empty() and DATA.point(reloaded.document.regions.desert[prop.id].position).is_equal_approx(DATA.point(prop.position)),"Reload three-region document with JSON float precision")
	Engine.set_meta("geteco_world_edit_document",doc)
	Engine.set_meta("geteco_live_preview_build",true)
	var region := REGION.new()
	region.initial_prewarm_only = true
	root.add_child(region)
	var holder := Node3D.new()
	region.add_child(holder)
	region._build_added(holder,prop)
	check(holder.get_child_count()==1,"Added prop builds in production adapter")
	check(holder.get_child(0).get_meta("editor_id","")==prop.id,"3D selection identity survives")
	check(not holder.find_children("*","CollisionShape3D",true,false).is_empty(),"Added prop keeps physical collision")
	var record := {"kind":"rest_bench","position":Vector3(-315,0,-914.2)}
	region._build_record(holder,record)
	var groups := REGION.PIECES.collect(holder)
	check(groups.size()==1,"Authored bench is independently editable")
	var id := "piece/"+REGION.piece_key(record)
	var row := {"id":id,"type":"piece","position":[-610.0,-930.0],"rotation":45.0,"stretch":[1.2,1.1],"source_record":REGION.PIECES.record_key(record)}
	doc.regions.desert[id] = row
	region.free()
	region = REGION.new()
	region.initial_prewarm_only = true
	root.add_child(region)
	var target := region._cell(DATA.xyz(row.position))
	check(region.records.get(target,[]).any(func(item): return item.kind=="rest_bench"),"Moved piece streams from its destination cell")
	holder = Node3D.new()
	region.add_child(holder)
	region._build_record(holder,record)
	groups = REGION.PIECES.collect(holder)
	check(groups.size()==1 and is_equal_approx(groups[0].global_position.x,-610),"Production geometry receives saved translation")
	check(not holder.find_children("*","CollisionShape3D",true,false).is_empty(),"Transformed bench keeps collision")
	var home_data: Dictionary = region.LAYOUT.buildings().filter(func(b): return b.id=="desert_home_00")[0]
	var home_record := {"kind":"building","data":home_data}
	check(REGION.editable_record(home_record),"Decorative desert house is editable")
	# Desde 10/10/2026 todo registro do deserto é editável (o visual se move; porta e gatilho ficam).
	check(REGION.editable_record({"kind":"building","data":{"kind":"bank"}}),"Service building is editable too")
	region._build_record(holder,home_record)
	var home_id := "piece/"+REGION.piece_key(home_record)
	var home_group: Node3D
	for group in REGION.PIECES.collect(holder):
		if "piece/"+str(group.get_meta("world_edit_piece_id"))==home_id: home_group=group
	check(home_group!=null and home_group.global_position.is_equal_approx(home_data.position),"House pivot agrees with production footprint")
	var house_change := {"id":home_id,"type":"piece","position":[-440.0,-1030.0],"rotation":45.0,"stretch":[1.3,1.2],"source_record":REGION.PIECES.record_key(home_record)}
	REGION.PIECES.apply(home_group,{home_id:house_change})
	check(is_equal_approx(home_group.global_position.x,-440.0),"House geometry supports translation, rotation and dimensions")
	check(not home_group.find_children("*","CollisionShape3D",true,false).is_empty(),"House retains physical shapes after editing")
	var high_point := preload("res://world/desert/DesertTerrainRelief.gd").PLATEAU_CENTER
	region.edit_changes[id].position = [high_point.x,high_point.y]
	var high_holder := Node3D.new()
	region.add_child(high_holder)
	region._build_record(high_holder,record)
	var high_group: Node3D = REGION.PIECES.collect(high_holder)[0]
	check(is_equal_approx(high_group.global_position.y,region._ground_height(high_point)),"Moved scenery follows the desert relief")
	region.free()
	var ui := UI.new()
	ui.edits_path = file
	ui.draft_path = file+".draft"
	root.add_child(ui)
	check(ui.catalog.has("desert"),"Shipped desert catalog loads")
	check(ui._region_at(Vector2(-180,-900))=="desert","Desert placement chooses correct region")
	check(ui._region_at(Vector2(600,-285))=="mountain","Eastern mountain connection remains mountain")
	ui._switch_region("desert")
	check(ui.canvas.objects.has(id),"2D map exposes the editable authored bench")
	check(ui.canvas.objects.has(prop.id),"Saved additions load into 2D")
	ui.free()
	check(DATA.disk_hash()==official,"Official world edits untouched")
	DirAccess.remove_absolute(file)
	print("WORLD_EDITOR_DESERT ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

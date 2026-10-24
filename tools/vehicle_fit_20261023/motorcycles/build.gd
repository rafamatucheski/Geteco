extends SceneTree
const OUT="res://artifacts/vehicle-fit-20261023/motorcycles/"
const MESH=preload("res://tools/fleet_fixups/FleetBatchMesh.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var report:={}
	for id: String in ["bike_sport","bike_cruiser","bike_urban"]:
		var original_path: String=OUT+"originals/"+id+".scn"
		var source: Node3D=(load(original_path) as PackedScene).instantiate() if FileAccess.file_exists(original_path) else preload("res://runtime/FleetCatalog.gd").create(id)
		if not FileAccess.file_exists(original_path): assert(MESH.save_model(source,original_path)==OK)
		var before:=MESH.counts(source)
		preload("res://tools/vehicle_fit_20261023/motorcycles/MotorcycleCraft.gd").new().apply_fit(source,id)
		var candidate: Node3D=MESH.bake(source,1.0,id)
		var after:=MESH.counts(candidate)
		var status:=MESH.save_model(candidate,OUT+id+".scn")
		report[id]={"before":before,"after":after,"stand_stowed":true,"status":status,"source":"res://assets/fleet/redesigned/"+id+".scn","candidate":OUT+id+".scn"}
		print("MOTORCYCLE_FIT ",id," ",report[id])
		candidate.free(); source.free()
	FileAccess.open(OUT+"manifest.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	quit(0)

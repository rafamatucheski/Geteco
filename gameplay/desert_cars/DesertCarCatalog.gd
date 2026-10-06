extends RefCounted
## Authored desert roster. Mechanical units are SI; legacy driving values remain
## available to existing fleet consumers (16 world pixels per metre).
const IDS := ["desert_faisca", "desert_coyote", "desert_siroco", "desert_bison", "desert_mirage", "desert_faisca_rally", "desert_coyote_drag", "desert_mirage_gt"]
static var _model_cache: Dictionary = {}
const MODELS := {
	"desert_faisca": {"label":"Faísca GT", "body":"hatch", "color":"dcaa38", "size":[1.72,1.42,3.80], "mass":.94, "torque_nm":172.0, "redline":6900.0, "gears":[3.42,2.12,1.43,1.08,.86], "final_drive":4.05, "wheel_radius":.29, "traction":.83, "drag_area":.65, "drivetrain":"fwd", "engine_family":"street", "price":14500, "turn_speed":3.25},
	"desert_coyote": {"label":"Coyote 440", "body":"muscle", "color":"9c4330", "size":[1.94,1.32,4.78], "mass":1.48, "torque_nm":390.0, "redline":5900.0, "gears":[2.87,1.91,1.39,1.0,.79], "final_drive":3.54, "wheel_radius":.34, "traction":.77, "drag_area":.78, "drivetrain":"rwd", "engine_family":"muscle", "price":32000, "turn_speed":2.45},
	"desert_siroco": {"label":"Siroco T", "body":"sedan", "color":"486573", "size":[1.82,1.46,4.55], "mass":1.27, "torque_nm":280.0, "redline":7100.0, "gears":[3.36,2.09,1.48,1.15,.94,.79], "final_drive":3.74, "wheel_radius":.32, "traction":.92, "drag_area":.66, "drivetrain":"awd", "engine_family":"sport", "price":41000, "turn_speed":2.95, "factory_turbo":true},
	"desert_bison": {"label":"Bison D", "body":"pickup", "color":"a39273", "size":[2.04,1.83,5.20], "mass":1.98, "torque_nm":440.0, "redline":4400.0, "gears":[3.50,2.12,1.36,1.0,.76,.62], "final_drive":3.45, "wheel_radius":.39, "traction":.89, "drag_area":1.02, "drivetrain":"4x4", "engine_family":"diesel", "price":37000, "turn_speed":2.15, "factory_turbo":true},
	"desert_mirage": {"label":"Mirage R", "body":"coupe", "color":"42705b", "size":[1.91,1.23,4.43], "mass":1.30, "torque_nm":350.0, "redline":7800.0, "gears":[3.15,2.08,1.54,1.20,.98,.81], "final_drive":3.70, "wheel_radius":.33, "traction":.96, "drag_area":.57, "drivetrain":"rwd", "engine_family":"vq35", "price":68000, "turn_speed":3.20}
}
## Race editions share their donor's mechanics, save format and collision bounds.
## Their authored identity is the body kit, wheels, paint, livery and night lighting.
const EDITIONS := {
	"desert_faisca_rally":{"base_id":"desert_faisca","label":"Faísca RX","color":"183853","style":"rally","livery":"rally","livery_color":"3be0df","livery_secondary":"cde765","race_number":27,"neon_color":"3be0df","neon_strength":1.0},
	"desert_coyote_drag":{"base_id":"desert_coyote","label":"Coyote 440 Drag","color":"492838","style":"drag","livery":"drag","livery_color":"ff783c","livery_secondary":"f3e3c0","race_number":44,"neon_color":"ff783c","neon_strength":1.0},
	"desert_mirage_gt":{"base_id":"desert_mirage","label":"Mirage GT","color":"d9e1dc","style":"gt","livery":"gt","livery_color":"73edc3","livery_secondary":"193b4b","race_number":8,"neon_color":"73edc3","neon_strength":1.0}
}
const PALETTES := {
	"desert_faisca":["dcaa38ff","af493fff","437878ff","ded6bdff"],
	"desert_coyote":["9c4330ff","253b52ff","77663eff","28292fff"],
	"desert_siroco":["486573ff","c4c3b9ff","573637ff","293532ff"],
	"desert_bison":["a39273ff","67755bff","9b573dff","dad1baff"],
	"desert_mirage":["42705bff","b8c3c1ff","843d4bff","283951ff"]
}
const PROFILES := {
	"hatch":{"cabin_front":-.19,"cabin_back":.405,"roof_front":-.095,"roof_back":.305,"door_back":.15,"hood_flat_front":-.43},
	"muscle":{"cabin_front":-.10,"cabin_back":.355,"roof_front":.015,"roof_back":.19,"door_back":.26,"hood_flat_front":-.445},
	"sedan":{"cabin_front":-.20,"cabin_back":.29,"roof_front":-.10,"roof_back":.16,"door_back":.035,"hood_flat_front":-.43},
	"pickup":{"cabin_front":-.22,"cabin_back":.06,"roof_front":-.12,"roof_back":.02,"door_back":.045,"hood_flat_front":-.445},
	"coupe":{"cabin_front":-.225,"cabin_back":.355,"roof_front":-.065,"roof_back":.11,"door_back":.23,"hood_flat_front":-.405}
}

static func ids() -> Array:
	return IDS.duplicate()

static func spec(id: String) -> Dictionary:
	var base_id := str(EDITIONS.get(id,{}).get("base_id",id))
	if not MODELS.has(base_id): return {}
	var s: Dictionary = MODELS[base_id].duplicate(true)
	s.merge(PROFILES[str(s.body)],true)
	s.merge({"base_id":base_id,"style":"street","livery":"none","neon_strength":0.0,
		"shoulder":.98 if s.body=="pickup" else (.78 if s.body=="muscle" else (.76 if s.body=="coupe" else .80))},true)
	if EDITIONS.has(id): s.merge(EDITIONS[id],true)
	s.merge({"id":id, "bounds_size":s["size"], "bounds_center":[0,float(s["size"][1])*.5,0],
		"colors":PALETTES.get(id,[str(s.color)+"ff"]).duplicate(), "durability":roundi(210.0*sqrt(float(s.mass))),
		"max_speed":float(s.redline)*TAU*float(s.wheel_radius)/(60.0*float(s.gears[-1])*float(s.final_drive))*16.0,
		"acceleration":float(s.torque_nm)*4.0, "braking":1450.0, "drift_factor":.88,
		"roof_prop":"none", "vehicle_kind":"car", "engine_pitch":1.0,
		"turbo_audio":bool(s.get("factory_turbo",false)), "desert_car":true}, true)
	return s

static func create_model(id: String) -> Node3D:
	if id not in IDS: return null
	if not _model_cache.has(id):
		var source := preload("res://gameplay/desert_cars/DesertCarModel.gd").create(spec(id))
		for child in source.get_children(): child.owner=source
		var packed := PackedScene.new()
		packed.pack(source)
		source.free()
		_model_cache[id]=packed
	return _model_cache[id].instantiate() as Node3D

static func profile_for_vehicle(vehicle: Node) -> String:
	if not is_instance_valid(vehicle): return IDS[0]
	var id := str(vehicle.get_meta("desert_car_id", ""))
	if id in IDS: return id
	id = str(vehicle.get("archetype"))
	if id in IDS: return id
	if id.contains("pickup") or id.contains("jeep"): return "desert_bison"
	if id.contains("muscle") or id.contains("ironback") or id.contains("cobra_v8"): return "desert_coyote"
	if id.contains("coupe") or id.contains("350z") or id.contains("m8"): return "desert_mirage"
	if id.contains("jetta") or id.contains("sedan"): return "desert_siroco"
	return "desert_faisca"

static func parts_for_vehicle(vehicle: Node) -> Dictionary:
	if not is_instance_valid(vehicle): return {}
	var value: Variant = vehicle.get_meta("desert_parts", {})
	return value.duplicate(true) if value is Dictionary else {}

static func door_spec(id: String) -> Dictionary:
	if id not in IDS: return {}
	var s := spec(id)
	var l := float(s["size"][2])
	var w := float(s["size"][0])
	var body := str(s.body)
	var front := l*float(s.cabin_front)
	var rear := l*float(s.door_back)
	return {"class":"tall" if body=="pickup" else "car","zf":front,"zr":rear,"sill":float(s.wheel_radius)*.75,"belt":float(s.shoulder),"top":float(s["size"][1])-.05,"x":w*.48}

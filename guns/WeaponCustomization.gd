extends RefCounted
## Saved per weapon; purchased kits remain owned when removed.
const PRICE := 350
const COMPATIBLE := ["pistol", "magnum", "smg", "shotgun", "sawed_off", "ak47", "m4a1", "hunting_rifle", "flamethrower"]
const FIREARMS := ["pistol", "magnum", "smg", "shotgun", "sawed_off", "ak47", "m4a1", "hunting_rifle"]
const CUSTOMIZABLE := ["knuckles", "knife", "bat", "axe", "pistol", "magnum", "smg", "shotgun", "sawed_off", "ak47", "m4a1", "hunting_rifle", "flamethrower"]
const SLOTS := {"flashlight":"LANTERNA", "laser":"LASER", "muzzle":"CANO", "magazine":"CARREGADOR", "grip":"EMPUNHADURA", "stock":"CORONHA", "scope":"MIRA", "finish":"ACABAMENTO"}
const PARTS := {
	"flashlight": {"slot":"flashlight", "label":"Lanterna tática", "price":350},
	"laser_red": {"slot":"laser", "label":"Laser vermelho", "price":450},
	"laser_green": {"slot":"laser", "label":"Laser verde", "price":500},
	"suppressor": {"slot":"muzzle", "label":"Silenciador", "price":650},
	"extended": {"slot":"magazine", "label":"Capacidade ampliada", "price":500},
	"vertical_grip": {"slot":"grip", "label":"Empunhadura de controle", "price":400},
	"stabilized_stock": {"slot":"stock", "label":"Coronha estabilizada", "price":450},
	"scope_2x": {"slot":"scope", "label":"Luneta 2×", "price":900},
	"matte": {"slot":"finish", "label":"Preto fosco", "price":200, "color":Color("282d32")},
	"sand": {"slot":"finish", "label":"Areia", "price":200, "color":Color("b9a175")},
	"olive": {"slot":"finish", "label":"Verde militar", "price":200, "color":Color("596348")},
	"chrome": {"slot":"finish", "label":"Cromado", "price":350, "color":Color("b9c9d3")},
	"wood": {"slot":"finish", "label":"Madeira escura", "price":250, "color":Color("73452c")},
}
const GEO = preload("res://scripts/player/WeaponPresentation3D.gd")

static func supports(id: String, part: String) -> bool:
	if id not in CUSTOMIZABLE or not PARTS.has(part): return false
	match PARTS[part].slot:
		"finish": return true
		"flashlight": return id in COMPATIBLE
		"laser": return id in FIREARMS
		"muzzle": return id in ["pistol", "smg", "shotgun", "ak47", "m4a1", "hunting_rifle"]
		"magazine": return id in ["pistol", "smg", "shotgun", "ak47", "m4a1", "hunting_rifle"]
		"grip": return id in ["smg", "shotgun", "ak47", "m4a1"]
		"stock": return id in ["smg", "shotgun", "ak47", "m4a1", "hunting_rifle"]
		"scope": return id == "hunting_rifle"
	return false

static func selected(state: Dictionary, id: String, slot: String) -> String:
	if slot == "flashlight": return "flashlight" if installed(state,id) else "none"
	return str(state.get(id,{}).get("parts",{}).get(slot,"none"))

static func owns(state: Dictionary, id: String, part: String) -> bool:
	if part == "none": return true
	if part == "flashlight": return state.get(id,{}).get("owned",false) == true
	return part in state.get(id,{}).get("owned_parts",[])

static func effective_data(id: String, state: Dictionary) -> Dictionary:
	var data: Dictionary = WeaponCatalog.get_weapon(id).duplicate(true)
	if selected(state,id,"magazine") == "extended":
		data["magazine_size"] = int(data.get("magazine_size",0)) + (2 if id == "shotgun" else (3 if id == "hunting_rifle" else int(data.get("magazine_size",0))/2))
	data["reload_multiplier"] = 1.18 if selected(state,id,"magazine") == "extended" else 1.0
	data["recoil_multiplier"] = (0.75 if selected(state,id,"grip") != "none" else 1.0) * (0.85 if selected(state,id,"stock") != "none" else 1.0)
	data["spread"] = float(data.get("spread",0.0)) * float(data.recoil_multiplier)
	data["suppressed"] = selected(state,id,"muzzle") == "suppressor"
	data["hearing_radius"] = 80.0 if data.suppressed else 240.0
	return data

static func normalize(value: Variant) -> Dictionary:
	var result := {}
	if not value is Dictionary: return result
	for id in CUSTOMIZABLE:
		var entry: Variant = value.get(id, {})
		if not entry is Dictionary: continue
		var clean := {"owned": id in COMPATIBLE and entry.get("owned",false) == true, "installed":false,
			"owned_parts":[], "parts":{}}
		clean.installed = clean.owned and entry.get("installed",false) == true
		if entry.get("owned_parts",[]) is Array:
			for part in entry.get("owned_parts",[]):
				if part is String and supports(id,part) and part != "flashlight" and part not in clean.owned_parts: clean.owned_parts.append(part)
		if entry.get("parts",{}) is Dictionary:
			for slot in entry.get("parts",{}):
				var part: Variant = entry.parts[slot]
				if part in clean.owned_parts and PARTS[part].slot == slot: clean.parts[slot] = part
		if clean.owned or not clean.owned_parts.is_empty(): result[id] = clean
	return result

static func installed(state: Dictionary, id: String) -> bool:
	return id in COMPATIBLE and state.get(id, {}).get("installed", false) == true

static func fit(root: Node3D, id: String, state: Dictionary, muzzle: Vector3) -> void:
	preload("res://guns/WeaponAttachmentVisuals.gd").apply(root,id,state.get(id,{}),muzzle)
	if not installed(state, id): return
	var mount := Node3D.new()
	mount.name = "TacticalFlashlight"
	root.add_child(mount)
	# Side clamp clears shotgun pumps and the supporting hand.
	mount.position = Vector3(0.049, muzzle.y - 0.018, muzzle.z + 0.09)
	if id == "pistol": mount.position = Vector3(0.0, 0.006, muzzle.z + 0.04)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("242b30")
	metal.metallic = 0.65
	metal.roughness = 0.4
	GEO._box(mount, "Clamp", Vector3(0,0.019,0.018) if id == "pistol" else Vector3(-0.024,0,0.018), Vector3(0.04,0.025,0.028), metal)
	GEO._cylinder(mount, "Body", Vector3.ZERO, 0.019, 0.085, metal, Vector3(90,0,0))
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color("d9e6df")
	lens.metallic = 0.3
	lens.roughness = 0.15
	GEO._cylinder(mount, "Lens", Vector3(0,0,-0.043), 0.015, 0.002, lens, Vector3(90,0,0))

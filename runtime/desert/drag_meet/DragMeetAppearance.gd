extends RefCounted
## Authored encounter identities opt into the same imported bodies as the city.
## Select before adding the model: no disposable procedural or imported rig.
const CATALOG := preload("res://assets/civilians/CivilianBodyCatalog.gd")
const MODEL := preload("res://assets/CivilianModel.gd")

static func set_animation_active(model: Node3D, active: bool) -> void:
	if not is_instance_valid(model): return
	# Stopping CivilianModel alone leaves MeshyBodyRig's child PoseDriver
	# polling the unchanged joints. Keep the visible rig, suspend both writers.
	# Impact/fall owns pose independently and must never be frozen by distance.
	var reaction: bool = model.has_method("_pose_strictly_live") and model._pose_strictly_live()
	var actor: Node = model.get("_owner_actor")
	var dead: bool = is_instance_valid(actor) and actor.get("dead") == true
	model.set_process((active or reaction) and not dead)
	var rig = model.get("_meshy")
	if rig != null and is_instance_valid(rig.driver):
		rig.driver.set_process(active or reaction)

static func apply(model: Node3D) -> bool:
	if not CATALOG.enabled: return false
	var wardrobe: Dictionary = MODEL._appearance_wardrobe(model.appearance_variant,model.coat_color,model.pants_color,Color.TRANSPARENT,model.wardrobe_overrides)
	var candidates: Array[Dictionary] = []
	var closest := 99
	for entry in CATALOG.available():
		if bool(entry.female)!=bool(wardrobe.female): continue
		var distance := absi(int(entry.build)-int(wardrobe.build))
		if distance<closest:
			closest=distance
			candidates=[entry]
		elif distance==closest: candidates.append(entry)
	if candidates.is_empty(): return false
	var variant := absi(int(model.appearance_variant))
	var entry: Dictionary = candidates[variant%candidates.size()]
	model.body_source = CATALOG.FOLDER+str(entry.file)
	# Clothing and skin share an atlas: brightness only, never a team-color hue.
	model.body_tint = {"hue":0.0,"brightness":.94+float(variant%5)*.03}
	model.body_accessories = []
	if int(wardrobe.get("hat",0))>0:
		model.body_accessories.append({"kind":"cap","color":model.coat_color,"band":model.coat_color.darkened(.55)})
	if bool(wardrobe.get("glasses",false)): model.body_accessories.append({"kind":"sunglasses"})
	return true

extends RefCounted
## Identidades escritas do encontro optam pelos mesmos corpos importados da cidade.
## Escolhe antes de adicionar o modelo: sem rig procedural ou importado descartável.
const CATALOG := preload("res://assets/civilians/CivilianBodyCatalog.gd")
const MODEL := preload("res://assets/CivilianModel.gd")

static func set_animation_active(model: Node3D, active: bool) -> void:
	if not is_instance_valid(model): return
	# Parar só o CivilianModel deixa o PoseDriver filho do MeshyBodyRig
	# consultando as juntas inalteradas. Mantém o rig visível e suspende os dois escritores.
	# Impacto/queda é dono da pose de forma independente e nunca pode ser congelado pela distância.
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
	# Roupa e pele dividem um atlas: só brilho, nunca um matiz de cor de equipe.
	model.body_tint = {"hue":0.0,"brightness":.94+float(variant%5)*.03}
	model.body_accessories = []
	if int(wardrobe.get("hat",0))>0:
		model.body_accessories.append({"kind":"cap","color":model.coat_color,"band":model.coat_color.darkened(.55)})
	if bool(wardrobe.get("glasses",false)): model.body_accessories.append({"kind":"sunglasses"})
	return true

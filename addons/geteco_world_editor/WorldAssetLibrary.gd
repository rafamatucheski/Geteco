@tool
extends RefCounted
const DATA := preload("res://world/editing/WorldEditData.gd")
const PROPS := preload("res://world/editing/WorldPropFactory.gd")
static func normalized(value: String) -> String:
	var result := value.to_lower()
	for pair in [["á","a"],["à","a"],["ã","a"],["â","a"],["é","e"],["ê","e"],["í","i"],["ó","o"],["ô","o"],["õ","o"],["ú","u"],["ç","c"]]: result = result.replace(pair[0],pair[1])
	return result
static func entry(label: String,row: Dictionary,tags := "") -> Dictionary:
	return {"label":label,"row":row,"search":normalized(label+" "+tags+" "+str(row.get("model",""))),"type":row.type,"action":"place"}
static func build(catalog: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for spec in preload("res://world/urban_detail/UrbanLowriseCatalog.gd").PRESETS:
		var row := DATA.new_entity("building",Vector2.ZERO)
		row.merge({"model":spec[1],"size":spec[2].duplicate(),"height":spec[3],"color":spec[4]},true)
		var tags := "casa residencia" if str(spec[1]).begins_with("house_") else "galpao industrial"
		result.append(entry(spec[0],row,tags+" construcao janelas laterais"))
	for spec in preload("res://world/urban_detail/UrbanSkylineCatalog.gd").PRESETS:
		var row := DATA.new_entity("building",Vector2.ZERO)
		row.merge({"model":spec[1],"size":spec[2].duplicate(),"height":spec[3],"color":spec[4]},true)
		result.append(entry(spec[0],row,"predio urbano torre edificio fachada janelas laterais"))
	for spec in [["Comercial baixo","office",[10,8],6,"b4aa96"],["Comercial alto","office",[12,12],18,"82999e"],["Residencial tijolo","brownstone",[9,10],10,"926754"],["Residencial claro","brownstone",[12,8],7.5,"b4aa92"],["Galpão industrial","warehouse",[18,14],7,"788e89"],["Galpão pequeno","warehouse",[10,8],5,"a78769"],["Loja de esquina","corner_shop",[9,7],4,"77938a"],["Loja larga","corner_shop",[14,8],4.5,"b29a78"],["Casa dos Cobra","cobra_house",[8,10],6,"d1b797"],["Casa dos Cobra larga","cobra_house",[10,10],7,"91a78b"],["Prédio em L","l_shaped_block",[18,16],12,"b29981"]]:
		var row := DATA.new_entity("building",Vector2.ZERO)
		row.merge({"model":spec[1],"size":spec[2],"height":spec[3],"color":spec[4]},true)
		result.append(entry(spec[0],row,"predio construcao edificio fachada"))
	var footbridge := DATA.new_entity("prop",Vector2.ZERO)
	footbridge.merge({"model":"footbridge","color":"3f6e8c","size":[2.6,34.6]},true)
	result.append(entry("Passarela de pedestres",footbridge,"passarela ponte pedestre travessia viaduto escada rua"))
	for spec in [["Pallet de madeira","pallet","a98857"],["Pilha de pallets","pallet_stack","a98857"],["Caixote de madeira","crate","9b7950"],["Tambor enferrujado","barrel","9d593c"],["Tambor azul","barrel","486d81"],["Caçamba de lixo","dumpster","4b7260"],["Sacos de lixo","trash_bags","313b37"],["Lixeira verde","bin","537d50"],["Barreira de concreto","barrier","97998d"]]:
		var row := DATA.new_entity("prop",Vector2.ZERO)
		var size: Vector2 = PROPS.SIZES[spec[1]]
		row.merge({"model":spec[1],"color":spec[2],"size":[size.x,size.y]},true)
		result.append(entry(spec[0],row,"objeto decoracao rua sucata"))
	for snow in [false,true]:
		for variant in 8:
			var row := DATA.new_entity("tree",Vector2.ZERO)
			row.variant = variant
			row.snow = snow
			result.append(entry("Pinheiro %d%s" % [variant+1," com neve" if snow else ""],row,"arvore vegetacao montanha"))
	for index in preload("res://world/editing/WorldGroundFactory.gd").SURFACES.size():
		var ground := preload("res://world/editing/WorldGroundFactory.gd")
		var row := DATA.new_entity("ground",Vector2.ZERO)
		row.surface = ground.SURFACES[index]
		result.append(entry(ground.LABELS[index],row,"terreno chao piso solo superficie"))
	var seen := {}
	for area in catalog:
		for row in catalog[area].get("objects",{}).values():
			if row.type != "tree" or row.get("tree_model","") != "harbor": continue
			var key := str(row.variant)
			if seen.has(key): continue
			seen[key] = true
			result.append(entry("Árvore urbana "+str(int(row.variant)+1),row.duplicate(true),"harbor arvore"))
	for surface in ["asphalt","earth"]:
		var row := DATA.new_entity("road",Vector2.ZERO)
		row.surface = surface
		result.append(entry("Rua de asfalto" if surface == "asphalt" else "Rua de terra",row,"via estrada caminho"))
	result.append(entry("Poste de luz quente",DATA.new_entity("light",Vector2.ZERO),"luz iluminacao"))
	return result

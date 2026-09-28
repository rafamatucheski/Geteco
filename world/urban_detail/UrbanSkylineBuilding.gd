extends "res://world/urban_detail/UrbanBuildingBase.gd"
## Solid exterior assets. Details are batched per material; no frame callbacks,
## lights, viewports or invented interior entrances.
var _batches: Dictionary = {}
# Portas e persianas reservam o trecho da fachada antes das janelas serem
# distribuídas; sem isso a grade do térreo nascia por cima da entrada.
var _openings: Array = []

func build() -> void:
	_openings.clear()
	match building_kind:
		"urban_setback": _setback()
		"urban_twin": _twin()
		"urban_slab": _slab()
		"urban_deco": _deco()
		"urban_infill": _infill()
		"urban_podium": _podium()
	_flush_details()

func _block(label: String, center: Vector3, size: Vector3, color: Color, style: String = "regular", floor_count: int = 0) -> void:
	add_solid_box(visuals_root,label,center,size,wall_material(color))
	var top := center.y+size.y*.5
	var bottom := center.y-size.y*.5
	var trim := UrbanMaterials.trim_stone()
	_detail(Vector3(center.x,top-.10,center.z),Vector3(size.x+.12,.20,size.z+.12),trim)
	_detail(Vector3(center.x,top+.015,center.z),Vector3(maxf(.1,size.x-.24),.03,maxf(.1,size.z-.24)),UrbanMaterials.roof_tar())
	var floors := floor_count if floor_count > 0 else maxi(1,floori(size.y/2.8))
	var pitch := size.y/float(floors)
	for floor_index in floors:
		var y := bottom+(floor_index+.52)*pitch
		for side in [-1,1]:
			_facade(label+str(floor_index)+"z"+str(side),Vector3(center.x,y,center.z+side*(size.z*.5+.025)),size.x,pitch,false,style)
			_facade(label+str(floor_index)+"x"+str(side),Vector3(center.x+side*(size.x*.5+.025),y,center.z),size.z,pitch,true,style)
		if style == "glass" or style == "bands":
			_detail(Vector3(center.x,bottom+floor_index*pitch+.10,center.z),Vector3(size.x+.10,.16,size.z+.10),UrbanMaterials.trim_dark())

func _facade(key: String, at: Vector3, width: float, pitch: float, sideways: bool, style: String) -> void:
	var columns := maxi(1,floori(width/(1.7 if style == "glass" else 2.6)))
	var step := width/float(columns)
	var window_width := step*(.85 if style == "glass" else .52)
	var window_height := pitch*(.76 if style == "glass" else .53)
	for column in columns:
		var offset := -width*.5+(column+.5)*step
		var pos := at+Vector3(0,0,offset) if sideways else at+Vector3(offset,0,0)
		if _blocked(pos,sideways,window_width,window_height): continue
		var frame_size := Vector3(.12,window_height+.16,window_width+.16) if sideways else Vector3(window_width+.16,window_height+.16,.12)
		_detail(pos,frame_size,UrbanMaterials.trim_dark())
		# Pane is centered on the facade with visible faces beyond the frame.
		var pane_size := Vector3(.135,window_height,window_width) if sideways else Vector3(window_width,window_height,.135)
		_detail(pos,pane_size,window_glass_material(key+str(column),.22))
		if style != "glass":
			var sill := Vector3(.22,.10,window_width+.26) if sideways else Vector3(window_width+.26,.10,.22)
			_detail(pos-Vector3(0,window_height*.5+.06,0),sill,UrbanMaterials.trim_stone())

func _reserve(sideways: bool, face: float, along: float, width: float, top: float) -> void:
	_openings.append({"sideways":sideways,"face":face,"along":along,"width":width,"top":top})

func _blocked(pos: Vector3, sideways: bool, window_width: float, window_height: float) -> bool:
	var face := pos.x if sideways else pos.z
	var along := pos.z if sideways else pos.x
	for opening in _openings:
		if opening.sideways != sideways or absf(face-opening.face) > .6: continue
		if absf(along-opening.along) > window_width*.5+opening.width*.5+.18: continue
		if pos.y-window_height*.5 < opening.top+.25: return true
	return false

# Chamada antes dos blocos para reservar o vão da porta na grade de janelas.
func _entry(width: float = 1.8, facade_z: float = INF, x: float = 0.0) -> void:
	var z := (building_size.y*.5 if is_inf(facade_z) else facade_z)+.04
	var h := minf(2.5,height*.65)
	_reserve(false,z,x,width+.6,h+.3)
	_detail(Vector3(x,.06,z+.45),Vector3(width+.8,.12,.9),UrbanMaterials.trim_stone())
	_detail(Vector3(x,h*.5,z),Vector3(width+.2,h+.1,.16),UrbanMaterials.trim_dark())
	_detail(Vector3(x,h*.5,z+.09),Vector3(width*.83,h*.9,.05),UrbanMaterials.glass_window())
	_detail(Vector3(x,h*.5,z+.13),Vector3(.07,h,.06),UrbanMaterials.metal_steel())
	_detail(Vector3(x,h+.22,z+.25),Vector3(width+1.0,.18,.85),UrbanMaterials.trim_stone())

func _plinth(center: Vector3, size: Vector3) -> void:
	# Embasamento escuro: sem ele o volume parece pousado no asfalto.
	_detail(Vector3(center.x,.22,center.z),Vector3(size.x+.10,.44,size.z+.10),UrbanMaterials.trim_dark())

func _rooftop(top: Vector3, size: Vector3, tank: bool = true) -> void:
	if size.x < 3.0 or size.z < 3.0: return
	var steel := UrbanMaterials.metal_steel()
	var dark := UrbanMaterials.trim_dark()
	for index in 2:
		var at := top+Vector3(size.x*(.28-index*.18),.35,size.z*(.26-index*.08))
		_detail(at,Vector3(.95,.62,.72),steel)
		_detail(at+Vector3(0,.33,0),Vector3(.7,.05,.5),dark)
	if tank and size.x > 4.5:
		var tank_at := top+Vector3(-size.x*.24,1.35,-size.z*.18)
		_detail(tank_at,Vector3(1.6,1.3,1.6),UrbanMaterials.roof_tin_rusty())
		_detail(tank_at+Vector3(0,.7,0),Vector3(1.75,.08,1.75),dark)
		for corner in [Vector2(-1,-1),Vector2(-1,1),Vector2(1,-1),Vector2(1,1)]:
			_detail(top+Vector3(-size.x*.24+corner.x*.65,.36,-size.z*.18+corner.y*.65),Vector3(.10,.72,.10),dark)
	_detail(top+Vector3(size.x*.32,1.6,-size.z*.30),Vector3(.06,3.2,.06),steel)
	_detail(top+Vector3(-size.x*.05,.22,size.z*.34),Vector3(size.x*.30,.44,.16),dark)

func _setback() -> void:
	var w := building_size.x
	var d := building_size.y
	_entry()
	_block("LowerTower",Vector3(0,height*.25,0),Vector3(w,height*.5,d),accent_color,"bands")
	_plinth(Vector3.ZERO,Vector3(w,0,d))
	_block("MiddleTower",Vector3(0,height*.685,-d*.05),Vector3(w*.76,height*.37,d*.76),accent_color.lightened(.09))
	_block("Crown",Vector3(0,height*.935,-d*.07),Vector3(w*.48,height*.13,d*.48),accent_color.darkened(.12))
	# Equipamento no terraço do recuo; a coroa fica limpa.
	_rooftop(Vector3(0,height*.87+.03,-d*.05),Vector3(w*.76,0,d*.76))

func _twin() -> void:
	var w := building_size.x
	var d := building_size.y
	var base_h := height*.16
	_entry(2.1)
	_block("SharedBase",Vector3(0,base_h*.5,0),Vector3(w,base_h,d),accent_color.darkened(.16),"glass")
	for side in [-1,1]:
		var tower_h := height-base_h
		_block("Tower"+str(side),Vector3(side*w*.29,base_h+tower_h*.5,-d*.06),Vector3(w*.34,tower_h,d*.73),accent_color,"glass")
		_rooftop(Vector3(side*w*.29,height+.03,-d*.06),Vector3(w*.34,0,d*.73),side == 1)
	# Passarela envidraçada entre as torres dá leitura de conjunto.
	var bridge_y := base_h+(height-base_h)*.55
	var gap := w*.26
	_detail(Vector3(0,bridge_y,-d*.06),Vector3(gap,2.4,d*.30),UrbanMaterials.glass_window())
	for edge in [-1,1]:
		_detail(Vector3(0,bridge_y+edge*1.25,-d*.06),Vector3(gap,.14,d*.32),UrbanMaterials.trim_dark())

func _slab() -> void:
	var w := building_size.x
	var d := building_size.y
	_entry(1.8,d*.36)
	_block("ResidentialBody",Vector3(0,height*.5,-d*.07),Vector3(w,height,d*.86),accent_color)
	var floors := maxi(1,floori(height/3.0))
	var pitch := height/float(floors)
	var bays := maxi(1,floori(w/3.4))
	var bay_w := w/float(bays)
	for level in range(1,floors):
		for bay in bays:
			var x := -w*.5+(bay+.5)*bay_w
			var y := level*pitch
			_detail(Vector3(x,y,d*.43),Vector3(bay_w-.18,.17,d*.14),UrbanMaterials.trim_stone())
			_detail(Vector3(x,y+.55,d*.495),Vector3(bay_w-.18,1.0,.10),UrbanMaterials.trim_stone())
			_detail(Vector3(x-bay_w*.5+.12,y+.55,d*.43),Vector3(.10,1.0,d*.14),UrbanMaterials.trim_stone())
	# Balcony slab/rail envelope is above street level and backed by solid rooms.
	_plinth(Vector3(0,0,-d*.07),Vector3(w,0,d*.86))
	_rooftop(Vector3(0,height+.03,-d*.07),Vector3(w,0,d*.86))

func _deco() -> void:
	var w := building_size.x
	var d := building_size.y
	_entry()
	_block("StoneShaft",Vector3(0,height*.39,0),Vector3(w,height*.78,d),accent_color)
	_block("Lantern",Vector3(0,height*.86,0),Vector3(w*.70,height*.16,d*.70),accent_color.lightened(.12))
	_block("Cap",Vector3(0,height*.97,0),Vector3(w*.40,height*.06,d*.40),accent_color.darkened(.14))
	for side in [-1,1]:
		for index in [-1,0,1]:
			# A pilastra central da frente cairia no meio da porta.
			var bottom := 3.2 if side == 1 and index == 0 else 0.0
			_detail(Vector3(index*w*.30,(bottom+height*.84)*.5,side*(d*.5+.08)),Vector3(.26,height*.84-bottom,.22),UrbanMaterials.trim_stone())
	_plinth(Vector3.ZERO,Vector3(w,0,d))
	_detail(Vector3(0,height+1.4,0),Vector3(.10,2.8,.10),UrbanMaterials.metal_steel())

func _infill() -> void:
	var w := building_size.x
	var d := building_size.y
	# Porta na primeira coluna: prédio estreito com entrada lateral na frente.
	var column := w/float(maxi(1,floori(w/2.6)))
	_entry(minf(1.4,column*.6),INF,-w*.5+column*.5)
	_block("BrickInfill",Vector3(0,height*.5,0),Vector3(w,height,d),accent_color)
	var trim := UrbanMaterials.trim_stone()
	for y in [height*.16,height-.15,height+.12]:
		_detail(Vector3(0,y,d*.5+.08),Vector3(w+.2,.23,.32),trim)
	for side in [-1,1]:
		_detail(Vector3(side*(w*.5-.18),height*.5,d*.5+.06),Vector3(.28,height,.18),trim)
	# Escada de incêndio na lateral, típica do prédio estreito de tijolos.
	var dark := UrbanMaterials.trim_dark()
	var floors := maxi(1,floori(height/2.8))
	for level in range(1,floors):
		var y := level*height/float(floors)
		_detail(Vector3(w*.5+.55,y,d*.12),Vector3(1.0,.08,d*.42),dark)
		_detail(Vector3(w*.5+1.02,y+.5,d*.12),Vector3(.05,1.0,d*.42),dark)
	_detail(Vector3(w*.5+.78,height*.5,d*.12),Vector3(.06,height*.9,.06),dark)
	_plinth(Vector3.ZERO,Vector3(w,0,d))
	_rooftop(Vector3(0,height+.03,0),Vector3(w,0,d))

func _podium() -> void:
	var w := building_size.x
	var d := building_size.y
	var base_h := height*.18
	_entry(2.4)
	_block("RetailPodium",Vector3(0,base_h*.5,0),Vector3(w,base_h,d),accent_color.darkened(.22),"glass")
	_block("GlassTower",Vector3(w*.09,base_h+(height-base_h)*.5,-d*.07),Vector3(w*.58,height-base_h,d*.66),accent_color,"glass")
	for side in [-1,1]:
		_detail(Vector3(w*.09+side*w*.29,height*.59,-d*.07),Vector3(.22,height*.82,.28),UrbanMaterials.metal_steel())
	# Toldos da base comercial, deixando livre o vão da entrada.
	for side in [-1,1]:
		_detail(Vector3(side*w*.30,minf(3.0,base_h*.8),d*.5+.55),Vector3(w*.30,.12,1.1),UrbanMaterials.roof_tin_rusty())
	_rooftop(Vector3(w*.09,height+.03,-d*.07),Vector3(w*.58,0,d*.66))

func _detail(center: Vector3, size: Vector3, material: Material) -> void:
	var key := material.get_instance_id()
	if not _batches.has(key): _batches[key] = {"material":material,"transforms":[]}
	_batches[key].transforms.append(Transform3D(Basis.from_scale(size),center))

func _flush_details() -> void:
	for batch in _batches.values():
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE
		multimesh.mesh = cube
		multimesh.instance_count = batch.transforms.size()
		for index in batch.transforms.size(): multimesh.set_instance_transform(index,batch.transforms[index])
		var instance := MultiMeshInstance3D.new()
		instance.name = "FacadeBatch"
		instance.multimesh = multimesh
		instance.material_override = batch.material
		# The headless preview builder has a dummy renderer: MultiMesh reads
		# lose their transforms. Carry the CPU copy to the editor snapshot.
		if Engine.has_meta("geteco_live_preview_build"):
			instance.set_meta("preview_instance_transforms",batch.transforms)
		visuals_root.add_child(instance)
	_batches.clear()

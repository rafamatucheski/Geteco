extends RefCounted
## Pure spatial storage. Callers commit a whole candidate only after success.
const WEAPONS := preload("res://gameplay/WeaponCatalog.gd")
const LONG := ["shotgun","sawed_off","ak47","m4a1","hunting_rifle","rpg","flamethrower"]
const TRUNK_SIZE := Vector2i(4,6)
const TRUNK_AMMO_SLOTS := 6
const ITEMS := {
	"apple":{"label":"Maçã","description":"Uma maçã fresca. Recupera 8 de vida.","heal":8,"stack":5,"icon":"apple"},
	"water":{"label":"Água","description":"Uma garrafa de água. Recupera 5 de vida.","heal":5,"stack":5,"icon":"water"},
	"sandwich":{"label":"Sanduíche","description":"Um lanche embalado. Recupera 20 de vida.","heal":20,"stack":5,"icon":"sandwich"},
	"first_aid":{"label":"Primeiros socorros","description":"Recupera 40 de vida.","heal":40,"stack":5,"icon":"med"},
	"lockpick":{"label":"Gazua","description":"Usada para abrir fechaduras.","stack":10,"icon":"key"},
	"garage_part":{"label":"Peça da garagem","description":"Entregue a peça ao Maciota.","quest":true,"stack":1,"icon":"scrap"},
	"backpack":{"label":"Mochila","description":"12 espaços. Deixa as mãos livres.","stack":1,"icon":"bag"},
	"handbag":{"label":"Mala de mão","description":"24 espaços. Ocupa uma mão e impede o uso de armas longas.","stack":1,"icon":"case"},
}

static func spec(id: String) -> Dictionary:
	if id.begins_with("weapon:"):
		var weapon := id.trim_prefix("weapon:")
		if not WEAPONS.WEAPONS.has(weapon): return {}
		return {"label":str(WEAPONS.WEAPONS[weapon].label).capitalize(),"description":"Munição vinculada à arma: até 99 tiros. O excedente ocupa espaço na bagagem.","w":4 if weapon in LONG else 2,"h":1,"stack":1,"icon":weapon,"weapon":weapon}
	if id.begins_with("ammo:"):
		var weapon := id.trim_prefix("ammo:")
		if not WEAPONS.WEAPONS.has(weapon) or int(WEAPONS.WEAPONS[weapon].magazine_size)<0: return {}
		return {"label":"Munição · "+str(WEAPONS.WEAPONS[weapon].short_label),"description":"Reserva para esta arma. Até 99 tiros por bloco.","stack":99,"icon":"ammo","ammo":weapon}
	if ITEMS.has(id): return ITEMS[id]
	if id.is_empty() or id.length()>128: return {}
	return {"label":id.replace("_"," ").capitalize(),"description":"Item guardado para uso durante a jornada.","stack":1,"quest":true,"icon":"quest"}

static func empty() -> Dictionary:
	return {"version":2,"bag":"","pockets":[],"storage":[],"trunk":[],"ground":[],"claimed":[],"serial":0}

static func dimensions(data: Dictionary, container: String) -> Vector2i:
	match container:
		"pockets": return Vector2i(2,1)
		"storage": return Vector2i(4,3 if data.bag=="backpack" else 6 if data.bag=="handbag" else 0)
		"trunk": return TRUNK_SIZE
	return Vector2i.ZERO

static func accepts(container: String,id: String) -> bool:
	return container!="trunk" or id.begins_with("weapon:") or id.begins_with("ammo:")

static func ammo_slots(entries: Array, ignored := -1) -> int:
	var local_count:=0
	for i in entries.size():
		if i!=ignored and str(entries[i].id).begins_with("ammo:"): local_count+=1
	return local_count

static func extent(entry: Dictionary) -> Vector2i:
	var definition := spec(str(entry.id))
	var size := Vector2i(int(definition.get("w",1)),int(definition.get("h",1)))
	return Vector2i(size.y,size.x) if entry.get("rotated",false) else size

static func fits(entries: Array, bounds: Vector2i, item: Dictionary, cell: Vector2i, ignored := -1) -> bool:
	var rect := Rect2i(cell,extent(item))
	if cell.x<0 or cell.y<0 or rect.end.x>bounds.x or rect.end.y>bounds.y: return false
	for i in entries.size():
		if i==ignored: continue
		var other: Dictionary = entries[i]
		if rect.intersects(Rect2i(Vector2i(int(other.x),int(other.y)),extent(other))): return false
	return true

static func find_cell(entries: Array, bounds: Vector2i, item: Dictionary) -> Vector2i:
	var occupied := {}
	for entry in entries:
		var branch_size:=extent(entry)
		for dy in branch_size.y:
			for dx in branch_size.x: occupied[Vector2i(int(entry.x)+dx,int(entry.y)+dy)]=true
	var size:=extent(item)
	for y in bounds.y:
		for x in bounds.x:
			if x+size.x>bounds.x or y+size.y>bounds.y: continue
			var available:=true
			for dy in size.y:
				for dx in size.x:
					if occupied.has(Vector2i(x+dx,y+dy)): available=false; break
				if not available: break
			if available: return Vector2i(x,y)
	return Vector2i(-1,-1)

static func add(data: Dictionary, container: String, id: String, amount: int) -> int:
	var definition := spec(id)
	if amount<=0 or definition.is_empty() or not data.has(container) or not accepts(container,id): return amount
	var entries: Array = data[container]
	var limit := int(definition.get("stack",1))
	for entry in entries:
		if entry.id!=id: continue
		var moved := mini(amount,limit-int(entry.amount))
		entry.amount += moved
		amount -= moved
		if amount==0: return 0
	while amount>0:
		if container=="trunk" and id.begins_with("ammo:") and ammo_slots(entries)>=TRUNK_AMMO_SLOTS: break
		var entry := {"id":id,"amount":mini(amount,limit),"x":0,"y":0,"rotated":false}
		var cell := find_cell(entries,dimensions(data,container),entry)
		if cell.x<0: break
		entry.x=cell.x; entry.y=cell.y
		entries.append(entry)
		amount -= int(entry.amount)
	return amount

static func add_carried(data: Dictionary, id: String, amount: int) -> int:
	return add(data,"storage",id,add(data,"pockets",id,amount))

static func count(data: Dictionary, id: String, carried_only := true) -> int:
	var amount := 0
	for container in (["pockets","storage"] if carried_only else ["pockets","storage","trunk"]):
		for entry in data[container]:
			if entry.id==id: amount += int(entry.amount)
	if not carried_only:
		for drop in data.ground:
			for entry in drop.entries:
				if entry.id==id: amount += int(entry.amount)
	return amount

static func remove_carried(data: Dictionary, id: String, amount: int) -> bool:
	if amount<=0 or count(data,id)<amount: return false
	for container in ["pockets","storage"]:
		var entries: Array = data[container]
		for i in range(entries.size()-1,-1,-1):
			if entries[i].id!=id: continue
			var take := mini(amount,int(entries[i].amount))
			entries[i].amount-=take; amount-=take
			if entries[i].amount==0: entries.remove_at(i)
			if amount==0: return true
	return false

static func move(data: Dictionary, source: String, index: int, target: String, cell := Vector2i(-1,-1), rotate := false) -> bool:
	if source not in ["pockets","storage","trunk"] or target not in ["pockets","storage","trunk"]: return false
	if index<0 or index>=data[source].size(): return false
	var entry: Dictionary = data[source][index].duplicate(true)
	if not accepts(target,str(entry.id)): return false
	if rotate: entry.rotated=not bool(entry.rotated)
	if cell.x<0:
		if source==target: return false
		if add(data,target,str(entry.id),int(entry.amount))!=0: return false
	else:
		if target=="trunk" and str(entry.id).begins_with("ammo:") and ammo_slots(data.trunk,index if source==target else -1)>=TRUNK_AMMO_SLOTS: return false
		if not fits(data[target],dimensions(data,target),entry,cell,index if source==target else -1): return false
		entry.x=cell.x; entry.y=cell.y
		if source==target: data[source][index]=entry; return true
		data[target].append(entry)
	data[source].remove_at(index)
	return true

static func validate(data: Variant) -> bool:
	if not data is Dictionary or not _integer(data.get("version"),1,2) or data.get("bag") not in ["","backpack","handbag"]: return false
	if not _integer(data.get("serial"),0,100000000): return false
	for container in ["pockets","storage","trunk"]:
		var bounds:=Vector2i(4,2500) if container=="trunk" and data.version==1 else dimensions(data,container)
		if not validate_entries(data.get(container),bounds): return false
	if data.version==2:
		for entry in data.trunk:
			if not accepts("trunk",str(entry.id)): return false
		if ammo_slots(data.trunk)>TRUNK_AMMO_SLOTS: return false
	if not data.get("ground") is Array or data.ground.size()>512 or not data.get("claimed") is Array or data.claimed.size()>4096: return false
	var ids := {}
	for id in data.claimed:
		if not id is String or id.is_empty() or id.length()>128 or ids.has(id): return false
		ids[id]=true
	ids.clear()
	for drop in data.ground:
		if not drop is Dictionary or not _integer(drop.get("uid"),1,int(data.serial)) or ids.has(int(drop.uid)): return false
		ids[int(drop.uid)]=true
		if drop.get("bag") not in ["backpack","handbag"] or not drop.get("region") is String or not drop.get("place") is String: return false
		if not drop.get("position") is Array or drop.position.size()!=3: return false
		for v in drop.position:
			if typeof(v) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(v)) or absf(float(v))>100000: return false
		if not validate_entries(drop.get("entries"),Vector2i(4,3 if drop.bag=="backpack" else 6)): return false
	return true

static func validate_entries(entries: Variant, bounds: Vector2i) -> bool:
	if not entries is Array or entries.size()>10000: return false
	var occupied: Dictionary={}
	for i in entries.size():
		var e: Variant = entries[i]
		if not e is Dictionary or not e.get("id") is String or spec(e.id).is_empty() or not e.get("rotated") is bool: return false
		if not _integer(e.get("amount"),1,int(spec(e.id).get("stack",1))) or not _integer(e.get("x"),0,3) or not _integer(e.get("y"),0,2499): return false
		var size:=extent(e)
		if int(e.x)+size.x>bounds.x or int(e.y)+size.y>bounds.y: return false
		for dy in size.y:
			for dx in size.x:
				var cell:=Vector2i(int(e.x)+dx,int(e.y)+dy)
				if occupied.has(cell): return false
				occupied[cell]=true
	return true

static func _integer(v: Variant, low: int, high: int) -> bool:
	return typeof(v) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(v)) and float(v)==floorf(float(v)) and v>=low and v<=high

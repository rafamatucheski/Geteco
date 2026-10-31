extends RefCounted
const GRID:=preload("res://systems/inventory/GridInventory.gd")
const WEAPONS:=preload("res://gameplay/WeaponCatalog.gd")
## Inventário congelado do antigo cheat de arsenal persistente. Adicionar novas armas
## à loja não pode impedir o reconhecimento de um save feito por aquela versão.
const LEGACY_ARSENAL := ["fists","knuckles","knife","bat","axe","katana","pistol","magnum","smg","shotgun","sawed_off","ak47","m4a1","rpg","flamethrower","grenade","hunting_rifle"]

static func upgrade(wallet: Dictionary) -> Dictionary:
	var data:=wallet.duplicate(true)
	var grid: Dictionary=data.get("grid_inventory",{})
	if not grid.is_empty() and int(grid.version)>=2: return data
	# O arsenal antigo gravava 9999 tiros para toda arma. Exige o arsenal
	# inteiro e pelo menos seis reservas enormes; uma compra grande comum
	# não é prova de cheat. Preserva a posse das armas e a munição paga.
	var massive:=0
	var full_arsenal:=true
	for id in LEGACY_ARSENAL:
		if not data.weapons.has(id): full_arsenal=false; continue
		var ammo: Dictionary=data.weapons[id]
		var total:=int(ammo.reserve)+int(ammo.magazine)
		if not grid.is_empty(): total+=GRID.count(grid,"ammo:"+id,false)
		if total>=9000: massive+=1
	if full_arsenal and massive>=6:
		for id in data.weapons:
			if int(data.weapons[id].magazine)<0: continue
			var paid:=0
			for receipt in data.transactions.values():
				if receipt.kind=="ammo" and receipt.item==id: paid+=int(receipt.rounds)
			if not grid.is_empty():
				for entries in [grid.pockets,grid.storage,grid.trunk]: _remove_ammo(entries,id)
				for drop in grid.ground: _remove_ammo(drop.entries,id)
			data.weapons[id].reserve=maxi(0,99-int(data.weapons[id].magazine))
			if not grid.is_empty() and paid>0: store_remainder(grid,"ammo:"+id,paid)
			elif paid>0: data.weapons[id].reserve+=paid
	if grid.is_empty(): return data
	var old: Array=grid.trunk.duplicate(true)
	grid.trunk=[]; grid.version=2
	# Põe as armas primeiro para que enxurradas de munição antiga não tirem espaço do arsenal.
	for entry in old:
		if str(entry.id).begins_with("weapon:"): store_remainder(grid,str(entry.id),int(entry.amount))
	for entry in old:
		if str(entry.id).begins_with("weapon:"): continue
		var left:=int(entry.amount)
		if not GRID.accepts("trunk",str(entry.id)): left=GRID.add_carried(grid,str(entry.id),left)
		store_remainder(grid,str(entry.id),left)
	return data

static func _remove_ammo(entries: Array,id: String) -> void:
	for i in range(entries.size()-1,-1,-1):
		if entries[i].id=="ammo:"+id: entries.remove_at(i)

static func store_remainder(grid: Dictionary,id: String,amount: int) -> void:
	amount=GRID.add(grid,"trunk",id,amount)
	while amount>0:
		var bag:=GRID.empty(); bag.bag="handbag"
		var drop: Dictionary={}
		if not grid.ground.is_empty() and grid.ground.back().get("pending",false):
			drop=grid.ground.back(); bag.storage=drop.entries
		var left:=GRID.add(bag,"storage",id,amount)
		if left==amount or drop.is_empty():
			bag.storage=[]; left=GRID.add(bag,"storage",id,amount)
			grid.serial+=1
			drop={"uid":grid.serial,"bag":"handbag","region":"","place":"","position":[0.0,0.0,0.0],"entries":bag.storage,"pending":true}
			grid.ground.append(drop)
		amount=left

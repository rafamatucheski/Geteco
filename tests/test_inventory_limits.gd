extends SceneTree
const ECONOMY=preload("res://systems/economy/Economy.gd")
const GRID=preload("res://systems/inventory/GridInventory.gd")
const WEAPONS=preload("res://gameplay/WeaponCatalog.gd")
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
	print("LIMITS ","PASS " if ok else "FAIL ",label)
func run() -> void:
	var e=ECONOMY.new(); e.enable_grid_inventory(); e.grid_equip_bag("backpack"); e.grant_weapon("pistol")
	e.grant_item("apple",3); e.grant_item("garage_part"); e.grant_item("water")
	for id in ["apple","water","garage_part","lockpick","handbag"]:
		var grid: Dictionary=e.grid_snapshot()
		check(GRID.add(grid,"trunk",id,1)==1 and grid.trunk.is_empty(),"trunk refuses "+id)
	var grid:=GRID.empty()
	check(GRID.add(grid,"trunk","ammo:pistol",600)==6 and grid.trunk.size()==6,"only six 99-round ammo stacks")
	check(GRID.add(grid,"trunk","weapon:ak47",1)==0,"guns fit alongside ammunition")
	var ammo_grid:=grid.duplicate(true); ammo_grid.trunk[0].amount=98
	check(GRID.add(ammo_grid,"trunk","ammo:pistol",1)==0 and GRID.ammo_slots(ammo_grid.trunk)==6,"fill existing stack at limit")
	check(GRID.add(grid,"trunk","ammo:magnum",1)==1,"seventh ammo stack rejected for another caliber")
	grid=GRID.empty()
	for i in 6: GRID.add(grid,"trunk","weapon:ak47",1)
	check(GRID.add(grid,"trunk","weapon:pistol",1)==1,"24-cell trunk has a hard spatial limit")
	check(GRID.validate(JSON.parse_string(JSON.stringify(e.grid_snapshot()))),"v2 grid JSON roundtrip")
	var before: Dictionary=e.snapshot()
	e.activate_arsenal_cheat(); e.equip_weapon("rpg"); e.consume_ammo("rpg"); e.reload_weapon("rpg")
	check(e.get_ammo("rpg").reserve==9999,"cheat still works in live session")
	check(e.snapshot()==before,"cheat weapon, ammo and selection never enter save")
	check(not e.grid_store_weapon("rpg","trunk"),"temporary weapon cannot enter trunk")
	check(e.grant_weapon("magnum"),"legitimate reward can be granted during cheat")
	check(e.snapshot().weapons.has("magnum"),"legitimate grant persists during cheat")
	check(e.restore_snapshot(JSON.parse_string(JSON.stringify(e.snapshot()))) and not e.cheat_all_weapons,"restore clears temporary arsenal")
	check(not e.owns_weapon("rpg") and e.owns_weapon("magnum"),"restored ownership excludes temporary guns")
	var uid: int=e.grid_drop_bag("harbor","",Vector3(2,0,3))
	var copy=ECONOMY.new()
	check(copy.restore_snapshot(JSON.parse_string(JSON.stringify(e.snapshot()))) and copy.grid_recover_bag(uid),"drop and recovery survive JSON migration version")
	# Real old-format spatial signature: all guns, thousands of rounds per gun.
	var old=ECONOMY.new(); old.enable_personal_loadout()
	var wallet: Dictionary=old.snapshot(); wallet.grid_inventory=GRID.empty(); wallet.grid_inventory.version=1
	var y:=0
	for id in WEAPONS.ORDER:
		if id=="fists": continue
		var mag:=mini(99,int(WEAPONS.WEAPONS[id].magazine_size))
		wallet.weapons[id]={"magazine":mag,"reserve":99-mag if mag>=0 else -1}
		wallet.grid_inventory.trunk.append({"id":"weapon:"+id,"amount":1,"x":0,"y":y,"rotated":false}); y+=1
		if mag<0: continue
		for i in 101:
			wallet.grid_inventory.trunk.append({"id":"ammo:"+id,"amount":99,"x":0,"y":y,"rotated":false}); y+=1
	wallet.inventory={"apple":3,"garage_part":1}
	for id in wallet.inventory:
		wallet.grid_inventory.trunk.append({"id":id,"amount":wallet.inventory[id],"x":0,"y":y,"rotated":false}); y+=1
	wallet.transactions["ammo:paid"]={"kind":"ammo","item":"pistol","amount":198,"rounds":99}
	check(ECONOMY.validate_snapshot(wallet),"old flooded save fixture is valid")
	check(copy.restore_snapshot(wallet),"old flooded save restores")
	check(copy.grid_snapshot().version==2 and ECONOMY.validate_snapshot(copy.snapshot()),"migration publishes a valid finite save")
	check(GRID.count(copy.grid_snapshot(),"ammo:pistol",false)==99,"paid ammunition survives cheat cleanup")
	check(GRID.count(copy.grid_snapshot(),"ammo:ak47",false)==0,"synthetic cheat ammunition removed")
	check(GRID.count(copy.grid_snapshot(),"apple",false)==3 and GRID.count(copy.grid_snapshot(),"garage_part",false)==1,"food and quest items preserved outside trunk")
	check(copy.grid_snapshot().trunk.size()<=24 and GRID.ammo_slots(copy.grid_snapshot().trunk)<=6,"migrated trunk remains bounded")
	check(not copy.grid_snapshot().ground.is_empty(),"legitimate overflow stays in recoverable bags")
	var once: Dictionary=copy.snapshot()
	var serialized: Dictionary=JSON.parse_string(JSON.stringify(once))
	var restored: bool=copy.restore_snapshot(serialized)
	if not restored: print("ROUNDTRIP_DIAG grid=",GRID.validate(serialized.grid_inventory)," ownership=",ECONOMY._validate_grid_ownership(serialized))
	if restored and JSON.stringify(copy.snapshot())!=JSON.stringify(once):
		for key in once:
			if JSON.stringify(copy.snapshot()[key])!=JSON.stringify(once[key]): print("ROUNDTRIP_DIAG field=",key," before=",JSON.stringify(once[key])," after=",JSON.stringify(copy.snapshot()[key]))
	check(restored and JSON.stringify(copy.snapshot())==JSON.stringify(once),"migration is idempotent")
	var ordinary=ECONOMY.new(); ordinary.grant_weapon("ak47"); ordinary.add_ammo("ak47",1000); ordinary.grant_item("first_aid",10)
	var total: int=ordinary.get_ammo("ak47").magazine+ordinary.get_ammo("ak47").reserve
	ordinary.enable_grid_inventory()
	check(ordinary.get_ammo("ak47").magazine+ordinary.get_ammo("ak47").reserve+GRID.count(ordinary.grid_snapshot(),"ammo:ak47",false)-GRID.count(ordinary.grid_snapshot(),"ammo:ak47")==total,"ordinary large purchase is not mistaken for cheat")
	check(ECONOMY.validate_snapshot(ordinary.snapshot()),"ordinary migration with overflow validates")
	print("LIMITS_RESULT checks=",checks," failures=",failures)
	print("SAVE_DIRECTORY ",OS.get_user_data_dir())
	quit(1 if failures else 0)

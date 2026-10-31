extends SceneTree
## O dinheiro pode ser restaurado antes do marcador do mundo. Nenhum esconderijo pode pagar duas vezes nem
## se marcar como coletado quando um jogador morto/carteira cheia não pode pegar a recompensa.
const STATE := preload("res://runtime/desert/expansion/DesertDiscoveryState.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
const RELICS := preload("res://world/desert/expansion/DesertRelics.gd")
const SITES := preload("res://world/desert/expansion/DesertRelicsSites.gd")
const RAIL := preload("res://world/desert/expansion/DesertRelicsRail.gd")
const BALLAST := preload("res://world/desert/expansion/DesertRelicsBallast.gd")
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func _initialize() -> void:
	var world := {}
	var wallet := ECONOMY.new()
	check(STATE.valid(STATE.data(world)),"Legacy world without discoveries gets valid defaults")
	var detached := STATE.data(world)
	detached.desert_relic_station = true
	check(not STATE.collected(world,"desert_relic_station"),"Returned state cannot mutate the actual world")
	check(not STATE.valid({"version":1}),"Truncated discovery state is rejected")
	var forged := STATE.defaults()
	forged.desert_relic_mine = 1
	check(not STATE.valid(forged),"Numeric truth does not pass as saved boolean")
	var initial := wallet.balance
	check(not STATE.claim(world,wallet,"unknown",true).ok and wallet.balance==initial,"Unknown ID cannot grant money")
	check(not STATE.claim(world,wallet,"desert_relic_station",false).ok and not world.has(STATE.KEY),"Dead player cannot collect or create saved marker")
	for secret in RELICS.secrets():
		var before := wallet.balance
		var result := STATE.claim(world,wallet,secret.id,true)
		check(result.ok and result.changed and result.reward_changed,"First collection grants "+secret.id)
		check(wallet.balance == before+int(secret.amount),"Authoritative reward matches displayed cache "+secret.id)
		var duplicate := STATE.claim(world,wallet,secret.id,true)
		check(duplicate.ok and not duplicate.changed and wallet.balance == before+int(secret.amount),"Second interaction is idempotent "+secret.id)
		var missing_markers := {}
		var recovered := STATE.claim(missing_markers,wallet,secret.id,true)
		check(recovered.ok and recovered.changed and not recovered.reward_changed,"Receipt reconstructs missing marker "+secret.id)
		check(wallet.balance == before+int(secret.amount),"Recovered marker never duplicates cash "+secret.id)
	var restored: Dictionary = JSON.parse_string(JSON.stringify(world))
	check(STATE.valid(restored[STATE.KEY]),"All markers survive JSON save/load")
	check(world.keys() == [STATE.KEY],"Discoveries create no campaign/story flags")
	var full := ECONOMY.new()
	full.grant_reward("discovery_wallet_limit",ECONOMY.LIMIT-full.balance)
	var blocked := {}
	check(not STATE.claim(blocked,full,"desert_relic_mine",true).ok and not blocked.has(STATE.KEY),"Full wallet preserves collectible and world state")
	_check_station_platform()
	_check_rail_collision_contract()
	_check_ballast_support()
	print("DESERT_DISCOVERIES checks=%d failures=%d" % [checks,failures])
	quit(0 if failures==0 else 1)

func _check_station_platform() -> void:
	var fixture := Node3D.new()
	var station := SITES.build(fixture,"station",Vector3(-1100,0,-585),613)
	var platform := station.find_child("OldPlatform",true,false) as CollisionShape3D
	var ramp := station.find_child("PlatformAccessRamp",true,false) as CollisionShape3D
	check(platform!=null and ramp!=null,"Station has actual platform and accessible ramp collision")
	if platform!=null and ramp!=null:
		var size: Vector3 = (platform.shape as BoxShape3D).size
		var center := Vector2(station.position.x+platform.position.x,station.position.z+platform.position.z)
		for offset in [-size.x*.5,0.0,size.x*.5]:
			var x: float = center.x+float(offset)
			var edge := Vector2(x,center.y+size.z*.5)
			var gap: float = RAIL.center(x).y-RAIL.GAUGE*.5-edge.y
			check(gap>.5 and gap<1.2,"Surviving platform edge stays alongside real curved rails: "+str(gap))
			check(not RELICS.reservation_clear(edge,1.0),"Full platform footprint stays clear of vegetation/rocks")
		var ramp_bottom: Vector3 = ramp.transform*Vector3(0,.015,-(ramp.shape as BoxShape3D).size.z*.5)
		var ramp_top: Vector3 = ramp.transform*Vector3(0,.015,(ramp.shape as BoxShape3D).size.z*.5)
		check(absf(ramp_bottom.y)<.002 and absf(ramp_top.y-.18)<.002,"Ramp connects actual ground height to platform top without a lip")
		check(ramp_top.z>platform.position.z-size.z*.5 and ramp_top.z<platform.position.z,"Ramp reaches physical platform footprint")
		for z in range(-578,ceili(center.y),2):
			check(not RELICS.reservation_clear(Vector2(-1100,float(z)),2.8),"Broad station-to-platform walk is reserved at "+str(z))
	fixture.free()

func _check_ballast_support() -> void:
	for across in [-.77,-.7175,-.665,.665,.7175,.77]:
		check(is_equal_approx(BALLAST.cross_height(float(across)),.142),"Ballast continuously covers vertical railhead faces at "+str(across))
	check(BALLAST.cross_height(-3.4)<0 and BALLAST.cross_height(3.4)<0,"Both ballast toes enter below ground without a raised edge")
	check(BALLAST.support_height(RAIL.START_X-8,0,RAIL.START_X,RAIL.END_X)<0 and BALLAST.support_height(RAIL.END_X+8,0,RAIL.START_X,RAIL.END_X)<0,"Longitudinal rail ends have buried approach toes")
	check(BALLAST.cross_height(0)<.05,"Recessed track centre preserves visible wooden sleepers")
	var previous := BALLAST.cross_height(-3.5)
	var maximum_step := 0.0
	for i in range(1,701):
		var current := BALLAST.cross_height(-3.5+float(i)*.01)
		maximum_step=maxf(maximum_step,absf(current-previous))
		previous=current
	check(maximum_step<=.0051,"Railway support has no abrupt cross-track height step")

func _check_rail_collision_contract() -> void:
	var fixture := Node3D.new()
	RAIL.build_chunk(fixture,Rect2(-1020,-572,40,44),613,func(_point: Vector2) -> float: return 0.0)
	var ballast_supports := fixture.find_children("RailBallastSupport","StaticBody3D",true,false)
	check(ballast_supports.size()==1,"Rail chunk owns one continuous ballast collision surface")
	if not ballast_supports.is_empty():
		var support := ballast_supports[0].get_child(0) as CollisionShape3D
		var faces: PackedVector3Array = (support.shape as ConcavePolygonShape3D).get_faces()
		var minimum_y := INF
		var maximum_y := -INF
		var minimum_up := 1.0
		for i in range(0,faces.size(),3):
			var normal := (faces[i+2]-faces[i]).cross(faces[i+1]-faces[i]).normalized()
			minimum_up=minf(minimum_up,normal.y)
		for vertex in faces:
			minimum_y=minf(minimum_y,vertex.y)
			maximum_y=maxf(maximum_y,vertex.y)
		check(minimum_y<0 and is_equal_approx(maximum_y,.142),"Physical ballast runs from buried toes to iron-head height")
		check(minimum_up>.88,"All ballast faces are gradual upward support, with no vertical lip")
	var mine := SITES.build(fixture,"mine",Vector3.ZERO,613)
	var step_shapes := 0
	for collision in fixture.find_children("*","CollisionShape3D",true,false):
		var owner := collision.get_parent() as StaticBody3D
		if owner==null: continue
		var label: String = collision.get_meta("desert_relic_solid","")
		if owner.get_meta("pedestrian_step",false):
			step_shapes+=1
			check(label in ["Rail","DiscardedRail","MineCartRail"],"Only low rail solids permit pedestrian stepping: "+label)
			var top: float = collision.position.y+(collision.shape as BoxShape3D).size.y*.5
			check(absf(float(owner.get_meta("pedestrian_step_top"))-top)<.00001,"Rail step metadata matches physical support top")
			if label=="Rail": check(absf(top-.142)<.00001,"Long rail collision reaches visible railhead top")
		else:
			check(label not in ["Rail","DiscardedRail","MineCartRail"],"Low rail cannot remain in the furniture blocker body")
	check(step_shapes>2,"Rail/mine fixtures contain actual step-enabled collision shapes")
	var cart := mine.find_child("MineCartBase",true,false)
	check(cart!=null and not cart.get_parent().get_meta("pedestrian_step",false),"Mine cart remains solid furniture, never a pedestrian step")
	fixture.free()

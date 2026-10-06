extends RefCounted
## Exterior landmarks at human scale. The station is a roofless foundation;
## the mine is visibly sealed. Neither creates an interior or changes cameras.
const BATCH := preload("res://world/desert/expansion/DesertRelicsBatch.gd")
const ROCKS := preload("res://world/desert/DesertSurfaceRocks.gd")
const RAIL := preload("res://world/desert/expansion/DesertRelicsRail.gd")

static func station_platform() -> Dictionary:
	# The station anchor is (-1100,-585); derive the apron from the actual track
	# centre so a future railway adjustment cannot leave an isolated platform.
	var track: Vector2 = RAIL.center(-1100.0)
	var world_center := track + Vector2(0,-3.15)
	return {"position":Vector3(0,.09,world_center.y+585.0), "size":Vector3(21,.18,3.2),
		"bounds":Rect2(world_center-Vector2(10.5,1.6),Vector2(21,3.2))}

static func build(parent: Node3D, id: String, at: Vector3, world_seed: int) -> Node3D:
	var batch = BATCH.new(parent,"DesertRelic_"+id,at)
	match id:
		"station": _station(batch)
		"mine": _mine(batch)
		"wagon": _wagon(batch)
		"wreck": _wreck(batch)
	_scatter(batch,id,world_seed)
	batch.root.set_meta("desert_relic_site",id)
	return batch.finish()

static func _station(b: RefCounted) -> void:
	# Open, broken foundations frame a former waiting room. The south and east
	# faces are completely open, with broad access to the cache beside the wall.
	b.box("StationFoundation",Vector3(0,.007,0),Vector3(14,.014,9),"stone",false)
	b.box("RearBrickWall",Vector3(0,.58,-4.2),Vector3(13.4,1.16,.48),"adobe")
	b.box("WestBrokenWall",Vector3(-6.7,.34,-2.1),Vector3(.48,.68,4.3),"adobe")
	b.box("NorthWestRemnant",Vector3(-5.8,1.32,-4.2),Vector3(1.8,1.48,.48),"adobe")
	b.box("CollapsedFrontPillar",Vector3(-6.5,.43,3.7),Vector3(.65,.86,.65),"adobe")
	b.box("BrokenMasonry",Vector3(5.9,.24,-3.2),Vector3(1.3,.48,1.1),"adobe")
	for i in 9:
		b.box("ExposedBrickCourse",Vector3(-5.9+float(i)*.69,.16,-3.945),Vector3(.61,.21,.045),"rust",false)
	for i in 4:
		b.box("MissingPlasterPatch",Vector3(-5.2+float(i)*2.15,.52,-3.94),Vector3(.76,.16,.047),"rust",false)
	# A freestanding chimney and skeletal veranda retain the silhouette of an
	# old stop while no roof hides the player approaching from normal gameplay.
	b.box("StationChimney",Vector3(-4.4,1.85,-3.25),Vector3(1.02,3.7,.92),"adobe")
	b.box("ChimneyRim",Vector3(-4.4,3.71,-3.25),Vector3(1.24,.18,1.14),"rust")
	b.box("ChimneyOpening",Vector3(-4.4,3.807,-3.25),Vector3(.7,.014,.62),"rubber",false)
	for x in [-5.7,-1.8,2.1]:
		b.box("VerandaPost",Vector3(x,1.4,5.6),Vector3(.19,2.8,.19),"wood")
	b.box("VerandaBeam",Vector3(-1.8,2.88,5.6),Vector3(8.1,.18,.2),"wood")
	b.beam("VerandaBrace",Vector3(-5.7,2.13,5.6),Vector3(-4.9,2.8,5.6),.13,"wood")
	b.beam("VerandaBrace",Vector3(2.1,2.13,5.6),Vector3(1.3,2.8,5.6),.13,"wood")
	# The ticket case stands in open space, never behind a collision-only wall.
	b.box("TicketChest",Vector3(4.4,.28,2),Vector3(.95,.56,.62),"wood")
	b.box("ChestHinge",Vector3(4.4,.78,1.72),Vector3(.98,.44,.055),"rust")
	b.box("ChestCorner",Vector3(3.96,.29,2.326),Vector3(.055,.56,.026),"rust",false)
	b.box("ChestCorner",Vector3(4.84,.29,2.326),Vector3(.055,.56,.026),"rust",false)
	_loot(b,"desert_relic_station",Vector3(4.4,.65,2))
	_bench(b,Vector3(-2.5,0,1.5))
	b.box("AbandonedSuitcase",Vector3(-3.9,.18,.5),Vector3(.65,.36,.44),"rust")
	b.box("SuitcaseHandle",Vector3(-3.9,.39,.5),Vector3(.23,.055,.065),"steel",false)
	# Weathered water tower: clear space between real supports, no huge invisible
	# cylinder projecting the elevated tank down to the ground.
	var tower := Vector3(-16,0,-7)
	for x in [-1.65,1.65]:
		for z in [-1.65,1.65]:
			b.box("TowerFoot",tower+Vector3(x,.16,z),Vector3(.76,.32,.76),"stone")
			b.box("TowerLeg",tower+Vector3(x,2.3,z),Vector3(.26,4.6,.26),"wood")
	for side in [-1.65,1.65]:
		b.beam("TowerCrossBrace",tower+Vector3(-1.65,.7,side),tower+Vector3(1.65,4.0,side),.15,"wood")
		b.beam("TowerCrossBrace",tower+Vector3(1.65,.7,side),tower+Vector3(-1.65,4.0,side),.15,"wood")
	b.cylinder("WaterTank",tower+Vector3(0,5.65,0),2.2,2.7,"wood")
	for y in [4.4,5.0,6.2,6.9]:
		b.cylinder("TankBand",tower+Vector3(0,y,0),2.23,.085,"rust",false)
	b.cylinder("TankRoof",tower+Vector3(0,7.08,0),2.37,.15,"rust")
	b.cylinder("TankHatch",tower+Vector3(.55,7.25,-.35),.43,.19,"steel")
	b.beam("WaterPipe",tower+Vector3(2.25,4.9,0),tower+Vector3(3.5,4.9,0),.16,"rust")
	b.beam("WaterPipeDrop",tower+Vector3(3.5,4.9,0),tower+Vector3(3.5,3.4,0),.16,"rust")
	# A broad, worn yard continuously joins the veranda to the surviving apron.
	# Its low ramp remains walkable without a forced step/teleport onto the slab.
	var platform := station_platform()
	var platform_at: Vector3 = platform.position
	var platform_start := platform_at.z-1.6
	b.box("WornStationYard",Vector3(0,.004,(6.0+platform_start)*.5),Vector3(22,.008,platform_start-6.0),"trail",false)
	b.box("OldPlatform",platform_at,platform.size,"stone")
	var ramp_length := 3.02
	var ramp_angle := atan2(.18,ramp_length)
	b.box("PlatformAccessRamp",Vector3(0,.09-.015*cos(ramp_angle),platform_start-1.49),Vector3(5.6,.03,sqrt(ramp_length*ramp_length+.18*.18)),"stone",true,Vector3(-ramp_angle,0,0))
	for i in 6:
		b.box("PlatformEdgeStone",Vector3(-9.0+float(i)*3.4,.09,platform_at.z+1.55),Vector3(3.2,.18,.1),"adobe")
	_fence(b,Vector3(10,0,-10),Vector3(23,0,-10),5)
	_fence(b,Vector3(23,0,-10),Vector3(23,0,1),4)
	b.cylinder("DryBarrel",Vector3(10.5,.48,-6.0),.39,.96,"rust")
	b.cylinder("BarrelRim",Vector3(10.5,.97,-6.0),.42,.06,"steel",false)

static func _mine(b: RefCounted) -> void:
	# A blocked adit set in an irregular stone headland. Both the rock hulls and
	# timbers are solid; the black recess is behind the physical closure.
	for spec in [
		[Vector3(-10,4.9,-8),Vector3(12,11,14),Color("82756b")],
		[Vector3(1,6.0,-12),Vector3(19,13,15),Color("8b7967")],
		[Vector3(11,3.9,-11),Vector3(10,8.5,11),Color("a08d73")],
		[Vector3(-15,1.6,-2),Vector3(7,3.7,7),Color("8d7e70")],
	]:
		ROCKS.rock(b.root,"MineHeadland",spec[0],spec[1],spec[2],true)
	b.box("MineRecess",Vector3(-5.0,1.75,-2.2),Vector3(4.1,3.5,.16),"rubber")
	for x in [-7.05,-2.95]:
		b.box("AditTimber",Vector3(x,1.8,-1.7),Vector3(.44,3.6,.46),"wood")
	b.box("AditHeader",Vector3(-5,3.6,-1.7),Vector3(4.9,.45,.5),"wood")
	for i in 5:
		b.box("SealedMinePlank",Vector3(-5,.45+float(i)*.61,-1.47),Vector3(4.2,.39,.15),"wood")
	b.beam("SealedMineBrace",Vector3(-7,.15,-1.27),Vector3(-3.0,3.1,-1.27),.23,"rust")
	b.beam("SealedMineBrace",Vector3(-3,.15,-1.26),Vector3(-7.0,3.1,-1.26),.23,"wood")
	for z in range(0,11):
		b.box("MineTrackTie",Vector3(-5,.025,float(z)),Vector3(1.8,.05,.17),"wood",false)
	for side in [-.53,.53]:
		b.box("MineCartRail",Vector3(-5+side,.075,5),Vector3(.065,.1,11),"rust",false)
		b.rail_collision("MineCartRail",Vector3(-5+side,.075,5),Vector3(.065,.1,11))
	_cart(b,Vector3(-4.9,0,5.8))
	# Hoist and pulley are visible from the highway approach, but no lit signs.
	for x in [3.8,7.4]:
		b.box("HoistSupport",Vector3(x,2.45,-2),Vector3(.3,4.9,.3),"wood")
	b.box("HoistHeader",Vector3(5.6,5,-2),Vector3(4.3,.3,.35),"wood")
	b.cylinder("HoistWheel",Vector3(5.6,4.6,-1.76),.72,.19,"rust",true,Vector3(PI*.5,0,0))
	b.cylinder("HoistAxle",Vector3(5.6,4.6,-1.56),.12,.65,"steel",true,Vector3(PI*.5,0,0))
	b.box("HoistCable",Vector3(5.0,2.9,-1.7),Vector3(.025,3.0,.025),"steel",false)
	b.box("HoistCable",Vector3(6.2,3.0,-1.7),Vector3(.025,2.8,.025),"steel",false)
	b.cylinder("WindingDrum",Vector3(5.6,.69,1.5),.55,1.6,"rust",true,Vector3(0,0,PI*.5))
	b.box("WinchFoundation",Vector3(5.6,.2,1.5),Vector3(2.3,.4,1.6),"stone")
	b.box("ToolCache",Vector3(13.2,.235,6),Vector3(1.0,.47,.65),"steel")
	b.box("ToolCacheLid",Vector3(13.2,.68,5.71),Vector3(1.04,.42,.06),"rust")
	_loot(b,"desert_relic_mine",Vector3(13.2,.5,6))
	b.box("PickaxeShaft",Vector3(11,.11,7.0),Vector3(1.5,.085,.085),"wood",false,Vector3(0,.3,0))
	b.box("PickaxeHead",Vector3(11.55,.12,6.8),Vector3(.16,.09,.72),"steel",false,Vector3(0,.3,0))
	for i in 3:
		b.box("OreCrate",Vector3(15+float(i)*1.4,.42,-1+float(i%2)*1.2),Vector3(.9,.84,.95),"wood")
	for i in 5:
		b.box("StoredTimber",Vector3(15.2,.17+float(i%2)*.18,-5.0+float(i)*.23),Vector3(5.6,.18,.19),"wood")
	_fence(b,Vector3(20,0,-6),Vector3(20,0,11),6)
	_fence(b,Vector3(-16,0,14),Vector3(-7,0,14),4)
	b.cylinder("OreBarrel",Vector3(9,.46,6.7),.36,.92,"rust")

static func _wagon(b: RefCounted) -> void:
	# A tipped, open freight wagon, with cargo spilled on the south side. Its
	# physical volumes follow the visible body instead of blocking the entire yard.
	b.box("WagonUnderframe",Vector3(0,.74,0),Vector3(10.7,.34,2.6),"steel",true,Vector3(.045,0,.035))
	b.box("WagonBed",Vector3(0,1.01,0),Vector3(10.4,.16,2.55),"wood")
	b.box("FarWagonSide",Vector3(0,1.77,-1.32),Vector3(10.7,1.6,.13),"rust")
	for x in [-5.25,5.25]:
		b.box("WagonEnd",Vector3(x,1.76,0),Vector3(.15,1.6,2.7),"rust")
	for x in [-4.45,-2.95,2.95,4.45]:
		for side in [-1.0,1.0]:
			b.cylinder("WagonWheel",Vector3(x,.42,side*1.12),.43,.19,"rubber",true,Vector3(PI*.5,0,0))
	for x in [-4.4,-2.65,-.9,.9,2.65,4.4]:
		b.box("WagonRib",Vector3(x,1.79,-1.41),Vector3(.13,1.82,.09),"steel",false)
	for x in [-3.8,3.8]:
		b.box("SurvivingNearSide",Vector3(x,1.59,1.32),Vector3(2.7,1.26,.13),"rust")
		b.box("WagonBogey",Vector3(x,.4,0),Vector3(2.2,.27,2.17),"steel")
	b.box("BentDoor",Vector3(1.55,.3,2.25),Vector3(2.6,.13,1.4),"rust",true,Vector3(.2,.14,.1))
	b.box("Coupler",Vector3(5.92,.7,0),Vector3(1.2,.18,.2),"steel")
	b.box("CargoCrate",Vector3(-2.8,1.5,.05),Vector3(1.7,.86,1.8),"wood")
	b.box("CargoCrate",Vector3(-.4,1.35,-.1),Vector3(1.3,.54,1.5),"wood")
	b.box("SpilledCargo",Vector3(-3.3,.41,3.5),Vector3(1.1,.82,1.05),"wood",true,Vector3(0,-.24,0))
	b.box("SpilledCargo",Vector3(-1.8,.27,4.3),Vector3(.9,.54,.85),"wood",true,Vector3(0,.21,0))
	b.box("CashTin",Vector3(0,.2,2.1),Vector3(.65,.4,.52),"steel")
	b.box("TinLid",Vector3(0,.53,1.865),Vector3(.69,.27,.04),"rust")
	_loot(b,"desert_relic_wagon",Vector3(0,.5,2.1))
	for i in 5:
		b.box("FallenCargoBoard",Vector3(-4.4+float(i)*.43,.06,5.6+float(i%2)*.5),Vector3(1.7,.12,.15),"wood",false,Vector3(0,float(i)*.47,0))

static func _wreck(b: RefCounted) -> void:
	# Wheel hubs, a collapsed cabin, cracked glass and the tailgate give the
	# silhouette of a full-size pickup whose lower body is swallowed by sand.
	b.box("PickupChassis",Vector3(0,.3,0),Vector3(1.92,.46,4.9),"rust")
	b.box("PickupHood",Vector3(0,.78,-1.62),Vector3(1.98,.29,1.55),"rust",true,Vector3(.06,0,.02))
	b.box("PickupCab",Vector3(0,.99,-.16),Vector3(1.94,1.22,1.7),"rust")
	b.box("CabWindshield",Vector3(0,1.37,-1.025),Vector3(1.58,.46,.045),"glass",false)
	b.box("CrackedGlass",Vector3(-.22,1.37,-1.052),Vector3(.035,.52,.013),"stone",false,Vector3(0,0,.32))
	b.box("CabRoof",Vector3(0,1.66,-.12),Vector3(2.03,.12,1.89),"roof")
	for side in [-1.0,1.0]:
		b.box("SideWindow",Vector3(side*.987,1.35,-.12),Vector3(.033,.47,1.24),"glass",false)
		b.box("PickupDoorHandle",Vector3(side*1.017,.98,.35),Vector3(.032,.05,.16),"steel",false)
		b.box("BedSide",Vector3(side*.95,.81,1.62),Vector3(.14,.66,1.95),"rust")
		for z in [-1.72,1.65]:
			b.cylinder("BuriedWheel",Vector3(side*1.0,.15,z),.38,.2,"rubber",true,Vector3(0,0,PI*.5))
			b.cylinder("WheelHub",Vector3(side*1.11,.15,z),.2,.015,"steel",false,Vector3(0,0,PI*.5))
	b.box("Tailgate",Vector3(0,.69,2.59),Vector3(1.9,.71,.12),"rust",true,Vector3(-.25,0,0))
	b.box("FrontBumper",Vector3(0,.4,-2.55),Vector3(2.16,.14,.2),"steel")
	b.box("Grille",Vector3(0,.68,-2.42),Vector3(1.09,.23,.05),"rubber",false)
	for x in [-.73,.73]:
		b.box("DeadHeadlamp",Vector3(x,.71,-2.43),Vector3(.35,.24,.055),"chalk",false)
	for i in 4:
		b.box("GrilleRib",Vector3(-.38+float(i)*.25,.68,-2.45),Vector3(.024,.2,.018),"steel",false)
	b.box("SuitcaseCache",Vector3(1.7,.19,3.0),Vector3(.7,.38,.48),"wood")
	b.box("SuitcaseLid",Vector3(1.7,.55,2.78),Vector3(.74,.34,.05),"rust")
	_loot(b,"desert_relic_wreck",Vector3(1.7,.45,3.0))
	ROCKS.rock(b.root,"SandAgainstWreck",Vector3(-.92,.05,1.65),Vector3(2.9,.46,4.4),Color("b9a079"),true)
	b.box("LostLicensePlate",Vector3(.7,.015,-4),Vector3(.52,.03,.17),"cream",false,Vector3(0,.34,0))

static func _cart(b: RefCounted, at: Vector3) -> void:
	b.box("MineCartBase",at+Vector3(0,.38,0),Vector3(1.45,.22,1.85),"steel")
	b.box("MineCartFarSide",at+Vector3(-.68,.82,0),Vector3(.09,.82,1.88),"rust")
	b.box("MineCartNearSide",at+Vector3(.68,.82,0),Vector3(.09,.82,1.88),"rust")
	for z in [-.9,.9]:
		b.box("MineCartEnd",at+Vector3(0,.82,z),Vector3(1.4,.82,.09),"rust")
	for side in [-1.0,1.0]:
		for z in [-.57,.57]:
			b.cylinder("MineCartWheel",at+Vector3(side*.6,.25,z),.25,.12,"steel",true,Vector3(0,0,PI*.5))
	for i in 4:
		b.box("OreInsideCart",at+Vector3(-.4+float(i%2)*.74,.59,float(i/2)*.63-.4),Vector3(.65,.29,.55),"stone")

static func _bench(b: RefCounted, at: Vector3) -> void:
	# One full footprint blocks walking through the seat, including its underside.
	b.box("BenchSeat",at+Vector3(0,.235,0),Vector3(2.5,.47,.61),"wood")
	b.box("BenchBack",at+Vector3(0,.85,-.27),Vector3(2.5,.48,.09),"wood")
	for x in [-1.04,1.04]:
		b.box("BenchBackPost",at+Vector3(x,.7,-.27),Vector3(.1,.8,.12),"rust")

static func _fence(b: RefCounted, start: Vector3, end: Vector3, count: int) -> void:
	var direction := (end-start).normalized()
	for i in count:
		var at := start.lerp(end,float(i)/float(count-1))
		b.box("FencePost",at+Vector3(0,.65,0),Vector3(.14,1.3,.14),"wood",true,Vector3(0,0,.045*sin(float(i)*4)))
		if i == count-1 or i%3 == 1: continue
		var next := at+direction*start.distance_to(end)/float(count-1)
		for h in [.54,1.05]:
			b.beam("FenceRail",at+Vector3(0,h,0),next+Vector3(0,h-.1,0),.11,"wood")

static func _loot(b: RefCounted, id: String, at: Vector3) -> void:
	var contents = BATCH.new(b.root,"DiscoveryContents",at)
	contents.root.add_to_group("desert_discovery_contents")
	contents.root.set_meta("discovery_id",id)
	contents.box("Envelope",Vector3(0,0,0),Vector3(.32,.016,.21),"cream",false)
	contents.box("BanknoteBundle",Vector3(.1,.033,.035),Vector3(.16,.055,.095),"roof",false)
	contents.box("BundleBand",Vector3(.1,.063,.035),Vector3(.046,.009,.099),"cream",false)
	contents.finish()

static func _scatter(b: RefCounted, id: String, world_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + absi(id.hash())
	# Rubble stays beside walls/outer yards; approaches and cash positions remain
	# authored clear. Thin fragments are ground dressing, not waist-high blockers.
	for i in 10:
		var at := Vector3(-9.0+rng.randf()*3.5,.035,8.0+rng.randf()*3.0)
		if id == "wreck": at = Vector3(-3.2+rng.randf(),.035,-3+rng.randf()*5)
		b.box("WeatheredFragment",at,Vector3(rng.randf_range(.18,.5),.07,rng.randf_range(.12,.35)),"rust" if i%3==0 else "stone",false,Vector3(0,rng.randf()*TAU,0))

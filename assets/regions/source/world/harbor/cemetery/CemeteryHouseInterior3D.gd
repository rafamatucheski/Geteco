extends "res://assets/regions/source/world/harbor/cemetery/CemeteryPropBuilder.gd"

var light: OmniLight3D
var ledger: Node3D

func _ready() -> void:
	box("StoneSlab", Vector3(9.3, .25, 7.4), Vector3(0, -.18, 0), "444940")
	for row in 18:
		for col in 5:
			var x := -3.62 + col * 1.81
			box("WornFloorboard", Vector3(1.79, .08, .39), Vector3(x, -.02, -3.4 + row * .4), ["71614a", "776850", "6a5b45"][(col + row) % 3])
	box("BackPlaster", Vector3(9.2, 2.8, .22), Vector3(0, 1.35, -3.6), "a39b7d")
	box("LeftPlaster", Vector3(.22, 2.8, 7.2), Vector3(-4.6, 1.35, 0), "8d9176")
	# Low right/south walls keep the playable floor and sleeping alcove readable.
	box("RightCutaway", Vector3(.22, .65, 7.2), Vector3(4.6, .28, 0), "8b9076")
	for x in [-2.6, 2.6]: box("SouthCutaway", Vector3(3.9, .45, .22), Vector3(x, .18, 3.6), "8b9076")
	for x in [-4.45, 0, 4.45]: box("RoofPost", Vector3(.15, 2.9, .20), Vector3(x, 1.4, -3.45), "4a4a37")
	box("BackSkirting", Vector3(9, .24, .10), Vector3(0, .1, -3.42), "4a4a37")
	box("DoorMat", Vector3(1.55, .015, .72), Vector3(0, .04, 2.97), "3d4e40")
	# Tool wall and workbench.
	box("ToolRackBacking", Vector3(3.4, 1.12, .09), Vector3(-2.5, 1.83, -3.4), "565b42")
	for x in [-3.55, -2.55]:
		var shovel := preload("res://assets/regions/source/prototypes/gameplay_repair_art_0909/ShovelTool3D.gd").new()
		shovel.name = "HangingSpade"
		shovel.position = Vector3(x, 2.27, -3.21)
		add_child(shovel)
		shovel.rotation = Vector3.ZERO
	beam("RakeShaft", Vector3(-1.53, 1.2, -3.2), Vector3(-1.53, 2.35, -3.2), .04, "a28758")
	box("RakeHead", Vector3(.55, .06, .06), Vector3(-1.53, 1.2, -3.2), "454e45")
	for i in 7: box("RakeTooth", Vector3(.024, .15, .04), Vector3(-1.78 + i * .08, 1.11, -3.2), "454e45")
	box("WorkbenchTop", Vector3(3.25, .14, 1.02), Vector3(-2.55, .86, -2.78), "8a7050")
	for x in [-3.93, -1.18]:
		for z in [-3.15, -2.39]: box("BenchLeg", Vector3(.11, .82, .11), Vector3(x, .41, z), "4b4b37")
	box("Drawer", Vector3(2.6, .26, .72), Vector3(-2.55, .66, -2.76), "60543a")
	box("DrawerPull", Vector3(.3, .035, .07), Vector3(-2.55, .68, -2.35), "b2a071")
	lantern(Vector3(-3.45, .96, -2.72))
	ledger = box("BurialLedger", Vector3(.75, .065, .52), Vector3(-2.35, .97, -2.56), "33473d")
	box("LedgerPages", Vector3(.68, .025, .46), Vector3(-2.35, 1.01, -2.56), "d9c99e")
	for i in 6: box("InkLine", Vector3(.40, .002, .008), Vector3(-2.3, 1.027, -2.72 + i * .06), "7e7961")
	box("BrassKey", Vector3(.15, .03, .055), Vector3(-1.59, .97, -2.6), "bc9a58")
	# Sleeping corner: iron bed, real mattress, patched quilt, boots and bedside cup.
	box("BedFrame", Vector3(1.65, .18, 2.55), Vector3(2.98, .38, -1.96), "394a41")
	box("Mattress", Vector3(1.52, .19, 2.40), Vector3(2.98, .55, -1.96), "baaf8d")
	box("PatchworkQuilt", Vector3(1.55, .12, 1.73), Vector3(2.98, .69, -1.65), "536b52")
	for x in [2.45, 2.97, 3.49]:
		for z in [-2.25, -1.72, -1.19]: box("QuiltPatch", Vector3(.49, .012, .49), Vector3(x, .755, z), "687957" if int((x+z)*10)%2 else "7f8060")
	box("Pillow", Vector3(1.12, .18, .48), Vector3(2.98, .73, -2.83), "ded4b2")
	for z in [-3.19, -.70]:
		for x in [2.16, 3.80]: cylinder("BedPost", .045, .94, Vector3(x, .47, z), "34473e")
		beam("IronBedRail", Vector3(2.16, .9, z), Vector3(3.80, .9, z), .05, "34473e")
	box("BedsideTable", Vector3(.68, .60, .7), Vector3(1.58, .30, -2.6), "786246")
	cylinder("EnamelCup", .09, .17, Vector3(1.59, .70, -2.61), "b6b5a1")
	for x in [2.4, 2.72]: box("MuddyBoot", Vector3(.19, .28, .37), Vector3(x, .14, -.37), "373d30")
	# Window, clock, memorial map and a small stove.
	box("WindowRecess", Vector3(1.70, 1.33, .08), Vector3(.2, 1.84, -3.44), "35483d")
	box("BlueWindow", Vector3(1.48, 1.08, .04), Vector3(.2, 1.84, -3.37), "769d9e")
	box("WindowCross", Vector3(.06, 1.15, .06), Vector3(.2, 1.84, -3.31), "ded0a4")
	box("WindowCross", Vector3(1.5, .06, .06), Vector3(.2, 1.84, -3.31), "ded0a4")
	box("MemorialMap", Vector3(.88, .72, .06), Vector3(-.36, 1.85, -3.27), "c8b98c")
	lettering("QUADRA 7\nS. / 1986", Vector3(-.36, 1.85, -3.22), 15, "555a43")
	box("Stove", Vector3(.72, .76, .76), Vector3(-3.75, .38, -.55), "39443b")
	cylinder("StovePipe", .10, 2.1, Vector3(-3.9, 1.78, -.74), "3e473d")
	cylinder("CoffeePot", .15, .22, Vector3(-3.70, .9, -.5), "8a7560")
	# Barrow and earth sacks beside the door; a central clear route remains.
	var barrow := Node3D.new()
	barrow.name = "Wheelbarrow"
	barrow.position = Vector3(-3, 0, 1.65)
	barrow.rotation.y = -.30
	add_child(barrow)
	box("TrayBase", Vector3(.90, .10, .9), Vector3(0, .51, 0), "536b58", barrow)
	for x in [-.48, .48]: box("TraySide", Vector3(.07, .28, 1.0), Vector3(x, .66, 0), "657b63", barrow)
	box("TrayFront", Vector3(1, .32, .08), Vector3(0, .69, -.47), "657b63", barrow)
	box("Soil", Vector3(.79, .15, .75), Vector3(0, .60, 0), "4c4534", barrow)
	var wheel := cylinder("RubberWheel", .25, .16, Vector3(0, .25, -.71), "303931", barrow)
	wheel.rotation.z = PI / 2
	for x in [-.39, .39]:
		beam("Handle", Vector3(x, .44, -.4), Vector3(x, .7, 1.2), .045, "838061", barrow)
		beam("Stand", Vector3(x, .07, .4), Vector3(x, .5, .25), .045, "414d3e", barrow)
	for i in 3:
		box("SoilSack", Vector3(.64, .35, .82), Vector3(3.65, .18 + (i / 2) * .32, 1.15 + (i % 2) * .85), "a09266")
	for x in [1.9, 2.4]:
		beam("WoodenCross", Vector3(x, .12, 3.25), Vector3(x, 1.14, 3.25), .065, "8e7651")
		beam("Crossbar", Vector3(x-.24, .88, 3.25), Vector3(x+.24, .88, 3.25), .065, "8e7651")
	light = OmniLight3D.new()
	light.position = Vector3(-1.8, 2.4, -.5)
	light.light_color = Color("ffc77e")
	light.light_energy = .8
	light.omni_range = 8
	light.shadow_enabled = true
	add_child(light)

func set_night(night: bool) -> void:
	if light: light.light_energy = .3 if night else .8

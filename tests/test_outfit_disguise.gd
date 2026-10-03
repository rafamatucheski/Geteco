extends SceneTree

const DISGUISE = preload("res://runtime/OutfitDisguise.gd")
const GAMEPLAY = preload("res://gameplay/Gameplay.gd")
const ECONOMY = preload("res://systems/economy/Economy.gd")
const RESIDENCE = preload("res://activities/Residence.gd")

class State extends RefCounted:
	var economy = ECONOMY.new()
	var place_id := "westgate_garden"
	var region_id := "harbor"
	func weapons_allowed() -> bool: return true

class World extends Node3D:
	var gameplay
	var player: CharacterBody3D

class Session extends RefCounted:
	var state = State.new()
	var world = World.new()
	var activities = {"residence": RESIDENCE.new()}
	var mountain_progression = null
	var return_point := Vector3.ZERO
	var applied := ""
	func apply_outfit() -> void: applied = state.economy.outfit

class Officer extends CharacterBody3D:
	var dead := false

var failures := 0
func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func wanted(session) -> void:
	session.world.gameplay.stars = 3
	session.world.gameplay.crime_points = 60
	session.world.gameplay.last_known_valid = true

func _run() -> void:
	var session := Session.new()
	root.add_child(session.world)
	session.world.player = CharacterBody3D.new()
	session.world.add_child(session.world.player)
	var gameplay = GAMEPLAY.new()
	session.world.gameplay = gameplay
	gameplay.configure(session.world, session.world.player, null, session.state)
	session.world.add_child(gameplay)
	gameplay.set_physics_process(false)
	session.activities.residence.data.active_home = "westgate_garden"
	var alternative: String = ECONOMY.Outfits.ORDER[1]
	session.state.economy.grant_outfit(alternative)
	wanted(session)
	gameplay.police_case.pending.append({"points": 60})
	gameplay.police_case.investigation_left = 300.0
	check(DISGUISE.equip(session, alternative) and gameplay.stars == 0, "home change clears all stars")
	check(gameplay.crime_points == 0 and not gameplay.last_known_valid and gameplay.police_case.pending.is_empty(), "pursuit and investigation reset")
	check(gameplay.police_case.investigation_left == 0.0, "old case cannot identify new clothing")
	wanted(session)
	check(DISGUISE.equip(session, alternative) and gameplay.stars == 3, "same outfit keeps pursuit")
	check(not DISGUISE.equip(session, "invalid") and gameplay.stars == 3, "invalid outfit keeps pursuit")
	session.state.place_id = ""
	DISGUISE.equip(session, "dante_classic")
	check(gameplay.stars == 3, "street inventory cannot erase pursuit")
	session.state.place_id = "harbor_clothing"
	session.world.player.position = Vector3(1000, 0, 1000)
	var officer := Officer.new()
	root.add_child(officer)
	officer.add_to_group("v2_police_officers")
	officer.position = Vector3(30, 0, 0)
	DISGUISE.equip(session, alternative, true)
	check(gameplay.stars == 3, "officer at exterior door range blocks disguise despite distant interior")
	officer.position.x = 31
	DISGUISE.equip(session, "dante_classic", true)
	check(gameplay.stars == 0, "shop change with distant police clears stars")
	wanted(session)
	officer.set_meta("police_place_id", "harbor_clothing")
	officer.position = session.world.player.position + Vector3.RIGHT
	DISGUISE.equip(session, alternative, true)
	check(gameplay.stars == 3, "police inside shop blocks disguise")
	session.state.place_id = "westgate_garden"
	officer.set_meta("police_place_id", "westgate_garden")
	DISGUISE.equip(session, "dante_classic")
	check(gameplay.stars == 0, "home wardrobe works during active pursuit")
	wanted(session)
	session.mountain_progression = {"data": {"rental": true}}
	DISGUISE.equip(session, alternative)
	check(gameplay.stars == 3, "rental override cannot disguise unchanged appearance")
	session.mountain_progression = null
	session.state.place_id = "harbor_clothing"
	officer.set_meta("police_place_id", "")
	officer.position = Vector3(100, 0, 0)
	var purchase_id: String = ECONOMY.Outfits.ORDER[2]
	var failed: Dictionary = session.state.economy.purchase("outfit", purchase_id, "disguise_unaffordable")
	check(not failed.ok and gameplay.stars == 3 and not session.state.economy.owns_outfit(purchase_id), "failed purchase preserves pursuit and inventory")
	session.state.economy.grant_reward("disguise_test", 100000)
	var bought: Dictionary = session.state.economy.purchase("outfit", purchase_id, "disguise_purchase")
	check(bought.ok and DISGUISE.equip(session, purchase_id, true) and gameplay.stars == 0, "new purchase equips clothing and clears distant pursuit")
	check(session.applied == purchase_id, "purchased appearance applied")
	# Parse the actual UI adapters too; no user save is read or written.
	for path in ["res://runtime/FullSession.gd", "res://runtime/HarborStorefronts.gd", "res://runtime/ResidenceServices.gd", "res://systems/inventory/ui/InventoryPanel.gd"]:
		check(load(path).can_instantiate(), "adapter compiles: " + path)
	officer.free()
	session.world.free()
	print("OUTFIT DISGUISE failures=%d" % failures)
	quit(1 if failures else 0)

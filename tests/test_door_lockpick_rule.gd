extends SceneTree
## Contrato da porta trancada (playtest 29/10): toda casa exige lockpick; polícia, bombeiros,
## hospital e lojas abrem sem. A regra vem do catálogo (tipo do lugar). Também confere o
## save ("door_lockpicks") e o estado de uma sessão falsa. Sem Main.tscn; não anda até portas.
const LOCKS := preload("res://runtime/DoorLockpick.gd")
const BUILDINGS := preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

class FakeState extends RefCounted:
	var world_state := {}

class FakeSession extends Node:
	var state := FakeState.new()

func _initialize() -> void:
	for id in ["harbor_police", "harbor_hospital", "harbor_fire_station", "harbor_clothing", "harbor_fuel",
			"harbor_supermarket", "harbor_ammunation", "mountain_gunshop", "harbor_bank", "mountain_outfitters",
			"mountain_boutique", "ski_lodge", "harbor_bar", "harbor_arcade", "maciota"]:
		check(not LOCKS.requires_lockpick(id), "%s abre sem lockpick" % id)
	for id in ["mountain_cabin", "mountain_cabin_encosta", "mountain_cabin_village_1", "santa_lua_home_1"]:
		check(LOCKS.requires_lockpick(id), "%s (casa) exige lockpick" % id)
	check(not LOCKS.requires_lockpick("lumberjack_shelter"), "abrigo público dos lenhadores abre")
	check(not LOCKS.requires_lockpick("cemetery_keeper"), "casa do zelador (missão) abre")
	check(not LOCKS.requires_lockpick("westgate_garden"), "casa à venda segue a trava do dono, não lockpick")
	var residential := 0
	var shops := 0
	for definition in BUILDINGS.definitions():
		var archetype := str(definition.archetype)
		var locked := LOCKS.requires_lockpick(definition.id)
		if archetype == "residential":
			residential += 1
			if not locked: check(false, "%s residencial trancado" % definition.id)
		if archetype in ["retail", "hospitality", "civic"]:
			shops += 1
			if locked: check(false, "%s (%s) aberto" % [definition.id, archetype])
	check(residential > 0, "catálogo tem prédios residenciais trancados (%d)" % residential)
	check(shops > 0, "catálogo tem lojas/bares abertos (%d)" % shops)
	check(LOCKS.valid_saved({}), "save sem portas arrombadas vale")
	check(LOCKS.valid_saved({"mountain_cabin": true}), "save com casa arrombada vale")
	check(not LOCKS.valid_saved({"harbor_police": true}), "save recusa porta pública como arrombada")
	check(not LOCKS.valid_saved({"mountain_cabin": 1}), "save recusa valor que não é bool")
	check(not LOCKS.valid_saved([]), "save recusa lista")
	var locks: Node = LOCKS.new()
	var session := FakeSession.new()
	locks.session = session
	if LOCKS.enabled():
		check(not locks.allows("mountain_cabin"), "casa trancada sem arrombar")
		check(locks.allows("harbor_police"), "delegacia sempre abre")
		session.state.world_state[LOCKS.STATE_KEY] = {"mountain_cabin": true}
		check(locks.allows("mountain_cabin"), "casa arrombada abre")
	locks.free()
	session.free()
	print("DOOR_LOCKPICK_RULE falhas=%d" % failures)
	quit(1 if failures > 0 else 0)

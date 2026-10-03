extends SceneTree
const DIGO := preload("res://systems/campaign/DigoProgress.gd")
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	var state := STATE.new()
	check(STATE.new().restore_snapshot(state.snapshot()),"saves anteriores sem Digo continuam válidos")
	check(not DIGO.workshop_unlocked(state.world_state),"oficina bloqueada antes do reencontro")
	check(DIGO.mark_met(state.world_state) and not DIGO.mark_met(state.world_state),"encontro idempotente")
	check(DIGO.complete_lesson(state.world_state) and not DIGO.complete_lesson(state.world_state),"aula concluída só uma vez")
	check(not DIGO.workshop_unlocked(state.world_state),"aula não antecipa amizade nem upgrades")
	check(not DIGO.complete_desert_race(state.world_state,"other_race",true),"outra prova não libera oficina")
	check(not DIGO.complete_desert_race(state.world_state,DIGO.DESERT_RACE_ID,false),"abandono não estabelece amizade")
	check(DIGO.complete_desert_race(state.world_state,DIGO.DESERT_RACE_ID,true),"chegada no deserto estabelece amizade")
	check(DIGO.workshop_unlocked(state.world_state) and not DIGO.complete_desert_race(state.world_state,DIGO.DESERT_RACE_ID,true),"amizade e desbloqueio idempotentes")
	var store := STORE.new()
	store.path = "res://evidence/digo/test-save-%d.json"%Time.get_ticks_usec()
	var save_ok := store.save(state)==OK
	check(save_ok,"persistência real em arquivo exclusivo")
	if not save_ok:
		print("DIGO_PROGRESS_RESULT checks=",checks," failures=",failures)
		quit(1)
		return
	var restored := STATE.new()
	var load_ok: bool = store.load_into(restored).get("ok",false)
	check(load_ok and DIGO.data(restored.world_state).lesson_completed and DIGO.workshop_unlocked(restored.world_state),"load conserva aula e amizade")
	if not load_ok:
		print("DIGO_PROGRESS_RESULT checks=",checks," failures=",failures)
		quit(1)
		return
	var previous := restored.snapshot()
	var bad := previous.duplicate(true)
	bad.world.digo.desert_raced = false
	check(not restored.restore_snapshot(bad) and restored.snapshot()==previous,"amizade sem corrida rejeitada atomicamente")
	bad = previous.duplicate(true)
	bad.world.digo.met = false
	check(not restored.restore_snapshot(bad),"aula sem encontro rejeitada")
	bad = previous.duplicate(true)
	bad.world.digo.lesson_completed = 1
	check(not restored.restore_snapshot(bad),"tipo inválido rejeitado")
	var gol := {"archetype":"digo_gol_1993","vehicle_id":"digo_gol_1993","region":"harbor","position":[-237,.13,-43.5],"yaw":-PI/2,"health":100.0}
	var amarok := {"archetype":"digo_amarok_2014","vehicle_id":"digo_amarok_2014","region":"harbor","position":[-237,.13,-47.0],"yaw":-PI/2,"health":100.0}
	var fleet := previous.duplicate(true)
	fleet.world.digo_vehicle = gol
	fleet.world.digo_amarok_vehicle = amarok
	check(restored.restore_snapshot(fleet),"Gol e Amarok coexistem em registros distintos")
	var fleet_before := restored.snapshot()
	bad = fleet_before.duplicate(true)
	bad.world.digo_amarok_vehicle.vehicle_id = "digo_gol_1993"
	check(not restored.restore_snapshot(bad) and restored.snapshot() == fleet_before,"ID do Gol no registro da Amarok é rejeitado atomicamente")
	bad = fleet_before.duplicate(true)
	bad.world.digo_amarok_vehicle.archetype = "digo_gol_1993"
	check(not restored.restore_snapshot(bad),"modelo errado da Amarok rejeitado")
	bad = fleet_before.duplicate(true)
	bad.world.digo_amarok_vehicle.position[0] = INF
	check(not restored.restore_snapshot(bad),"posição não finita da Amarok rejeitada")
	print("DIGO_PROGRESS_RESULT checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func check(ok: bool, title: String) -> void:
	checks += 1
	print("DIGO_PROGRESS ","PASS " if ok else "FAIL ",title)
	if not ok: failures += 1

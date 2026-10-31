extends "res://tests/test_robberies.gd"
## Economic contract: loot stays at risk until exit; bank death costs R$ 5000.
func _run() -> void:
	var session := Session.new()
	var room := Room.new()
	var player := Player.new()
	var gameplay := Gameplay.new()
	root.add_child(room)
	root.add_child(player)
	root.add_child(gameplay)
	session.room=room
	session.world={"player":player,"gameplay":gameplay,"driving":{"occupied":false}}
	session.state={"place_id":"harbor_bank","equipped_weapon":"pistol","economy":Economy.new()}
	session.state.economy.grant_reward("starting_money",8000)
	var heist := Heist.new()
	root.add_child(heist)
	heist.configure(session)
	heist.set_physics_process(false)
	heist._room=room
	heist.data.bank_alarm=true
	heist.data.guards[0]=0
	heist.data.keycard_available=true
	heist.data.keycard_taken=true
	heist.data.vault_open=true
	for point in Heist.LOOT:
		player.position=point
		heist._collect_nearby()
	check(heist.data.bank_pending==15000 and session.state.economy.balance==8000,"three piles are R$15000 carried, not deposited")
	check(heist.haul_label.text.contains("15.000"),"carried total is visible")
	var saved: Dictionary=JSON.parse_string(JSON.stringify(heist.snapshot()))
	check(heist.restore_snapshot(saved) and heist.data.bank_pending==15000,"carried haul survives snapshot")
	check(heist.player_died()==5000,"bank death charges exactly R$5000")
	check(session.state.economy.balance==3000 and heist.data.bank_pending==0,"death loses unbanked haul plus penalty")
	check(heist.player_died()==0 and session.state.economy.balance==3000,"duplicate death notification cannot charge twice")
	gameplay.health=0
	heist.bank_departed()
	check(session.state.economy.balance==3000,"rescue cannot secure lost haul")
	check(Heist.validate_snapshot(heist.snapshot()),"failed robbery remains save valid")
	# New bank cycle retains the unique death receipt ledger.
	heist._reopen_bank()
	heist._death_latched=false
	gameplay.health=100
	heist.data.bank_alarm=true
	heist.data.guards[0]=0
	heist.data.keycard_available=true
	heist.data.keycard_taken=true
	heist.data.vault_open=true
	player.position=Heist.LOOT[0]
	heist._collect_nearby()
	heist.bank_departed()
	check(session.state.economy.balance==8000 and heist.data.bank_pending==0,"partial escape secures only its R$5000 pile")
	heist.bank_departed()
	check(session.state.economy.balance==8000,"duplicate departure cannot pay twice")
	for i in [1,2]:
		player.position=Heist.LOOT[i]
		heist._collect_nearby()
	heist.bank_departed()
	check(session.state.economy.balance==18000,"later escape secures remainder, exact R$15000 cycle")
	check(heist.player_died()==5000 and session.state.economy.balance==13000,"new death charges new receipt, secured loot remains in wallet")
	# Uma carteira pobre é esvaziada, nunca fica negativa nem intocada.
	heist._death_latched=false
	session.state.economy.spend(12000,"poor_wallet_setup")
	check(heist.player_died()==1000 and session.state.economy.balance==0,"death with under R$5000 empties available wallet")
	check(heist.data.bank_deaths==3,"one ledger entry per distinct death")
	var invalid: Dictionary=heist.snapshot()
	invalid.bank_pending=15001
	check(not Heist.validate_snapshot(invalid),"malformed haul rejected")
	for version in [null,"3",NAN,3.5]:
		invalid=heist.snapshot()
		invalid.version=version
		check(not Heist.validate_snapshot(invalid),"invalid schema version rejected without script error "+str(version))
	session.state.place_id="harbor_fuel"
	heist._death_latched=false
	check(heist.player_died()==0 and heist.data.bank_deaths==3,"death in another place cannot charge bank penalty")
	for message in failures: push_error(message)
	print("BANK_STAKES checks=%d failures=%d"%[checks,failures.size()])
	heist.free()
	room.free()
	player.free()
	gameplay.free()
	stop_reward_audio()
	await process_frame
	quit(0 if failures.is_empty() else 1)

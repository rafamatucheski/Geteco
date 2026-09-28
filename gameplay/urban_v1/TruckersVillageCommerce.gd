extends RefCounted
## Local cash register and consumables. Wallet receipts prevent replaying
## rewards or purchases when older village state is restored alongside a wallet.
const DRINK_PRICE := 20
const DRINK_HEAL := 25
const REGISTER_CASH := 180
const REGISTER_COOLDOWN := 600.0
const HOSTILITY_SECONDS := 120.0
var data := {"version":1,"drink_serial":0,"robbery_serial":0,"register_cooldown":0.0,"hostility":0.0}
var quest

func configure(owner_quest) -> void:
	quest = owner_quest
	reconcile()

func buy_drink() -> bool:
	if not quest.counter_available(): return false
	var session = quest.session
	var gameplay = session.world.gameplay
	if gameplay.health >= 100:
		session.show_message("Sua vida já está cheia.")
		return false
	if data.drink_serial >= 1000000: return false
	var serial := int(data.drink_serial)+1
	if not session.state.economy.spend(DRINK_PRICE,"tonico_drink_%d"%serial):
		session.show_message("Você precisa de R$ 20 para comprar a bebida.")
		return false
	data.drink_serial = serial
	gameplay.heal(DRINK_HEAL)
	session.show_message("Bebida consumida · +25 de vida.")
	quest.save_when_allowed()
	return true

func rob_register() -> bool:
	if not quest.counter_available(): return false
	var session = quest.session
	if session.state.equipped_weapon in ["","fists"]:
		session.show_message("Empunhe uma arma para ameaçar o caixa.")
		return false
	if data.register_cooldown > 0:
		session.show_message("O caixa está vazio.")
		return false
	if data.robbery_serial >= 1000000: return false
	var serial := int(data.robbery_serial)+1
	if not session.state.economy.grant_reward("tonico_register_%d"%serial,REGISTER_CASH): return false
	data.robbery_serial = serial
	data.register_cooldown = REGISTER_COOLDOWN
	quest.trigger_conflict(session.world.player)
	session.world.gameplay.register_crime(30,quest.COOLER_POINT)
	session.show_message("R$ 180 roubados · Os moradores se armaram! Saia da vila.")
	# Crime/active quest checkpoint restrictions remain authoritative.
	quest.save_when_allowed()
	return true

func tick(delta: float) -> void:
	if not is_finite(delta) or delta <= 0: return
	data.register_cooldown = maxf(0,float(data.register_cooldown)-delta)
	data.hostility = maxf(0,float(data.hostility)-delta)
	if quest.session.world.gameplay.health <= 0: data.hostility = 0.0

func snapshot() -> Dictionary:
	return data.duplicate(true)

func restore_snapshot(saved: Dictionary) -> bool:
	if not validate_snapshot(saved): return false
	data = saved.duplicate(true)
	reconcile()
	return true

func reconcile() -> void:
	if quest == null or quest.session == null: return
	var transactions: Dictionary = quest.session.state.economy.snapshot().transactions
	for receipt in transactions:
		if str(receipt).begins_with("spend:tonico_drink_"):
			data.drink_serial = maxi(int(data.drink_serial),str(receipt).trim_prefix("spend:tonico_drink_").to_int())
		elif str(receipt).begins_with("reward:tonico_register_"):
			var serial := str(receipt).trim_prefix("reward:tonico_register_").to_int()
			if serial > data.robbery_serial:
				data.robbery_serial = serial
				data.register_cooldown = REGISTER_COOLDOWN
				data.hostility = HOSTILITY_SECONDS

static func validate_snapshot(saved: Dictionary) -> bool:
	if saved.get("version") != 1: return false
	for key in ["drink_serial","robbery_serial"]:
		var value: Variant = saved.get(key)
		if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or value < 0 or value > 1000000 or float(value) != floorf(float(value)): return false
	for key in ["register_cooldown","hostility"]:
		var value: Variant = saved.get(key)
		if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or value < 0: return false
	if saved.register_cooldown > REGISTER_COOLDOWN or saved.hostility > HOSTILITY_SECONDS: return false
	if saved.register_cooldown > 0 and saved.robbery_serial == 0: return false
	return true

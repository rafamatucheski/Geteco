extends RefCounted
## Productive V1 service contracts; callbacks belong to their native 3D adapters.
const SERVICES := {
	"northgate_auto_repair": {
		"price": 100,
		"requires": "player-driven vehicle stopped in the Northgate service bay",
		"delivers": "repair vehicle and clear wanted level",
		"source": "world/harbor/HarborAutoService.gd:PRICE,_repair",
	},
	"personal_car_repair": {
		"price": 50,
		"requires": "damaged unlocked Monaliza parked in Maciota's garage; player inside garage",
		"delivers": "repair Monaliza",
		"source": "world/harbor/monaliza/PersonalCarManager.gd:REPAIR_FEE,can_repair,repair",
	},
	"personal_car_recovery": {
		"price": 50,
		"requires": "unlocked Monaliza eligible for recovery; player at its garage bay",
		"delivers": "recover and repair Monaliza in the service bay",
		"source": "world/harbor/monaliza/PersonalCarManager.gd:RECOVERY_FEE,can_recover,recover",
	},
	"body_armor": {
		"price": 500,
		"requires": "armor below maximum",
		"delivers": "restore armor up to 100",
		"transaction": "Economy.purchase_body_armor(current_armor, maximum_armor, transaction_id)",
		"source": "world/harbor/interiors/HarborAmmunationInterior.gd:_data,purchase; characters/Player.gd:buy_armor_amount",
	},
}
const AMMO_MINIMUM_PRICE := 40
const AMMO_PRICE_PER_ROUND := 2
const EXPLOSIVE_PRICE_PER_ROUND := 60
# No vehicle-sale prices existed in VehicleCatalog. Do not invent a dealership.

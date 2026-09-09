class_name VehicleUpgradeManager
extends Node

## Gerenciador Universal de Upgrades de Veículos e Tuning (Need For Speed Style)
## Controla o desbloqueio progressivo por zonas de Nitro (NOS), Neon Underglow, Turbo e Blindagem.

signal upgrade_purchased(upgrade_id: String, level: int)
signal custom_neon_changed(new_color: Color)

var unlocked_upgrades := {
	"nitro_stage": 0,     # NOS desativado em todas as zonas
	"neon_underglow": 1,  # Neon desbloqueado na Zona 1
	"turbo_stage": 1,     # Turbo desbloqueado na Zona 1
	"armor_plating": 0    # Desbloqueado após derrotar o Don Hector
}

var active_customization := {
	"nitro_equipped": false,
	"neon_equipped": true,
	"neon_color": Color("#00cec9"), # Ciano vibrante
	"turbo_equipped": true,
	"armor_equipped": false
}

func _ready() -> void:
	add_to_group("vehicle_upgrade_manager")

func apply_upgrades_to_vehicle(vehicle: Node2D) -> void:
	if not is_instance_valid(vehicle): return
	
	# Legacy customization must never re-enable NOS on any vehicle.
	active_customization["nitro_equipped"] = false
	unlocked_upgrades["nitro_stage"] = 0
	for property in ["has_nitro", "is_nitro_active"]:
		if property in vehicle: vehicle.set(property, false)
	for property in ["nitro_amount", "nitro_max"]:
		if property in vehicle: vehicle.set(property, 0.0)

	if active_customization["neon_equipped"] and unlocked_upgrades["neon_underglow"] > 0:
		vehicle.set("has_neon", true)
		vehicle.set("neon_color", active_customization["neon_color"])
		if vehicle.has_method("_setup_neon_underglow"):
			vehicle._setup_neon_underglow()
			
	if active_customization["turbo_equipped"] and unlocked_upgrades["turbo_stage"] > 0:
		vehicle.set("has_turbo", true)
		var boost_mult = 1.0 + 0.15 * float(unlocked_upgrades["turbo_stage"])
		if "max_speed" in vehicle:
			vehicle.max_speed *= boost_mult

func set_neon_color(color: Color) -> void:
	active_customization["neon_color"] = color
	active_customization["neon_equipped"] = true
	custom_neon_changed.emit(color)

func unlock_next_zone_upgrades(zone_index: int) -> void:
	if zone_index >= 1:
		unlocked_upgrades["armor_plating"] = 1
		unlocked_upgrades["nitro_stage"] = 0
		unlocked_upgrades["turbo_stage"] = 2

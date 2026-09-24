extends Node3D
## Adaptador entre o Responder original e o EmergencyManager real. O Responder
## fala com `manager.incidents/gameplay/extinguish/complete/report_injury/release`;
## aqui tudo, exceto `release`, vai direto ao gerente real, de modo que existe um
## único registro de ocorrências e um único atendimento médico. Só `release` é
## nosso: o gerente real apagaria a viatura no ponto de estacionamento, e aqui
## a viatura precisa embarcar a equipe e ir embora dirigindo.

signal crew_released(crew: CharacterBody3D)
signal completion_refused(key: int)

var emergency: Node3D
var gameplay: Node3D
var incidents: Dictionary = {}
## incidente -> papel com que a equipe saiu; confere se ainda é o papel da ocorrência.
var roles: Dictionary = {}

func setup(real: Node3D) -> void:
	emergency = real
	gameplay = real.gameplay
	roles.clear()
	# Mesmo Dictionary do gerente real; ele nunca o reatribui.
	incidents = real.incidents

func extinguish(fire: Node3D, amount: float) -> void:
	emergency.extinguish(fire, amount)

func complete(key: int) -> void:
	var record: Dictionary = incidents.get(key, {})
	if record.is_empty(): return
	var expected: String = roles.get(key, "")
	var patient_dead: bool = is_instance_valid(record.actor) and record.actor.get("dead") == true
	# `complete` do gerente age pelo papel da ocorrência: com o paciente morto
	# ele removeria o corpo (legista) ou reviveria o morto (paramédico).
	if expected != "" and (record.role != expected or (expected == "medic" and patient_dead)):
		if expected == "medic" and patient_dead: emergency.report_injury(record.actor, true)
		completion_refused.emit(key)
		return
	emergency.complete(key)
	roles.erase(key)

func report_injury(actor: Node3D, fatal: bool = false) -> void:
	emergency.report_injury(actor, fatal)

func release(crew: CharacterBody3D) -> void:
	if is_instance_valid(crew): roles.erase(int(crew.get("incident_id")))
	crew_released.emit(crew)

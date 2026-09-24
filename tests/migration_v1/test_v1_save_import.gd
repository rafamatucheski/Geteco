extends SceneTree

const IMPORT := preload("res://migration/v1/V1SaveImport.gd")
const FIXTURES := preload("res://tests/migration_v1/V1Fixtures.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const SOURCE := "user://v1_import_contract_source.json"
const DESTINATION := "user://v1_import_contract_destination.json"

class FakeLaunch extends Node:
	var selected_path := DESTINATION
	func prepare_import_destination(slot_id: String) -> Error:
		if slot_id != "slot_01": return ERR_INVALID_PARAMETER
		if FileAccess.file_exists(selected_path) or FileAccess.file_exists(selected_path+".bak") or FileAccess.file_exists(selected_path+".tmp"): return ERR_ALREADY_EXISTS
		return OK

var checks := 0
var failures: Array[String] = []

func _init() -> void:
	_cleanup()
	var source_text := JSON.stringify(FIXTURES.start(),"\t")
	var source_file := FileAccess.open(SOURCE,FileAccess.WRITE)
	check(source_file != null,"fixture de importação abre somente no user isolado")
	if source_file != null:
		source_file.store_string(source_text)
		source_file.close()
	var conversion := IMPORT.inspect(SOURCE)
	check(conversion.get("read_error",FAILED)==OK and conversion.get("ready_for_publication",false),"save V1 seguro é lido e validado antes de publicar")
	check(FileAccess.get_file_as_string(SOURCE)==source_text,"inspeção não altera o arquivo V1")
	var launch := FakeLaunch.new()
	var error := IMPORT.publish(conversion,"slot_01",launch)
	check(error==OK and not STORE.read_valid(DESTINATION).is_empty(),"proposta validada publica uma cópia V2 em slot vazio")
	check(FileAccess.get_file_as_string(SOURCE)==source_text,"publicação mantém o arquivo V1 intacto")
	check(IMPORT.publish(conversion,"slot_01",launch)==ERR_ALREADY_EXISTS,"importação nunca sobrescreve slot existente")
	var owned_car := FIXTURES.start()
	owned_car.campaign.cobra_campaign = {"secret_owned":{"ashbend_coupe":{"owned":true,"position":[7050.0,2290.0],"rotation":PI,"paint":"9f673f","health":90,"was_driven":false}}}
	var secret_conversion := preload("res://migration/v1/V1SaveConverter.gd").convert(owned_car)
	check(secret_conversion.get("ready_for_publication",false),"cupê secreto da V1 agora tem identidade V2 segura")
	var secret_record: Dictionary = secret_conversion.proposal.world.get("ashbend_secret_car",{})
	check(secret_record.get("paint","") == "9f673f" and is_equal_approx(float(secret_record.get("position",[0])[0]),7050.0/16.0),"posição e pintura do cupê secreto migram")
	var ambiguous := preload("res://migration/v1/V1SaveConverter.gd").convert(FIXTURES.unknown_fields())
	check(not ambiguous.ready_for_publication and IMPORT.publish(ambiguous,"slot_02",launch)==ERR_INVALID_DATA,"campos sem conversão bloqueiam publicação")
	var invalid_file := FileAccess.open(SOURCE,FileAccess.WRITE)
	invalid_file.store_string("{inválido")
	invalid_file.close()
	check(IMPORT.inspect(SOURCE).read_error==ERR_PARSE_ERROR,"JSON inválido é recusado sem criar destino")
	launch.free()
	_cleanup()
	print("V1_SAVE_IMPORT ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func check(condition: bool,label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _cleanup() -> void:
	for path in [SOURCE,DESTINATION,DESTINATION+".bak",DESTINATION+".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

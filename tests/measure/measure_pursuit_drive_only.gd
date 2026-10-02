extends "res://tests/measure/measure_pursuit_drive_roundtrip.gd"
## Regressão apenas da direção/perseguição/contato/volta; combate não retestado.
func _combat()->void:
	print("DRIVE_ONLY combat phase omitted; production combat remains enabled")
func _finish()->void:
	super._finish()
	var path:=output_dir.path_join("pilot.json")
	var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	report.mode="drive-contact-return-only"
	report.limits="Perfil atual da cadeia reprovada: setup inicial explícito, percurso/contato/volta só Input e física produtiva. Diretores, densidade, áudio, colisão e dano intactos. Sem fase de combate; prova anterior separada não substitui este percurso. Sem baseline equivalente para ganho causal; recuperação apenas observada."
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()

extends SceneTree
## Synthetic persistence acceptance. Never instantiates Main.tscn and never
## resolves the default user:// save. Requires --isolated-save-root=<unique
## absolute directory below OS.get_temp_dir()>.

const STATE:=preload("res://runtime/GameState.gd")
const STORE:=preload("res://runtime/SaveStore.gd")
var failures:Array[String]=[]
var checks:=0

func _initialize()->void: _run()

func check(ok:bool,label:String,detail:="")->void:
	checks+=1
	print(("SAVE PASS " if ok else "SAVE FAIL ")+label+((" | "+detail) if detail!="" else ""))
	if not ok: failures.append(label); push_error(label+((" | "+detail) if detail!="" else ""))

func isolated_root()->String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--isolated-save-root="): return arg.trim_prefix("--isolated-save-root=").replace("\\","/").trim_suffix("/")
	return ""

func canonical(path:String)->String:
	return ProjectSettings.globalize_path(path).replace("\\","/").simplify_path().to_lower()

func report_snapshot_difference(label:String, expected:Dictionary, actual:Dictionary)->void:
	if storage_equivalent(expected,actual): return
	print("SAVE DIFF ",label," expected=",JSON.stringify(expected))
	print("SAVE DIFF ",label," actual=",JSON.stringify(actual))

func storage_equivalent(expected:Dictionary,actual:Dictionary)->bool:
	# Compare in the representation the JSON store actually guarantees. This
	# permits only JSON's int/float normalization (for example 32 -> 32.0), not
	# missing keys or changed values.
	return JSON.parse_string(JSON.stringify(expected))==JSON.parse_string(JSON.stringify(actual))

func _run()->void:
	var directory:=isolated_root()
	var temp:=canonical(OS.get_temp_dir()).trim_suffix("/")+"/"
	var resolved:=canonical(directory).trim_suffix("/")+"/"
	if directory.is_empty() or not directory.is_absolute_path() or not resolved.begins_with(temp) or resolved==temp:
		push_error("SYNTHETIC_SAVE refuses non-unique storage outside OS.get_temp_dir(): "+directory)
		quit(2); return
	var path:=directory.path_join("progress.json")
	check(not path.begins_with("user://") and canonical(path).begins_with(resolved),"caminho absoluto permanece no diretorio temporario exclusivo",canonical(path))
	check(canonical(path)!=canonical(STORE.PATH),"caminho padrao do jogador nunca e usado",canonical(STORE.PATH))

	var state=STATE.new()
	state.economy.grant_reward("acceptance_seed",725)
	state.grant_weapon("pistol"); state.equip_weapon("pistol")
	state.combat_state={"health":63.0,"armor":25.0,"crime_points":32,"hidden_time":4.5,"customization":{}}
	state.world_state.pedestrian={"region":"harbor","position":[49.25,.08,93.4]}
	state.world_state.time=.61; state.set_location("harbor")
	check(state.campaign.begin("primeiro_giro"),"estado sintetico inclui missao ativa")
	var first_step:Dictionary=state.campaign.apply_event("bank_receipt_received",{"target_id":"helena","on_foot":true,"unarmed":true})
	check(first_step.ok and state.campaign.step==1,"estado sintetico inclui objetivo intermediario")

	var store=STORE.new(); store.path=path
	check(store.path==path and store.path!=STORE.PATH,"SaveStore usa somente o destino injetado")
	check(store.save(state)==OK,"primeiro snapshot e publicado")
	check(FileAccess.file_exists(path),"arquivo sintetico existe no destino isolado")
	var first_snapshot:Dictionary=state.snapshot()
	state.economy.grant_reward("acceptance_second",75); state.combat_state.health=41.0
	check(store.save(state)==OK,"segundo snapshot e publicado com backup")
	check(FileAccess.file_exists(path+".bak"),"backup sintetico fica no mesmo diretorio isolado")
	var latest_snapshot:Dictionary=state.snapshot()

	var loaded=STATE.new(); var result:Dictionary=store.load_into(loaded)
	check(result.get("ok",false) and not result.get("recovered",false),"snapshot mais recente e carregado")
	report_snapshot_difference("latest",latest_snapshot,loaded.snapshot())
	check(storage_equivalent(latest_snapshot,loaded.snapshot()),"restauracao preserva economia combate missao e mundo")
	check(loaded.economy.balance==800 and loaded.equipped_weapon=="pistol","saldo e arma restaurados")
	check(int(loaded.combat_state.health)==41 and loaded.campaign.step==1,"vida e objetivo intermediario restaurados")

	var corrupt:=FileAccess.open(path,FileAccess.WRITE)
	check(corrupt!=null,"primario sintetico pode ser interrompido para testar recuperacao")
	if corrupt!=null: corrupt.store_string("{ interrupted synthetic acceptance"); corrupt.close()
	var recovered=STATE.new(); var recovered_result:Dictionary=store.load_into(recovered)
	check(recovered_result.get("ok",false) and recovered_result.get("source","")=="backup","backup isolado recupera primario interrompido",str(recovered_result))
	report_snapshot_difference("backup",first_snapshot,recovered.snapshot())
	check(storage_equivalent(first_snapshot,recovered.snapshot()),"recuperacao volta ao ultimo snapshot valido anterior")
	check(store.save(recovered)==OK,"estado recuperado volta a ser publicavel sem apagar evidencia corrupta")
	check(STORE.read_valid(path).size()>0,"arquivo final isolado e valido")
	print("HARBOR_SYNTHETIC_SAVE_ROOT ",resolved)
	print("HARBOR_SYNTHETIC_SAVE_ACCEPTANCE ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

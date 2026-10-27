extends SceneTree
const MODELS = preload("res://gameplay/ArsenalWeapon3D.gd")
const VARIANTS = preload("res://gameplay/WeaponVariantModels.gd")
const POSE = preload("res://gameplay/WeaponRigPose.gd")
const AUDIO = preload("res://gameplay/CombatAudio.gd")
const CATALOG = preload("res://gameplay/WeaponCatalog.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 27102026
	var effects := preload("res://gameplay/CombatEffects.gd").new()
	root.add_child(effects)
	for id: String in VARIANTS.IDS:
		var model := Node3D.new()
		root.add_child(model)
		var tip: Vector3 = MODELS.build(model,id)
		check(tip.z < -.20, id+" has its own barrel and muzzle, not the pistol fallback")
		check(model.find_children("*","MeshInstance3D",true,false).size() > 0,id+" has rendered geometry")
		var data := CATALOG.get_weapon(id)
		var rig := POSE.new()
		rig.attack(id,float(data.get("recoil_multiplier",1)))
		check(rig.recoil>0,id+" has recoil")
		var frame: Dictionary = {}
		for i in 60: frame = rig.update(id,1.0/60.0,true,false,0.0,false,false,0.0)
		check(bool(frame.get("visible",false)),id+" is visible after drawing")
		check(bool(frame.get("long_weapon",false)) == (id != "pistol_suppressed"),id+" uses matching hand/shoulder pose")
		check(not rig.reload_targets(id,.5).is_empty(),id+" has a reload motion")
		if id == "shotgun_auto":
			check(model.get_node_or_null("Pump")==null,"semiautomatic has fixed fore-end, no manual pump")
			rig.attack(id)
			for i in 15: frame=rig.update(id,1.0/60.0,true,false,0,false,false,0)
			check(is_zero_approx(float(frame.get("pump",0))),"semiautomatic never pumps between shots")
		if id.begins_with("smg_"): check(model.get_node_or_null("CurvedMagazine")!=null,id+" keeps detachable magazine animated")
		var shot: AudioStream = AUDIO.gunfire_take(id,rng)
		var reload: AudioStream = AUDIO.reload_take(id,rng)
		check(shot!=null and shot.get_length()>0,id+" has playable shot now")
		check(reload!=null and reload.get_length()>0,id+" has playable reload now")
		check(AUDIO.reload_seconds(id)>.5,id+" reload fallback has a duration")
		var shell_slot: int = effects._next_shell
		effects.weapon_shot(id,Vector3(0,1,0),Vector3.FORWARD,2)
		check(effects._next_shell != shell_slot,id+" ejects casing on discharge")
		check(bool(effects._shell_state[shell_slot].get("shotgun",false)) == (id=="shotgun_auto"),id+" ejects correct case type")
		model.free()
	for i in 100: effects.weapon_shot("smg_compact",Vector3(0,1,0),Vector3.FORWARD,1)
	check(effects._shells.size()==effects.MAX_SHELLS,"rapid automatic fire keeps a bounded casing pool")
	effects.free()
	print("VARIANT_PRESENTATION checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)

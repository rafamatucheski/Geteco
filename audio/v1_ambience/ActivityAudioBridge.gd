extends Node
## Read-only bridge to live V2 activity state; activity systems remain authoritative.
const BANK := preload("res://audio/v1_ambience/V1AudioCatalog.gd")
var world
var voices: Array[AudioStreamPlayer] = []
var previous_mode := ""
var previous_gate := 0
var previous_mountain_mode := ""
var previous_mountain_gate := 0
var previous_campaign_gate := -1
var previous_campaign_countdown := -1

func _ready() -> void:
	for index in 2:
		var voice := AudioStreamPlayer.new()
		voice.name = "ActivityCue%d"%index
		voice.bus = &"SFX" if AudioServer.get_bus_index(&"SFX")>=0 else &"Master"
		voice.volume_db = -8
		add_child(voice)
		voices.append(voice)

func _process(_delta: float) -> void:
	if world == null or world.session == null: return
	_update_free_activities()
	_update_mountain_activity()
	_update_campaign_race()

func _update_free_activities() -> void:
	var activities = world.session.activities
	if activities == null: return
	var motorsport = activities.motorsport
	var mode := str(motorsport.mode)
	if mode != previous_mode:
		if not mode.is_empty():
			previous_gate = int(motorsport.gate)
			_play("countdown" if mode=="race" else "mission_start")
		elif not previous_mode.is_empty() and bool(motorsport.finished): _play("complete")
	if mode=="race" and int(motorsport.gate)>previous_gate:
		previous_gate = int(motorsport.gate)
		_play("checkpoint")
	previous_mode = mode

func _update_mountain_activity() -> void:
	var progression = world.session.mountain_progression
	if progression == null: return
	var race = progression.race
	var mode := str(race.mode)
	if mode != previous_mountain_mode:
		if not mode.is_empty():
			previous_mountain_gate = int(race.gate)
			_play("countdown")
		elif not previous_mountain_mode.is_empty() and bool(race.finished): _play("complete")
	if mode=="race" and int(race.gate)>previous_mountain_gate:
		previous_mountain_gate = int(race.gate)
		_play("checkpoint")
	previous_mountain_mode = mode

func _update_campaign_race() -> void:
	var campaign = world.session.state.campaign
	if campaign == null or str(campaign.active_id)!="cobra_race":
		previous_campaign_gate = -1
		previous_campaign_countdown = -1
		return
	var status: Dictionary = campaign.race_status()
	var countdown := ceili(float(status.get("countdown",0.0)))
	var gate := int(status.get("checkpoint",status.get("gate",0)))
	if countdown>0 and previous_campaign_countdown<=0: _play("countdown")
	if previous_campaign_gate>=0 and gate>previous_campaign_gate: _play("checkpoint")
	previous_campaign_countdown = countdown
	previous_campaign_gate = gate

func _play(kind: String) -> void:
	var stream := BANK.activity(kind)
	if stream == null: return
	var voice := voices[0]
	for candidate in voices:
		if not candidate.playing:
			voice = candidate
			break
	voice.stream = stream
	voice.play()

func _exit_tree() -> void:
	for voice in voices:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null

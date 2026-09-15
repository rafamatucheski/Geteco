extends Node2D
## Ground fragments with a short ballistic bounce, then persistent scattered remains.
var pieces: Array[Dictionary] = []
var age := 0.0

func _ready() -> void:
	get_node("/root/WorldRenewal").watch_transient(self, 30.0)

static func spawn(parent: Node, point: Vector2, direction: Vector2, speed: float, material: String, extent := Vector2(24,22)) -> Node2D:
	var debris := load("res://world/shared/ImpactDebris.gd").new() as Node2D
	parent.add_child(debris)
	debris.global_position = point
	# Storage art has its own elevated Z layer; fragments belong to the ground,
	# below vehicles (Z = 8), regardless of which prop spawned them.
	debris.z_as_relative = false
	debris.z_index = 5
	var audio := AudioStreamPlayer2D.new()
	audio.stream = preload("res://world/harbor/HarborAudioBank.gd").sound("wood_break") if material == "wood" else ProceduralAudio.get_trashcan_hit_stream()
	audio.bus = &"SFX"
	audio.volume_db = -10
	audio.max_distance = 500
	debris.add_child(audio)
	audio.finished.connect(audio.queue_free)
	audio.play()
	for i in (18 if material == "wood" else 24):
		var size := Vector2(randf_range(9,22),randf_range(2,5)) if material == "wood" else Vector2(randf_range(3,9),randf_range(3,7))
		var palette := [Color("ad8750"),Color("795733"),Color("c49b60")] if material == "wood" else [Color("dbd3b8"),Color("57624b"),Color("939ba1"),Color("ba985f")]
		debris.pieces.append({"p":Vector2(randf_range(-extent.x*.4,extent.x*.4),randf_range(-extent.y*.4,extent.y*.4)),"v":direction*minf(speed*.45,180)+Vector2.from_angle(randf()*TAU)*randf_range(25,100),"h":randf_range(3,16),"up":randf_range(45,110),"a":randf()*TAU,"spin":randf_range(-8,8),"size":size,"color":palette[i%palette.size()]})
	if material == "trash":
		# The lid and dented bin remain identifiable among paper and loose rubbish.
		debris.pieces[0].size = Vector2(extent.x*1.15,5)
		debris.pieces[0].color = Color("72786c")
		debris.pieces[1].size = Vector2(extent.x*.8,extent.y*.65)
		debris.pieces[1].color = Color("414b40")
		debris.pieces[1].v *= .3
	return debris

func _process(delta: float) -> void:
	age += delta
	for piece in pieces:
		piece.p += piece.v * delta
		piece.v = piece.v.move_toward(Vector2.ZERO, 85*delta)
		if piece.h > 0 or piece.up > 0:
			piece.up -= 300*delta
			piece.h += piece.up*delta
			piece.a += piece.spin*delta
			if piece.h < 0:
				piece.h = 0.0
				piece.up = -piece.up*.25 if absf(piece.up)>30 else 0.0
	modulate.a = 1.0-smoothstep(24,30,age)
	queue_redraw()
	if age >= 30: queue_free()

func _draw() -> void:
	for piece in pieces:
		draw_set_transform(piece.p, piece.a)
		draw_rect(Rect2(-piece.size*.5,piece.size),Color(0,0,0,.2))
		draw_set_transform(piece.p-Vector2(0,piece.h),piece.a)
		draw_rect(Rect2(-piece.size*.5,piece.size),piece.color)
		draw_line(-piece.size*.5,Vector2(piece.size.x*.5,-piece.size.y*.5),piece.color.lightened(.2),1)
	draw_set_transform(Vector2.ZERO)

extends "res://assets/CivilianModel.gd"
## Rig e andar civis compartilhados, com pequenos acessórios presos às juntas reais.
const ART := preload("res://world/places/amusement_park/ParkGeometry.gd")
const PALETTES := [["347f95","a63f55","e4b754"],["a64951","3c626b","ddbd57"],["735290","cab44a","46978a"],["c47c38","496aa0","a63f55"]]
var clown_index := 0

func _ready() -> void:
	var colors: Array = PALETTES[clown_index%4]
	appearance_locked = true
	appearance_variant = 740+clown_index
	coat_color = Color(colors[0])
	pants_color = Color(colors[1])
	wardrobe_overrides = {"female":clown_index%2==1,"build":0,"top":1,"bottom":0,"shoe":0,"height":1.0,
		"hat":0,"hair":1,"beard":0,"glasses":false,"backpack":false,"bag":0,
		"hair_color":Color(colors[2]),"inner":Color("e8d7b6"),"shoe_color":Color(colors[2])}
	# Corpo do Meshy com roupa na cor do palhaço, peruca e nariz vermelho; sem catálogo, segue o corpo do kit.
	if preload("res://assets/civilians/RoleBodyCatalog.gd").apply(self, "clown", clown_index, clown_index % 2 == 1, true):
		body_tint = {"hue": [0.0, 0.35, -0.3, 0.55][clown_index % 4], "tone": Color(colors[0]).lightened(0.35) * 1.5, "brightness": 1.1}
		body_accessories = [{"kind": "clown", "color": Color(colors[2]), "band": Color("d1202a")}]
	super._ready()
	head_node.set_instance_shader_parameter("skin_color",Color("eee4ce"))
	var head := ART.new()
	head_node.add_child(head)
	head.ball(Vector3(0,.145,.153),Vector3.ONE*.047,"b73c48")
	for side in [-1,1]:
		head.ball(Vector3(side*.087,.18,-.004),Vector3(.085,.12,.115),colors[2])
		head.ball(Vector3(side*.058,.132,.109),Vector3(.025,.023,.012),"b73c48")
	head.box("Smile",Vector3(0,.099,.127),Vector3(.063,.012,.008),"b73c48")
	head.cylinder(Vector3(0,.296,-.008),.14,.025,colors[1])
	head.cylinder(Vector3(0,.385+clown_index*.012,-.008),.087,.17+clown_index*.024,colors[0])
	head.cylinder(Vector3(0,.321,-.008),.089,.032,colors[2])
	head.flush()
	var chest := ART.new()
	spine.add_child(chest)
	chest.ball(Vector3(0,.282,.147),Vector3(.040,.040,.026),colors[1])
	for side in [-1,1]: chest.ball(Vector3(side*.052,.282,.135),Vector3(.095,.067,.025),colors[2])
	for y in [.08,.15,.22]: chest.ball(Vector3(0,y,.158),Vector3.ONE*.033,"e8d7b6")
	chest.cylinder(Vector3(0,.391,0),.108,.030,"e8d7b6")
	chest.flush()

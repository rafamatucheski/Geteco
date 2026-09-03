extends Area2D

@export var mission_id: String = "mission_01"
@export var mission_dialog: String = "Ei, você! Roube o carro esportivo vermelho e traga para a garagem."

var is_ringing: bool = true
var player_nearby: bool = false

@onready var phone_sprite = $Sprite2D

func _ready():
    body_entered.connect(_on_body_entered)
    body_exited.connect(_on_body_exited)

func _process(_delta):
    # Efeito visual retrô: telefone tremendo quando está tocando
    if is_ringing:
        var time = Time.get_ticks_msec() / 1000.0
        phone_sprite.position.x = sin(time * 30.0) * 1.5
    else:
        phone_sprite.position.x = 0

    # Atender o telefone
    if is_ringing and player_nearby and Input.is_action_just_pressed("interact"):
        answer_phone()

func answer_phone():
    is_ringing = false
    print("----- CHAMADA ATENDIDA -----")
    print(mission_dialog)
    # No futuro, enviaremos essa string de diálogo para a interface (HUD)
    
func _on_body_entered(body):
    if body.is_in_group("player"):
        player_nearby = true

func _on_body_exited(body):
    if body.is_in_group("player"):
        player_nearby = false

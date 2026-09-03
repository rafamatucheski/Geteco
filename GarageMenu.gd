extends CanvasLayer

signal repaired
signal canceled

@export var repair_cost: int = 150

@onready var price_label = $Panel/VBoxContainer/PriceLabel
@onready var yes_btn = $Panel/VBoxContainer/HBoxContainer/YesButton
@onready var no_btn = $Panel/VBoxContainer/HBoxContainer/NoButton

func _ready():
    price_label.text = "Reparar Veículo e Limpar Ficha?\nPreço: $%d" % repair_cost
    yes_btn.pressed.connect(_on_yes)
    no_btn.pressed.connect(_on_no)

    # Verifica se tem dinheiro suficiente (lendo diretamente da HUD caso exista)
    # Procuramos o HUD globalmente para chegar no dinheiro
    var hud = get_tree().get_root().get_node_or_null("World/CityDemo/HUD")
    if not hud:
        hud = get_tree().get_first_node_in_group("hud") # Caso tenhamos adicionado a HUD num grupo
        
    yes_btn.grab_focus()

func _on_yes():
    repaired.emit()
    queue_free()

func _on_no():
    canceled.emit()
    queue_free()

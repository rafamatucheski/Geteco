# 🏪 ShopInterior - Cena Reutilizável de Interior de Loja (Top-Down)

Esta cena fornece um modelo modular, cartunesco e 100% procedural para interiores de lojas em perspectiva top-down, construído exclusivamente com nós nativos do Godot (`Polygon2D`, `Line2D`, `StaticBody2D`, `CollisionShape2D`, `Area2D`, `Marker2D`).

---

## 📁 Arquivos:
* **Cena:** `res://interiors/ShopInterior.tscn` (ou `res://scenes/ShopInterior.tscn`)
* **Script:** `res://interiors/ShopInterior.gd`

---

## 🧱 Elementos Inclusos na Cena:
1. **Piso (Floor):** Ladrilhos estilizados com sombreamento cartunesco e capacho de boas-vindas na entrada.
2. **Paredes e Colisões (Walls):** 4 paredes perimetrais sólidas com colisores (`StaticBody2D`) e vão de porta no sul.
3. **Balcão de Atendimento (Counter):** Balcão de madeira em "L" com colisões e ponto para o vendedor (`ClerkSpot`).
4. **Caixa Registradora (CashRegister):** Miniatura com teclado, visor digital verde e gaveta de dinheiro.
5. **Prateleiras de Produtos (Shelves):** Prateleiras ao longo das paredes norte e oeste com colisão.
6. **Porta de Entrada/Saída (Doorway):** `Area2D` com gatilho de colisão e `SpawnPoint` (`Marker2D`) para posicionar o jogador ao entrar.
7. **Pontos de Exposição Vazios (DisplaySlots):**
   * `Slot_Pedestal_01` até `Slot_Pedestal_04`: Pedestais no chão com borda brilhante para itens/armas principais.
   * `Slot_Wall_01` até `Slot_Wall_03`: Pontos na parede norte para pendurar itens/armas.

---

## 🚀 Como Instanciar no Jogo ou Via Código:

### 1. No Editor do Godot:
1. Arraste `res://interiors/ShopInterior.tscn` para dentro da sua cena.
2. No painel **Inspector**, você pode customizar as propriedades expostas:
   * `Shop Name`: Nome da loja (ex: `"AMMU-NATION"`, `"CONVENIÊNCIA 24H"`, `"FARMÁCIA"`).
   * `Accent Color`: Cor de destaque do letreiro e detalhes.
   * `Floor Color Primary` / `Floor Color Secondary`: Cores dos ladrilhos do piso.

### 2. Via GDScript:
```gdscript
# Carrega e instancia o interior da loja
var shop_scene = preload("res://interiors/ShopInterior.tscn")
var shop_instance: ShopInterior = shop_scene.instantiate()
add_child(shop_instance)

# Posiciona o jogador no ponto de entrada
var player_spawn_pos = shop_instance.get_spawn_position()
player.global_position = player_spawn_pos

# Conecta sinais da porta
shop_instance.player_exited_door.connect(_on_player_leave_shop)

# Adiciona um item/arma a um pedestal vazio
var item_mesh = create_weapon_pickup_node()
shop_instance.set_slot_item("Slot_Pedestal_01", item_mesh)
```

---

## 🔌 Sinais Disponíveis:
* `signal player_entered_door(body: Node2D)`: Emitido quando um corpo entra no gatilho da porta.
* `signal player_exited_door(body: Node2D)`: Emitido quando um corpo sai pelo vão da porta.
* `signal display_slot_activated(slot_id: String, slot_node: Marker2D)`: Emitido ao interagir com um pedestal.

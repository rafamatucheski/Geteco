# Guia de Integração — Prensa do Neco (Geteco V2)

Componente 3D modular e independente para apresentação cinematográfica e cinemática do esmagamento de veículos na sucata do Neco (`geteco_v2/world/neco_press/`).

---

## 1. Responsabilidades e Fronteiras de Arquitetura

O `NecoPress3D` é um **componente estritamente visual e de apresentação cinemática**. Para preservar o isolamento do domínio de jogo:
- **NÃO apaga entidades do jogo**: Não chama `queue_free()` ou remove nós do mundo.
- **NÃO desloca o veículo físico/entidade real**: A física e os nós reais de `Vehicle` permanecem sob controle do gameplay e do integrador. O integrador passa uma duplicata/representação visual (`vehicle_visual: Node3D`) para a prensa animar.
- **NÃO altera save games**: Não acessa `SaveManager` nem grava estados.
- **NÃO concede dinheiro nem recompensas**: Toda a economia, cálculo de valor residual e pagamento ao jogador pertencem exclusivamente a `GarageRewards`.
- **NÃO decide elegibilidade**: A verificação de quais veículos podem ser prensados e o acionamento da missão continuam em `GarageRewards` / `MissionWorld`.
- **NÃO possui textos decorativos ou descritivos**: Fachadas e estrutura em conformidade com `AGENTS.md`.

---

## 2. Origem da Geometria: Preservação V1 e Reconstruções Nativas

Para cumprir o critério de preservação das proporções e reaproveitamento do original, a geometria foi mapeada a partir de `cars/salvage/SalvageYard3D.gd:248-263, 373-418` e `world/places/SalvageYardNative.gd:248-263`:

### Geometria Original Preservada da Fonte V1:
- **Plataforma da Base**: Caixa `Vector3(3.4, 0.5, 5.0)` em cinza escuro industrial (`#566556`).
- **Quatro Colunas Estruturais**: Caixas `Vector3(0.28, 3.8, 0.28)` em amarelo de maquinário (`#d39c43`) nas coordenadas de canto `(±1.6, 1.9, ±2.2)`.
- **Trilhos Guia do Pórtico**: Caixas longitudinais `Vector3(0.28, 0.4, 9.7)` em aço escovado (`#788579`) em `Y = 3.90m`.
- **Placa Prensadora (Cabeçote)**: Caixa `Vector3(2.9, 0.35, 4.5)` em aço de alto desgaste (`#59665a`).
- **Cilindros Hidráulicos**: Par de corpos cilíndricos com raio de `0.14m` e altura de `1.30m` em ferro escuro (`#27292a`).
- **Dentes de Advertência Frontais**: Conjunto de 7 prismas amarelos (`#dfb35b`) marcando o limite da cama de recepção.
- **Unidade de Força Hidráulica**: Gabinete principal `Vector3(1.0, 1.4, 1.3)` posicionado lateralmente em `(2.35, 0.70, -0.50)` (`#8d6240`).

### Detalhes Reconstruídos em Geometria Nativa 3D (onde o V1 era plano ou simplificado):
- **Motor Elétrico da Bomba**: Cilindro horizontal (`raio = 0.22m, comprimento = 0.65m`) montado sobre o gabinete com carcaça usinada.
- **Bloco de Válvulas e Coletor de Pressão**: Caixa `Vector3(0.35, 0.35, 0.50)` em ferro fundido.
- **Tubulação/Mangueira Hidráulica Flexível**: Malha tubular (`raio = 0.04m, altura = 2.6m`) interligando a unidade geradora de pressão ao pórtico superior.
- **Quatro Travessas Transversais de Amarração**: Vigas estruturais `Vector3(3.48, 0.30, 0.35)` em amarelo maquinário nos pontos `Z = [2.2, -0.5, -3.2, -6.8]`, evitando a sensação de trilhos "flutuantes".
- **Hastes Cromadas dos Pistões**: Hastes telescópicas internas em cromo polido (`#c1c7b9`, `raio = 0.08m, altura = 1.40m`) visíveis durante a extensão do curso.
- **Nervuras Estruturais da Placa**: 4 perfis em I transversais reforçando a parte superior da placa prensadora.

---

## 3. Instalação e Montagem na Cena

A instalação deve ser feita via `NecoPressFactory`, sem acoplamento direto ou dependência de nós externos:

```gdscript
# Opção A: Instalação automática pré-alinhada no pátio do Neco (7.2, 0.0, -1.5)
var press := NecoPressFactory.create_press_at_salvage_yard()
add_child(press)

# Opção B: Instalação arbitrária com coordenadas e rotação customizadas
var press := NecoPressFactory.create_press(Vector3(10.0, 0.0, 25.0), deg_to_rad(90.0))
add_child(press)
```

---

## 4. Especificações da Área de Recepção de Veículos

Todas as coordenadas abaixo são relativas à origem local do nó `NecoPress3D` (`Vector3.ZERO`):

| Propriedade | Valor | Observações |
| :--- | :--- | :--- |
| **Ponto Central da Cama (X, Y, Z)** | `Vector3(0.0, 0.50, 0.0)` | O piso da plataforma está a `Y = 0.50m` de altura em relação à base do chão. |
| **Dimensões Úteis da Cama** | `Largura: 2.6m`, `Altura: 2.0m`, `Comprimento: 4.8m` | Capacidade para sedans, peruas, caminhonetes leves e esportivos. |
| **Orientação Recomendada** | Frente voltada para `+Z` | A borda frontal com os 7 dentes de alerta fica em `Z = +2.40m`. Veículos entram de ré ou de frente alinhados ao eixo Z. |
| **Origem Global da Sucata** | `Vector3(7.2, 0.0, -1.5)` | Localização padrão no mapa da Sucata do Neco (conforme V1 `SalvageYard3D` e V2 `SalvageYardNative`). |

### Helpers de Transform e Posicionamento:
- `get_reception_center() -> Vector3`: Retorna `Vector3(0.0, 0.50, 0.0)` em coordenadas locais.
- `get_reception_size() -> Vector3`: Retorna os limites `Vector3(2.6, 2.0, 4.8)`.
- `get_reception_transform() -> Transform3D`: Retorna o `Transform3D` global da vaga de esmagamento.

---

## 5. Contrato da API de Apresentação e Interação Física

### Métodos Públicos

#### `start_presentation(vehicle_visual: Node3D) -> bool`
Inicia o ciclo cinematográfico de esmagamento utilizando o nó visual fornecido.
- Retorna `true` se a animação foi iniciada com sucesso.
- Retorna `false` se a prensa já estiver ocupada (`is_active() == true`) ou se `vehicle_visual` for nulo.
- O nó visual sofre deformação gradual de escala vertical (`scale.y` reduzida para 16% com leve abaulamento lateral `scale.x/z` de 8% e 4%).

#### `cancel_presentation() -> void`
Interrompe imediatamente qualquer sequência em andamento.
- Mata as tweens ativas.
- Retorna o prato da prensa com segurança para a posição de repouso recuada (`Vector3(0.0, 2.9, -5.5)`).
- Emite o sinal `presentation_cancelled()`.
- Reseta o estado para `IDLE` e limpa as referências sem destruir nós.

#### `is_active() -> bool`
Retorna `true` se a máquina estiver executando qualquer fase ativa.

#### `get_current_phase() -> String`
Retorna o nome da fase atual: `"IDLE"`, `"APPROACHING"`, `"CRUSHING"`, `"HOLDING"`, `"RETRACTING"` ou `"CANCELLED"`.

#### `get_crusher_plate_aabb() -> AABB`
Retorna o `AABB` global da placa móvel da prensa em tempo real (`Vector3(2.9, 0.35, 4.5)`).

#### `get_crusher_plate_body() -> AnimatableBody3D`
Retorna o nó de corpo físico preso à placa móvel (dimensões `2.9 x 0.35 x 4.5m`), permitindo ao integrador consultar colisões, configurar collision layers ou detectar contato. O componente não cria rotinas de esmagamento ou dano interno a personagens/jogadores por conta própria, deixando a resposta de impacto a cargo da física do jogo.

### Sinais Emitidos
- `presentation_started(vehicle_visual: Node3D)`: Disparado no instante de início.
- `phase_changed(new_phase: String)`: Disparado a cada transição de fase.
- `presentation_completed(compacted_visual: Node3D)`: Disparado ao final do ciclo completo. Devolve a referência do nó visual compactado para o integrador tratá-lo (gerar sucata, liberar áudio ou pagar recompensa).
- `presentation_cancelled()`: Disparado em caso de cancelamento forçado.

---

## 6. Cronograma e Fases da Sequência

A sequência visual completa tem duração de **3,55 segundos**:

```
[0.00s] --- IDLE
   │
   ▼ start_presentation(visual)
[0.00s - 0.65s] APPROACHING (0.65s):
   Placa desliza no trilho superior de Z = -5.5 até Z = 0.0 (overhead).
   │
   ▼
[0.65s - 1.75s] CRUSHING (1.10s):
   Placa desce de Y = 2.90 até Y = 0.90 (curso de 2 metros).
   Veículo visual sofre compressão física correspondente (scale.y -> 0.16).
   │
   ▼
[1.75s - 2.10s] HOLDING (0.35s):
   Pausa em carga máxima de prensagem hidráulica.
   │
   ▼
[2.10s - 3.55s] RETRACTING (1.45s):
   Sub-etapa 1 (0.80s): Placa sobe verticalmente de Y = 0.90 até Y = 2.90.
   Sub-etapa 2 (0.65s): Placa recua horizontalmente no trilho de Z = 0.0 até Z = -5.5.
   │
   ▼
[3.55s] FINISHED / IDLE:
   Emite presentation_completed(compacted_visual).
```

---

## 7. Exemplo de Uso pelo Integrador (`GarageRewards`)

```gdscript
# Exemplo de chamada na entrega do carro
func _on_player_delivered_scrap_vehicle(vehicle: Vehicle) -> void:
    var press: NecoPress3D = get_node("NecoPress3D")
    
    # 1. Obter a representação visual (ou duplicar malha visual do carro)
    var visual_node: Node3D = vehicle.get_visual_model()
    
    # 2. Desabilitar física real do veículo e atracar na cama da prensa
    vehicle.set_physics_process(false)
    vehicle.global_transform = press.get_reception_transform()
    
    # 3. Conectar evento de conclusão para entrega de recompensa
    press.presentation_completed.connect(func(compacted_mesh: Node3D) -> void:
        # Apenas agora conceder recompensa financeira e persistir save
        GarageRewards.award_scrap_payout(vehicle.vehicle_id)
        # Substituir por fardo de sucata ou liberar remoção
        compacted_mesh.queue_free()
        vehicle.queue_free()
    , CONNECT_ONE_SHOT)
    
    # 4. Iniciar apresentação
    press.start_presentation(visual_node)
```

---

## 8. Registro de Itens Não Validados

Conforme as restrições operacionais desta etapa:
- **Nenhum teste automatizado em runtime foi executado** nesta rodada.
- **Nenhum teste de performance / frame time (FPS) foi medido** em cena com o jogo rodando.
- **Interação física de colisão com o jogador** enquanto a placa se move não foi avaliada in-game (a placa possui um `AnimatableBody3D`, mas camadas de colisão específicas com a cápsula do jogador devem ser validadas na integração geral de física).
- **Áudio de sucateador/prensa**: Efeitos sonoros (rangido de metal, bomba hidráulica e estalo de compressão) não estão integrados no componente de apresentação e devem ser acionados via escuta do sinal `phase_changed`.


## Integração no pátio — implementada, não validada

SalvageYardNative agora monta uma única prensa da fábrica em(7.2,0,-1.5); a geometria antiga e o antigo casco convexo amplo Press foram removidos. O componente registra grupo native_neco_press. A sequência dura0.65+1.10+0.35+0.80+0.65=3.55s: compactação Vector3 simultânea à descida, tween em física. Cancelamento mata o único tween, restaura escala original/posição de repouso, libera guarda e retorna IDLE de forma síncrona; não existe tween de recuperação concorrente.

Segurança/API: get_admission_bounds() devolve AABB local(-2,0,-8.2),size(4,5.2,11); get_admission_transform() transforma o centro para consulta física; is_admission_clear() exige ausência de corpos nas camadas2/4 (jogador/NPCs/veículos) em toda a trajetória. start_presentation recusa área ocupada e instala guarda estática temporária antes de mover a placa. Placa móvel tem camadas/máscaras0 para não empurrar/esmagar atores; guarda bloqueia entrada enquanto ativa. O chamador deve fornecer proxy visual sem corpo físico, com carro real retirado da trajetória pela lógica de transação. Não há exclusão automática do veículo-alvo ou de passageiros. Admissão de teleport/save deve também respeitar esse volume. Cancelamento/conclusão liberam guarda; componente não paga, destrói carro, altera missão ou save.

Nenhum Godot, teste ou benchmark executado neste lote. Pendente parser/import, observar3.55s reais, cancelar em cada fase, descarregarchunk durante sequência, aproximar cápsulas/cascos pelos limites, conferir proxy e regressão da missão Neco. Sem validação de performance ou segurança física em execução ainda.

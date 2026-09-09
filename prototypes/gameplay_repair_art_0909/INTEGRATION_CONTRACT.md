# Contrato de Integração — Arte e Animações (Antigravity & Astra)

Este contrato especifica as interfaces, nós, sinais, propriedades e fluxos de animação dos componentes entregues em D:/geteco/game/prototypes/gameplay_repair_art_0909/.

**Divisão de Responsabilidades**:
- **Antigravity**: Modelos visuais 3D, controladores de animação desacoplados, rigs, poses e validação isolada.
- **Astra**: IA, física, rotas, performance, ativação de regiões por proximidade e integração final no mundo compartilhado (PoliceVehicleStop.gd, PoliceOfficer.gd, world/harbor/HarborCemetery.gd, world/harbor/events/HarborWorldEvents.gd, etc.).

---

# 1. Primeiro: Retirada Policial do Motorista

Controlador desacoplado em [PoliceDriverExtraction.gd](file:///d:/geteco/game/prototypes/gameplay_repair_art_0909/PoliceDriverExtraction.gd).

### 1.1 Arquitetura Desacoplada
- O controlador **NÃO constrói malhas internamente** (não instancia outro Dante, policial ou carro).
- Recebe os nós existentes do jogo ou da cena através do método:
  `gdscript
  extraction.bind_actors(dante, officer, vehicle, door_left, door_right)
  `
- **Compatibilidade Polimórfica**:
  - dante: Aceita nó 3D direto (Node3D) ou personagem 2D com viewport (CharacterBody2D contendo model_root).
  - officer: Aceita nó 3D direto (Node3D) ou policial 2D com viewport (PoliceOfficer contendo model_root).
  - ehicle: Aceita veículo 3D ou veículo com portas articuladas/método _animate_car_door(side, hold_time).
  - door_left / door_right (opcionais): Se omitidos, o controlador busca automaticamente DoorPivot_Left/DoorPivot_Right ou VehicleDoor3D no veículo.
- **Mapeamento de Articulações**:
  - Detecta automaticamente e armazena os membros: 	orso_node, left_upper_arm, left_lower_arm, 
ight_upper_arm, 
ight_lower_arm, left_upper_leg, 
ight_upper_leg (compatível com DanteCGIModel.gd, PoliceOfficer.gd e rigs de produção).
  - Salva em cache as rotações de descanso originais de cada membro no momento do ind_actors(), assegurando restauração perfeita sem poses presas.

### 1.2 Métodos Disponíveis para a Astra
`gdscript
# 1. Injeção dos atores
extraction.bind_actors(dante, officer, vehicle, door_left, door_right)

# 2. Configurações
extraction.speed_multiplier = 1.0     # 1.0 = velocidade normal do jogo
extraction.vehicle_speed = 0.0        # Se > 5.0 km/h, o início é prevenido por segurança

# 3. Disparo da animação (Astra decide o momento exato)
var started_ok: bool = extraction.start_extraction(-1.0) # -1.0 = Porta do motorista (esquerda)
# ou
var started_ok: bool = extraction.start_extraction(1.0)  # +1.0 = Porta do passageiro (direita)

# 4. Interrupção e Rollback Seguro (Astra decide quando cancelar)
extraction.interrupt_extraction("Suspeito acelerou o veículo.")
# ou
extraction.cancel() # Alias idêntico à convenção de PoliceVehicleStop.gd

# 5. Restauração imediata de poses
extraction.reset_poses()

# 6. Verificação de estado
if extraction.is_running():
    # Animação em andamento
`

### 1.3 Sinais Emitidos
| Sinal | Momento de Emissão | Uso Recomendado para a Astra |
|---|---|---|
| extraction_started(side: float) | Policial inicia avanço tático em direção à porta | Desabilitar controles do jogador (ctor.is_control_disabled = true) |
| door_opened(side: float) | Porta do veículo abriu suavemente (~64° para fora) | Tocar áudio de abertura de porta e fala policial de rendição |
| driver_extracted() | Dante saiu do habitáculo e tocou os dois pés no solo | Atualizar seat_point para exit_point no mundo 2D/3D |
| suspect_handcuffed() | Mãos viradas para trás e algemas de aço travadas | Aplicar estado CUFF, registrar prisão e preparar respawn/delegacia |
| sequence_completed() | Sequência finalizada com sucesso | Transição final de gameplay (suspect.arrest_and_respawn()) |
| extraction_interrupted(reason: String) | Rollback concluído: porta fechada e policial em cobertura | Restaurar controle ou reengajar em tiroteio de perseguição |

### 1.4 Status: O que está Executado vs. O que Depende da Astra
- **Executado e Validado pelo Antigravity**:
  - Controlador desacoplado PoliceDriverExtraction.gd sem malhas internas.
  - Suporte completo a extração esquerda e direita.
  - Abertura suave de porta, alcance à cabine, descida de Dante e aplicação de algemas de aço.
  - Interrupção segura (cancel) com fechamento de porta, recuo do policial para cobertura e retorno de Dante ao assento sem poses presas nem concorrência de tweens.
  - Vídeo de demonstração em velocidade normal: ideo_police_extraction.mp4.
- **Depende da Integração da Astra**:
  - Chamar ind_actors() dentro do ciclo de abordagem de PoliceVehicleStop.gd / PoliceOfficer.gd.
  - Definir a checagem de distância da porta e velocidade residual antes de disparar start_extraction().
  - Conectar os sinais suspect_handcuffed / sequence_completed ao fluxo de Wanted e respawn.

---

# 2. Depois: Cemitério e Interações

Componentes em:
- [FuneralSequenceController.gd](file:///d:/geteco/game/prototypes/gameplay_repair_art_0909/FuneralSequenceController.gd)
- [Casket3D.gd](file:///d:/geteco/game/prototypes/gameplay_repair_art_0909/Casket3D.gd)
- [GraveSiteVisual.gd](file:///d:/geteco/game/prototypes/gameplay_repair_art_0909/GraveSiteVisual.gd)
- [MournerCharacterModel.gd](file:///d:/geteco/game/prototypes/gameplay_repair_art_0909/MournerCharacterModel.gd)
- [EliasStorytellerModel.gd](file:///d:/geteco/game/prototypes/gameplay_repair_art_0909/EliasStorytellerModel.gd)
- [CemeteryWorkerModel.gd](file:///d:/geteco/game/prototypes/gameplay_repair_art_0909/CemeteryWorkerModel.gd)
- [ShovelTool3D.gd](file:///d:/geteco/game/prototypes/gameplay_repair_art_0909/ShovelTool3D.gd)

### 2.1 Funeral Completo e Cova Dinâmica
- **Desobstrução do Corredor Central**: O corredor central (Norte-Sul, X = 0) permanece totalmente livre para passagem de viaturas e pedestres. O cortejo vira para o lote lateral (X = 3.4m).
- **Caixão 3D (Casket3D.gd)**: Dimensões de 2.05m x 0.68m x 0.44m em mogno escuro com 6 alças de latão e pontos de pega (get_grip_world_pos(i) / get_grip_local_pos(i)).
- **Cova Dinâmica (GraveSiteVisual.gd)**:
  - OPEN: Cavidade aberta com paredes de terra, pranchas guia, correias tensionadas e pilha lateral de terra.
  - LOWERING: Descida suave do caixão acompanhado pelas correias até o fundo da cavidade.
  - FILLING: Terra sobe encobrindo o caixão, consumindo o monte lateral.
  - COMPLETED: Montículo fechado com cruz de madeira e 5 rosas vermelhas com fita memorial.

### 2.2 Métodos de Funeral para a Astra Conectar ao world/harbor/events/HarborWorldEvents.gd
`gdscript
var funeral_ctrl: FuneralSequenceController = ...

# Injeção opcional de cova e coveiro existentes (se omitidos, instancia os da pasta):
funeral_ctrl.set_grave_site(existing_grave_node)
funeral_ctrl.set_gravedigger(existing_worker_node)

# Configurações:
funeral_ctrl.ceremony_wait_time = 4.0 # Duração do momento de oração solene (segundos)
funeral_ctrl.speed_multiplier = 1.0   # 1.0 = velocidade normal do jogo

# Execução:
funeral_ctrl.start_sequence()  # Inicia cortejo -> cerimônia -> descida -> aterramento -> dispersão
funeral_ctrl.cancel_sequence() # Cancela com segurança e limpa atores temporários
`

### 2.3 Sinais do Funeral
| Sinal | Descrição |
|---|---|
| sequence_started | Cortejo inicia avanço com carregadores sustentando o caixão |
| procession_arrived | Cortejo alcança o lote lateral e repousa o caixão sobre a cova |
| ceremony_started | Carregadores e visitantes assumem postura de respeito e oração |
| lowering_started | Caixão e correias iniciam a descida mecânica suave |
| lowering_completed | Caixão repousa no fundo da cavidade |
| illing_started | Coveiro aproxima com a pá e inicia aterramento |
| illing_completed | Túmulo completamente fechado com cruz e arranjo de flores |
| dispersal_started | Participantes iniciam caminhada de retorno à saída |
| sequence_completed | Ciclo concluído; atores temporários removidos da memória |
| sequence_cancelled | Cancelamento imediato sem vazamento de nós na árvore |

### 2.4 Elias (Contador de Histórias) vs. Coveiro e Pá 3D
- **Elias (EliasStorytellerModel.gd)**:
  - Silhueta única que o distingue imediatamente de qualquer NPC: Sobretudo tweed marrom (#4e4844), cachecol de lã ocre caído (#b8743a), boina maruja clássica (#2a2725), óculos de leitura com aros dourados, barba e bigode brancos longos e bolsa lateral carteiro em couro.
  - Poses articuladas: set_pose(0) (WAIT), set_pose(1) (TALK), set_pose(2) (WALK), set_pose(3) (INSPECT).
  - Chamada contínua: update_animation(delta, is_moving).
- **Pá 3D (ShovelTool3D.gd)**:
  - Modelo 3D com cabo de freixo e empunhadura em D.
  - Ancoragem limpa: shovel.attach_to_hand(worker.right_hand_mount).
  - Poses funcionais:
    1. set_pose(0) (HOLD): Pá vertical ao lado do corpo, sem penetrar o solo.
    2. set_pose(1) (CARRY): Pá no ombro, lâmina suspensa a 1.38m de altura (**zero clipping** com o piso durante caminhada).
    3. set_pose(2) (DIG): Dupla empunhadura e alavanca com flexão de tronco para escavação.
- **Rota Pedestre de Entrada e Saída (Sem Spawn Aéreo)**:
  1. Coveiro surge fora do cemitério no portão norte (Vector3(0, 0, -12.5)).
  2. Entra a pé com a pá em CARRY pelo portal norte.
  3. Caminha pela margem do corredor central até o túmulo de trabalho.
  4. Executa a tarefa de manutenção ou aterramento com a pá em DIG.
  5. Retorna com a pá em CARRY pelo corredor e dispersa na calçada norte.

### 2.5 Status: O que está Executado vs. O que Depende da Astra
- **Executado e Validado pelo Antigravity**:
  - Caixão 3D e Cova dinâmica com 4 estados.
  - Coreografia do funeral com corredor central livre, cancelamento e repetição limpos sem vazamento de memória.
  - Elias com identidade visual inconfundível.
  - Pá 3D com poses HOLD, CARRY (sem penetração no terreno) e DIG.
  - Vídeos de demonstração em velocidade normal: ideo_funeral_cycle.mp4 e ideo_shovel_and_elias.mp4.
- **Depende da Integração da Astra**:
  - Alocar as coordenadas dos lotes em `world/harbor/HarborCemetery.gd`.
  - Acionar o início do evento fúnebre através de `world/harbor/events/HarborWorldEvents.gd`.
  - Integrar Elias ao sistema de diálogo existente (`CemeteryStoryteller.gd`).
  - Ativar/desativar a renderização do cemitério conforme a proximidade da câmera do jogador.

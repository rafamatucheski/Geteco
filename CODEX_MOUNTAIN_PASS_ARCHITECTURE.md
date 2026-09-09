# CODEX — ARQUITETURA TÉCNICA E SISTEMAS: REGIONAL MOUNTAIN PASS (SERRA DA NEVASCA)
**Documento de Engenharia e Consolidação Arquitetural para Sistemas Autônomos (Codex / Agentes AI / Equipe)**  
**Data de Emissão:** 2026-09-07  
**Status do Módulo:** Consolidado, Testado e Verificado em Runtime (0 Falhas)  
**Engine:** Godot Engine v4.7.2.stable.official (Renderers: Forward+ / Mobile / Compatibility / Headless)  
**Localização do Projeto:** `d:\geteco\game`  

---

## 1. VISÃO GERAL EXECUTIVA & ESCOPO

Este documento consolida com exaustão técnica **absolutamente tudo** que foi concebido, implementado, integrado, corrigido e testado na expansão da **Região 2 — Mountain Pass (Serra da Nevasca)** do jogo *GETECO*.

A expansão Mountain Pass é um divisor de águas técnico no projeto:
1. **Transição Contínua Inter-Distrital:** Conexão direta entre o Distrito Portuário (*Harbor Preview*) e a Serra da Nevasca através da ponte suspensa (*Harbor Bridge* em `x = 3200..4380`) e do túnel rodoviário perfurado na rocha.
2. **Hibridismo 2D / 3D Volumétrico (PBR):** Integração de visualização top-down 2D fluida com projeção isométrica 3D real (`SubViewport` + `Camera3D` + materiais PBR com iluminação dinâmica, sombras e materiais metálicos/ásperos) em veículos e interiores habitáveis.
3. **Mecânica de Visão Cutaway Dinâmica:** Remoção progressiva e suave de telhados e maciços rochosos em túneis subterrâneos e chalés quando o ator (a pé ou embarcado) cruza os pórticos.
4. **Armamento Lendário com UI Vetorial In-Game:** Totens e estações de armas com cards de estatísticas renderizados proceduralmente, ícones vetoriais de precisão e concessão direta aos inventários do jogador (`Player.gd`).
5. **Simulação Térmica e Clima Adverso:** Mecânica de sobrevivência ao frio extremo (hipotermia, congelamento periférico da tela por vinheta, isolamento veicular, fogueiras/fontes de calor radiante e nevascas dinâmicas com arraste por vento).

---

## 2. MAPA ESTRUTURAL DE ARQUIVOS CRIADOS E INTEGRADOS

Abaixo está o inventário completo de arquivos adicionados e sincronizados na árvore `district/mountain_pass/`, `prototypes/`, e na raiz do projeto:

```
d:\geteco\game\
├── district\
│   ├── harbor_preview\
│   │   └── HarborBridge.gd                  [MODIFICADO] Trava anti-loop de transição e guardas de cena
│   └── mountain_pass\
│       ├── MountainPass.gd                  [NOVO] Controlador central da região e orquestrador
│       ├── MountainPass.tscn                [NOVO] Cena raiz do distrito da montanha
│       ├── MountainPassRoad.gd              [NOVO] Traçado spline 2D, asfalto e cascalho de serra
│       ├── MountainTunnel.gd                [NOVO] Túnel subterrâneo jogável com cutaway e iluminação âmbar
│       ├── MountainCabin3D.gd               [NOVO] Chalé 3D PBR volumétrico (lareira, móveis, Silas Vance)
│       ├── MountainCabinInterior.gd         [NOVO] Interior 2D/3D integrado com estações de armas lendárias
│       ├── MountainCabinProps3D.gd          [NOVO] Biblioteca de adereços 3D para o chalé alpino
│       ├── MountainInteriorManager.gd       [NOVO] Gerenciador de transição exterior/interior e câmeras
│       ├── MountainSceneryBuilder.gd        [NOVO] Construtor procedural de 1.513 linhas: estradas de terra,
│       │                                          lago secreto, avião bimotor submerso, cofre e chalés
│       ├── MountainSUV.gd                   [NOVO] Summit SUV 4x4 dos Lobos de Gelo jogável em 3D
│       ├── ArcticJeep.gd                    [NOVO] Jeep Artic 4x4 Off-road pronto para roubo no lago
│       ├── MountainPickup.gd                [NOVO] Caminhonete Ranch Pickup 4x4 rústica jogável
│       ├── ColdSurvivalController.gd        [NOVO] Sistema termodinâmico corporal e hipotermia
│       ├── ColdStatusHUD.gd                 [NOVO] HUD de frio, indicador térmico e vinheta de congelamento
│       ├── IceStormManager.gd               [NOVO] Tempestade de gelo, vento balístico e nevasca
│       ├── MountainAltitudeParallax.gd      [NOVO] Parallax de altitude com vista panorâmica da metrópole
│       ├── MountainPineTree.gd              [NOVO] Pinheiros alpinos com acúmulo de neve e colisão física
│       └── MountainRangerNPC.gd             [NOVO] Guarda florestal e patrulheiros de altitude
├── PlayerCar.gd                             [MODIFICADO] Sincronização em tempo real de motorista (Dante)
├── tests\
│   ├── test_full_driving_to_tunnel.gd       [NOVO] Teste ponta a ponta: Direção Harbor -> Ponte -> Túnel
│   ├── test_mountain_pass_integration.gd    [NOVO] Teste de integração de terreno, clima e veículos
│   └── test_mountain_cabin_weapons_and_entrance.gd [NOVO] Teste de entrada no chalé e armas lendárias
└── docs\
    └── CODEX_MOUNTAIN_PASS_ARCHITECTURE.md  [CÓPIA ESPELHADA EM DOCS]
```

---

## 3. REGISTRO ESPACIAL DE COORDENADAS E PONTOS DE INTERESSE (POIs)

Todas as entidades operam no sistema global de coordenadas 2D de Godot (`x`: horizontal leste-oeste, `y`: vertical norte-sul). Na serra, valores de `y` decrescentes representam maiores altitudes em direção ao topo da cordilheira.

| POI / Elemento | Coordenadas Globais (X, Y) | Dimensões / Raio | Camada / Z-Index | Descrição Arquitetural |
|---|---|---|---|---|
| **Harbor Bridge (Ponta Oeste)** | `(3200.0, 400.0)` | Comprimento: 1180px | Z=1 | Início do vão sobre a baía oceânica |
| **Gatilho Retorno ao Porto** | `(2950.0, 400.0)` | `60.0 x 220.0` | Z=0 | Retorno contínuo ao `HarborGame.tscn` (apenas em marcha a oeste) |
| **Harbor Bridge (Ponta Leste)** | `(4380.0, 400.0)` | Comprimento: 1180px | Z=1 | Fim do vão estaiado e acesso ao pé da serra |
| **Gatilho Ida para Montanha** | `(4650.0, 400.0)` | `60.0 x 220.0` | Z=0 | Gatilho na ponte que despacha para `MountainPass.tscn` |
| **Portal Oeste do Túnel** | `(4950.0, 400.0)` | Largura pista: 160px | Z=2 (int) / Z=8 (roof) | Início do corte na rocha maciça; ativação do cutaway |
| **Vão do Túnel Rodoviário** | `(4950.0 a 5800.0, 400.0)` | `850.0 x 160.0` | Z=2 | Iluminação âmbar a cada 180px (`PointLight2D`), asfalto escuro |
| **Portal Leste do Túnel** | `(5800.0, 400.0)` | Largura pista: 160px | Z=2 / Z=8 | Saída do túnel; desativação do cutaway (teto se fecha) |
| **Trilha 1: East Vale Road** | `(6350, 560)` a `(8700, 460)` | Largura: 38px | Z=-4 | Conexão de cascalho com marcas de pneu duplas para chalés |
| **Serraria (Logging Camp)** | `(6350.0, 560.0)` | `350.0 x 250.0` | Z=2 | Galpão de cedro, toras, serragem e fogueira de calor |
| **Fogueira da Serraria** | `(6440.0, 580.0)` | Raio: 220px | Z=2 | Grupo `heat_source` para aquecimento termodinâmico |
| **Chalé 1 (Pine Crest)** | `(7350.0, 620.0)` | `150.0 x 110.0` | Z=2 | Chalé dos pinhais com interior jogável e alpendre |
| **Chalé 2 (Timberline)** | `(8350.0, 480.0)` | `170.0 x 120.0` | Z=2 | Chalé principal com Mountain Pickup 3D no pátio |
| **Chalé 3 (Ranger Station)** | `(6050.0, 780.0)` | `130.0 x 95.0` | Z=2 | Posto de patrulha florestal com rádio e mantimentos |
| **Botão de Entrada Chalé** | `(7350.0, 699.2)` | `216.0 x 26.0` | Z=20 | Placa física com tecla "[E] APERTE E PARA ENTRAR" |
| **Trilha 2: Timber Ridge** | `(6650, 120)` a `(7750, -220)` | Largura: 36px | Z=-4 | Estrada de terra em aclive conectando à Ammu-Nation |
| **Ammu-Nation da Montanha** | `(7750.0, -220.0)` | `210.0 x 150.0` | Z=2 | Loja de armas com estande de tiro outdoor e estacionamento |
| **Trilha 3: Smuggler's Cut** | `(6120, 320)` a `(6200, -320)` | Largura: 28px | Z=-4 | Trilha sinuosa entre penhascos rochosos |
| **Trilha 4: Secret Tarn Trail** | `(6200, -320)` a `(5640, -960)` | Largura: 26px | Z=-4 | Caminho secreto descendo ao lago glacial escondido |
| **Lago Secreto (Glacial Tarn)**| `(5450.0, -1150.0)` | `510.0 x 340.0` | Z=-3 | Bacia de água verde-turquesa profunda com gelo flutuante |
| **Acampamento dos Contrabandistas** | `(5630.0, -970.0)` | `180.0 x 170.0` | Z=2 | Pátio de cascalho com fogueira, caixas e barris |
| **Arctic Jeep 3D (Veículo Roubável)** | `(5610.0, -955.0)` | `84.0 x 42.0` | Z=8 | Jeep militar ártico 4x4 pronto para ignição imediata |
| **Avião Bimotor Submerso** | `(5375.0, -1165.0)` | Envergadura: 190px | Z=-2 | Fuselagem de hidroavião caída com mancha de combustível |
| **Ilha do Cofre Secreto** | `(5525.0, -1135.0)` | `115.0 x 100.0` | Z=-1 | Ilhota com pinheiro solitário, píer, barco a remo e stepping stones |
| **Cofre Pelican de Ouro e Sniper** | `(5517.0, -1130.0)` | `40.0 x 28.0` | Z=0 | Caixa militar aberta com lingotes de ouro e rifle de precisão |
| **Mirante da Serra (Scenic Overlook)** | `(7400.0, -950.0)` | Balcão: 280px | Z=2 | Mirante com binóculos de montanha e vista da cidade |
| **Bunker e Heliponto do Cume**| `(8800.0, -1800.0)` | `320.0 x 320.0` | Z=2 | Complexo militar fortificado no pico mais alto |

---

## 4. ESPECIFICAÇÃO DETALHADA DOS COMPONENTES

### 4.1. `MountainPass.gd` — Controlador Central da Região
- **Tipo / Herança:** `Node2D`
- **Ciclo de Vida:** Instanciado via `MountainPass.tscn` ao cruzar a ponte do Porto.
- **Responsabilidades:**
  1. Instancia o fundo de altitude multi-camadas (`MountainAltitudeParallax`).
  2. Constrói o leito da rodovia da serra (`MountainPassRoad`).
  3. Gerencia o túnel subterrâneo (`MountainTunnel`).
  4. Garante a continuidade visual da `HarborBridgeCrossing` sem colisão de gatilhos recursivos.
  5. Constrói o gatilho de retorno ao Porto (`HarborReturnCrossing`) em `x = 2950.0` (filtrando estritamente velocidade a oeste para evitar disparos acidentais ao spawnar).
  6. Dispara o construtor procedural `MountainSceneryBuilder.build_full_scenery()`.
  7. Instancia os controladores climáticos e de sobrevivência (`ColdSurvivalController`, `ColdStatusHUD`, `IceStormManager`).
  8. Instancia o veículo padrão do jogador: `SummitSUV` em `Vector2(4700, 400)` para continuidade automotiva imediata.

### 4.2. `MountainTunnel.gd` — Túnel com Cutaway em Tempo Real
- **Tipo / Herança:** `Node2D`
- **Variáveis Exportadas:**
  - `tunnel_length: float = 850.0`
  - `tunnel_width: float = 150.0`
- **Mecânica de Cutaway (`_update_cutaway()`):**
  - Monitora uma `Area2D` interna denominada `CutawayTriggerArea` com máscara de colisão `1 | 2 | 4 | 8`.
  - **Saneamento Defensivo:** Na função `_update_cutaway()`, a lista de corpos `_inside_bodies` é filtrada com `is_instance_valid(b)` antes de avaliar a contagem. Isso impede travamentos se um veículo ou pedestre for desalocado enquanto estiver dentro do túnel.
  - **Interpolação Suave:** Utiliza `Tween` com transição `TRANS_QUAD` e atenuação `EASE_OUT` (duração 0.28s) para animar o `modulate:a` do nó `TunnelRoof` entre `1.0` (coberto/opaco) e `0.0` (revelado).
  - **Iluminação Âmbar:** Fileira de `PointLight2D` espaçados a cada 180px com tom de sódio de emergência (`Color(1.0, 0.72, 0.32)`), garantindo iluminação visual top-down na pista interna sem estourar a cena exterior.

### 4.3. `MountainCabin3D.gd` — Cenário Volumétrico PBR do Chalé
- **Tipo / Herança:** `Node3D`
- **Renderização e Arquitetura:**
  - Construído exclusivamente em 3D procedural no Godot 4 com `StandardMaterial3D` em modo `SHADING_MODE_PER_PIXEL`.
  - **Materiais PBR Customizados:**
    - Toras de pinho escuro: `Color("#3d2817")`, `roughness = 0.85`
    - Piso de tábuas enceradas: `Color("#52361b")`, `roughness = 0.45`
    - Couro conhaque capitonê (Sofá Chesterfield): `Color("#703a18")`, `roughness = 0.35`, `metallic = 0.05`
    - Ardósia e granito rústico: `Color("#383b40")`, `roughness = 0.9`
    - Ferro forjado / canos de fogão: `Color("#1a1a1c")`, `metallic = 0.85`, `roughness = 0.3`
    - Latão e cobre polido (chaleira e Banker's Lamp): `Color("#d49b42")`, `metallic = 0.95`, `roughness = 0.2`
    - Vidro esmeralda luminoso: `Color("#0a5c36")`, `glow = 1.2`
  - **Geometria de Destaque:**
    - **Lustre Roda de Carroça:** `TorusMesh` de ferro fundido com 6 lâmpadas Edison incandescentes com emissão quente.
    - **Lareira Monumental de Pedras:** Boca de fornalha com fogão a lenha de ferro fundido, lenhas em brasa (`glow = 2.5`) e luz pontual com cintilação.
    - **Tapete de Pele de Urso 3D:** Silhueta anatômica com cabeça esculpida de urso pardo e focinho escurecido.
    - **Cama Rústica de 4 Postes:** Toras verticais roliças com colcha acolchoada e criado-mudo com abajur.
    - **NPC Silas Vance 3D:** Boneco 3D modelado posicionado atrás da mesa de operações de montanha, com jaqueta de frio azul marinho, calça cáqui, botas e gorro ushanka tradicional.

### 4.4. `MountainCabinInterior.gd` — Integração 2D/3D & Armas Lendárias
- **Herança:** `HarborInteriorBase.gd` (`district/harbor_preview/interiors/HarborInteriorBase.gd`)
- **Projeção Câmera 3D:**
  - Cria um `SubViewport` (`Vector2i(720, 500)`) contendo o nó `MountainCabin3D`.
  - A `Camera3D` está posicionada em ângulo cinematográfico elevado (`position = Vector3(0.0, 5.2, 5.8)`, `rotation_degrees = Vector3(-42.0, 0.0, 0.0)`), com `fov = 48.0`.
  - O resultado é projetado em um `Sprite2D` 2D que serve de fundo fidedigno, mantendo as colisões físicas de parede e portas 2D nos perímetros da sala.
- **Estações de Armas & Totens Interativos:**
  1. **Fuzil de Caça Lendário ("PRESA DO INVERNO"):**
     - Posição: `Vector2(200, -60)` (Armaria na parede leste)
     - ID do Item: `"hunting_rifle"`
     - Rarity Badge: `★ LENDÁRIO · TIER 5 ★` (Cor: Dourado `#f1c40f`)
     - Dano Base: 120 HP (Crítico na Cabeça: 420 HP)
     - Precisão: 99% (Luneta Óptica 8x)
     - Alcance: 950 metros
     - Munição Concedida: 35 cartuchos `.308 Win AP`
     - Perfurante: Balas atravessam blindagem corporal e causam lentidão de movimento instantânea.
  2. **Faca de Caça Tática ("LÂMINA DO RASTREADOR"):**
     - Posição: `Vector2(-200, -70)` (Cozinha/bancada dos caçadores)
     - ID do Item: `"knife"`
     - Rarity Badge: `◆ MIL-SPEC · TÁTICO ◆` (Cor: Ciano `#00d2d3`)
     - Dano Base: 35 HP (Golpes críticos rápidos a 2.0 ataques/segundo)
     - Alcance: 54px (Corpo-a-corpo direto)
     - Efeito Especial: Provoca sangramento contínuo e permite abate furtivo silencioso.
- **UI Vetorial dos Cards:**
  - Renderiza cartões HUD holográficos dinâmicos com contorno em neon na cor do item, brasão de raridade, ícone desenhado por vetor (fuzil com coronha de nogueira e luneta; faca tática com serilha no dorso) e grid de especificações técnicas.
  - Ao aproximar-se, exibe prompt interativo pulsante: `[E] COLETAR [NOME DA ARMA]`.
  - Ao coletar, dispara efeito sonoro procedural de recarga/trava de ferrolho, emite feedback visual de coleta e equipa imediatamente o jogador.

### 4.5. `MountainSceneryBuilder.gd` — Cenografia Orgânica da Serra (1.513 linhas)
Construtor puramente estático que modela a paisagem natural da serra:
- **Rede de Estradas de Terra (Backcountry Dirt Roads):**
  - Quatro trajetos baseados em `Curve2D` interpolados com marcas paralelas de pneu (`width = 9.0`, cor `#241c14`, opacidade 75%) e leito de cascalho batido.
  - Conectores que descem para a serraria, para a Ammu-Nation e para as margens do lago secreto.
- **Complexo dos Chalés:**
  - 3 chalés estruturados com alpendre de tábuas de cedro, chaminé de pedra com fumaça aquecida por `PointLight2D` e pilha de toras de lenha cortadas.
  - **Porta do Chalé 1:** Equipada com placa física destacada com borda dourada contendo a tecla `[E]` em caixa alta e o texto `APERTE E PARA ENTRAR`, alinhando-se com precisão de 100% à exigência do usuário.
- **Loja Ammu-Nation de Montanha:**
  - Edifício rústico com letreiro vermelho e amarelo, estande de tiro outdoor com fardos de feno e alvos circulares, vagas de estacionamento delimitadas por batentes de madeira e entrada registrada no `MountainInteriorManager`.
- **O Lago Secreto dos Contrabandistas (Secret Glacial Tarn):**
  - **Localização:** `Vector2(5450, -1150)`
  - **Geometria da Água:** Bacia natural em 3 níveis de profundidade (praia de cascalho, águas rasas azul-turquesa `#175b6a`, águas profundas abissais `#0b2f3a`).
  - **Cascata Congelada:** Queda d'água vinda do paredão norte com espuma e blocos de gelo flutuantes à deriva.
  - **Acampamento dos Contrabandistas:** Pátio de terra batida com círculo de pedras e fogueira acesa com emissão de luz e calor (`heat_source`), caixas e galões.
  - **Arctic Jeep 3D:** Jeep off-road camuflado ártico, com rodas largas, estepe traseiro e suspensão reforçada pronto para ignição e fuga pela trilha.
  - **Destroços do Avião Bimotor (Smuggler Floatplane Wreck):** Hidroavião bimotor acidentado com asa direita de alumínio na superfície e asa esquerda partida e submersa; mancha de combustível iridescente na água; hélice com ogiva amarela entortada; barris de combustível amarrados por cabos.
  - **Ilha Secreta do Cofre:** Acessível por pedras de travessia (*stepping stones* com anéis de refração na água); conta com píer de madeira rústico, barco a remo amarrado, pinheiro solitário e cofre militar Pelican azul-marinho aberto contendo lingotes de ouro reluzentes e um fuzil sniper especial.

### 4.6. Veículos 3D Jogáveis da Montanha

#### A. Summit SUV 4x4 (`MountainSUV.gd`)
- **Herança:** `HarborCoupe.gd`
- **Modelo 3D:** `SummitSUVModel.gd`
- **Física:** Velocidade máxima 520 px/s, aceleração 420 px/s², velocidade de giro 3.2 rad/s. Suspensão com tração nas quatro rodas e altura do solo elevada.
- **Cor Padrão:** Azul glacial tático (`Color("#2980b9")`).
- **Câmera:** Possui nó `Camera` interno configurado com `DynamicCamera.gd`.
- **Correção de Desembarque:** Implementa override em `exit_vehicle()` garantindo que `$Camera.enabled = false` seja chamado, prevenindo que a câmera do veículo retenha o foco após o motorista desembarcar.

#### B. Arctic Jeep 4x4 (`ArcticJeep.gd`)
- **Herança:** `HarborCoupe.gd`
- **Modelo 3D:** `SummitSUVModel.gd` com variantes táticas.
- **Física:** Velocidade máxima 480 px/s, aceleração 460 px/s² (torque inicial elevado para aclives com lama e neve), giro 3.4 rad/s.
- **Estética:** Pintura branca polar de camuflagem (`Color("#ecf0f1")`), faróis de milha de alta penetração.
- **Segurança de Câmera:** Override idêntico em `exit_vehicle()` para liberação imediata da câmera do jogador.

#### C. Mountain Pickup 4x4 (`MountainPickup.gd`)
- **Herança:** `HarborCoupe.gd`
- **Modelo 3D:** `SummitSUVModel.gd` (carroceria de caçamba rústica de fazenda).
- **Física:** Velocidade máxima 490 px/s, aceleração 390 px/s², tração traseira com bloqueio de diferencial.
- **Estética:** Vermelho rústico de rancho (`Color("#c0392b")`).

### 4.7. Mecânicas de Clima e Sobrevivência ao Frio Extremo

#### `ColdSurvivalController.gd`
- Monitora a temperatura corporal do jogador (`max_temperature = 100.0`, `current_temperature`).
- **Zona de Frio:** Ativa quando `global_position.y <= -1500.0` (cotas superiores da serra) ou quando `force_cold_active = true`.
- **Taxas de Equilíbrio Térmico:**
  - Perda normal ao relento: -3.5 unidades/s.
  - Perda durante nevasca/blizzard: -5.5 unidades/s.
  - Aquecimento dentro de veículos: +20.0 unidades/s (o isolamento da cabine e aquecedor veicular protegem o jogador).
  - Aquecimento próximo a fogueiras (`heat_source` em raio de 220px): +35.0 unidades/s.
- **Hipotermia:** Quando a temperatura atinge `0.0`, emite `hypothermia_started` e drena 5 HP/s da vida do jogador até encontrar abrigo.

#### `ColdStatusHUD.gd`
- Exibe termômetro estético no canto superior da tela com cores graduais (azul polar para frio extremo, laranja quente próximo a lareiras).
- Vinheta periférica de cristais de gelo que se expande pelas bordas da tela conforme o frio aumenta.
- Dispara áudios de dentes batendo e palpitações de batimento cardíaco abafado durante hipotermia.

#### `IceStormManager.gd`
- Sistema de partículas dinâmicas de flocos de neve e rajadas de gelo horizontais com velocidade modulada entre 350 e 800 px/s.
- Aplica força lateral física sutil de arrasto de vento nos veículos em trânsito pela rodovia exposta da serra.

---

## 5. POST-MORTEM DOS BUGS CRÍTICOS & CORREÇÕES ARQUITETURAIS

Durante os primeiros testes ao volante atravessando a ponte e rumando ao túnel, foram observados congelamentos severos, desaparecimento do veículo e teletransporte indevido do protagonista. A auditoria minuciosa das chamadas de engine e física identificou **cinco falhas fundamentais**, que foram integralmente corrigidas:

### Falha 1: Loop Recursivo de Recarga de Cena na Ponte
- **Diagnóstico:** O script `HarborBridge.gd` criava dinamicamente em `_ready()` uma `Area2D` de transição chamada `MountainPassCrossing` localizada em `x = 4650.0`. Como a própria cena `MountainPass.tscn` instanciou a `HarborBridge` em `x = 0.0` para manter a integridade visual da ponte estaiada, ao cruzar `x = 4650.0`, o gatilho da ponte na montanha disparava uma recarga imediata de `MountainPass.tscn` sobre si mesma! Isso reiniciava a cena enquanto o carro estava em movimento, destruindo o carro e gerando uma tempestade de nós órfãos.
- **Solução Implementada:**
  1. Criação da flag `@export var is_in_mountain_pass: bool = false` em `HarborBridge.gd`.
  2. Adição de trava no método `_setup_crossing_trigger()`:
     ```gdscript
     if is_in_mountain_pass:
         return
     var cur = get_tree().current_scene if get_tree() else null
     if cur != null and (cur.name == "MountainPass" or cur.scene_file_path.contains("mountain_pass")):
         return
     ```
  3. No `MountainPass.gd:_setup_bridge()`, a ponte é explicitamente instanciada com `bridge.set("is_in_mountain_pass", true)`.
  4. Adição de trava de disparo único `_transitioning: bool = false` com transição diferida (`call_deferred`).

### Falha 2: Dessincronização e Teletransporte do Jogador (Dante) ao Dirigir
- **Diagnóstico:** No `PlayerCar.gd`, ao entrar no carro (`enter_vehicle()`), o nó do jogador era ocultado (`player_body.hide()`) e sua física desligada (`player_body.set_physics_process(false)`). Porém, as coordenadas `global_position` do jogador **não eram atualizadas** enquanto o carro se deslocava pela estrada! O jogador continuava congelado nas coordenadas antigas onde embarcou no carro (no meio do Porto, a 2.000 pixels de distância). Ao desembarcar ou ao trocar de cena, o sistema reposicionava a câmera ou o jogador para o local original, causando a percepção de "teletransporte involuntário" ou sumiço instantâneo.
- **Solução Implementada:**
  - Em `PlayerCar.gd:_physics_process()` (linhas 525–530), logo após o `move_and_slide()` do veículo, foi adicionada a sincronização contínua de posição do motorista:
    ```gdscript
    if is_driven_by_player:
        var current_driver := get_tree().get_first_node_in_group("player") as Node2D
        if current_driver and is_instance_valid(current_driver):
            current_driver.global_position = global_position
    ```
  - Agora, independentemente de quantos quilômetros o carro percorra, o nó do jogador acompanha rigorosamente a posição do chassi a cada frame de física.

### Falha 3: Retenção de Câmera Desativada no Desembarque de Veículos 3D
- **Diagnóstico:** Em `MountainSUV.gd`, `ArcticJeep.gd` e `MountainPickup.gd`, a câmera interna do veículo (`$Camera`) era ativada no `enter_vehicle()`, mas o método padrão `exit_vehicle()` herdado de `HarborCoupe.gd` não desabilitava explicitamente a câmera do carro. Isso gerava conflito de prioridade com a `Camera2D` do jogador, travando a viewport e impedindo a movimentação fluida do boneco a pé.
- **Solução Implementada:**
  - Sobrescrita de `exit_vehicle()` em todos os três veículos:
    ```gdscript
    func exit_vehicle() -> void:
        if has_node("Camera"):
            $Camera.enabled = false
        super.exit_vehicle()
    ```

### Falha 4: Corrupção do Array de Corpos no Túnel (`MountainTunnel.gd`)
- **Diagnóstico:** Se um veículo entrasse no túnel e sofresse qualquer operação de troca de cena ou reconstrução enquanto estivesse dentro de `_inside_bodies`, a referência se tornava um ponteiro inválido, gerando erros de `null instance reference` na atualização do cutaway.
- **Solução Implementada:**
  - Higienização automática com filtro lambda antes de calcular a opacidade:
    ```gdscript
    _inside_bodies = _inside_bodies.filter(func(b): return is_instance_valid(b))
    ```

### Falha 5: Ausência de Retorno Físico ao Porto
- **Diagnóstico:** Ao trafegar pela serra de volta no sentido Oeste, a pista terminava no vazio ou não havia gatilho que devolvesse o jogador ao `HarborGame.tscn`.
- **Solução Implementada:**
  - Adição em `MountainPass.gd` de um gatilho de retorno dedicado (`HarborReturnCrossing`) em `x = 2950.0`, com validação vetorial estrita: só despacha a transição se `body.velocity.x <= 10.0` (ou seja, se estiver efetivamente trafegando em marcha à ré ou direção Oeste rumo ao Porto).

---

## 6. SUÍTE DE TESTES AUTOMATIZADOS & RESULTADOS DE VALIDAÇÃO

Todos os fluxos foram comprovados através de scripts executados diretamente no binário do Godot em modo `--headless`.

### 6.1. Execução: `tests/test_full_driving_to_tunnel.gd`
- **Comando:**
  ```powershell
  & "D:\Downloads Chrome\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --script tests/test_full_driving_to_tunnel.gd
  ```
- **Log de Verificação:**
  ```text
  --- TESTE COMPLETO: FLUXO DE DIREÇÃO PONTE -> TÚNEL -> SERRA ---
  1. Validação de instâncias:
     Player pos: (3260.0, 400.0)
     SUV pos: (3350.0, 400.0)
     Bridge pos: (0.0, 0.0)
     Tunnel pos: (4950.0, 400.0)
  SUCESSO: HarborBridge não possui MountainPassCrossing em MountainPass (sem conflito de recarga)!
  2. Dante entrando no Summit SUV...
  3. Conduzindo SUV pela ponte cruzando x = 4650...
     SUV passou por x = 4650! Posição atual: (4892.169, 400.0)
     Player sincronizado em: (4892.169, 400.0)
  SUCESSO: Posição do jogador acompanhou o carro em tempo real!
  4. Entrando no túnel subterrâneo (x = 4950 a 5800)...
     Posição dentro do túnel: (5534.005, 400.0)
  SUCESSO: Mecânica de cutaway abriu o teto do túnel perfeitamente! is_revealed = true
  5. Atravessando e saindo do túnel...
     Posição na saída do túnel: (6659.841, 423.7981)
  SUCESSO: Teto do túnel fechou após a saída do veículo! is_revealed = false
  6. Desembarcando do SUV...
     Player pos pós-desembarque: (6725.924, 382.3415)
     SUV pos pós-desembarque: (6725.924, 406.821)
     Distância de desembarque: 24.4794616699219
  SUCESSO: Boneco desembarcou exatamente ao lado da porta do SUV (dist = 24.5 px)!
  SUCESSO: Boneco visível e com controles ativos após desembarque!
  --- FIM DO TESTE: 0 FALHAS ---
  ```

### 6.2. Execução: `tests/test_mountain_cabin_weapons_and_entrance.gd`
- **Comando:**
  ```powershell
  & "D:\Downloads Chrome\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --script tests/test_mountain_cabin_weapons_and_entrance.gd
  ```
- **Log de Verificação:**
  ```text
  --- INICIANDO TESTE: CHALE EXTERIOR E ARMAS LENDARIAS ---
  SUCESSO: hunting_rifle no catalogo com dano 120
  SUCESSO: hunting_rifle presente na ordem de armas
  SUCESSO: Porta exterior com custom prompt: [E] APERTE E PARA ENTRAR NO CHALÉ
  SUCESSO: Botao visual de entrada no alpendre verificado!
  SUCESSO: Iluminacao e alpendre do chale completos!
  SUCESSO: Estacoes de Fuzil Lendario e Faca de Caca Tatica encontradas!
  SUCESSO: Componentes de UI, icones vetoriais e cards validados!
  SUCESSO: Fuzil Lendario equipado com sucesso no Player!
  SUCESSO: Faca de Caca Tatica adicionada ao inventario!
  SUCESSO: Banner de notificacao de item lendario renderizado!
  --- FIM DO TESTE: 0 FALHAS ---
  ```

---

## 7. DIRETRIZES DE MANUTENÇÃO E EXTENSÃO PARA O CODEX

Ao manter ou expandir o ecossistema do *Mountain Pass*, agentes e desenvolvedores devem aderir às seguintes diretrizes estruturais:

1. **Topologia de Nós em Interiores 3D:** Qualquer novo cômodo volumétrico deve herdar ou seguir o padrão de `MountainCabinInterior.gd`, utilizando um `SubViewport` exclusivo com `own_world_3d = true`, isolando o pipeline de renderização 3D das coordenadas e draw calls da cena 2D principal.
2. **Registro de Fontes de Calor:** Para criar novos pontos de aquecimento (fogueiras, aquecedores a querosene, lareiras), instancie uma `Area2D` com grupo `"heat_source"`. O `ColdSurvivalController` detecta automaticamente qualquer nó pertencente a esse grupo em raio menor que `220.0px`.
3. **Instanciação de Veículos 3D:** Todos os veículos da montanha devem herdar de `HarborCoupe.gd` e sobrepor obrigatoriamente `exit_vehicle()` para desligar sua `Camera2D` nativa antes de retornar o controle ao jogador.
4. **Gatilhos Inter-Distritais:** Jamais crie instâncias de `HarborBridge` em cenas fora de `HarborGame` sem setar `bridge.is_in_mountain_pass = true`. A ponte precisa saber em qual distrito está para não duplicar gatilhos de travessia.
5. **Persistência e Save State:** As transições entre distritos usam `SaveManager.request_autosave("transicao_mountain_pass")` e `SaveManager.request_autosave("retorno_harbor")`. Os estados de inventário do jogador, armas equipadas e temperatura corporal persistem no dicionário global de savegame.

---
*Fim do Documento Técnico CODEX — Mountain Pass Architecture.*

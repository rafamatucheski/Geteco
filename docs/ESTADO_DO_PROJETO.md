# GETECO — Estado do Projeto

> Levantamento amplo do projeto: o que é, em que tecnologia, quais sistemas existem, o
> que funciona, o que precisa de revisão e quais são os próximos passos. Feito por
> leitura direta do código e da documentação em **2026-09-15**, na última posição do
> HEAD (`9e17b23`), com uma segunda passada no mesmo dia acrescentando varredura de
> arquivos não utilizados e análise de organização de pastas. É uma fotografia, não um
> documento vivo — sistemas mudam rápido neste repositório (ver
> [Convenções de agentes](#convenções-de-processo-multi-agente)). Para o mapa técnico
> canônico mantido pela equipe, veja [docs/ARCHITECTURE.md](ARCHITECTURE.md) e
> [README.md](../README.md); este documento complementa os dois com uma varredura de
> sistemas de gameplay que eles não cobrem.
>
> **Nota da segunda passada**: no momento desta atualização, `EmergencyVehicle.gd` e
> `PoliceOfficer.gd` tinham mudanças não commitadas, modificadas poucos minutos antes
> (09:24–09:29) — sinal de outra sessão/editor trabalhando em paralelo, conforme o
> próprio [CLAUDE.md](../CLAUDE.md) prevê. Este documento e o commit que o acompanha
> **não tocam nesses dois arquivos**.

## Índice

1. [O que é o GETECO](#o-que-é-o-geteco)
2. [Tecnologia](#tecnologia)
3. [Estrutura de pastas](#estrutura-de-pastas)
4. [Fluxo de entrada no jogo](#fluxo-de-entrada-no-jogo)
5. [Sistemas centrais](#sistemas-centrais)
6. [O mundo: Harbor e Mountain Pass](#o-mundo-harbor-e-mountain-pass)
7. [Campanha e narrativa](#campanha-e-narrativa)
8. [Áudio](#áudio)
9. [O que funciona hoje (resumo)](#o-que-funciona-hoje-resumo)
10. [Pendências conhecidas e itens que precisam de revisão](#pendências-conhecidas-e-itens-que-precisam-de-revisão)
11. [Arquivos não utilizados (varredura verificada)](#arquivos-não-utilizados-varredura-verificada)
12. [Organização de pastas — análise e recomendação](#organização-de-pastas--análise-e-recomendação)
13. [Passos futuros / backlog registrado](#passos-futuros--backlog-registrado)
14. [Testes e verificação](#testes-e-verificação)
15. [Histórico registrado (docs/history)](#histórico-registrado-docshistory)
16. [Ferramentas de manutenção (tools/)](#ferramentas-de-manutenção-tools)
17. [Convenções de processo multi-agente](#convenções-de-processo-multi-agente)

> Plano de reorganização por domínio (Cars/Guns/Police/Systems/Geodata/Characters/Economy),
> decidido nesta sessão mas ainda não executado:
> [docs/PLANO_REORGANIZACAO_PASTAS.md](PLANO_REORGANIZACAO_PASTAS.md).

---

## O que é o GETECO

Jogo de ação top-down no espírito dos GTA 2D clássicos: uma cidade portuária viva com
trânsito, pedestres, polícia com nível de procurado, serviços de emergência, lojas,
missões, e uma segunda região de montanha/neve conectada por streaming contínuo — tudo
numa única árvore de cena, sem tela de carregamento entre as duas regiões.

**Decisão técnica central do projeto**: a simulação é **2D** (`CharacterBody2D`,
`Area2D`, `Path2D` para faixas de trânsito), mas personagens, veículos e vários props são
**modelos 3D renderizados dentro de `SubViewport`s** e exibidos como sprites no mundo 2D.
Essa escolha explica boa parte do custo de carregamento e da arquitetura de câmera do
projeto (ver [docs/ARCHITECTURE.md](ARCHITECTURE.md)).

## Tecnologia

- **Motor**: Godot 4.7.2, perfil `Forward+`/Vulkan em runtime real; `renderer/rendering_method="mobile"` no `project.godot` (o jogo já mira a esteira mobile mesmo rodando em desktop hoje).
- **Linguagem**: GDScript em todo o projeto vivo.
- **Física**: 2D (`CharacterBody2D`/`Area2D`), gravidade zerada, interpolação de física ligada.
- **Áudio**: majoritariamente **síntese procedural** (motores de veículo, ambiência de cidade, sirenes) em vez de samples gravados — ver [Áudio](#áudio).
- **Sem framework de teste externo**: cada teste é um script `SceneTree` independente, executado via `--script`, que imprime resultado e sai com código 0/1.
- **Referências por caminho de string** (`res://...`), não por UID — mover arquivo exige atualizar ~1.163 referências distintas manualmente ou via `tools/move_folder_refactor.py`.
- **Editor plugin próprio**: `addons/city_layout_editor` (habilitado), ferramenta de autoria de malha viária/lotes dentro do editor do Godot.

## Estrutura de pastas

| pasta | o que é |
|---|---|
| `ui/` | Menus e HUD de interface (~35 scripts). `MainMenu.tscn` é o entrypoint. |
| `world/harbor/` | **O jogo principal.** Distrito portuário: `HarborGame.tscn`, campanha, gangue Cobras, interiores, eventos. 206 scripts `.gd`. |
| `world/mountain_pass/` | Segunda região, carregada por streaming quando o jogador se aproxima. 125 scripts `.gd`. |
| `world/shared/` | Infraestrutura compartilhada entre regiões: malha viária, tráfego, pedestres, combate, emergência, ferrovia, salvage, motos, natureza. 160 scripts `.gd`. |
| raiz (`*.gd`) | Sistemas globais: `Player`, `PlayerCar`, `WantedManager`, `EmergencyVehicle`, `PoliceOfficer`, `HUD`, `SaveManager`, catálogos de armas/veículos/roupas — ~19 autoloads declarados em `project.godot`. |
| `audio/`, `cutscenes/`, `data/` | Som, cutscene de abertura, dados de campanha. |
| `interiors/`, `missions/`, `scenes/`, `scripts/`, `assets/` | Peças menores usadas pelo jogo vivo. |
| `legacy/` | Geração anterior do jogo. **Não é código morto** — `HarborSceneRoute.for_save()` ainda carrega `legacy/Main.tscn` para saves antigos sem a flag `harbor_campaign_active`. |
| `prototypes/` | Trabalho de arte isolado, nada carregado automaticamente pelo jogo (ver [tabela abaixo](#o-mundo-harbor-e-mountain-pass)). `prototypes/gameplay_repair_art_0909/` é território do Antigravity. |
| `OLD/` | Arquivo morto de verdade — tem `.gdignore`, o Godot ignora a pasta inteira. |
| `tests/` | 760 arquivos (547 seguem `test_*.gd`): regressão, capturas de imagem (`capture_*`), auditorias pontuais (`audit_*`, `profile_*`, `diagnose_*`). |
| `tools/` | Utilitários de manutenção do repositório (ver [seção dedicada](#ferramentas-de-manutenção-tools)). |
| `docs/` | Documentação estrutural; `docs/history/` guarda relatórios de sessão datados. |

## Fluxo de entrada no jogo

```
project.godot  run/main_scene
      └── ui/MainMenu.tscn
            ├── Novo Jogo → ui/GameLoading.gd (prefetch threaded) → cutscenes/opening/ → world/harbor/HarborGame.tscn
            └── Carregar Jogo → SaveManager (slots com auditoria) → HarborSceneRoute.for_save()
                                                                            ├── harbor_campaign_active → HarborGame.tscn
                                                                            └── sem a flag        → legacy/Main.tscn
```

`HarborGame.tscn` é uma cena **herdada** de `HarborPreview.tscn`; `HarborGame.gd` estende
`HarborPreview.gd`. A camada `HarborPreview` monta o distrito (ruas, prédios, tráfego,
pedestres); a camada `HarborGame` acrescenta campanha, missões e HUD de jogo.

Menu → fundo estilizado (`SunsetMenuPresentation.gd`) → barra de carregamento com
prefetch (`ResourceLoader.load_threaded_request` já disparado no hover do botão) →
**cutscene de abertura** (montagem fotográfica atual, ver [Áudio](#áudio) e narrativa
abaixo) → entrada no mundo já dentro da sequência de chegada (delegacia → ferro-velho do
Neco → Maciota).

## Sistemas centrais

### Autoloads (singletons globais, `project.godot`)

| autoload | arquivo | responsabilidade |
|---|---|---|
| `ProjectTypography` | `ui/ProjectTypography.gd` | Registra as fontes Barlow como fallback global de tema. |
| `PresentationBudget` | `PresentationBudget.gd` | Fila que limita construção de apresentação 3D a ~2000µs/frame, priorizando o ator mais próximo do centro de tela. |
| `Localization` | `Localization.gd` | i18n pt_BR/en para menus, HUD, cutscene de abertura e diálogo — cobertura parcial e deliberada (placas decorativas do mundo ficam de fora). |
| `SettingsManager` | `SettingsManager.gd` | Vídeo/áudio/janela, persistido em `user://settings.cfg` (separado do save de jogo). |
| `MissionVoiceMixer` | `audio/MissionVoiceMixer.gd` | Bus dedicado de diálogo de missão com *ducking* de -16dB sobre o áudio do mundo. |
| `WantedManager` | `WantedManager.gd` | Núcleo do nível de procurado: pontos de crime → estrelas, despacho de polícia. |
| `EmergencyPool` | `EmergencyPool.gd` | Pool fixo de veículos/oficiais de emergência: **7 polícia** (3 sedãs + 2 SUVs + 2 motos), 2 ambulância, 2 bombeiro, 2 coroner. |
| `CityAudioManager` | `CityAudioManager.gd` | Ambiência sonora contínua da cidade. |
| `TrafficLightManager` | `TrafficLightManager.gd` | Autoridade única de semáforos (máquina de estados por fase). |
| `CampaignState` | `CampaignState.gd` | Estado persistente de campanha (flags, territórios, salvage, corridas, incidente do banco, casos médicos/coroner) — puro dado, sem referência a nós de cena. |
| `NPCMedicalCare` | `world/shared/emergency/NPCMedicalCare.gd` | Rastreia NPCs residentes feridos como "incidente" com identidade estável entre streaming e reload. |
| `CoronerCare` | `world/shared/emergency/CoronerCare.gd` | Livro de custódia de corpos (descoberto → transporte → morgue → enterro). |
| `WorldRenewal` | `world/shared/WorldRenewal.gd` | Relógio único de manutenção de mundo (recupera veículos/props fora de vista). |
| `DistrictRestriction` | `DistrictRestrictionManager.gd` | Regra da "tornozeleira eletrônica" do Bairro 1 (aviso/breach/perseguição letal). |
| `SaveManager` | `SaveManager.gd` | Save/load versionado, `user://saves/slot_NN.json`, escrita atômica. |
| `RegionTravel` | `RegionTravel.gd` | Mantém o veículo do jogador entre troca de cena na rota legada (fallback de `ContinuousWorld`). |
| `GameInput` | `ui/GameInput.gd` | Ações de jogo: teclado, gamepad, touch, atalhos de arma 1–10. |
| `GameLoading` | `ui/GameLoading.gd` | `CanvasLayer` de loading com prefetch threaded e telemetria de fases. |

### Player e controles

`Player.gd` (1724 linhas, `CharacterBody2D`): movimento a pé com sistema de "gait"
sincronizado ao deslocamento real em pixels, sem rotação do próprio corpo 2D — a
orientação visual gira o rig 3D dentro do `SubViewport`. Câmera dinâmica
(`DynamicCamera.gd`) com zoom adaptativo por velocidade, vinheta neon e modo overview
(F9). `PlayerCar.gd` (1213 linhas) cuida da física do carro: tração/derrapagem via
`VehicleMotionSafety.grip()`, nitro, freio de mão, dano e reparo.

### Armas e combate

`WeaponCatalog.gd` — **16 armas**, catálogo único e centralizado: 5 corpo-a-corpo (punho,
soco inglês, faca, taco, machado — sem munição, `magazine_size = -1`) e 11 de fogo
(pistola, magnum, SMG, shotgun/serrada, AK-47/M4A1, RPG explosivo, lança-chamas, granada,
rifle de caça como pickup de descoberta). Dano cai com a distância via
`distance_damage()`. Recarga animada por arma, com áudio dedicado.

Combate corpo-a-corpo (`Player._perform_melee_attack()`): cone de ~80° na frente do
jogador, janelas de acerto sincronizadas com a pose de cada arma, epoch de cancelamento
se a arma trocar no meio do golpe, facada com raycast de obstrução e priorização por
distância. NPCs também usam melee (`NPCCombatRig.gd`). Sistema testado
(`test_axe_swing`, `test_bat_swing`, `test_knife_single_target`, `test_weapon_range`).

### Veículos

`VehicleCatalog.gd` (492 linhas) — frota por bioma/distrito (city, desert, winter, beach,
industrial, forest, emergency, gang_specials) com massa, velocidade, aceleração,
frenagem, drift, durabilidade e classe de modelo 3D. `RaceCatalog.gd` cobre 5 corridas
clandestinas noturnas fixas.

Dano visual: portas 2D processuais com hinge (`VehicleDoorVisual.gd`), arranhões
limitados ao footprint (`VehicleSurfaceWear2D.gd`, máx. 6 simultâneos), deformação de
malha 3D (substituiu o antigo sistema de placas/fragmentos — ver
`docs/history/VEHICLE_DAMAGE_CAMERA_2026-09-08.md`).

**Recuperação de veículos** é o **Ferro-Velho do Neco** (`world/shared/salvage/`,
documentado em `docs/salvage-yard-0910.md`): guincho dirigível com engate/desengate por
raycast, prensa 3D, cota diária de 6 entregas, até 3 encomendas por dia com prazo
($2400), reconstrução após save/reload, e integração com `WantedManager` (guinchar
viatura de polícia gera estrelas). **Nota**: `GarageTrigger.gd`/`GarageMenu.gd` na raiz
têm nome parecido mas são **código legado morto**, usados só por `legacy/city_demo/`.
`VehicleUpgradeManager.gd` (upgrade estilo NFS) também está efetivamente desligado hoje —
o próprio código força nitro a zero e não é chamado de nenhum lugar do jogo vivo.

### Polícia, nível de procurado e emergência

Cadeia de despacho (confirmada em código e em `ARCHITECTURE.md`):

```
WantedManager._dispatch_police()
   └── HarborEmergencyDirector.request_dispatch()   (world/harbor/)
         └── EmergencyDepotDirector.request_dispatch()   (world/shared/emergency/)
               └── EmergencyPool.get_vehicle()      (autoload, pool finito)
```

`WantedManager.gd`: pontos de crime acumulam para até 6 estrelas
(`[0,12,30,60,100,160,240]`), com memória de incidente menor que expira em 12s antes de
virar perseguição. `PoliceOfficer.gd` (984 linhas): 5 tiers de unidade (patrulha →
detetive → SWAT → FBI → exército), cada um com arma própria, prisão com aviso, embarque
em viatura, cobertura atrás do carro. `EmergencyVehicle.gd` (1744 linhas) cobre os 4
tipos (polícia/ambulância/bombeiro/coroner) num script único; **não usa
`NavigationAgent2D`** — direção manual (`lerp_angle`) rumo a waypoint, com recuperação de
travamento dando ré (fonte conhecida de bugs de circulação).

Serviços médicos/coroner (`world/shared/emergency/`, ~40 scripts especializados):
resgate de ambulância (`MedicalRescueSequence`, `MedicalStretcher`), chegada ao hospital,
supressão de incêndio (`FireSuppression`, `VehicleWaterCannon`), depósitos
(`EmergencyDepotDirector`). `NPCMedicalCare` e `CoronerCare` (autoloads) dão identidade
estável a cada incidente/corpo através de streaming e reload de save.

### Save/Load

`SaveManager.gd`: 5 slots + autosave em `user://saves/`, JSON versionado
(`save_version=1`), escrita atômica (`.tmp` + rename). Recusa salvar durante perseguição
ativa (`current_stars > 0`) ou com a prensa do ferro-velho ocupada. Não é dono de nenhum
dado — apenas orquestra `CampaignState.to_save_data()`, `Player.serialize()`,
`RegionTravel.snapshot_world()` e `WantedManager.serialize()`.

### HUD

`HUD.gd` (442 linhas): dinheiro, estrelas, vida/armadura, ícone de arma renderizado em 3D
(`WeaponIcon3D`, não sprite estático), munição. Tem layout alternativo "classic status" e
ainda expõe alguns botões de teste/debug embutidos na própria cena (buzina, farol,
overview do mapa) — sinal de que a HUD final ainda carrega resíduo de QA.

## O mundo: Harbor e Mountain Pass

### Harbor (distrito portuário — o jogo vivo)

~50 prédios sólidos, ~45 acessos, ~20 segmentos de rua autorados, 40 faixas dirigidas, 38
junções (números crescem com as expansões). Subsistemas: distritos
(`HarborDistrict`/`North`/`East`/`SouthPort`), malha viária (`HarborRoadLayout`,
`HarborRoadNetwork`, `HarborBridge` — ponte estaiada compartilhada com a montanha),
ferrovia de frete (`HarborRailLine`), transporte público local (`HarborTransitBus`) e
intermunicipal (`terminal/`, `urban_transit/`), logística portuária (empilhadeiras,
caminhões-contêiner, guindastes), segurança do porto, cemitério, moradores e vida
noturna, lojas/interiores (banco, roupas, ammunation, clínica, delegacia, hospital,
garagem, morgue, bombeiros — 20 scripts em `interiors/`). O navio "Northstar" é
explorável a pé mas **não é pilotável** (`ship_pilotable = false`).

**Gangue Cobras** (`world/harbor/cobras/`): enclave residencial "Ashbend Court",
integrado em produção — máquina de estados de encontro (calmo → aviso → confronto),
percepção com oclusão de parede, população finita, reputação, retirada. 22 arquivos de
teste dedicados cobrem território, corrida, campanha (5 missões), veículo secreto e
regressões de tráfego do anel Cobra.

### Mountain Pass (segunda região — neve/montanha)

Conectada por ponte estaiada e por streaming contínuo (ver abaixo). Gangue territorial
própria — os **Lobos de Gelo**, que tomaram o bunker do cume com metralhadoras e
barricaram a pista de pouso (revelado via diálogo do NPC guarda florestal Silas Vance).
Conteúdo: túnel jogável, madeireira, lago com ponte pênsil, caverna secreta com arma
rara, subida hairpin com mirante, pista de gelo liso, tempestade de gelo/granizo, sistema
de frio/hipotermia como mecânica própria, bunker militar de radar, estação de esqui
completa (lift, pista, aluguel), vila/resort, avião cargueiro acidentado (escala 1:1,
~24m, explorável, com corte de teto), e um "mistério" narrativo — um monstro
(`MountainShadow`) que se revela após o jogador coletar 3 pistas espalhadas.

### Streaming contínuo (`world/harbor/ContinuousWorld.gd`)

Uma única árvore com as duas regiões. A montanha é pré-carregada em thread e instanciada
quando o jogador se aproxima da emenda (`SEAM_X = 7300.0`). Fora da vizinhança ativa
(>3200px da emenda), a região fica `process_mode = PROCESS_MODE_DISABLED` e
`visible = false` — não simula nem renderiza, mas preserva a instância. Veículos que
cruzam a ponte são transferidos de faixa entre regiões via `_handoff()` (reparent direto,
sem respawn, com checagem de colisão num raio de 110px antes de aceitar a transferência).
Um único `Player`/câmera serve as duas regiões.

### `world/shared/` — infraestrutura compartilhada

14 subpastas, 160 scripts: `roads/` (malha viária, roteador de emergência,
`JunctionTrafficController`), `traffic/` (`TrafficVehicle.gd`, 2.726 linhas — núcleo do
tráfego ambiente), `pedestrians/` (aparência processual, rotinas de vida), `combat/` (23
scripts de sangue/ferimento/explosão), `emergency/` (38 scripts, a maior subpasta),
`rail/`, `nature/`, `interiors/` (infraestrutura genérica reaproveitada por Harbor e
Mountain), `salvage/` (ferro-velho), `motorcycles/`, `ammunation/`, `atmosphere/`,
`pickups/`, `transit/` (coach intermunicipal entre as duas regiões).

### `prototypes/` — arte isolada, nada carregado pelo jogo

| pasta | propósito |
|---|---|
| `gameplay_repair_art_0909/` | **Território do Antigravity — não editar.** Demos de funeral, personagem Elias, retirada policial. |
| `living_cast/` | Modelos de personagens e frota 3D (base para o catálogo de veículos vivo). |
| `dante_cgi/` | Modelos/cenas de comparação do protagonista para a CGI. |
| `garage/` | Protótipo de interface de garagem. |
| `harbor_art_pack/` | Props do porto (hoje integrados ao armazém real do Harbor). |
| `loadout/` | Prévia HTML (fora do Godot) de inventário de três slots. |
| `menu_concept/` | Conceito visual do menu. |

## Campanha e narrativa

Progressão jogável hoje (decisão de autoria de 11/09/2026, substitui uma versão anterior
"ligação → Maciota direto"):

1. **Abertura** (cutscene fotográfica) → desembarque no terminal.
2. **Delegacia**: Dante descobre que o irmão foi solto e está envolvido em contrabando/rachas.
3. Ligação anônima direciona ao ferro-velho do Neco, onde conhece **Maciota** (sedã preto estilo M8).
4. **Passeio de carro** com Maciota por rotas reais do mapa até a garagem Westgate.
5. Maciota oferece ajuda em troca de favores → libera o quadro Cobra e a missão **"Primeiro giro"** ($150, recompensa é o carro pessoal "Monaliza").
6. **Campanha Cobra** (`CobraCampaignState.gd`): 5 missões (`cobra_contact` → `cobra_race` → `cobra_collection` → `cobra_supply` → `cobra_finale`), recompensas totalizando **$1.520**, progredindo por "dias" de jogo (10 min ativos = 1 dia).
7. **Assalto ao banco**: sistema lateral (não é a missão principal), em etapas — segurança, cartão, cofre, coleta, fuga, reação de guardas, cerco externo, evacuação pós-assalto. Trabalho ativo recente (commits `cdb16af` a `afe2769`).

**Personagens**:
- **Dante Ferraz** (29) — protagonista, ex-policial expulso ao tentar ajudar o irmão.
- **Vicente "Vico" Ferraz** (36) — irmão de Dante, solto, líder de um clã (nome ainda não definido), será o boss final. Documento marcado como **spoiler**, não deve vazar para diálogos do mapa 1.
- **Márcio "Maciota" Azevedo** (48) — mecânico/despachante do porto, NPC aliado central do mapa 1.
- **"Monaliza"** — **não é personagem, é o carro pessoal de Dante** (cupê azul/laranja turbo), entregue como recompensa do "Primeiro giro".

Documentos de planejamento maiores (`docs/CAMPAIGN_STORY_BIBLE.md`,
`docs/CAMPAIGN_MISSIONS.md` — 37 missões em 4 mapas planejados: Harbor → Deserto →
Cidade 2 → Vegas — `docs/CAMPAIGN_PRODUCTION.md`,
`docs/CAMPAIGN_CHARACTERS_AND_CONNECTIONS.md`) são **autoria, não implementação**, e os
próprios documentos frisam essa distinção repetidamente. O arquivo legado
`data/campaign/campaign_v1.json` (premissa antiga, distrito 2 = "rural_badlands") está em
conflito com o cânone atual e não deve ser ligado aos desbloqueios da campanha nova.

### Cutscene de abertura (`cutscenes/opening/`)

Versão vigente (`v3/`): **montagem fotográfica de 25 imagens fixas, 1920×1080, 86
segundos** — café/rotina → ligação anônima → notícia da soltura do irmão → reações
emocionais silenciosas → foto dos irmãos → saída → viagem de ônibus → chegada ao
terminal. Substituiu, por pedido do usuário, uma tentativa anterior de animação 3D
contínua com o personagem renderizado ao vivo (essas ferramentas de produção continuam no
repositório, só não são usadas em runtime). Voz do interlocutor sintética via Qwen3-TTS
VoiceDesign; voz de Dante via edge-tts — documentado como ainda sujeito a avaliação
artística. `world/harbor/HARBOR_FIRST_MISSION.md` ainda descreve a versão antiga (10
imagens, 41,5s) e está **desatualizado** frente a `cutscenes/opening/v3/README.md`.

## Áudio

Majoritariamente **síntese procedural**, não samples gravados:
- `CityAudioManager` (autoload): ambiência contínua da cidade.
- Motores de veículo por **família** (street, sport, muscle, SUV, diesel, truck, bus,
  emergência), cada uma com 3 camadas por faixa de giro e cadeia física (pulsos de
  combustão → ressoadores → assobio de turbina/câmbio) — documentado em
  `audio/AUDIO_README.md`. Reforço recente: som realista de caminhões/ônibus com assobio
  de turbina na troca de marcha (commit `a3dbed9`).
- `MissionVoiceMixer` (autoload): bus dedicado de diálogo com ducking sobre o mundo.
- `ExpressiveVoice.gd`: motor de voz sintética por personagem (Dante, Maciota, caller)
  para diálogos ainda sem dublagem gravada final — pausas silenciosas, verificação de
  pico/clipping.
- Gravações humanas em progresso para vozes de missão: `audio/mission_voices/` tem
  `dante_human/`, `dante_pt_2026-09-14/`, `maciota_pt_2026-09-14/`, com briefs de
  gravação — indica transição em curso de voz sintética para voz gravada.
- `audio/weather/`, `audio/monaliza_review/` (kit exclusivo do carro pessoal), `audio/combat/`, `audio/vehicle_crashes/`, `audio/police_dispatch/`, `audio/radio/`, `audio/living_city/`.

## O que funciona hoje (resumo)

Com base em leitura de código real (não só documentação) e nos 34/34 testes headless
focados citados em `world/harbor/HARBOR_IMPLEMENTATION_2026-09-06.md` (nota: essa é uma
suíte focada, não a suíte inteira do repositório):

- Entrada completa menu → carregamento → cutscene → mundo jogável.
- Movimento a pé e de veículo, troca de câmera, sistema de armas (16 armas, incl. melee) com recarga e mira.
- Nível de procurado com despacho de polícia em 5 tiers, prisão, embarque em viatura.
- Serviços de emergência (ambulância, bombeiro, coroner) com identidade estável de incidente entre streaming/reload.
- Ferro-velho/guincho de veículos, completo e testado.
- Save/load versionado com bloqueios de segurança (não salva em perseguição ou com prensa ocupada).
- Streaming contínuo Harbor↔Mountain sem tela de carregamento, com handoff de tráfego sem respawn.
- Gangue Cobras: território, encontro, 5 missões de campanha, corrida, carro secreto, boss.
- Cutscene de abertura fotográfica de 86s com áudio sincronizado.
- Sistema de tutoriais contextuais integrado (loja térmica, túnel, arma rara, jogador procurado entrando em interior).
- Áudio procedural de motor por família de veículo, ambiência de cidade, mixagem de diálogo dedicada.
- Suíte de 760 arquivos de teste, incluindo medição de performance com renderização real.

## Pendências conhecidas e itens que precisam de revisão

**Confirmadas por este levantamento (2026-09-15):**

- **Congelamento de ~9,2s num único frame no carregamento** — `HarborPreview._start_review()`
  constrói o mundo inteiro de uma vez (`docs/ARCHITECTURE.md`). Não há evidência de que
  tenha sido resolvido; é a pendência de maior impacto percebido.
- **`test_harbor_safety` é instável**: 2 falhas em 3 execuções segundo o commit mais
  recente, causa não isolada (veículo civil que não retoma a tempo / telemetria de
  travamento de cruzamento).
- **Circulação de emergência**: `EmergencyVehicle.gd` não usa `NavigationAgent2D` —
  direção manual com recuperação de travamento por ré, que pode entrar em ciclo se o
  waypoint for inalcançável. Casos observados sem causa isolada (viatura com 15 ciclos de
  ré em 45s; ambulância que não sai do pool para ocorrência perto do hospital).
- **Conexão ao "Mapa 2"**: `HarborGateway.get_map2_connection_contract()` retorna
  `connected=false` — a montanha já é jogável via streaming, mas é tratada como região
  técnica separada do "Mapa 2" narrativo mencionado nos documentos de campanha.
- **`.tscn` com BOM não carrega**: `legacy/district/bairro1_v2/landmarks/LandmarksV2.tscn`
  e `prototypes/living_cast/FleetShowcasePhase2.tscn`. Nenhum está no jogo vivo.
- **`VehicleUpgradeManager.gd`** e **`GarageTrigger.gd`/`GarageMenu.gd`** são código morto
  vestigial na raiz do projeto — não referenciados pelo jogo vivo, mas ainda presentes ao
  lado de sistemas ativos, o que pode confundir quem procura o sistema real de upgrade ou
  de garagem (que são, respectivamente, inexistente hoje e o Ferro-Velho do Neco).

**Documentação desatualizada encontrada nesta varredura** (vale corrigir):

- `docs/ARCHITECTURE.md` lista `RegionTravel.gd:190` carregando `res://PlayerCar.tscn`
  (cena inexistente) como crash latente. **Isso já não é verdade**: o código atual
  (linha ~205) carrega `res://cars/traffic/SavedPlayerCar.tscn`, que existe —
  confirmado tanto por leitura do arquivo quanto por `python tools/check_references.py`
  (0 quebras conhecidas, 0 novas). A entrada correspondente em
  `tools/check_references.py::KNOWN_BROKEN` também ficou obsoleta e pode ser removida.
- `docs/ARCHITECTURE.md` diz que `EmergencyPool` tem 4 viaturas de polícia; o código
  (`EmergencyPool.gd:6`) define `POOL_SIZE_POLICE = 7` (3 sedãs + 2 SUVs + 2 motos).
- `world/harbor/HARBOR_FIRST_MISSION.md` ainda descreve a cutscene de abertura antiga (10
  imagens, 41,5s); a versão vigente é `cutscenes/opening/v3/` (25 imagens, 86s).

**Áreas historicamente instáveis, sem confirmação de estado atual** (citadas em múltiplos
documentos ao longo do tempo, sem um documento definitivo mais recente que feche o
assunto):

- Fila de trânsito em "Courtyard Lane" (corrigida numa rodada, remencionada em documentos anteriores e posteriores).
- Atendimento automático de incêndio no Harbor (endereçado, mas com casos de fila/travamento sem causa isolada).
- Frames-outlier de ~250–300ms parcialmente não explicados (`PERFORMANCE_VALIDATION.md`): o gargalo do `JunctionTrafficController` fazendo hash de string de ~98 mil caracteres a cada consulta foi identificado, mas os picos de frame persistem — "sinalizado, não corrigido".

## Arquivos não utilizados (varredura verificada)

Metodologia: script de varredura reversa (o inverso de `tools/check_references.py`) —
para cada `.gd` das pastas "vivas" (`ui/`, `world/`, raiz do projeto, `audio/`,
`cutscenes/`, `data/`, `interiors/`, `missions/`, `scenes/`, `scripts/`, `assets/`,
`addons/`; **673 arquivos**), procura o caminho `res://...` do arquivo em todo o resto
do repositório (3.570 arquivos de texto — inclui `tests/`, `tools/`, `legacy/`,
`prototypes/`, `docs/`, exclui apenas `OLD/`, que o Godot já ignora). Se o caminho não
aparece em lugar nenhum, verifica também se o arquivo declara `class_name` e se esse
identificador é usado como tipo em outro lugar (cobre referência via nome de classe
global, não só por caminho).

**Limite explícito do método**: não cobre string construída dinamicamente em runtime
(ex.: concatenação de caminho a partir de variável). Por isso os resultados abaixo são
**candidatos**, não uma prova de código morto — antes de apagar, confirme abrindo o
arquivo no editor do Godot e usando "Localizar uso" (ou rode o jogo e procure o ponto
esperado de uso).

### Resultado: só 2 arquivos em todo o projeto vivo não têm nenhuma referência

| arquivo | observação |
|---|---|
| `world/mountain_pass/MountainGunCounterSupport.gd` | Estende `HarborInteriorBase.gd`, implementa um balcão de compra de arma/munição para a Ammu-Nation da montanha (NPC "Armeiro Vance", 4 armas + munição). Código completo e funcional, não um stub. Sem nenhuma referência em cena, script ou teste — provavelmente superado pela versão em `world/mountain_pass/art/review_0908/MountainGunShopInterior3D.gd`, que é a que de fato aparece integrada. |
| `world/mountain_pass/MountainLakeGeometry.gd` | Gera o contorno do lago, colisão da margem e recuperação de atores presos na água. Também código completo e funcional, sem nenhuma referência. Pode ter sido substituído por uma implementação equivalente dentro de `MountainExpedition.gd` ou de outro script do lago — não confirmei qual. |

Isso é, na prática, um resultado **muito positivo de higiene de código**: de 673 scripts
vivos, apenas 2 (0,3%) ficaram órfãos. Recomendo confirmar os dois manualmente (abrir no
editor, checar se algo os carrega por convenção de nome/pasta) antes de remover; se
confirmados órfãos, o destino correto é `OLD/` (arquivo morto, com `.gdignore`), não
apagar — preserva histórico e segue a convenção já estabelecida no projeto.

### Achados relacionados (não são "não utilizados", mas mudam a classificação)

- **`GarageMenu.gd`/`GarageMenu.tscn` e `GarageTrigger.gd`/`GarageTrigger.tscn`**
  (raiz do projeto): referenciados **só** por `legacy/city_demo/scripts/CityDemo.gd`.
  Não são código morto — `legacy/` carrega em runtime para saves antigos — mas também
  **não fazem parte do jogo vivo** (`world/harbor/`). Estão fisicamente na raiz do
  projeto, ao lado de sistemas realmente vivos como `Player.gd`, sem nada que sinalize
  que são exclusivos do legado. A recuperação de veículo do jogo atual é outro sistema,
  o Ferro-Velho do Neco (`world/shared/salvage/`) — ver [Sistemas centrais](#sistemas-centrais).
- **`VehicleUpgradeManager.gd`** (raiz): mesma situação — referenciado só por
  `legacy/CentralDistrict.gd` e por `tests/test_save_gate_engine_families.gd` (que
  existe justamente para garantir que o upgrade legado continua desativado). Não é
  código morto, é cobertura de compatibilidade com saves antigos.
- **`MissionManager.gd`, `IronCobraMember.gd`, `IronCobraCulDeSac.gd`** (raiz):
  encontrados ao ler o conteúdo desses arquivos para resolver o plano de reorganização
  ([docs/PLANO_REORGANIZACAO_PASTAS.md](PLANO_REORGANIZACAO_PASTAS.md)) — mesma
  categoria dos dois itens acima. `MissionManager.gd` só é instanciado por
  `legacy/CentralDistrict.gd` (a menção em `CampaignState.gd` é um comentário dizendo o
  oposto: que `CampaignState` não o chama). `IronCobraCulDeSac.gd`/`IronCobraMember.gd`
  são uma implementação antiga da gangue/território Cobra (cul-de-sac estilo Grove
  Street) usada só através do `MissionManager.gd` legado — o sistema de gangue Cobra
  **vivo** é outro, em `world/harbor/cobras/`. Os dois coexistem no repositório sem
  nenhum aviso de que um deles é o remanescente.
- **`ChopShopCrusher3D.gd`/`ChopShopZone.gd`** (raiz): ao contrário do que os documentos
  de backlog sugerem ("área de desmanche de carros" listada como não implementada em
  `MAP1_EXPANSION_BACKLOG.md`), esses dois scripts **são usados por
  `world/harbor/HarborGame.gd`** e têm testes próprios (`tests/test_port_boss_garage.gd`,
  `tests/test_monaliza_reward.gd`). Não confirmei em jogo se cobre o mesmo escopo que o
  backlog descrevia — vale conferir antes de tratar aquele item do backlog como
  totalmente pendente.

## Organização de pastas — análise e recomendação

### O que existe hoje

A raiz do projeto tem **82 scripts `.gd` soltos** (mais seus `.uid` e `.tscn`
companheiros) sem nenhuma subpasta — é onde vivem os autoloads, `Player`/`PlayerCar`,
catálogos (armas, veículos, roupas, colecionáveis, corrida), entidades de emergência,
pedestres/gangue, HUD, e também os remanescentes exclusivos do legado citados acima. Por
tema, aproximadameste: 10 autoloads, ~15 veículo/física, ~7 armas/projétil, ~10
polícia/emergência, ~7 pedestres/NPC/gangue, ~9 economia/colecionáveis/loja, ~4 corrida,
~6 apresentação/áudio/render, e os 3 arquivos legado-only.

Também na raiz, fora de `docs/`: `AGENTS.md`, `MANIFEST.md`,
`CODEX_MOUNTAIN_PASS_ARCHITECTURE.md`, `GUIA_LAYOUT_GODOT.md`,
`SESSION_REPORT_2026-09-07.md`, além de `car.png`, `getecologo.png`, `icon.svg` soltos
(fora de `assets/`). `AGENTS.md` merece nota à parte: **não é um arquivo redundante com o
CLAUDE.md** — guarda regras de gameplay permanentes que não estão documentadas em mais
nenhum lugar (ex.: Maciota e seu mecânico nunca podem morrer por nenhuma causa; a garagem
dele é área sem armas). Vale linkar esse arquivo a partir do README/CLAUDE.md para não
ficar invisível.

`world/harbor/` também tem 76 scripts soltos na própria raiz da pasta (fora das 13
subpastas temáticas que já existem: `campaign/`, `cemetery/`, `cobras/`, `events/`,
`hospital/`, `interiors/`, `monaliza/`, `residences/`, `restaurants/`, `sewer/`,
`terminal/`, `urban_transit/`) — dá pra ver agrupamentos naturais não extraídos ainda
(ferrovia, logística portuária, clima) mas o padrão de já ter 13 subpastas temáticas
mostra que a pasta *tende* a se organizar por tema conforme cresce, só não terminou o
processo.

`tests/` é a mais plana de todas: 760 arquivos, uma única subpasta (`tests/visual/`).
Sem categorização por sistema (só o prefixo do nome — `test_`, `capture_`, `audit_`,
`profile_`, `diagnose_`, `measure_`, `render_` — indica o tipo).

### O sistema de três camadas de "código antigo" já faz sentido

`OLD/` (morto, `.gdignore`), `legacy/` (não morto, carregado para saves antigos) e
`prototypes/` (arte isolada, não carregada automaticamente) são três categorias
diferentes e o README/CLAUDE.md já explicam a diferença com clareza. **Essa parte da
organização está bem, não precisa mudar.** O problema real não é a separação entre essas
três camadas — é que alguns arquivos *exclusivos* do legado (`GarageMenu.gd`,
`GarageTrigger.gd`, `VehicleUpgradeManager.gd`) ficaram fisicamente fora dessa separação,
na raiz junto com o jogo vivo.

### Atualização (2026-09-15, mesma sessão): decisão tomada de reorganizar por domínio

O usuário confirmou o objetivo: pastas por domínio de sistema (`/Cars`, `/Guns`,
`/Police`, `/Systems`, `/Geodata`, `/Assets`, `/Characters`) para que a árvore de pastas
já diga o que é o quê, em vez da pilha atual. Duas decisões:

- **Escopo**: só o material global/compartilhado (raiz do projeto + `world/shared/`).
  `world/harbor/` e `world/mountain_pass/` continuam como pastas de região.
- **Timing**: planejar agora, executar depois — só quando `EmergencyVehicle.gd`/
  `PoliceOfficer.gd` (em edição por outra sessão no momento deste documento) estiverem
  commitados.

O mapeamento completo, domínio por domínio, arquivo por arquivo, está em
[docs/PLANO_REORGANIZACAO_PASTAS.md](PLANO_REORGANIZACAO_PASTAS.md) — inclui os 5 casos
ambíguos que ainda precisam de uma palavra do usuário e o procedimento de execução por
fases seguindo o `CLAUDE.md`. A análise abaixo (escrita antes dessa decisão) continua
valendo como registro do raciocínio de custo × benefício que levou à abordagem faseada.

### Recomendação original desta análise (mantida como contexto, ver decisão acima)

O motivo é custo × benefício, não teoria de arquitetura:

- O projeto usa **referência por caminho de string** (não UID) — `tools/check_references.py`
  contou **1.163 referências distintas** para conferir. Mover qualquer coisa exige
  reescrever todas as ocorrências, rodar `check_references.py`, **reimportar no Godot**
  (o cache `.godot/global_script_class_cache.cfg` fica obsoleto e quebra resolução de
  classe mesmo com strings certas) e rodar a suíte de verificação inteira — o próprio
  [CLAUDE.md](../CLAUDE.md) descreve esse procedimento como obrigatório e não trivial.
- O projeto está em ritmo de multi-agente ativo agora mesmo — **este próprio levantamento
  encontrou `EmergencyVehicle.gd` e `PoliceOfficer.gd` sendo editados por outra sessão
  enquanto eu escrevia este documento**. Uma reorganização grande de pastas é exatamente
  o tipo de mudança que gera conflito com trabalho paralelo em andamento, e o repositório
  já perdeu trabalho uma vez por interação mal coordenada entre ferramentas
  (`docs/recuperacao-e-pendencias-codex-0914.md`, referenciado no commit `9e17b23`).
- O benefício de mover 82+76 arquivos em subpastas temáticas é sobretudo navegabilidade —
  e a nomenclatura já é consistente o bastante (prefixo `Harbor*`, `Mountain*`,
  `Vehicle*`, `Weapon*`, `Cobra*`) para que buscar por nome no editor praticamente já
  resolva o problema que subpastas resolveriam.

**Onde vale a pena investir, em vez de uma reorganização ampla:**

1. Confirmar e arquivar os 2 arquivos órfãos (`MountainGunCounterSupport.gd`,
   `MountainLakeGeometry.gd`) em `OLD/`, seguindo o procedimento de mover do CLAUDE.md.
2. Corrigir as duas informações desatualizadas do `docs/ARCHITECTURE.md` encontradas na
   primeira passada deste documento (crash de `RegionTravel.gd` já corrigido; contagem
   de viaturas de polícia) e remover a entrada obsoleta de
   `tools/check_references.py::KNOWN_BROKEN`.
3. Levar `AGENTS.md` para dentro da malha de documentação linkada (README/CLAUDE.md),
   já que hoje suas regras de gameplay ficam sem nenhum ponto de entrada.
4. Se algum dia fizer sentido mover algo, começar pelo menor risco: os 3 arquivos
   exclusivos do legado (`GarageMenu.*`, `GarageTrigger.*`, `VehicleUpgradeManager.gd`)
   para dentro de `legacy/`, já que são usados por um único consumidor (`legacy/`) cada.
   Isso já reduziria a poluição da raiz sem tocar em nada que o jogo vivo usa.

Nenhum desses quatro pontos foi executado nesta passada — são recomendação, não ação.
Avise se quiser que eu execute algum deles seguindo o procedimento completo do
[CLAUDE.md](../CLAUDE.md) (`git mv` + atualizar referências + `check_references.py` +
reimportar no Godot + suíte de verificação).

## Passos futuros / backlog registrado

De `world/harbor/MAP1_EXPANSION_BACKLOG.md` (07/09/2026), ainda não implementado:

- Interior 3D jogável da Ammu-Nation.
- Armas secretas desbloqueadas por pistas espalhadas.
- Área de desmanche de carros (distinta do ferro-velho do Neco).
- Maior diversidade visual/arquitetônica entre territórios.
- Minigame de entrega de pizza.
- Missões de táxi.
- 2 corridas Cobra opcionais adicionais.

Da narrativa (`world/harbor/campaign/NARRATIVE_CANON_SPOILERS.md`), decisões em aberto:

- Nome do clã do irmão (candidatos: "Pacto de Ferro", "Os Renegados", "Eclipse", "Ordem do Asfalto" — nenhum aprovado).
- Momento/forma de revelação da liderança do irmão.
- Papel do irmão numa corrida na "Cidade 2".
- Elenco secundário (Helena Duarte, Raul "Biela" Nascimento, Célia Paiva, Otávio "Cromo" Valença, entre outros) tem biografia proposta mas **não está modelado/implementado**.

Da campanha de produção mais ampla (`docs/CAMPAIGN_MISSIONS.md`): 37 missões planejadas
em 4 mapas (Harbor → Deserto → Cidade 2 → Vegas) — hoje só o mapa Harbor (+ Mountain Pass
como região técnica) está implementado.

Outros pendentes explícitos vistos na varredura:
- Rodoviária de múltiplas linhas e viagens entre distritos (hoje só uma parada/linha local).
- Transição de voz sintética para voz humana gravada nos diálogos de missão (gravações já em andamento em `audio/mission_voices/`).

## Testes e verificação

Não há framework externo — cada arquivo em `tests/` é um `SceneTree` standalone:

```bash
GODOT="D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
"$GODOT" --path . --script res://tests/<nome>.gd
```

**Nunca usar `--headless` para medir performance** — o driver de renderização dummy torna
FPS/draw calls/custo de GPU sem significado; `tests/measure_*` e `tests/profile_*`
dependem de Vulkan real.

Suíte de verificação recomendada após mudança estrutural
([docs/ARCHITECTURE.md](ARCHITECTURE.md), [CLAUDE.md](../CLAUDE.md)):

```bash
python tools/check_references.py
"$GODOT" --path . --script res://tests/profile_load_time_0909.gd
"$GODOT" --path . --script res://tests/test_menu_flow_integration.gd
"$GODOT" --path . --script res://tests/test_opening_cutscene_runtime.gd
"$GODOT" --path . --script res://tests/test_pedestrian_life_routines.gd
"$GODOT" --path . --script res://tests/test_pedestrian_render_lod.gd
```

**Honestidade de verificação** (regra do próprio projeto, repetida aqui porque é
central): uma suíte verde não prova que o jogo está correto — prova que aqueles casos
passaram. Vários defeitos reais já apareceram em partida de verdade com suítes aprovadas.
Praticamente todos os documentos de sessão em `world/harbor/` seguem essa disciplina:
citam números de teste específicos como evidência e fecham com uma seção de limites
("não é a suíte inteira", "não prova sessão humana contínua", etc.) em vez de alegar mais
do que foi comprovado. Vale manter esse padrão em qualquer relatório futuro.

## Histórico registrado (`docs/history/`)

Relatórios de sessão datados de 2026-09-08 (trabalho paralelo entre Claude Code e
Antigravity), um resumo por arquivo:

- **CONTINUOUS_WORLD_REVIEW** — revisão pós-integração Harbor+Mountain: mundo contínuo, curvas da ponte/serra, dano por deformação, spawn de polícia em pista válida.
- **HARBOR_CRASH_PERFORMANCE** — correção de crash na ponte (`HarborEmergencyDirector._owns_unit` acessando instância destruída) a partir de logs reais.
- **HARBOR_STORAGE_INTEGRATION** — integração do depósito do Harbor Art Pack no pátio da Autoridade Portuária.
- **LOADOUT_PREVIEW_AND_FIXES** — prévia HTML de loadout, correções de colisão na ponte e instanciação faseada de veículos da montanha.
- **MINIMAP_PAYNSPRAY** — minimapa vetorial e serviço Pay 'n' Spray na oficina Northgate ($100).
- **MONALIZA_INTEGRATION** — integração do carro pessoal Monaliza (porta-malas, recuperação/reparo por $250, persistência).
- **MOUNTAIN_PASS_HARBOR_INTEGRATION** — segunda ponte Harbor↔Serra, persistência de rota, colisão de água.
- **MOUNTAIN_PLANE_SHOP** — avião cargueiro explorável e Ammu-Nation 3D na montanha.
- **POLICE_PURSUIT_FIXES** — spawn/perseguição/sirene da polícia em pista válida, comportamento em interiores.
- **REVISAO_ESTABILIDADE** — estabilidade física de veículos, otimização de malhas, faróis do trânsito.
- **SAVE_COORDINATE_RECOVERY** — recuperação de coordenadas de save corrompidas/legadas, incl. posição inválida da Monaliza.
- **TUTORIAL_INTEGRATION** — integração real dos microtutoriais ao HarborGame.
- **VEHICLE_DAMAGE_CAMERA** — deformação de malha 3D/riscos 2D substituindo placas/fragmentos; correção de transição de câmera entre veículos.
- **VEHICLE_FEEDBACK_FIXES** — entrada/saída instável de veículo, ordem de desenho de viaturas, coleta de dinheiro.
- `PROMPT_*` (Claude/Antigravity) — os próprios prompts de tarefa dados aos agentes naquela rodada, lado a lado com os relatórios de entrega.

Dentro de `world/harbor/` há uma segunda camada de documentos de auditoria/validação
datados de 2026-09-06 (`HARBOR_PLAYABILITY_AUDIT`, `HARBOR_IMPLEMENTATION`,
`HARBOR_FINAL_TEST_RESULTS`, `HARBOR_EXTERNAL_INTEGRATION_REVIEW`,
`HARBOR_CORNERS_WEATHER`, `COUPE_HANDLING_VALIDATION`, `COURTYARD_FLOW_VALIDATION`,
`PERFORMANCE_VALIDATION`, `SMOOTHNESS_VALIDATION`, `WORLD_GEODATA`,
`TERMINAL_VALIDATION`, `RCM_INTRO_AUDIO`) que documentam o fechamento do primeiro bairro
jogável — ver [Pendências conhecidas](#pendências-conhecidas-e-itens-que-precisam-de-revisão)
para os pontos que essas auditorias deixaram em aberto.

## Ferramentas de manutenção (`tools/`)

| script | função |
|---|---|
| `check_references.py` | Varre todo `preload`/`load` de `res://` e confere existência; mantém lista `KNOWN_BROKEN`. |
| `move_folder_refactor.py` | Move arquivos/pastas e reescreve automaticamente as referências `res://`. |
| `build_living_city_audio.py` | Prepara gravações CC0 de ambiente urbano/rádio, com cache e manifesto de procedência. |
| `build_meshy_outfit_mask.py` | Gera máscara de regiões de roupa (UV) do modelo Meshy do Dante. |
| `build_regional_audio.py` | Prepara áudio CC0 de vento/metal para ambientação regional. |
| `build_vehicle_crash_audio.py` | Edita gravações CC0 de batida em one-shots. |
| `build_water_audio.py` | Gera loop original de correnteza/água. |
| `check_living_city_audio.py` | Valida áudios decodificados e exporta prévia. |
| `expand_radio.py` / `expand_soundscape.py` | Baixa/normaliza músicas e camadas de ambiente para a rádio da cidade. |
| `render_rail_route_map.py` | Desenha o trajeto ferroviário exportado por um teste. |
| `world_photo.gd` | Tira uma "foto" panorâmica do mapa inteiro em produção. |

## Convenções de processo multi-agente

Resumo do [CLAUDE.md](../CLAUDE.md) (regras completas lá, não duplicadas aqui):

- Mais de um agente (Claude, Antigravity) e o desenvolvedor no editor trabalham no mesmo
  repositório ao mesmo tempo. `prototypes/gameplay_repair_art_0909/` é território
  exclusivo do Antigravity.
- Mover/renomear exige `git mv` + atualizar toda referência + `check_references.py` +
  **reimportar no Godot** (`--import`) — o cache de `class_name` fica obsoleto e quebra
  resolução de classe mesmo com strings corretas.
- Cada agente commita o próprio trabalho antes de encerrar a sessão; trabalho não
  commitado já causou perda real (ver `docs/recuperacao-e-pendencias-codex-0914.md`,
  referenciado no commit `9e17b23` mais recente — recuperação de trabalho perdido por
  `git checkout` indevido de outra ferramenta sobre arquivos não commitados).
- Nunca `git reset --hard`, `push --force`, `checkout .` ou `clean -f` sem pedido
  explícito; ninguém dá push sem o usuário pedir.

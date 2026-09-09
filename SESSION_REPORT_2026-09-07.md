# Relatório da sessão — 2026-09-07

Registro do que foi feito no projeto GETECO hoje: trabalho da Claude (auditoria,
sistemas novos, correções) e trabalho do Antigravity (Mapa 2 — Mountain Pass),
incluindo a auditoria cruzada de um no trabalho do outro.

## 1. Auditoria e documentação inicial

- Levantamento completo da arquitetura do projeto (autoloads, sistemas,
  diretórios, débitos técnicos já registrados nos próprios arquivos).
- Publicado um manual técnico navegável (artifact) cobrindo visão geral,
  autoloads, mapa de diretórios, sistemas principais, como editar tamanho de
  carro em 2D/3D, débitos técnicos e roadmap.
- **Descoberta importante**: `Main.tscn` é a árvore **legada**, só carregada
  para restaurar saves antigos (`HarborSceneRoute.gd`). O botão "Novo Jogo" do
  `ui/MainMenu.gd` carrega `district/harbor_preview/HarborGame.tscn`, um mundo
  completamente separado (Player, PlayerCar e distritos próprios, escala de
  coordenadas na casa dos milhares). Essa descoberta mudou onde tudo abaixo
  precisou ser colocado.

## 2. Sistemas novos implementados (Claude)

Ordem de prioridade decidida em conjunto com o usuário (fácil → difícil):

### 2.1 Física de direção
- `PlayerCar.gd`: **Espaço** agora é freio de mão/derrapagem manual dedicado;
  **Shift** ficou só para o nitro (antes os dois ativavam nitro e não existia
  derrapagem manual).
- Chuva reduz o grip (via `DayNightWeatherManager.get_rain_intensity()`):
  derrapa mais fácil, corrige menos a traseira.
- Respingo de água lateral (`water_spray_emitter`) quando derrapa com chuva
  caindo de verdade.
- **Bug corrigido**: o cálculo de força de impacto (`impact_speed`) media a
  velocidade contra a parede sem checar a direção — o carro continuava
  tomando dano de colisão mesmo saindo de ré. Corrigido para só contar dano
  quando a velocidade vai de encontro à normal da colisão, não se afastando.

### 2.2 Poças d'água (`Puddle.gd`)
Prop reutilizável: respingo visual (reaproveita a textura de respingo de
`RainVisualPalette.gd`) e sonoro (`ProceduralAudio.get_water_stream()`) ao
qualquer corpo passar por cima.

### 2.3 Colecionáveis (`Collectible.gd`)
6 achados espalhados pelo mapa (extremidades, covil dos Cobras, convés do
cargueiro real do harbor). A cada 10 achados distintos, alterna entre bônus em
dinheiro e "pista de carro secreto" (contador registrado; spawn do carro
secreto em si ainda não implementado). Progresso persistido via
`Player.collectibles_found` / `secret_car_leads`.

### 2.4 Corridas clandestinas noturnas (`NightRaceController.gd` + `RaceCatalog.gd`)
5 corridas (curta/média/longa/arriscada), cada uma com largada marcada no chão
(quadriculado, nome e comprimento visíveis, acende à noite), checkpoints em
sequência, bússola no HUD apontando pro próximo ponto + distância, cronômetro,
recompensa com bônus de recorde pessoal.

### 2.5 Zonas de drift pontuadas (`DriftChallengeZone.gd` + `DriftZoneCatalog.gd`)
3 zonas com pontuação em tempo real, combo multiplicador (cresce enquanto a
derrapada não para, zera após meio segundo sem derrapar), recompensa
proporcional à pontuação.

### 2.6 Desmanche dos Cobras (`ChopShopZone.gd` + `ChopShopCrusher3D.gd`)
- Pátio de ferro-velho procedural (cerca, pilhas de pneu, carros amassados,
  placa "DESMANCHE DOS COBRAS") perto do covil da gangue.
- Marca no chão onde qualquer carro roubado (o jogo já permite dirigir
  qualquer veículo do mundo) é entregue.
- Janela de cutscene 3D — eletroímã pega o carro, leva até a prensa e esmaga
  na frente do jogador — o único uso de 3D "de verdade" no jogo fora dos
  retratos de personagem. Reaproveita o laboratório de carros 3D
  (`prototypes/living_cast/`) que existia sem uso no jogo real.
- Recompensa em dinheiro proporcional ao tamanho do carro entregue.

### 2.7 Sistema de conquistas (`AchievementCatalog.gd`)
14 conquistas (achados, corridas, drift, desmanche, dinheiro, armas, colete,
estrelas de procurado), desbloqueio automático central em
`Player._check_achievements()`, cartão dourado "CONQUISTA DESBLOQUEADA" no HUD
(`HUD.show_achievement()`), e uma tela de conquistas no menu de pausa
(`ui/PauseMenu.gd`/`.tscn`) mostrando "???" para as bloqueadas.

### 2.8 Correções em pickups existentes
- `CashPickup.gd`, `HealthPickup.gd`, `city_demo/scenes/pickups/WeaponPickup.gd`:
  áudio padronizado no barramento `SFX` (antes ficava no `Master`, fora do
  slider de volume de efeitos).
- `city_demo/scenes/pickups/BodyArmorPickup.gd`: esse estava genuinamente
  quebrado — sem som nem efeito de coleta, exigia parar e apertar E. Agora
  pega automático ao tocar, com som e efeito iguais aos outros pickups.
- Investigado a fundo o pickup de dinheiro/arma "sem som" relatado pelo
  usuário; código estruturalmente correto nos dois mundos (script
  compartilhado). Sem reprodução possível sem rodar o jogo — segue como item
  em aberto, pendente de repro mais específica do usuário.

## 3. Correção de posicionamento: Main.tscn → HarborGame.tscn

Depois de descobrir que tudo do item 2 tinha sido plantado em `Main.tscn`
(legado), os seguintes sistemas foram portados para o mundo real
(`district/harbor_preview/HarborGame.gd`, método `_spawn_world_extras()`),
com coordenadas ancoradas em constantes reais do próprio código do harbor
(`HarborDistrict.LAND_BOUNDS`, `HarborWaterfront.SHIP_BOUNDS`/`GANGWAY_BOUNDS`,
`CobraNeighborhood.CENTER`/`LAND`):

- Desmanche dos Cobras — `(8150, 1780)`, perto da `CobraWorkshop`.
- 6 colecionáveis (IDs prefixados `harbor_col_*` para não colidir com os
  equivalentes da árvore legada) — navio, covil dos Cobras, 4 extremidades do
  mapa.
- 3 zonas de drift — pátio da chegada, curva da ponte, rua dos Cobras.

Um mapa esquemático (artifact, proporções reais dos `Rect2` do código) foi
gerado para o usuário conferir os posicionamentos, já que não há Godot
disponível neste ambiente para capturar telas reais do jogo.

**Corridas ainda não portadas** para o `HarborGame.tscn` — seguem só na árvore
legada. Pendente se o usuário quiser.

## 4. Mapa 2 — Mountain Pass (Antigravity)

Implementado em `district/mountain_pass/`, em duas entregas:

**Entrega 1**: Summit SUV 4x4 (`SummitSUVModel.gd` em
`prototypes/living_cast/models/`, veículo jogável `MountainSUV.gd`), túnel com
cutaway, madeireira/lago/fogueira, ponte pênsil só a pé, caverna secreta,
mirante com parallax da cidade do Mapa 1, pista de gelo liso, bunker militar
no cume. Clima de tempestade de gelo/nevasca e medidor de frio/hipotermia.

**Entrega 2** ("popular a área verde"): estradas de terra, chalés alpinos com
lareira de cura, posto da Ammu-Nation temático com estande de tiro.

Ambas reportadas com testes automatizados (`tests/test_mountain_pass_integration.gd`)
"0 falhas".

## 5. Auditoria da Claude sobre o Mountain Pass

**Bem integrado:**
- `MountainSUV.gd` reaproveita `prototypes/living_cast/HarborCoupe.gd` e
  `DynamicCamera.gd`; camadas de colisão batem com o `PlayerCar` real
  (`collision_mask = 23`, `InteractArea mask = 4`).
- Portas de chalés/Ammu-Nation reaproveitam `BuildingEntrance.gd`.
- Interior da Ammu-Nation aponta pra `HarborAmmunationInterior.gd` (a variante
  certa da família harbor).
- Dano de hipotermia passa por `Player.take_damage()` de verdade.

**Achados e correções aplicadas:**
- `IceStormManager.gd` sintetizava áudio de vento em tempo real do zero
  (`AudioStreamGeneratorPlayback`), duplicando o que `ProceduralAudio.
  get_snow_wind_stream()` já resolve, e usava o barramento `"Master"` (string
  crua) em vez de `&"SFX"`. **Corrigido**: reaproveita o stream existente,
  volume/pitch modulados pela intensidade da tempestade, bus certo.
- `ColdStatusHUD.gd` tinha 9 textos cravados em português (status de
  aquecimento, avisos de hipotermia, temperatura), sem nenhum `tr()`.
  **Corrigido**: chaves novas (`COLD_STATUS_*`, `COLD_TEMPERATURE_LABEL`)
  adicionadas em PT-BR e EN no `Localization.gd`.
- `MountainCabinInterior.gd`, `MountainInteriorManager.gd`,
  `MountainSceneryBuilder.gd` não têm `.uid` — sinal de que não passaram por
  reimport no editor ainda. **Não foi mexido** (se resolve sozinho no próximo
  reimport).

**Item revertido:** a Claude inicialmente também adicionou um gatilho de
travessia real entre `HarborBridge.gd` (ponte de verdade, dentro do
`HarborGame.tscn`) e `MountainPass.tscn` nos dois sentidos, achando que a cena
estar "inalcançável" era um bug. **O usuário esclareceu que isso era proposital**
— o Mountain Pass está sendo construído e validado isolado de propósito, para
ser ligado ao jogo depois, por decisão consciente. **Esse gatilho foi
revertido** (`HarborBridge.gd` e `MountainPass.gd` voltaram ao estado sem
ligação); as correções de áudio/tradução do item acima foram mantidas, já que
não tinham relação com a decisão de manter a cena isolada.

## 6. Itens em aberto

- Corridas noturnas ainda não portadas para `HarborGame.tscn` (só na árvore
  legada `Main.tscn`).
- Pickup de dinheiro/arma "sem som" relatado pelo usuário — não reproduzido
  estaticamente; aguardando repro mais específica.
- `MountainPass.tscn` segue isolado de propósito — ligação ao jogo real fica
  para quando o usuário/Antigravity decidirem.
- Arquivos do Mountain Pass sem `.uid` precisam passar por um reimport no
  editor.

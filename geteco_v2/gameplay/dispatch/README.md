# Despacho físico de viaturas e veículos de emergência

Controlador independente: `DispatchController.gd`. Não substitui o sistema de
procurado de `Gameplay.gd` nem o atendimento do `EmergencyManager`: **lê** as
estrelas, a última posição conhecida e o registro de ocorrências que eles já
mantêm, e coloca veículos reais (`scripts/Vehicle.gd`, modelos do
`FleetCatalog`), dirigidos pelas ruas do `NativeTrafficRoutes`, para responder.

> **Estado de verificação (21/09/2026): funcionalmente executado.** As suítes
> dirigidas de regras, polícia, emergência e ciclo de vida, a regressão de
> gameplay e uma perseguição integrada em `Main.tscn` passaram. A medição
> comparativa de FPS continua pendente porque havia outras sessões do Godot
> ativas; portanto, desempenho não está aprovado.

## Arquivos

| Arquivo | Papel |
|---|---|
| `DispatchRules.gd` | Constantes e regras da V1 (px → m, ÷16), sem estado |
| `DispatchRoadRouter.gd` | Dijkstra sobre o grafo dirigido de `NativeTrafficRoutes`; bloqueio temporário de arestas; candidatos de nascimento; rota de saída |
| `DispatchVehicle.gd` | `Vehicle` original com atribuição de dano ao jogador desativada; física compartilhada e controle externo explícito |
| `DispatchDriver.gd` | Piloto: conduz o `Vehicle` pelas entradas externas (`throttle/steer/brake`), sensor frontal/traseiro, ré e pedidos de novo plano |
| `DispatchUnit.gd` | Máquina de estados de uma viatura + equipe |
| `DispatchOfficer.gd` | `PoliceAgent` original com modo "voltar e embarcar" |
| `DispatchIncidentBridge.gd` | Adaptador entre o `Responder` original e o `EmergencyManager` real |
| `DispatchController.gd` | Laço, limites, despacho, eventos, API pública |

Nenhum asset novo: os veículos são `police_cruiser`, `medic_box`,
`rescue_pumper` e `station_wagon` (legista) do catálogo original; as equipes
são `PoliceAgent` e `Responder` existentes. `assets/dispatch/` não foi usado.

## Integração (o que o integrador precisa chamar)

Em `ProductionWorld.gd`, **depois** de `world.gameplay` estar na árvore:

```gdscript
world.dispatch = preload("res://gameplay/dispatch/DispatchController.gd").new()
world.dispatch.configure(world, world.gameplay, traffic_routes)
world.add_child(world.dispatch)
```

| Momento | Chamada |
|---|---|
| Troca de região (`travel`), antes de liberar a região | `world.dispatch.dismiss_all("travel")` |
| Depois de `traffic_routes.configure(region.roads)` | `world.dispatch.refresh_roads()` |
| Carregar save / reiniciar sessão | `world.dispatch.dismiss_all("load")` (nada é persistido) |
| Entrar/sair de interior | `dispatch.player_position_override = porta_exterior` ao entrar; `Vector3.INF` ao sair (sem isso, a posição do interior, longe do mapa, suspende e recicla tudo) |
| "Leavemealone" / cheat | `gameplay.clear_wanted()` já basta: as equipes voltam a pé e partem. Para sumir na hora: `dismiss_all("cheat")` |
| Garagens/pátios reais (opcional) | `dispatch.set_depots("police"|"medic"|"fire"|"mortician", [Vector3, ...])` (pontos sobre uma rua); sem isso o nascimento é em faixa fora da vista, a 32,5–112,5 m |
| Desligar o módulo | `dispatch.set_enabled(false)` (recolhe tudo e devolve o despacho embutido) |

### Integração explícita implementada e validada funcionalmente

Por autorização do usuário, a integração modifica agora os contratos centrais.
Os testes que esperavam temporizadores `1e9` foram atualizados para o contrato
de ownership explícito. A integração funcional foi executada; o benchmark
renderizado antes/depois ainda não foi executado.

`configure()` chama `claim_dispatch()`, que ativa `Gameplay.dispatch_owned` e
`EmergencyManager.dispatch_owned`, inclusive com `enabled=false` durante o
carregamento. Os portões bloqueiam apenas novos despachos legados; limpeza de
ocorrências e atualização da procura continuam. Nenhum contador ou temporizador
é adulterado. Equipes legadas já existentes entram na contagem de limites a pé
e de emergência enquanto terminam sua atuação.

`set_enabled(true)` reivindica o despacho. `set_enabled(false)` recolhe unidades
e devolve os portões ao legado; `set_enabled(false, false)` mantém os portões
fechados em uma suspensão temporária. O integrador pode suspender o processamento
durante startup sem liberar ownership. Destruir o controlador recolhe unidades
e destroços e libera os portões.

Ao trocar região: `dismiss_all("travel")`, `gameplay.on_region_changed()` e
`gameplay.emergency.reset_region()` antes de liberar o mapa; depois atualizar
ruas e chamar `refresh_roads()`. Crime e estrelas persistem, mas observadores,
última posição e cache de navegação são invalidados. Incidentes e incêndios
transitórios são removidos sem apagar suas entidades fonte. Portões permanecem
adquiridos. Admissão de carros prepara também colisões térmicas da região.

Em interiores, `player_position_override` representa apenas a porta exterior:
viaturas navegam para essa porta, não veem o jogador através de outro ambiente,
e a polícia a pé também não ganha linha de visão entre mapas.

### Eventos (`signal dispatch_event(event_name, data)` e `controller.events`)

`dispatched`, `spawn_failed`, `unit_state` (`enroute → parked → working →
[recall] → departing`), `unit_finished` (`reason`: `left`, `vehicle_lost`,
`suspended_too_long`, `departure_timeout`, `recovery_stranded`, `wrecked`, ou o
motivo de `dismiss_all`), `unit_suspended`, `unit_resumed`, `unit_wrecked`,
`officer_boarded`, `crew_boarded`, `crew_lost`, `incident_invalid`,
`response_timeout`, `incident_abandoned`, `no_road_access`, `no_exit`,
`no_route`, `replanned`, `route_blocked`, `departure_blocked`, `crew_depleted`,
`patient_died`.

Recuperação de ultrapassagem (detalhes em `overtaking/README.md`):
`overtake_state` (entra em `holding_oncoming`/`recovering`/`returning`),
`overtake_unresolved`, `park_deferred`, `park_recovery_stalled`,
`assignment_released` (a unidade encerrou o atendimento porque a recuperação não
progride; o veículo segue recuperando; `cause` = `recovery_stalled` para um
episódio longo ou `recovery_cumulative` para o orçamento somado; traz
`recovery_total` e `episode_age`) e `recovery_stranded` (unidade removida
fora da vista depois de partir com a recuperação pendente). `controller.status()`
ganhou `stranded` e `released_slots`.

`data.unit` é o `DispatchUnit`; `controller.events` guarda os últimos 64 como
dicionários de texto (úteis em teste e em HUD). `controller.status()` devolve
contagens por serviço, policiais a pé, destroços e unidades suspensas.

## Comportamento

### Concluído e validado funcionalmente

- **Polícia**: com estrelas > 0, despacha por `INITIAL_DELAY`/`INTERVAL`,
  `MAX_ACTIVE` e `DEPLOYMENT` (`WantedManager`). Nasce em faixa, fora do
  frustum, entre 520 e 1800 px (32,5–112,5 m), com o pé livre e rota até o
  crime. Dirige pelo grafo de ruas; formação por `serial % 5`
  (perseguidor, flancos, interceptor, contenção); só para quando o alvo está
  parado há 1,5 s (ou a pé / sem contato) dentro do raio de parada
  (`140 + 36·(serial%3)` px). Reporta contato (`gameplay.report_contact`) a
  650 px, então perseguir mantém a procura viva. A partir de 2 estrelas atira
  no carro do jogador com a regra de `PoliceVehicleCombat` (18,75 m, 0,9 s de
  mira, rajadas de 2, dano 5) por `gameplay.police_shoot`, que respeita
  `weapons_allowed()`.
- **Desembarque seguro**: só com a viatura parada; saída com chão sólido,
  cápsula livre e sem parede entre porta e ponto; no máximo 2 policiais por
  viatura e 5 a pé no total (mesmo teto de `Gameplay`). Sem saída livre, a
  viatura espera 8 s e volta à perseguição.
- **Emergência**: reaproveita o registro do `EmergencyManager` (24 incidentes,
  raio 68,75 m, 10 s entre despachos, 3 equipes, papel `medic`/`mortician`/
  `fire`). A viatura original chega dirigindo, para, desembarca o `Responder`
  original pelo lado direito e só ele conclui o atendimento
  (`complete`/`extinguish`, exigindo proximidade e linha de visão). Nenhum
  cronômetro deste módulo conclui ocorrência.
- **Embarque e partida**: a equipe volta a pé; a viatura só parte depois do
  embarque (`crew_boarded`/`officer_boarded`) e sai dirigindo até ficar fora
  da vista e a mais de 62,5 m.
- **Cancelamento e liberação**: procura zerada → recall; ocorrência que some
  ou vira inválida → a viatura desiste e parte; `cancel_incident(key)`;
  equipe abatida solta a ocorrência; prazo de 120 s para chegar e 300 s
  totais; viatura destruída deixa a equipe terminar e vira destroço (máx. 4,
  removido só fora da vista). Ocorrências sem dono voltam ao gerente real, que
  aplica o prazo dele.
- **Ultrapassagem de carro que cedeu e recuperação** (`overtaking/`; escrita, não
  executada): a viatura desvia, passa e volta à faixa só por curvas cujo casco foi
  varrido. Enquanto há manobra pendente ou caso sem solução, `driver.settled()` é
  falso: a unidade não estaciona nem desembarca (fica em `enroute` segurando o
  freio; `park_deferred`). Há duas coisas distintas, de propósito:
  - **recuperação física** (piloto): o veículo só volta ao eixo por curva
    aprovada; sem curva, fica parado e marca `unresolved`. Motor bloqueado, carro
    contrário parado, retorno bloqueado e rota nula fora do eixo **não** têm saída
    física implementada (ver `overtaking/README.md`, "sem solução");
  - **encerramento do atendimento** (unidade): com o episódio de recuperação
    passando de 60 s (ou 25 s já `unresolved`), **ou** o orçamento cumulativo do
    atendimento (`unit.recovery_total`, 90 s somando todos os episódios) esgotado
    com recuperação em curso, `_end_assignment_for_recovery` solta a ocorrência,
    apaga a sirene e parte (`assignment_released`), sem desembarcar, teleportar nem
    remover o veículo. O acumulador só conta recuperação física (não passagem
    normal, espera, perseguição ou estacionada), pausa fora dela e com a unidade
    suspensa, e não zera por troca de rota, estado ou episódio. Vale para polícia
    (que não tem prazo de resposta) e serviços. Partindo com recuperação física por 45 s
    **e** fora da vista **e** a mais de 25 m do jogador, a unidade é removida
    (`recovery_stranded`); visível ou perto, o veículo continua onde está até o
    `departure_timeout`, a suspensão longa ou `dismiss_all`.
  - Esperas sem solução informam o motivo e a condição para sair
    (`overtake.exit_condition()`, campo `needs` nos eventos de recuperação);
    nenhuma é resolvida por teleporte, retorno forçado ou desembarque.
  - `finish` desconecta os sinais unidade ↔ piloto ↔ ultrapassagem e zera
    `driver.overtake` (antes ficava um ciclo de referências). Testes de
    `tests/dispatch/` (`parked`, `cancel_api`, `dismiss_and_wrecks`, limite de 64
    eventos) precisarão de adaptação; ver `overtaking/README.md`, "Revisão estática".
  - Cancelamento (`cancel_incident`, fim da procura, partida) = recuperação
    física, que **não** reinicia uma recuperação já em curso. Troca de região,
    `dismiss_all`, `finish` e veículo destruído = remoção imediata, sem recuperar.
- **Limites**: 8 veículos vivos no total, 3 equipes de emergência, viaturas
  ativas por `MAX_ACTIVE`, 5 policiais a pé; replanejamento de perseguição a
  cada 1–1,5 s por viatura e só se o alvo andou > 3 m.
- **Suspensão distante**: além de 130 m do jogador a viatura, a equipe e a
  colisão são congeladas e escondidas; voltam a menos de 115 m se o local
  estiver livre; após 45 s suspensa a unidade é liberada.
- **Caminho bloqueado**: sensor frontal a 10 Hz; espera 3 s por trânsito que
  anda; parado por obstáculo fixo → ré real (com sensor traseiro) → novo plano
  com a aresta bloqueada por 20 s de tempo simulado (o plano nasce na faixa
  oposta, ou seja, exige retorno físico) → após 4 tentativas sem progresso
  desiste: estaciona se estiver perto o bastante para a equipe seguir a pé;
  senão parte. Ocorrência sem rua a ≤ 22,5 m (360 px) não recebe viatura.
- **Composição da equipe**: cada viatura leva 2 policiais. Quem desce e morre
  não é reposto: sem ninguém a bordo a viatura parte (`crew_depleted`) e a
  reposição só nasce como viatura nova, gastando `DEPLOYMENT`. O tiro a partir
  da viatura exige os dois a bordo.
- **Paciente que morre durante o atendimento**: o paramédico é reencaminhado
  (`patient_died`), a ocorrência vira `mortician` e é liberada para a viatura do
  legista. A ponte recusa `EmergencyManager.complete()` quando o papel da
  equipe já não é o da ocorrência, para o paramédico nem reviver nem remover o
  corpo.
- **Suspensão de pessoas**: policiais e socorristas a pé perdem camada, máscara,
  física e vista junto com a viatura; a retomada só ocorre com o casco **e**
  a cápsula de cada pessoa livres.
- **Recolhimento**: `dismiss_all` recolhe viaturas, equipes e destroços; sair
  da árvore faz o mesmo (os carros são filhos de `world`).
- **Atribuição explícita de atropelamentos**: `Actor.receive_damage` consulta
  `Vehicle.is_player_damage_source()`. A resposta exige condução manual e
  `player_damage_attribution=true`; a viatura define essa flag como falsa.
  `set_external_driver(true)` mantém controle automático e ocupação consistentes
  durante todo o quadro. `DispatchVehicle` não duplica mais a cinemática:
  usa os mesmos freios, colisões, sirene e bloqueio `engine_disabled` do carro.
- **Sem teletransporte**: depois do nascimento a viatura só se move por
  `move_and_slide`. `Vehicle.place` é usado uma vez, na criação.
- **Regras permanentes**: nada aqui toca Maciota, mecânico ou a garagem. O
  dano ao jogador passa por `damage_player`/`police_shoot`, que retornam sem
  efeito com `weapons_allowed() == false` (garagem sem armas). As viaturas
  saem do grupo `drivable` para que `Driving.can_enter` não as ofereça.

### Lacunas (não implementado; não declarar como feito)

- Motocicletas e helicóptero da polícia; viatura tática só muda velocidade e
  vida na regra, não a pintura; barreiras/espeta-pneus (`SpikeStrip`),
  bloqueio de banco, `PoliceVehicleStop` (ordem de sair do carro com 1 estrela).
- Roubo de viatura (`report_police_car_theft`) e estrela adicional por ele.
- Transporte do paciente ao hospital, carro funerário específico do legista,
  agrupamento de ocorrências por lote (cada ocorrência tem sua viatura; V1
  agrupava até 8/3 alvos), persistência de incidentes entre regiões/saves.
- Rádio de despacho e áudio novo: só a sirene já existente do
  `VehicleEquipment` (policial e emergência com barra de luzes). O legista não
  tem sirene.
- Viatura presa na faixa contrária por recuperação sem saída (carro contrário
  parado ao lado dos bloqueadores, retorno bloqueado, motor bloqueado) continua
  visível e parada depois de encerrar o atendimento; só sai por recuperação
  posterior, remoção fora da vista, suspensão longa ou `dismiss_all`. Sem ré
  controlada para esses casos. Unidades presas em `departing` **sempre** contam em
  `MAX_UNITS` (8). Só a vaga de `MAX_ACTIVE`/`MAX_CREWS` de até 2 delas (as mais
  antigas, presas há ≥ 20 s) é liberada; polícia presa além disso volta a contar em
  `MAX_ACTIVE`. Com muitas presas à vista, novos despachos podem ficar bloqueados
  por `MAX_UNITS`. Os prazos e limites novos (90 s, 20 s, 2) **não são
  calibrados por benchmark**; os cenários funcionais foram executados. Polícia
  com muita recuperação somada em perseguição longa é encerrada (e gasta
  `DEPLOYMENT`).
- Trânsito ambiente **não cede** à sirene; a viatura depende de esperar,
  recuar e replanejar. Sem estacionamento de acostamento: estaciona na faixa e
  bloqueia essa pista enquanto a equipe trabalha.
- Retorno em pista estreita depende de `can_rotate` do `Vehicle`; sem
  manobra de "três pontos" além de ré + novo plano.
- Depósitos/garagens de emergência reais da V1 (`EmergencyDepotDirector`) não
  existem na V2: usar `set_depots` quando houver pontos.
- Expiração do bloqueio de aresta usa o relógio simulado do controlador.
- Edge cases sem teste: ruas de ponte com desnível (o ponto de nascimento
  usa a altura da rota + 0,12 m), modelos de ruas sobrepostas, região
  `mountain`.
- **Desempenho não medido.** Custos novos a medir: até 8 corpos `Vehicle`
  (cada um com 2 `SpotLight3D` sem sombra e 2 emissores se tiver sirene),
  5 `PoliceAgent` com A* de 256 expansões a cada 1,2 s (já existente), até 3
  `Responder`, `get_closest_offset` por quadro por viatura, buscas de rota
  (varredura de todas as arestas + Dijkstra) a cada replanejamento e ao
  despachar, primeira instância de cada modelo `.scn`.

## Testes e comandos

```powershell
.\tests\dispatch\Run.ps1 -Suite import      # 1) reconstrói caches (scripts novos)
.\tests\dispatch\Run.ps1 -Suite all         # 2) regras e suítes dirigidas
.\tests\dispatch\Run.ps1 -Suite integration # 3) ciclo real em Main.tscn, sem save
.\tests\dispatch\Run.ps1 -Suite rules       #    (ou uma suíte por vez)
python tools/check_references.py              # 4) 0 quebras novas
```

O runner **não confia no código de saída**. Um erro de script aborta uma
função no meio e o teste seguiria adiante, então cada suíte só passa se:
não houver `SCRIPT ERROR`/`Parse Error`/`Cannot infer`/etc. na saída; todos os
grupos do manifesto imprimirem `GROUP_OK`; e a linha final
`DISPATCH_X groups=n/n checks=N failures=0` existir com `n` completo e `N`
acima do mínimo. Saída completa em `tests/dispatch/results/*.log`.

As suítes dirigidas cobrem física real (`CharacterBody3D`, piso e parede
sólidos) em cena de laboratório. A suíte `integration` cobre o ciclo completo
na `Main.tscn`, com mundo e controlador de produção, mas não substitui a
calibração em todos os mapas. Regressão do combate/emergência original continua
em `tests/test_gameplay.gd` e `tests/test_full_session.gd`.

Desempenho (só em janela renderizada, Vulkan, nunca `--headless`; feche outros
jogos):

```powershell
.	ests\dispatch\Run.ps1 -Suite measure -Stars 4    # baseline e dispatch, mesmo cenário
.	ests\dispatch\Run.ps1 -Suite measure -Stars 6
```

O cenário é fixo e `measure_dispatch.gd` recusa rodar sem `--no-save
--skip-arrival --population=24 --seed=N` (sem save pessoal, sem cinemática de
chegada, população e semente iguais). Grava `tests/dispatch/results/<label>.json`
(p50/p95/p99/máx em **ms**, quadros > 33,3 ms). Só depois de comparar
antes/depois na cena integrada e nos cenários afetados (perseguição em carro,
ambulância com a câmera olhando) se pode falar em desempenho.

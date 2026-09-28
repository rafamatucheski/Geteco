# Ultrapassagem de carros que cederam passagem

Fecha a interação entre `gameplay/traffic_yield/` (o carro ambiente encosta e
para: `Vehicle.get_meta("traffic_yield_state")` = `held` | `pulling`) e o
`DispatchDriver`: a viatura desvia **à esquerda**, passa e volta à faixa.

> **Validação parcial em 28/09/2026:** `tests/dispatch/test_fire_traffic.gd`
> passou 25 verificações headless com o caminhão e a física reais: fila de dois
> carros, recuperação com ré, chegada ao destino sem dano, contramão ocupada,
> sensor traseiro, sirene e exclusão do carro controlado pelo jogador.
> Performance e revisão visual na cena real continuam pendentes: havia duas
> instâncias do Godot abertas, impedindo um comparativo isolado antes/depois.
> Esses testes não certificam os demais estados do módulo nem passagem universal
> em ruas estreitas, cruzamentos ou curvas.

O bombeiro com sirene reconhece também carros ambiente parados no mesmo sentido,
mesmo antes de cederem passagem. Antecipa o planejamento pelo espaço da rampa e
freia enquanto aguarda uma manobra válida. Se já estiver perto demais, permite
uma ré de até 3 segundos, com sensor traseiro contínuo e as tentativas limitadas
do piloto. Todo desvio continua dependendo da varredura de casco e pista livre.

Teste dirigido: `godot --headless --path . --script res://tests/dispatch/test_fire_traffic.gd -- --no-save`.

## Divisão de responsabilidades

| Peça | Faz | Não faz |
|---|---|---|
| `Vehicle` / `DispatchVehicle` | **Única** execução da física, freio, `engine_disabled`, colisão e dano (`is_player_damage_source`, `player_damage_attribution`) | — |
| `DispatchDriver` | Segue a rota principal **ou** a curva de desvio; aplica o teto de velocidade; não recua nem replaneja enquanto espera/ultrapassa | Não duplica `_drive_player`, não mexe em `controlled` (só `set_external_driver`, como já fazia) |
| `overtaking/OvertakeController.gd` | Máquina de estados, corredor à frente, espera, aborto, retorno | Não move o veículo |
| `overtaking/OvertakePlanner.gd` | Monta e valida a `Curve3D` do desvio | — |
| `overtaking/OvertakeRules.gd` | Parâmetros e funções puras | — |
| `traffic_yield/YieldRoadModel.gd` | Geometria da pista (largura, eixo, mão única, cruzamentos) — ganhou `room_raw`, `left_raw`, `signed`, `one_way`, `refresh_if_changed()` | — |

## Como ligar (API)

```gdscript
driver.enable_overtaking(traffic_routes, true)   # (grafo, permitir faixa contrária com sirene)
driver.disable_overtaking()
driver.overtake                                   # OvertakeController (ou null)
driver.overtake.state, .last_reason, .speed_limit, .allow_oncoming
driver.overtake.state_changed                     # signal(state, reason)
```

Sem chamada explícita, o primeiro `tick` do piloto tenta descobrir o grafo em
`vehicle.get_parent().production.traffic_routes` (contrato já existente do
`ProductionWorld`). Em cena sem essa referência a ultrapassagem fica **desligada**
(é o caso dos testes de despacho atuais em laboratório).

O `DispatchController._make_unit` já chama `unit.driver.enable_overtaking(routes, true)`
e liga os sinais (ver "Eventos"), então a descoberta automática só serve a cenas sem
`DispatchController`. `TrafficYieldController.configure`, `release_all` e
`refresh_roads` **não mudaram**.

## O que é verificado antes de sair da faixa

Todas as amostras do caminho (a cada 1,5 m, da rampa de entrada até a volta ao
eixo mais 8 m de cauda) precisam passar. Uma falha = sem desvio, motivo
registrado em `last_reason`:

| Verificação | Motivo se falhar |
|---|---|
| Bloqueadores só `held`/`pulling`; qualquer outro veículo na faixa até 32 m | `non_yielding_vehicle_ahead` |
| Bloqueador ainda se acomodando (> 4,5 m/s) | `blocker_moving` |
| Deslocamento necessário (largura do bloqueador + 0,6 + meia-largura própria − posição dele) ≤ 4,5 m | `shift_too_large` |
| Rampa de entrada inteira cabe antes do primeiro bloqueador (6 m de rampa por m de desvio; 3,5 abaixo de 3 m/s; mín. 8 m) | `no_room_to_swerve` |
| Rota principal não termina no trecho | `route_ends` |
| Rota quase reta (≤ 0,12 rad por amostra) | `curve_too_tight` |
| Fora de zona de cruzamento (vértice com ≥ 3 saídas, raio = meia-largura + 3 m + meia-largura da viatura) | `junction` |
| Sobre pista do grafo | `off_pavement` |
| Casco + 0,25 m/lado e 0,4 m/ponta dentro dos dois limites da pista (nunca calçada) | `narrow_road` |
| Mão dupla: casco só cruza o eixo se `allow_oncoming` **e** sirene ligada | `oncoming_lane_forbidden` |
| Mão única: limite é a largura da própria pista (mesmo sentido, sem contramão) | `narrow_road` |
| Casco completo livre de sólidos e de outros carros em todas as amostras, inclusive a volta à faixa | `obstructed` |
| Faixa contrária livre (caixa de meia-pista, camadas 1|2|4) por todo o trecho + 40 m à frente | `oncoming_traffic` |
| Motor bloqueado (`engine_disabled`) | não inicia |

## Estados e esperas

```
idle -> waiting -> passing -> idle
passing -> holding_oncoming -> passing                (tráfego contrário: espera explícita; exige folga E desvio ainda livre)
passing -> returning -> idle                          (tráfego contrário antes/depois dos bloqueadores)
holding_oncoming -> returning -> idle                 (fora de "beside", com curva de retorno aprovada)
passing | returning -> recovering -> returning -> idle   (aborto, travamento, suspensão, ordem de parar)
```

`holding_oncoming` **não** vira `recovering`: aborto, `settle()`, `cancel` e retomada
o deixam como está (ver "Cancelamento"). Motivo: `recovering` descarta a curva de
desvio, e com o bloqueador ao lado o retorno nunca passa, mesmo com a faixa
contrária livre; em `holding_oncoming` a viatura ainda pode seguir em frente.

- **waiting**: reavalia a cada 0,25 s. O piloto **não** conta travamento (nada de ré
  nem novo plano por cima do carro parado). Volta a `idle` se os bloqueadores
  somem ou estão longe. Após **20 s** desiste (`wait_timeout`), cooldown de 20 s,
  e o piloto volta à recuperação normal (ré, novo plano).
- **passing**: segue o desvio (6 m/s; 5 m/s na faixa contrária). Ao chegar ao fim
  da curva, já no eixo, `finish_bypass()` devolve a rota principal.
- **holding_oncoming**: parada **explícita** com o desvio preservado (ver abaixo).
- **recovering**: parada (teto 0) procurando uma curva de retorno ao eixo com a
  varredura de casco aprovada; reavalia a cada 0,25 s. `last_reason` mostra
  `return_blocked:<motivo>` enquanto não houver. Um `abort` repetido com a
  recuperação já em curso **só atualiza a causa**: não reinicia `_recover_age`
  nem a curva.
- **returning**: segue a curva de retorno a 3 m/s.

## Relógios, eixo lembrado e "sem solução"

Dois relógios, para não confundir esperar com progredir:

| Relógio | Reinicia? | Serve para |
|---|---|---|
| `_hold_age` (em `holding_oncoming`), `_recover_age` (em `recovering`) | Sim, a cada nova espera/tentativa | Paciência de **uma** espera: 10 s (`OPPOSING_PATIENCE`) / 12 s (`RECOVER_PATIENCE`) → `unresolved` |
| **`episode_age`** (público) | **Não**: corre do primeiro aborto/espera fora do eixo até voltar (`finish_bypass`, `already_in_lane`, `reset`) ou até retomar a passagem (`oncoming_cleared`) | Episódio > 45 s (`EPISODE_PATIENCE`) → `unresolved` com `recovery_no_progress`; é o que a `DispatchUnit` lê para encerrar o atendimento |

Antes, aborto → tentativa → travamento → aborto zerava `_recover_age` a cada volta e
nunca declarava nada. Agora cada `returning` que trava conta (`RETURN_MAX_FAILURES`
= 3 no mesmo episódio → `unresolved` com `return_failed_repeatedly`). `unresolved`
declarado por episódio longo ou por voltas repetidas **não é apagado** por uma curva
de retorno aprovada no momento (`_clear_unresolved_on_progress`): só some quando a
viatura volta ao eixo.

**Eixo lembrado (`_axis`).** A rota principal do início da manobra fica congelada
até a volta. Lateral, fase (antes/ao lado/depois), retorno e memória dos
bloqueadores são medidos nela, não em `driver.route`. Consequências:

- **Troca de rota** durante a manobra (perseguição replanejando): `rebase_route` é
  um ponto de contrato sem efeito; nada reancora e nada aborta. A rota nova só passa
  a valer quando a viatura volta ao eixo. (Antes: rota que apontava para outro lado
  abortava, e a recuperação era medida na rota nova, o que podia declarar "já na
  faixa" só porque a rota nova nasce da posição da viatura.)
- **Rota nula** fora do eixo: `driver.set_route(null)` não para o piloto. Se havia
  curva de desvio/retorno, ele a segue; se estava em `recovering`, a recuperação
  planeja sobre o eixo lembrado e o piloto segue a curva aprovada
  (`follows_without_route()`). Sem curva aprovada fica parado. Nada é inventado.
  Em `waiting`/`idle` rota nula só descarta.

## O que a volta ao eixo tenta (e o que não tenta)

`_plan_return` só devolve curva se:

1. o rumo da viatura ainda é compatível com o do eixo (cosseno ≥ 0,35,
   `RETURN_MIN_ALIGNMENT`): sem meia-volta; senão `heading_mismatch`;
2. alguma rampa passa na varredura de casco completa: a normal, depois 1,6× e 2,4×
   (`RETURN_RAMP_SCALES`; **só mais suaves**, nunca mais curtas, porque o esterço de
   uma rampa curta não foi verificado). Cada tentativa é a varredura completa de
   sempre (sólidos, carros, pista, cruzamento, curva);
3. se o eixo acaba perto, a cauda de validação encurta até 1 m depois da rampa
   (`RETURN_MIN_TAIL`); a rampa inteira ainda precisa caber (`route_ends` se não).

Não tenta: ré, volta pela direita com bloqueador ao lado, meia-volta, salto.

## Tráfego contrário durante o desvio

Com a viatura na faixa contrária, a cada 0,25 s calcula-se a folga prevista
`oncoming_margin` = folga atual à frente − distância que ainda falta para sair da
faixa contrária (dianteira do último bloqueador + meio comprimento + 6 m) − quanto
avança quem vem de frente **no tempo que a viatura leva para sair** (`v ≥ 3 m/s`
mesmo parada). Parado ou sólido conta como fixo. Se a folga ≥ 4 m: segue. Senão,
conforme a posição em relação aos bloqueadores:

| Fase | Resposta |
|---|---|
| **before** (ainda atrás do primeiro) | `returning`: curva de retorno à faixa própria, validada (os bloqueadores não estão ao lado). Se a varredura falhar → `holding_oncoming` |
| **beside** (ao lado de algum) | Voltar é impossível (o carro ao lado está na faixa própria): `holding_oncoming` — para, mantém o desvio e reavalia. Volta a `passing` quando a folga permite |
| **after** (passou de todos) | `returning` como em *before*; se falhar → `holding_oncoming` |

Em `holding_oncoming`, a cada 0,25 s:

- folga ≥ 4 m **e** `curve_clear` (a mesma varredura de casco, agora sobre o que
  falta do desvio preservado) → volta a `passing` (`oncoming_cleared`) e encerra o
  episódio. Se a folga abriu mas o desvio está obstruído: `last_reason =
  bypass_obstructed`;
- fase diferente de *beside* e curva de retorno aprovada → `returning`;
- senão, fica parado. Passados **10 s** marca `unresolved = true`, e **continua
  esperando**. Nada é forçado. Motivo:

| `unresolved_reason` | Situação |
|---|---|
| `oncoming_stopped_ahead` | *beside*, e o corpo que define a folga está **parado ou é sólido** (`STATIONARY_SPEED` 0,3 m/s): esperar não abre a folga sozinha |
| `oncoming_deadlock` | *beside*, corpo contrário que anda: folga insuficiente, pode abrir |
| `return_blocked_by_oncoming` | *before/after*, e nenhuma rampa de retorno passou |
| `bypass_obstructed` | folga aberta, mas algo entrou no desvio preservado |
| `engine_disabled_while_displaced` | motor bloqueado |

`oncoming_stopped_ahead` é só **classificação**: o comportamento é o mesmo do
deadlock (parada explícita). Não há saída física implementada (ver "sem solução").

## Cancelamento, suspensão e rota

| Situação | Comportamento |
|---|---|
| Algo à frente e parado > 1 s durante o desvio | `abort("blocked_while_passing")` → `recovering`. A curva de desvio é **descartada** (ver limitações) |
| Desvio > 30 s (sem contar a espera pela faixa contrária) ou motor bloqueado | `abort` → `recovering`; com motor bloqueado, `unresolved = true` (`engine_disabled_while_displaced`) e nada se planeja; se o motor voltar, a recuperação retoma sozinha |
| Travamento do piloto (`_recover`) | `on_stuck()` → `abort("stuck")` (não em `holding_oncoming`); **sem ré** enquanto a manobra estiver ativa. Vindo de `returning`, conta em `_return_failures` |
| **Suspensão** (sem tick > 20 quadros) e retomada | `recover_if_displaced("resumed")`. Fora do eixo (≥ 0,3 m): `passing` **antes/depois** dos bloqueadores → `recovering`; `passing` **ao lado** deles → `holding_oncoming` (`resumed_revalidating`, revalida com `curve_clear`); **`returning` → `recovering` (replaneja, a curva pode estar obsoleta)**; `recovering` e `holding_oncoming` → nada (a espera revalida com `curve_clear`). Em `waiting` → descarta; em `idle` → nada. Perto do eixo → descarta. Nunca há salto: a curva sai da posição atual |
| **Cancelamento / partida** (`driver.cancel_overtaking(reason)`, `overtake.cancel(reason)`) | Mesmo caminho da retomada, **exceto** que `returning` **não** é interrompido (a curva vale; só atualiza a causa) e `passing` **ao lado** dos bloqueadores **segue** a passagem validada (abortar prenderia a viatura na faixa contrária). `recovering` e `holding_oncoming` não reiniciam relógio nenhum. Antes, a partida reiniciava `_recover_age` e derrubava um retorno válido |
| **Ordem de parar** (`hold(true)` do despacho ao estacionar) durante a manobra | `settle()`: `passing` antes/depois dos bloqueadores → aborta e **termina a volta à faixa antes de frear**; `passing` ao lado deles → **continua a passagem** e a unidade estaciona depois; `returning`, `recovering` e `holding_oncoming` seguem como estão; `waiting` → descarta. O piloto não freia enquanto há manobra ativa |
| Piloto troca a rota principal (perseguição replaneja ~1 s) | Nada: a referência é o eixo lembrado (ver acima). Sem `route_diverged`/`route_restored` |
| `set_route(null)` fora do eixo | O piloto segue a curva já validada, ou recupera sobre o eixo lembrado, ou fica parado. Nunca anda sem curva aprovada |
| Veículo destruído | `reset("vehicle_unavailable")` |
| Troca de região / `dismiss_all` | O `DispatchController` libera as unidades e o piloto morre com elas; o grafo é o mesmo objeto reconfigurado (`YieldRoadModel.refresh_if_changed()`) |

Retorno: `returning` só existe com curva aprovada (casco completo livre de sólido
e de carros, sobre pista, sem cruzamento). O eixo é considerado recuperado com
desvio lateral < 0,2 m.

## Contrato de parada concluída (integração com `DispatchUnit`)

Velocidade baixa **não** é parada concluída. O piloto expõe:

```gdscript
driver.is_stopped()        # só física: |speed| < 0,35
driver.pending_recovery()  # ultrapassagem ativa (passing/returning/recovering/holding_oncoming) ou unresolved
driver.settled()           # is_stopped() and not pending_recovery()   <- o que estacionar/desembarcar exige
driver.stop_status()       # "settled" | "moving" | "recovery_pending" | "recovery_unresolved"
driver.at_route_end()      # agora usa settled()
```

`DispatchUnit` passou a usar `settled()`:

| Ponto | Antes | Agora |
|---|---|---|
| `_service_enroute` (chegada) e `_police_enroute` (raio de parada) | `hold(true)`; `is_stopped()` → `parked` | `hold(true)`; só `settled()` → `parked`. Com recuperação pendente fica em `enroute` segurando o freio, registra `park_deferred` (uma vez) e `park_recovery_stalled` (após 30 s) |
| `_service_parked` / `_police_parked` | `is_stopped()` → desembarca | Se `pending_recovery()` volta a `enroute` sem desembarcar; só desembarca com `settled()` |

O piloto, ao receber `hold(true)` no meio de uma manobra, chama `settle()`
(termina a volta à faixa antes de frear). A unidade só estaciona depois.

### Encerrar o atendimento ≠ recuperar o veículo

Esperar `settled()` para sempre prendia a unidade. Agora são duas coisas separadas:

| | O que é | Quem decide | O que faz |
|---|---|---|---|
| **Recuperação física** | O veículo volta ao eixo por curva aprovada | `OvertakeController` (piloto) | Só se move com trajetória e casco verificados; sem isso fica parado, com `unresolved` |
| **Encerramento do atendimento** | A unidade desiste de estacionar/atender | `DispatchUnit` | Solta a ocorrência, apaga a sirene, vai para `departing`. **Não** desembarca, teleporta nem remove o veículo |

Gatilhos (em `enroute`, polícia e serviços), avaliados por `_recovery_stall_cause()`:

| `cause` | Condição | Relógio |
|---|---|---|
| `recovery_stalled` | `overtake.episode_age ≥ 60 s`, ou `unresolved` **e** `episode_age ≥ 25 s` | UM episódio (não reinicia com aborto/rota/cancelamento) |
| `recovery_cumulative` | `unit.recovery_total ≥ 90 s` **e** há recuperação em curso agora | Soma de todos os episódios do atendimento |

Usam o relógio do episódio / o acumulador e não `_park_wait`: `_park_reset` zera o
segundo a cada oscilação do alvo.

**Acumulador cumulativo (`unit.recovery_total`).** "Atendimento" = a vida da unidade
(uma viatura de polícia ou uma viatura de serviço = uma ocorrência).

- **Avança** a cada tick da unidade, não suspenso e não destruído, em que
  `overtake.in_recovery()` (episódio em `holding_oncoming`/`recovering`/`returning`)
  ou `unresolved`. Isto é recuperação física; **passagem normal (`passing`), espera
  pelo bloqueador (`waiting`), ociosidade, estacionada e perseguição comum não contam**.
- **Pausa** fora de recuperação e durante a suspensão distante (a unidade nem chega ao
  contador). Não recua.
- **Não zera** por troca de rota, de estado da unidade (`enroute`/`parked`/`recall`/
  `departing`), de episódio, por voltar ao eixo, por `resume_pursuit` nem por partir.
  Só some com a unidade.
- **Termina** o atendimento quando passa de 90 s **estando em recuperação**. Se o
  orçamento se esgota mas a viatura já voltou ao eixo, a unidade segue; o orçamento
  esgotado só se cobra no próximo episódio (aí o atendimento encerra logo ao entrar
  em recuperação). Escolha deliberada: não interromper quem já se recuperou.
- Sem perdão por tempo: uma viatura que faz 90 s de recuperação somados ao longo de
  uma perseguição longa também é encerrada. É trocada por outra (partindo, ela não
  conta em `MAX_ACTIVE`), mas gasta `DEPLOYMENT`. Os 90 s **não são calibrados**.

Evento `assignment_released`: `cause`, `status`, `reason`, `needs`,
`recovery_total` e `episode_age` (s, arredondados a 0,1).

A partida (`_begin_departure`) chama `cancel_overtaking("departure")`, que não
reinicia uma recuperação em curso: o veículo continua recuperando e só depois segue a
rota de partida.

### Unidades presas em `departing` e os limites de veículos

Só conta como "presa" a partida com recuperação física (`in_recovery()` ou `unresolved`,
não passagem normal) contínua: `unit.stranded_age` cresce e zera quando a recuperação
sai ou a partida recomeça.

| Limite | Como conta |
|---|---|
| `MAX_UNITS` (8) | **Sempre** todas as unidades vivas, presas ou não. É o teto real de carros e **não foi tocado** |
| `MAX_ACTIVE` (polícia) | Polícia partindo normalmente **não conta** (já era assim). Presa (`stranded_age ≥ 20 s`, `STRANDED_SLOT_SECONDS`) **volta a contar**, exceto as até 2 mais antigas (`MAX_STRANDED_RELEASED`) |
| `MAX_CREWS` (serviços) | Serviço partindo conta até sair de cena, **exceto** as até 2 presas mais antigas |

Ou seja, a vaga de perfil só é liberada para no máximo 2 unidades presas por vez,
e o carro delas continua em `MAX_UNITS`. Com 8 unidades vivas, nada novo é despachado,
presas ou não. Efeito: 2 viaturas presas não travam mais todo novo atendimento do
mesmo perfil, mas as presas além disso e o total continuam limitados. O conjunto
liberado é recalculado a cada consulta (as mais antigas primeiro); se uma sai, a
seguinte mais antiga assume. `controller.status()` traz `stranded` e `released_slots`.

Limitação: presas visíveis/perto do jogador só saem por recuperação, `departure_timeout`
(exige fora da vista), suspensão longa (>130 m + 45 s) ou `dismiss_all`. Se o jogador
mantém 8 presas à vista, novos despachos ficam bloqueados por `MAX_UNITS`; não há
remoção na frente do jogador.

Se, já partindo, a recuperação continua pendente por 45 s
(`STRANDED_REMOVAL_SECONDS`) **e** a viatura está fora da vista **e** a mais de 25 m
do jogador, a unidade é **removida** (`finish("recovery_stranded")`, remoção imediata,
evento `recovery_stranded`). Visível ou perto: fica onde está, até o `departure_timeout`
(180 s, mesma condição de vista) ou a suspensão longa. Não há remoção na frente do jogador.

## Cancelamento: recuperação física × remoção imediata

| Origem | Chamada | Efeito |
|---|---|---|
| Redirecionamento com o veículo em jogo (`_begin_departure`: incidente inválido, prazo, sem acesso, equipe perdida, fim da procura, `cancel_incident`) | `driver.cancel_overtaking(reason)` | **Recuperação física**: manobra ativa e fora do eixo → `recovering` → volta só com curva validada; senão descarta |
| Recuperação sem progresso (`_end_assignment_for_recovery`) | `_begin_departure` → `cancel_overtaking("departure")` | **Recuperação física continua** (não reinicia); só o atendimento acaba |
| `unit.finish(reason)` — inclui `dismiss_all` (troca de região, `set_enabled(false)`, `_exit_tree`), `left`, `suspended_too_long`, `wrecked`, `recovery_stranded` | `driver.discard_overtaking("removed:<motivo>")` | **Remoção imediata**: `overtake.reset`, sem recuperação (o veículo é liberado) |
| Viatura destruída (`_on_wrecked`) | `driver.discard_overtaking("wrecked")` | Descarta |
| Suspensão e retomada | detecção por intervalo de quadros no piloto | Recuperação física se havia manobra ativa fora do eixo |

Troca de região **nunca** tenta recuperar: `dismiss_all` remove imediatamente.

## Eventos (registro existente do `DispatchController`, sem HUD)

O `DispatchController._make_unit` liga os sinais do piloto ao `emit_dispatch_event`
(`controller.events` / `dispatch_event`):

| Evento | Quando | Dados |
|---|---|---|
| `overtake_unresolved` | `unresolved` muda (inclusive ao limpar) | `unresolved`, `reason` |
| `overtake_state` | entra em `holding_oncoming`, `recovering` ou `returning` | `state`, `reason` |
| `park_deferred` | hold pedido, mas há recuperação pendente | `status`, `reason` |
| `park_recovery_stalled` | 30 s sem poder estacionar por recuperação pendente | `status`, `reason` |
| `assignment_released` | Recuperação sem progresso: a unidade encerra o atendimento e parte (o veículo segue recuperando) | `cause` (`recovery_stalled` \| `recovery_cumulative`), `status`, `reason`, `needs`, `recovery_total`, `episode_age` |
| `recovery_stranded` | Partindo com recuperação pendente 45 s, fora da vista: unidade removida (antecede `unit_finished` com `reason = recovery_stranded`) | `status`, `reason` |

Sinais crus, se preferir: `driver.overtake_state_changed(state, reason)`,
`driver.overtake_unresolved_changed(unresolved, reason)` (repassam o objeto
`OvertakeController`, recriado a cada `enable_overtaking`).

## Revisão estática das integrações (por leitura; nada executado)

**Chamadores do contrato `settled()` / `pending_recovery()` / `at_route_end()`**
(único consumidor no repositório é `DispatchUnit`; `grep` em `*.gd` não achou outro):

| Chamador | Uso | Estado da revisão |
|---|---|---|
| `_police_enroute` (raio de parada) | `hold(true)`; só `settled()` → `parked`, senão `_park_pending` | ok; checa `_recovery_stall_cause()` antes |
| `_service_enroute` (chegada) | idem; `at_route_end()` exige `settled()` | ok. Com recuperação pendente no fim da rota, `at_route_end()` é falso: cai em `hold(false)` sem `no_road_access` até a recuperação sair, o prazo de 120 s ou `_recovery_stall_cause()` |
| `_police_parked`, `_service_parked` | `pending_recovery()` → volta a `enroute`; só desembarca com `settled()` e ≥ 0,6 s | ok: única porta de desembarque/`spawn_officer`/`spawn_responder` |
| `on_gave_up` | `hold(true)` + `parked` sem checar `settled()` | ok: `*_parked` refaz a checagem no tick seguinte |
| `_tick_departing` | `at_route_end()` para replanejar a partida | ok: com recuperação pendente não replaneja (o veículo não está no fim da rota de fato) |
| `on_crew_released` | `abs(speed) < 0.6` para embarcar (não usa `settled()`) | **pendente/observado**: a equipe só está a pé com a viatura em `hold(true)` (sem manobra nova), então a recuperação não coexiste; não alterado |

**Encerramento lógico × saída física (sem laços):**

- Prazo de serviço (120 s) e fim da procura (`stars == 0` → `recall`) chamam
  `_begin_departure`, que chama `cancel_overtaking("departure")`. A partida **não**
  reinicia a recuperação (ver tabela de cancelamento), e `departing` nunca volta a
  `enroute` (só `recall` com `resume_pursuit`, que exige `stars > 0`). Não há laço.
- `_end_assignment_for_recovery` só dispara em `enroute` e leva a `departing`;
  o episódio zera ao voltar ao eixo, então uma recuperação que progride não é encerrada.
- Recuperação intermitente (espera contrária que abre e fecha, cada episódio < 60 s)
  não dispara o encerramento por `episode_age`, mas soma em `recovery_total` e
  dispara `recovery_cumulative` aos 90 s (polícia e serviços). Fechado por leitura.

**Remoção imediata e limpeza:** `finish` → `discard_overtaking` (`reset`) →
`_detach_driver`: desconecta os quatro sinais que o controlador liga em `_make_unit`
e chama `disable_overtaking()`. Antes, os Callables ligavam unidade ↔ piloto ↔
ultrapassagem em ciclo de `RefCounted` que nada liberava. Depois de `finish`,
`unit.driver.overtake` é `null`. Nenhuma referência a carros ambiente é guardada
(só `traffic_yield_state` é lido a cada avaliação; posições dos bloqueadores são
números), então `TrafficYieldController.release_all/refresh_roads` e a remoção de
uma viatura não se afetam; nada é escrito nos metadados dos carros ambiente.

**Corrigido nesta revisão:** `settle()` e o cancelamento abortavam `passing` mesmo
ao lado dos bloqueadores, gerando um `recovering` sem retorno possível (ver tabela de
cancelamento); ciclo de referências acima.

**Condição para sair de cada espera** (`overtake.exit_condition()`, campo `needs` nos
eventos `overtake_unresolved`, `park_deferred`, `park_recovery_stalled`,
`assignment_released`, `recovery_stranded`). Nenhuma é forçada:

| Motivo | Condição |
|---|---|
| `oncoming_stopped_ahead` | o carro contrário voltar a andar (não há ré) |
| `oncoming_deadlock` / `oncoming_traffic` | folga prevista ≥ 4 m na faixa contrária |
| `bypass_obstructed` | desvio preservado livre na varredura |
| `return_blocked:*` / `return_blocked_by_oncoming` | faixa própria livre à frente, bloqueador ao lado sair, sem cruzamento/curva na rampa |
| `engine_disabled_*` | motor liberado |
| `recovery_no_progress` / `return_failed_repeatedly` | curva de retorno aprovada que a viatura complete |
| `heading_mismatch` | rumo compatível com o eixo (não há meia-volta) |
| `route_ends` (em `return_blocked:`) | não há saída: o eixo não comporta a rampa; só remoção, suspensão longa ou `dismiss_all` |

**Contratos de teste existentes a adaptar** (não atualizados; nada de `tests/dispatch`
referencia o módulo de ultrapassagem):

- `test_dispatch_emergency` (espera `parked`) e `test_dispatch_police` (viatura chega e
  desembarca): dependem de `settled()`; só valem se a ultrapassagem estiver ociosa. Em
  cena de laboratório sem grafo real o planejador devolve `no_graph` e não interfere,
  mas isso **não foi verificado**.
- `test_dispatch_lifecycle`: `cancel_api` (espera `departing`), `dismiss_and_wrecks` e
  `controller_leaves_tree` passam por `finish`; agora `driver.overtake` vira `null`
  depois dele. Qualquer verificação que leia `unit.driver.overtake` após `finish` quebra.
- O registro tem 64 eventos (`event_limit`): eventos novos de recuperação
  (`overtake_state`, `overtake_unresolved`, `assignment_released`) podem expulsar
  eventos que testes procuram em cenários longos.
- Faltam testes novos para tudo o que este README descreve.

## Leitura

```gdscript
driver.overtake.state            # idle | waiting | passing | holding_oncoming | recovering | returning
driver.overtake.last_reason      # ex.: oncoming_traffic, return_blocked:obstructed, returning_after_resumed
driver.overtake.unresolved       # true = sem manobra livre há tempo demais (continua esperando)
driver.overtake.unresolved_reason
driver.overtake.episode_age      # s do episódio de recuperação (0 fora de episódio)
driver.overtake.follows_without_route()   # fora do eixo, com eixo lembrado
driver.cancel_overtaking(reason)   # recuperação física
driver.discard_overtaking(reason)  # remoção imediata
```

Instruções ao integrador: nada a instalar (as conexões estão em
`DispatchController._make_unit`); `TrafficYieldController.configure`,
`release_all` e `refresh_roads` não mudaram. Testes existentes de despacho
(`tests/dispatch/*`) **não foram atualizados** para o novo contrato.

## Parâmetros (`OvertakeRules.gd`)

`EVAL_INTERVAL 0,25 s` · `DETECT_AHEAD 32 m` · `TRIGGER_MIN 12 m` /
`TRIGGER_SECONDS 1,6 s` · `CLEAR_SIDE 0,6 m` · `PAD_SIDE 0,25` /
`PAD_END 0,4` · `MAX_SHIFT 4,5 m` · rampas `6,0` / `3,5` por m, mín. `8 m` ·
`FRONT_CLEAR 2,5 m` · `TAIL 8 m` · `SAMPLE_STEP 1,5 m` · `MAX_TURN 0,12 rad` ·
`CENTER_MARGIN 0,05 m` · `ONCOMING_LOOKAHEAD 40 m` · `PASS_SPEED 6` /
`ONCOMING_SPEED 5` / `RETURN_SPEED 3 m/s` · `BLOCKER_MAX_SPEED 4,5 m/s` ·
`WAIT_MAX 20 s` · `PASSING_MAX 30 s` · `STUCK_ABORT 1 s` ·
`RESUME_GAP_FRAMES 20` · `EPISODE_PATIENCE 45 s` · `RETURN_MAX_FAILURES 3` ·
`RETURN_RAMP_SCALES 1 / 1,6 / 2,4` · `RETURN_MIN_ALIGNMENT 0,35` ·
`RETURN_MIN_TAIL 1 m` · `STATIONARY_SPEED 0,3 m/s`. Na unidade
(`DispatchRules.gd`): `RECOVERY_GIVE_UP_SECONDS 60` ·
`RECOVERY_GIVE_UP_UNRESOLVED_SECONDS 25` · `STRANDED_REMOVAL_SECONDS 45` ·
`RECOVERY_CUMULATIVE_SECONDS 90` · `STRANDED_SLOT_SECONDS 20` ·
`MAX_STRANDED_RELEASED 2` (os três últimos, novos e **não calibrados**).
Nenhum foi calibrado em jogo.

## Limitações (não esconder)

- Em pista de 8 m com o carro ambiente já encostado (~0,6 m), a viatura precisa
  de ~2,7 m à esquerda: isso **só cabe ocupando a faixa contrária**. Com
  `allow_oncoming = false`, sem sirene, ou com qualquer coisa na faixa contrária,
  espera. Em mão única estreita (largura 4) quase nunca cabe.
- A contramão permitida é uma **decisão de regra** (sirene ligada, mão dupla,
  faixa livre, sem cruzamento): não há dado de "contramão proibida" por
  trecho no grafo. Se o mapa tiver ruas onde isso deva ser vedado, falta um
  atributo em `NativeTrafficRoutes` (não alterei).
- Veículo em aproximação: só se vê o que já está **dentro** da caixa da faixa
  contrária (40 m). Sem previsão de velocidade; quem vem muito rápido de mais
  longe pode chegar ao trecho. O reaviso a cada 0,25 s aborta e a viatura para
  **na faixa contrária** até poder voltar: é o pior caso e ainda não tem saída
  melhor (ré ou volta pela direita não foram implementadas; ver "sem solução").
- Custo do retorno bloqueado: até 3 varreduras completas (rampa normal, 1,6× e
  2,4×) a cada 0,25 s por viatura em `recovering`, e uma varredura do desvio
  preservado a cada 0,25 s em `holding_oncoming` com folga aberta. **Não medido.**
- Só trecho reto, fora de cruzamento; sem ultrapassagem em curva, ponte com
  desnível ou rotatória. Limite direito/esquerdo = largura cadastrada do eixo;
  degraus baixos e meio-fio dentro da largura não são vistos.
- A varredura do casco é estática no instante do plano: um carro que entra
  depois só é pego pelo sensor frontal do piloto e pelo aborto.
- `slow` do traffic_yield (carro que não achou espaço) conta como "veículo que
  não cede": a viatura espera em vez de passar por ele.
- Se outro sistema trocar `route` de um carro ambiente durante a espera, o
  estado `held` pode ficar obsoleto; nada disso é detectado.
- Custo por avaliação: uma caixa de corredor + até ~30 consultas de casco (+1
  de faixa contrária), a cada 0,25 s por viatura, só com bloqueador à vista.
  **Não medido.**

## Casos ainda **sem solução física** (esperam, não se recuperam)

Aqui "sem solução" é do **veículo**. A **unidade** já não fica presa por causa deles
(ver "Encerrar o atendimento"): encerra o atendimento em 25–60 s e, fora da vista,
é removida 45 s depois de partir. O veículo, enquanto visível, continua onde está.

| Caso | O que o código faz | Por que não há movimento |
|---|---|---|
| **Carro contrário parado à frente, viatura ao lado dos bloqueadores** (`oncoming_stopped_ahead`) | Parada explícita; classifica pelo corpo que define a folga; retoma a passagem sozinha se ele andar | Voltar é impossível (o carro ao lado ocupa a faixa própria). **Ré controlada não foi implementada**: exigiria varrer o trecho de trás, dirigir de ré por uma curva e validar a volta depois. Sem execução para calibrar, foi deixada de fora |
| **Mesmo caso com corpo contrário que anda** (`oncoming_deadlock`) | Idem; a folga costuma abrir | — |
| **Retorno bloqueado** (`return_blocked:*`): fila ou sólido na faixa própria à frente, bloqueador ainda ao lado, cruzamento na rampa, curva, fora de pista | Tenta a rampa normal, 1,6× e 2,4×; reavalia a cada 0,25 s; `unresolved` após 12 s | Nenhuma das rampas passa na varredura. Rampa mais curta (mais rápida) não foi tentada por falta de esterço verificado |
| **Rumo incompatível com o eixo** (`heading_mismatch`) | Fica parada | Voltar exigiria meia-volta; não há manobra verificada para isso |
| **Motor bloqueado fora do eixo** (`engine_disabled_while_displaced`) | Nada se planeja; **retoma sozinha** se o motor voltar | Sem motor não há movimento |
| **Rota nula fora do eixo, sem curva aprovada** | Recuperação sobre o eixo lembrado; se nenhuma curva passa, parada | Mesmo motivo do retorno bloqueado |
| **Eixo curto demais** (`route_ends`): a rampa inteira não cabe antes do fim do eixo | Encurta só a cauda; se a rampa não cabe, parada | Não há geometria de rua além do fim do eixo |
| **Desvio perdido após aborto** (`blocked_while_passing`, `passing_timeout`, `stuck`) | Vai para `recovering` e só tenta **voltar** | Prosseguir pela frente (o desvio já validado) não é tentado; com o bloqueador ao lado, o retorno espera ele sair. `holding_oncoming` preserva o desvio; estes abortos, não |

Casos de percepção, também sem solução:

- Tráfego contrário que **surge depois** da última avaliação (0,25 s) ou de
  fora da caixa de 40 m só é pego pelo sensor frontal e pelo aborto.
- O `curve_clear` da retomada varre casco estático: quem entrar depois da varredura
  só é pego pelo sensor frontal e pelo aborto.

Estacionar com recuperação impossível (`unresolved`): a unidade **não** estaciona nem
desembarca (contrato `settled()`); fica em `enroute` segurando o freio,
`park_deferred` / `park_recovery_stalled` no registro, e então encerra o atendimento
(`assignment_released`). O veículo pode seguir parado na faixa contrária, visível,
até a recuperação sair, o `departure_timeout`, a suspensão longa ou `dismiss_all`.

**Nada disto foi executado.** Não há teste que cubra o novo comportamento, e os
prazos (25/45/60 s) são escolhas sem calibração.

## Pendentes explícitos

Testes (nenhum escrito) — cenários mínimos: mão dupla larga com faixa contrária
livre; a mesma com veículo contrário; mão única larga e estreita; cruzamento
dentro do trecho; curva; obstáculo estático ao lado; bloqueador que volta a
andar; bloqueadores em fila; `engine_disabled` no meio; suspensão/retomada
deslocado; destruição; troca de região; perseguição replanejando durante o
desvio. Medição renderizada de frame time com e sem a ultrapassagem.

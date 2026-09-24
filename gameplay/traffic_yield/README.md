# Trânsito ambiente cedendo às sirenes

Módulo independente em `gameplay/traffic_yield/`. Detecta viatura com sirene se
aproximando por trás, faz o carro ambiente reduzir, procura espaço lateral
**dentro da pista**, para à direita e volta à rota depois que a viatura passa.
Nada é teleportado: o módulo só troca `Vehicle.route` (contrato que o tráfego já
usa) e deixa `Vehicle._drive_traffic` conduzir, frear e colidir. Nenhum arquivo
existente foi alterado.

> **Estado: escrito, NÃO executado.** Nenhum teste nem benchmark rodou nesta
> etapa (pedido explícito). Não há testes escritos para o módulo (o escopo era
> só esta pasta); os cenários a cobrir estão no fim. Espere erros de sintaxe
> ou de calibração na primeira execução.

## Arquivos

| Arquivo | Papel |
|---|---|
| `YieldRules.gd` | Constantes (todas novas: a V1 não tinha equivalente) e testes geométricos puros: ameaça, "já passou", "logo atrás" |
| `YieldRoadModel.gd` | Espaço lateral permitido lido do grafo de `NativeTrafficRoutes` (largura da pista) e zonas de cruzamento |
| `YieldAgent.gd` | Um carro cedendo: `pulling → held → merging → rota original` ou `slow` |
| `TrafficYieldController.gd` | Varredura, limites, cooldown, eventos, API |

## Como funciona

1. **Detecção** (a cada 0,2 s): para cada carro ambiente (`traffic`, com `route`,
   inteiro, visível, sem `awaiting_ground`, fora de `dispatch_unit` e de
   `residence_vehicle`) e cada viatura com sirene em movimento (≥ 2,5 m/s;
   `equipment.siren_on` com barras de luz e conduzida pelo despacho ou pelo
   jogador): ameaça se estiver à frente da viatura, no mesmo sentido
   (cos ≥ 0,45), dentro do corredor lateral (4,5 m + meia-largura) e a menos de
   `clamp(velocidade × 3,5 s, 35, 60)` m.
2. **Manobra**: segue a rota original por 10/16/24/34 m (primeiro comprimento que
   serve) e desloca para a direita até o menor espaço da pista ao longo do trecho
   (máx. 3 m), com rampa suave. A curva só vale se **todas** as amostras
   estiverem sobre pista (`YieldRoadModel.lateral`), fora de cruzamentos
   (vértices com ≥ 3 saídas) e sem colisão na varredura do casco
   (`Vehicle.rotation_shape`, máscara 7, o mesmo volume que o `Vehicle` usa para
   girar). Sem curva válida → modo `slow`: só limita a 2 m/s.
3. **Parada**: a curva é aberta (`traffic_open`), então o próprio `Vehicle` freia
   e para no fim. Enquanto isso a velocidade é limitada a 3,5 m/s.
4. **Retomada**: sem ameaça por 1,2 s e sem viatura a menos de 10 m atrás, com
   `Vehicle.obstacle_ahead()` livre, monta uma curva de retorno de 14 m até o eixo
   da faixa (varredura do casco de novo). Antes de o `Vehicle` parar no fim dela a
   rota original volta. Se algo bloquear, espera e tenta a cada 0,25 s. Teto de
   30 s parado; depois disso volta assim que o espaço permitir.
5. **Segurança**: preso 4 s a meio caminho → assume `held` onde está; veículo
   destruído, assumido pelo jogador ou removido do tráfego → agente encerra sem
   mexer; `release_all` devolve a rota original de todos.

## Pontos de conexão (o integrador faz)

```gdscript
# ProductionWorld, depois de world.gameplay e (se existir) world.dispatch:
world.traffic_yield = preload("res://gameplay/traffic_yield/TrafficYieldController.gd").new()
world.traffic_yield.configure(world, traffic_routes)
world.add_child(world.traffic_yield)
```

| Momento | Chamada |
|---|---|
| `travel(region)`, **antes** de liberar os veículos | `world.traffic_yield.release_all("travel")` |
| Depois de `traffic_routes.configure(region.roads)` | `world.traffic_yield.refresh_roads(traffic_routes)` |
| Carregar save / reiniciar | `release_all("load")` |
| Desligar | `set_enabled(false)` |
| Fontes diferentes das padrão | `configure(world, routes, ambient_callable, emergency_callable)` (`Array` de veículos) |

Fontes padrão (duck typing, sem dependência dura): ambiente =
`world.production.vehicles`; sirenes = `world.dispatch.units[*].vehicle` e o
carro do jogador se ocupado. Sem `world.dispatch`, só o jogador com sirene
faz o trânsito ceder.

**Leituras que o despacho pode fazer (opcional):** cada carro cedendo carrega
`vehicle.get_meta("traffic_yield_state")` = `pulling | held | merging | slow`
(ausente quando livre). Sinal `yield_event(name, data)` e `controller.events`
com `started`, `finished` (`resumed`, `vehicle_unavailable`, `released`),
`released_all`; `status()` conta por modo.

## Interação com a ultrapassagem das viaturas

O despacho agora tenta ultrapassar carros em `held`/`pulling` (ver
`gameplay/dispatch/overtaking/README.md`). Do lado deste módulo: a viatura **ao
lado** (até 7 m à frente do carro que cedeu) também impede a volta dele à faixa
(`YieldRules.PASSING_ZONE`), e `YieldRoadModel` ganhou `room_raw`, `left_raw`,
`signed`, `one_way` e `refresh_if_changed()`. Os pontos de conexão
(`configure`, `release_all`, `refresh_roads`) não mudaram. O modo `slow` não é
ultrapassável (a viatura o trata como veículo que não cede).

## Limitações (não esconder)

- **A ultrapassagem depende do despacho e nem sempre cabe** (ver o README
  dela). Em pista de 8 m o carro que cede só ganha ~0,6 m (faixa a 2 m do eixo,
  1,04 de meia-largura, margem 0,35); a viatura precisa da faixa contrária para
  passar, e sem espaço, sem sirene ou com tráfego contrário ela espera atrás do
  carro que cedeu.
- **"Calçada" = fora da largura cadastrada da pista.** Não há outra fonte de
  meio-fio na V2; se a malha de calçada ficar dentro da largura do eixo, o
  módulo não sabe. A varredura do casco só enxerga sólidos (máscara 7), não
  degraus baixos.
- Só cede o carro **no mesmo sentido** e no corredor da viatura. Tráfego em
  sentido oposto, ruas paralelas e a viatura que vai virar num cruzamento à
  frente não são previstos (a detecção é em linha reta, não pela rota da
  viatura).
- **Cruzamentos**: não se para dentro de zona de cruzamento; se o trecho de 34 m
  toca um, o carro só reduz (`slow`) e continua bloqueando a faixa. Carro já
  dentro do cruzamento não é tratado especialmente.
- Suposição de **mão direita** (`direção × UP`), a mesma de `NativeTrafficRoutes`.
  Pontes de mão única (largura 4) dão ~0,6 m de espaço como as demais.
- **Velocidade**: o tráfego ambiente já não passa de 5,5 m/s; "reduzir" é o teto de
  3,5 m/s (`speed` é escrito diretamente, e o `Vehicle` reacelera no quadro
  seguinte até o teto da curva) mais a frenagem do fim de rota aberta.
- Se outro sistema trocar `Vehicle.route` durante a cessão, a rota original
  guardada pode ficar obsoleta; nada disso é detectado.
- Cooldown de 3 s por veículo para evitar oscilação; parâmetros são
  estimativas sem calibração.
- Sem áudio, sem buzina, sem sinalização visual do carro que cede.
- Nada é persistido. Nenhum evento é enviado ao HUD.
- **Desempenho não medido.** Custos novos: escrita de `hazards` por quadro; por
  varredura (5 Hz) O(ambiente × sirenes); ao iniciar uma cessão, até 4 tentativas
  de curva, cada uma com até 17 buscas de aresta (varredura de todas as
  arestas do grafo) e ~17 consultas físicas, no máximo 2 inícios por
  varredura e 10 carros simultâneos; retomada: até 7 consultas a cada 0,25 s
  enquanto esperar espaço.

## Cenários que os testes futuros devem cobrir

Rua reta de duas faixas com viatura vindo a 15 m/s (ambiente para à direita
sem sair da pista e volta depois); obstáculo sólido ao lado (não sobe nele, cai
em `slow`); cruzamento à frente (`slow`); rua de mão única; viatura que passa e
outra que vem em seguida (cooldown); ambiente destruído ou assumido pelo
jogador durante a cessão; `release_all` no meio da manobra; troca de região;
oito carros ao mesmo tempo (limite de dois inícios por varredura); medição de
frame time renderizada com e sem o módulo.

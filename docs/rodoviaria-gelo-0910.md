# Linha Harbor–Vila da Neve

A cena de produção `HarborGame` cria `HarborMountainCoachService` depois de
`ContinuousWorld`. Há um único ônibus regional persistente, com modelo nativo
3D de viagem, três eixos, bagageiros e portas animadas. A linha usa as pistas e
as reservas de cruzamentos da cidade, a ponte e a estrada da montanha. O pátio
da rodoviária e o serviço urbano existente mantêm suas rotinas próprias.

## Destino

`MountainTransitVillageLayout` define coordenadas locais da montanha; no mundo
contínuo somam-se `(4300, -4960)`. A vila fica na metade da subida, a leste da
estrada, com o berço em `(7500, -1760)`. A entrada sai da pista de subida, passa
pela plataforma 01 e faz um retorno ao norte para a pista de descida.

O terminal admite um ônibus por vez, com reserva exclusiva e verificação da
ocupação física da vaga. A vila contém quatro chalés com entradas funcionais,
uma loja ligada ao interior existente `mountain_outfitters`, caminhos, bancos,
iluminação e um braseiro que funciona como fonte de calor. A floresta e os
guardrails respeitam a reserva da vila e de seus acessos.

## Passageiros

`MountainTransitPassengers` recebe o ônibus depois de parado com portas abertas.
As chegadas alternam grupos de 5, 2, 4 e 3 passageiros. Cada grupo mistura
viajantes agasalhados e visitantes sem acessórios de inverno, com aparências,
velocidades, intervalos e chalés de destino diferentes.

Todos saem pela porta voltada à plataforma e caminham com colisão. Os visitantes
sem agasalho vão à loja, permanecem alguns segundos no interior e reaparecem com
gorro/capuz, cachecol e luvas antes de seguir ao chalé. A compra é uma rotina do
NPC; a loja do jogador conserva seu próprio estoque e pagamento. O ônibus pode
partir depois do desembarque, enquanto as compras e caminhadas continuam.

A população tem limite de dez viajantes. Só passageiros já dentro dos chalés
são reciclados para uma próxima chegada; ninguém desaparece caminhando na vila.
O ônibus, os passageiros em serviço e o tráfego próximo continuam sendo
simulados fora da câmera, respeitando a pausa global.

O retorno à estrada espera uma abertura no tráfego antes de iniciar a junção.
Nos dois cruzamentos próximos do retorno da rodovia, o controlador conserva a reserva anterior
enquanto solicita a seguinte pelas regras normais de sinal e ocupação; a reserva
anterior só é liberada depois que o veículo inteiro sai da área. Isso impede o
bloqueio observado no retorno curto da rodovia sem liberar tráfego conflitante.
O tráfego inicial é distribuído por outras pistas: esse pequeno retorno continua
percorrível, mas não recebe carros criados no meio dos seus conectores.

A janela de atividade ao redor do ônibus acompanha o alcance de 1.600 px usado
para o jogador e inclui carros e pedestres. Isso evita suspender uma fila ou um
pedestre em travessia quando o jogador está em outra região.

Além dessa janela, os dois orçamentos consultam `TrafficSimulationBudget`:
veículos que possuem uma reserva de cruzamento e sua cadeia imediata de
bloqueadores continuam ativos até liberar a passagem. Carros e pedestres
distantes sem essa dependência continuam suspensos. O diagnóstico identificou
um carro suspenso dentro do cruzamento 29, mantendo o vermelho e acumulando
filas nos cruzamentos 30 e 37; aumentar apenas o raio do ônibus não resolveria
a causa. As reservas e os semáforos permanecem sob a autoridade do controlador.

Os postes dos cinco cruzamentos usados pela linha em `(5880, -2000)`,
`(4650, -1100)`, `(5550, -2000)`, `(5550, -1100)` e `(4650, 400)` recebem
26 px de recuo adicional. A base física e o modelo 3D se movem juntos; os
semáforos mantêm suas regras. A verificação cobre também o casco na orientação
anterior enquanto avança 14,4 px em curvas, amostradas a cada 2 px, para evitar
contatos durante a manobra do ônibus comprido.

Nas curvas do grafo de Harbor, os veículos verificam o corredor ocupado pelo
casco ao longo do conector e da pista seguinte. Isso evita parar por um
pedestre na calçada que apenas cruza a projeção reta de um sensor. Pessoas no
trajeto ou se aproximando dele continuam provocando a parada; o jogador e as
colisões físicas são preservados. O ajuste é opt-in para Harbor: os demais
grafos conservam o comportamento padrão. O diagnóstico encontrou o mesmo
bloqueio lateral em carros ambientes que mantinham os cruzamentos 6 e 12
ocupados e impediam o retorno do ônibus.

## Verificação

- `tests/test_mountain_transit_village.gd`: duas chegadas reais de 5 e 2 pessoas,
  três compras de roupa, sete caminhadas até chalés, recusa de segundo ônibus,
  notificação idempotente e limite da população. Passou sem falhas.
- `tests/test_harbor_mountain_coach.gd`: varredura do casco nas pistas reais,
  junções entre cidade/serra/acesso, reserva exclusiva e percurso de ida e volta.
  Passou na cena completa, com 17 pernas em cada sentido, uma chegada à vila e
  retorno ao mesmo berço de Harbor. Percorreu 38.888,79 px; maior deslocamento
  entre pistas de 0,0011 px. Evidência `regional-full-corridor-monitor.log` em
  `artifacts/rodoviaria-3d-0910`: `round_trips=1`, `failures=0`. O monitor apenas
  registrou estados, sem mover veículos nem liberar reservas durante a viagem.
- `tests/test_adjacent_junction_reservations.gd`: semáforo vermelho, reserva
  ocupada, retenção simultânea e liberação depois de sair do cruzamento.
- `tests/test_reserved_traffic_budget.gd`: ambos os orçamentos mantêm e acordam
  donos de reservas, veículos e pedestres bloqueadores; após liberar a reserva,
  eles podem dormir. Ciclos de sensores terminam e tráfego sem relação permanece
  suspenso. Passou sem falhas.
- `tests/test_regional_coach_pedestrian_turn.gd`: pedestres na calçada, dentro
  da curva, na pista seguinte, aproximando-se da pista e jogador; cobre também
  carros ambientes nas curvas dos cruzamentos 6 e 12 e o comportamento padrão
  de grafos sem opt-in. Passou sem falhas.
- `tests/capture_mountain_regional_coach.gd`: cena de produção renderizada em
  Vulkan; início de teste na aproximação para registrar parada, desembarque,
  saída e compras. Esse enquadramento não substitui o teste do percurso completo.

As execuções headless usam `--fixed-fps 60`; as capturas usam Forward+.
O percurso completo usa tempo de simulação 8x e admite até dez minutos de
execução, incluindo os ciclos normais de semáforos e filas.
Evidências da vila e do desembarque em
`D:/geteco/artifacts/rodoviaria-gelo-0910/`, incluindo
`03_onibus_na_micro_rodoviaria.png`, `04_onibus_retornando.png` e
`05_passageiros_com_agasalhos.png`.

### Verificação ferroviária independente

O teste legado `rail_level_crossing_runtime_test.gd` apresentou conflito do
`BoroughTraffic_11` no frame 3263. O mesmo resultado foi reproduzido carregando
o controlador original de `git HEAD` somente na memória do teste, sem substituir
o arquivo compartilhado. Evidências `regional-rail-final.log` e
`regional-rail-baseline.log` em `artifacts/rodoviaria-3d-0910`; essa falha não foi
introduzida pela reserva composta, que permanece restrita ao retorno da rodovia.

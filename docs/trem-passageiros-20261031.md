# Trem de passageiros — etapas 2 e 3 (31/10/2026)

Continuação de [plano-trem-20260928.md](plano-trem-20260928.md). Card do Trello: "Trem de
passageiros, elevado e viaduto" — as etapas 2-3 esperavam locais das estações e preço. O dono
deixou a decisão para o agente.

## O que já existia antes desta rodada

Ao reler o código, boa parte das etapas 2-3 já estava no ramo (feita depois do plano):

- `world/railway/RailwayNetwork.gd`: quatro estações elevadas no trilho que existe, grafo de
  rotas, túneis, catraca norte (`GATE_POSITION`).
- `world/railway/RailwayWorld.gd`: trilho em streaming por chunk, pilares, plataformas,
  coberturas, escadas e acessos.
- `world/railway/TrainModel.gd`: composição com portas e rodas.
- `runtime/railway/RailwayTransit.gd`: trem ambiente em vai e vem (Central → Northgate →
  Pinhais/Cobre alternando), embarque pela plataforma, viagem com câmera externa, opção
  **viagem rápida** (`travel_to(id, true)`) e **pular** durante a viagem (`skip_trip`); a chegada
  monta a região de destino (`controller._mount_region`) e espera 3 quadros de física antes de
  soltar o jogador, então o streaming fica pronto sob a cortina (`door_transition`).
- `ui/railway/RailwayUI.gd`: painel de destinos e HUD da viagem; mapa e minimapa mostram as estações.
- Polícia: `_eligible` recusa embarque com qualquer estrela (`gameplay.stars > 0`), igual ao táxi
  (`PassengerTransport`). Não existe regra de "perder estrela ao embarcar" em nenhum transporte,
  então **mantive a recusa** em vez de inventar uma fuga pelo trem.

## Estações (as que existem no trilho)

| id | Nome | Região / zona | Observação |
|----|------|---------------|------------|
| `harbor_central` | Harbor Central | harbor | centro, viaduto junto da calçada norte |
| `harbor_north` | Northgate | harbor | saída norte, sobre a água |
| `mountain_pines` | Pinhais | mountain | serra |
| `desert_copper` | Cobre | desert | só depois da última missão da cidade 1 |

## Preço (decidido nesta rodada)

Tarifa por zona (`EconomyBalance.RAIL_FARE_*`), igual para viajar de trem ou pular:

| Trecho | R$ |
|--------|----|
| Harbor Central ↔ Northgate | 15 |
| Harbor ↔ Pinhais | 25 |
| Pinhais ↔ Cobre | 35 |
| Harbor ↔ Cobre | 40 |

Por quê: barato perto do dinheiro de bolso (guincho, entregas) para o trem ser útil desde cedo;
o deserto custa mais para não virar atalho de graça. Cobrado com `Economy.charge_fee` (sem
recibo — viagem é repetível e um recibo por bilhete encheria `MAX_OPAQUE_RECEIPTS`).

## O que foi implementado

- `runtime/railway/RailwayFares.gd` (lógica pura): `fare(from, to)`, `buy(wallet, from, to,
  serial, ticket)`. Cada abertura do painel da estação é um embarque (`_trip_serial`); repetir o
  mesmo embarque devolve ok sem novo débito. Sem saldo, nada muda e a razão ("Saldo insuficiente:
  o bilhete custa R$ 40.") aparece no painel.
- `RailwayTransit.travel_to`: cobra depois de toda recusa barata (estação travada, rota vazia) e
  antes de fechar o painel. `destinations()` leva `fare`; o painel mostra "Viagem · 1:34 · Bilhete R$ 25".
- Anúncios: no embarque ("Bilhete R$ 25 · Linha Geteco para Pinhais. Boa viagem!"), a 82 % do
  percurso ("Próxima estação: Pinhais.") e na chegada ("Estação Pinhais. Desembarque pela plataforma.").
- Testes: `tests/test_railway_fares.gd` (tarifa, todos os pares entre R$ 15 e 40, débito na
  `Economy` real, recusa sem saldo, não cobra duas vezes, viagem inválida não cobra).
  `tests/test_railway_runtime.gd` agora dá R$ 300 ao save novo e confere o débito de R$ 15;
  `tests/measure/measure_railway.gd` liga `cheat_infinite_money` (medição não testa carteira).

## Verificado e não verificado

- Verificado: `gdparse` (gdtoolkit) nos arquivos mexidos. **Godot não foi executado** nesta
  sessão (sem binário): nem `test_railway_fares`, nem `test_railway_runtime`, nem o jogo. Rodar
  pela fila antes de confiar: `tools/run_godot_locked.sh --path . --script res://tests/test_railway_fares.gd`
  e `res://tests/test_railway_runtime.gd`.
- Nenhuma medição de desempenho (a mudança não adiciona trabalho por quadro além de uma comparação).

## Pendências

- **Câmera de vista bonita**: a viagem tem uma câmera externa ortográfica fixa
  (`_update_camera`). Planos variados (travelling lateral na ponte, vista da serra) precisam
  conferir `RailwayCameraClearance` e ver no jogo renderizado; não fiz às cegas.
- **Arte**: elevado/viaduto ferroviário da V1 (Breakwater sobre a Rodoviária), ponte ferroviária
  e painel de horário com texto na estação — exigem modelagem; ficam para quem tiver o editor.
- Civis esperando/embarcando na plataforma (etapa 2 do plano) e som de anúncio gravado
  (hoje o anúncio é texto via `show_message`).
- Reembolso (`RailwayFares.refund`/`settle`, `Economy.refund_fee`): morte ou prisão no meio da
  viagem devolvem o bilhete daquele embarque uma única vez (o bilhete é liquidado antes do crédito,
  então dois eventos não dobram), com o aviso "Reembolso do trem: R$ N devolvidos." e sem o
  "RECEBIDO" central (refund_fee não emite `money_gained`). Chegada liquida o bilhete: sem
  reembolso. Carregar save e sair para o menu são recusados em viagem (`is_transition_blocked`);
  se a cena cair mesmo assim, `_exit_tree` cancela sem reembolso, porque o save não tem o débito
  (save bloqueado durante a viagem) e o estado em memória é descartado.
- Decidir se a viagem rápida deve custar mais/menos que a viagem de trem (hoje igual).

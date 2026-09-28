# Trem — plano em 3 etapas (28/09/2026)

Pedido do usuário: trazer o trem da V1 de volta e ter uma linha de passageiros que
vai e volta entre uma estação no porto e outra no alto da serra, com opção de
viajar no trem ou usar viagem rápida. **Locais das estações ainda serão definidos
pelo usuário** — não começar a etapa 2 sem essa resposta.

## Situação em 28/09

- A V2 **não tem trem, trilho nem viaduto ferroviário**. A migração já registra isso
  como pendência bloqueadora (`docs/HARBOR_V1_CITY_3D_MIGRATION_2026-09-22.md:46`).
- `south_port_rail` na V2 é o guarda-corpo do navio Santa Mare, não trilho.
- A V1 (ramo `v1-legado`, tag `v1-final`) tinha um trem de carga ambiente
  (locomotiva + 6 vagões) num circuito de mão única: viaduto da Breakwater → túnel →
  ponte ferroviária → serraria → floresta → encosta nevada → túnel norte → retorno
  subterrâneo ao porto. Volta de ~4 min 47 s, sem paradas nem embarque.
  Mapa e captura: `evidence/train-v1-20260928/`.
- Fontes da V1 em `v1-final:geodata/rail/`: `AmbientTrain.gd`, `DistrictRailLine.gd`
  (+ `.tscn`), `HarborMountainRailRoute.gd`, `RailStructure3D.gd`,
  `RailMinimapOverlay.gd`, `RailUnderpassReveal.gdshader`, `RegionalRailScenery.gd`,
  `TrainAudioBank.gd`, `TrainPiece3D.gd`; mais `world/harbor/HarborRailLine.gd`,
  `world/harbor/HarborTrain.gd` e os testes `test_harbor_train_3d.gd`,
  `test_harbor_mountain_rail.gd`. Relatórios: `v1-final:docs/measurements/rail-route-0910/`
  e `train-3d-0910/` (rota em `route.json`).
- A troca de região já existe (`ProductionWorld.travel(region_id)`), base para a
  viagem rápida.

## Etapa 1 — Portar a ferrovia e o trem de carga da V1

- Trazer trilhos, viaduto da Breakwater (sobre a Rodoviária), túneis, ponte
  ferroviária e subida da serra para as regiões nativas da V2 (`NativeRegion`, chunks
  em streaming), convertendo coordenadas V1 (px) com `PlaceCatalog._at`.
- Trem de carga ambiente com a mesma composição, som e ocultação por vagão nos
  portais; passagem por baixo com transparência localizada
  (`RailUnderpassReveal.gdshader`).
- Não usar decoração genérica no lugar da estrutura (regra da migração).
- Conferir conflitos com o que mudou depois da V1: ruas editadas no MUNDO, a
  passarela da `market_street`, prédios novos, planos de túnel do canal e elevado
  da rodovia (`docs/plano-passarela-tunel-elevado-20260927.md`) — o elevado
  ferroviário e o rodoviário não podem se cruzar no mesmo nível.
- Minimapa: trilhos e símbolo do trem, fora do GPS dos carros.
- Testes: portar `test_harbor_train_3d` e `test_harbor_mountain_rail` (volta completa,
  streaming, identidade dos vagões, ruas livres sob o viaduto). Medir desempenho na
  Main renderizada (nunca headless), p50/p95/p99 em ms.

## Etapa 2 — Linha de passageiros com duas estações

- Composição de passageiros (locomotiva + 2–3 carros) em **vai e vem** entre:
  - **Estação do Porto** — perto de onde os contêineres são desembarcados (hipótese:
    porto sul, guindastes do Santa Mare; confirmar com o usuário);
  - **Estação do Cume** — alto da serra, perto do trecho da encosta nevada da V1.
- Decidir com o usuário: linha própria ou compartilhar trechos com o circuito de
  carga (se compartilhar, precisa de desvio/sinalização para não colidirem).
- Estações: plataforma, cobertura, bancos, painel de horário, iluminação; parada de
  alguns segundos, portas, som de chegada/partida. Horário previsível (a cada N
  minutos de jogo).
- Civis esperando e embarcando como ambiente (reaproveitar a ideia do
  `FootbridgeCrossers`).

## Etapa 3 — Embarque do jogador e viagem rápida

- Na plataforma, o jogador escolhe:
  - **Viajar de trem**: entra, fica sentado, câmera acompanha o percurso com a troca
    de região durante a viagem; pode descer na chegada.
  - **Viagem rápida**: tela escurece e aparece na outra estação
    (`ProductionWorld.travel`).
- Decidir com o usuário: custo da passagem e se a viagem rápida só libera depois da
  primeira viagem de trem.
- Integrar com procurado/polícia (bloquear embarque com nível alto?), save (última
  estação), HUD e mapa (ícone das estações).
- Testes no jogo real: embarcar, viajar, descer, viagem rápida nos dois sentidos,
  salvar/carregar no meio.

## Decisões pendentes do usuário

1. Local exato das duas estações.
2. Custo da passagem / liberação da viagem rápida.
3. Trem de carga continua junto ou vira um só com o de passageiros.

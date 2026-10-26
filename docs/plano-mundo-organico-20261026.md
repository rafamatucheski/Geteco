# Mundo orgânico: o jogo com a forma da maquete (26/10/2026)

Referência visual: [maquete do mapa da tecla M](design/mapa-3d-tecla-m-20261026.html). Pedido: o mundo
de verdade, e não só o mapa, deve ter aquela forma (três ilhas de costa curva, cordilheiras, praias e
penhascos), e a forma tem que aguentar o mundo crescer com as próximas regiões (Delta, Brumal). Nada foi
implementado. As afirmações sobre o código abaixo vêm de leitura em 26/10.

## Por que hoje fica quadrado

| Onde | Como a forma nasce hoje | Consequência |
| --- | --- | --- |
| Harbor | `source_data.harbor_land`: retângulos da V1 divididos por 16 (`NativeRegion`, `HarborOcean.configure`) | O mar, a espuma da margem (`shore_distance`), o muro de costa (`CoastalProtection`) e o mapa (`WorldMapData`) herdam as quinas |
| Deserto | `DesertLayout.BOUNDS`, um retângulo de 1780 × 856 m, selado por `_boundary_ridge` e `ScenarioBoundary3D.build_desert`, com as cordilheiras de horizonte (`DesertHorizon`) por fora | Não existe mar em volta; visto de cima é um bloco |
| Serra | Terreno contínuo (`MountainTerrain3D`) a partir dos registros de células, ligado à margem da ponte | Sem costa própria; termina onde terminam as células |
| Região lógica | `WorldConnection3D.logical_region`: deserto pelo retângulo; serra por `x ≥ SEAM` e um limite norte; o resto é Harbor | Já não depende da forma da costa: dá para mudar a costa sem mexer nessa regra |

Cada sistema tem a própria ideia de onde termina a terra. Por isso o mundo parece colado em pedaços.

## A ideia: uma forma de mundo só

Criar uma fonte única, a **forma do mundo** (`world/shape/WorldShape.gd` mais um arquivo de dados),
com o contorno de cada ilha como curva fechada e as zonas de costa marcadas (cais, praia, pedra,
penhasco). Todo sistema que precisa saber "aqui é terra ou mar" passa a perguntar a ela:

- **Mar:** um oceano só, para o mundo inteiro, generalizando o `HarborOcean` (que já é em pedaços e
  já calcula a distância até a margem uma vez por pedaço). As margens vêm das curvas da forma.
- **Costa:** o `CoastalProtection` vira "costa por zona". Cais reto onde há rua de porto, praia onde é
  mata ou deserto, pedras e penhasco na serra.
- **Terreno:** fora da área jogável e dentro da ilha, relevo de verdade (cordilheiras, encostas,
  praias); fora da ilha, fundo do mar. As áreas jogáveis e as estradas não mudam de lugar.
- **Mapa:** o `WorldMapData` lê a mesma forma. O mapa 2D, o mapa 3D da tecla M e o mundo passam a
  bater sempre, sem ajuste à mão.
- **Crescer:** uma região nova (o Delta, Brumal) é uma ilha nova na forma, mais a região em
  streaming. Mar, costa e mapa saem de graça.

## O que não muda

- Estradas, cruzamentos, trânsito, navegação e posições dos lugares. Elas definem o que é jogável; a
  costa nova fica em volta delas.
- As regras de região lógica e das pontes (`WorldConnection3D`), a obra da ponte norte e a progressão.
- Saves: nenhuma coordenada de lugar ou de spawn se move. Um save parado na beira de uma costa que
  mudou precisa de teste próprio (etapa 1).

## Etapas

Cada etapa é um commit próprio, com interruptor `GETECO_WORLD_SHAPE` (ou um por etapa), A/B no
export release e testes de contrato. Uma etapa só começa com a anterior aprovada no jogo.

### 0. A forma, a ferramenta e os contratos

**Feita em 26/10.** Como ficou:

- **Curvas:** `world/shape/world_shape.json`, geradas por `node tools/world_shape/generate_world_shape.mjs`
  a partir de `tools/world_shape/world_geography.json` (exportado por `tests/tools/export_world_map_data.gd`).
- **Consultas:** `world/shape/WorldShape.gd` (ilha, terra ou mar, distância à costa, tipo de costa).
- **Contratos:** `tests/test_world_shape.gd`, 18/18, agora na lista completa da `tools/run_core_suite.sh`.
- **Prévia:** `python tools/world_shape/preview_world_shape.py` grava `evidence/world-shape/preview.png`,
  com as violações em vermelho.

Ajustes que os contratos pediram em relação à maquete:

- suavização que tira penínsulas finas;
- folga do deserto de −40 para −30 m;
- terra garantida na cabeceira norte da ponte;
- um terceiro canal entre Harbor e a serra (o mais estreito tinha 29 m; agora 89 m).

A prévia saiu num PNG gerado por script, não no editor de mundo. Por isso a maquete ainda desenha a
costa pela fórmula antiga, um pouco diferente das curvas finais.

- Gerar as curvas a partir da própria maquete: o campo de distância que desenha a costa dela já
  respeita as áreas jogáveis e os canais das pontes. Extrair o contorno em polígonos suaves e gravar
  em dados.
- Prévia de cima no editor de mundo (`addons/geteco_world_editor`, que já lê `harbor_land`), para
  ajustar as curvas à mão.
- Testes de contrato: toda estrada, lugar, prédio e ponto de spawn fica em terra com folga; as duas
  pontes passam sobre água; os canais têm largura mínima; nenhuma ilha encosta na outra.
- Nada visível muda no jogo ainda.

### 1. Oceano do mundo

**Feita em 26/10.** O que entrou:

- **`world/shape/WorldSea.gd`**, montado uma vez sob a cortina e retido (`ProductionWorld`, logo antes de
  `ready_for_play`, com pré-aquecimento do material). `GETECO_WORLD_SEA=0` desliga.
- **Água:** um mar em volta de tudo, 0,2 m abaixo da água de Harbor, com a mesma faixa rasa perto da costa.
- **Chão-base:** cobre as ilhas para a vista de longe. Perto do jogador ele se esconde nas células que a
  região já montou.
- **Trechos rebaixados:** a cava, o cânion, os lagos e o canal viram fundo rebaixado ou água parada, em
  vez de buraco.
- **Harbor** continua com a terra de hoje até a etapa 3.

Verificação:

- `tests/test_world_sea.gd`: 19/19, já na suíte completa.
- Fotos de cima com `tests/capture/capture_world_sea_overview.gd`.
- Montagem em ~1,5 s, fatiada em pedaços de 5 ms.

Ficou para a etapa 2: a cordilheira sul do deserto (`DesertHorizonRelief`) passa por cima do canal entre o
deserto e Harbor, e as bordas oeste e sul das cordilheiras são retas e saem um pouco da costa.

- O mar passa a cercar as três ilhas, inclusive o deserto. Margens e espuma vêm das curvas.
- Testes: os de `test_harbor_ocean.gd` e `test_ocean_edge_equivalence.gd` adaptados à nova forma;
  save parado perto da costa carrega em terra.
- Desempenho: o oceano já é em pedaços; medir a rota da ponte e a do deserto.

### 2. Deserto ilha

**Feita em 26/10.** O que entrou:

- **Forma:** a ilha cobre todo o retângulo jogável mais 12 m. O chão do deserto e o selo de pedra são
  retangulares e continuam iguais; com a costa entrando no retângulo, o chão ficaria por cima do mar. A
  folga da serra foi para 0 para o canal entre as duas manter 40 m ou mais.
- **Cordilheiras:** as do `DesertHorizonRelief` só vão até 18 m antes da costa (menor de três raios por
  ponto, por causa das baías) e baixam onde sobra pouco espaço. A crista norte segue com ~115 m para o
  horizonte da arrancada. A sul some, porque entre o selo e o canal até Harbor não sobra espaço.
  `GETECO_DESERT_ISLAND=0` volta às antigas.
- **Faixa de praia:** o chão-base dela fica sempre à vista. Perto do jogador ela não tem chão de região
  e sem isso apareceria o vazio.

Verificação:

- `tests/test_desert_island.gd`: 4/4, já na suíte completa. Nenhum vértice fora da ilha, na praia ou
  dentro da área jogável.
- Fotos de cima e no jogo (`tests/capture/capture_desert_coast.gd`).

Limites:

- A leste a costa acompanha o selo num canal estreito até a serra. Fica reto até a etapa 4 mexer no lado
  da serra.
- Com a câmera normal a costa quase nunca entra na tela: o selo de pedra e as cordilheiras ficam na
  frente.

- Entre a área jogável e a costa: as cordilheiras viram serras de verdade dentro da ilha, com praia e
  pedra na costa. O selo (`_boundary_ridge`, `ScenarioBoundary3D`) continua segurando o jogador na
  área jogável; muda o que se vê além dele.
- Relevo novo entra em pedaços no streaming e no pré-aquecimento, como o horizonte atual.

### 3. Harbor com costa de verdade

- Troca os retângulos da V1 pelas curvas: cais reto onde o porto e as ruas encostam no mar, margem
  natural na mata a oeste, no Lago Sereno e no parque.
- É a etapa de maior risco: chão, calçadas, `HarborFacadeGround`, túnel do canal e porto leem a terra.
  Fazer bairro por bairro.

### 4. Serra ilha

- Costa com pedras e penhascos em volta do terreno da serra, mais a margem da ponte leste.

### 5. Mapa

- O mapa 2D e o 3D da tecla M passam a ler a forma; a maquete deixa de ser desenho e vira o mapa.

## Riscos

- **Desempenho:** mais terreno e mais mar à vista. Mitigar com pedaços grandes de baixa resolução
  longe do jogador e nada calculado na primeira aparição (regra do `HOW-TO-DEVELOP`).
- **Harbor:** muitos sistemas leem `harbor_land` (editor, oceano, costa, mapa, mirante, testes). A
  troca precisa ser de uma vez, com a forma nova expondo a mesma consulta que os retângulos expõem.
- **Física:** costa nova não pode criar degrau onde hoje há passagem (cais, rampas, ponte). Os testes
  de ponte e de travessia (`test_bridge_approach_terrain`, `test_native_driving`) cobrem parte disso.

## Ordem recomendada

Etapa 0 primeiro, porque não muda nada visível e responde a pergunta mais importante: se as curvas da
maquete cabem em volta de tudo que é jogável sem mover nada. Depois a 1 e a 2, que mudam mais a cara do
mundo com menos risco. A 3 por último, bairro por bairro.

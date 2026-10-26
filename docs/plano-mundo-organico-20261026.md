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

- Gerar as curvas a partir da própria maquete: o campo de distância que desenha a costa dela já
  respeita as áreas jogáveis e os canais das pontes. Extrair o contorno em polígonos suaves e gravar
  em dados.
- Prévia de cima no editor de mundo (`addons/geteco_world_editor`, que já lê `harbor_land`), para
  ajustar as curvas à mão.
- Testes de contrato: toda estrada, lugar, prédio e ponto de spawn fica em terra com folga; as duas
  pontes passam sobre água; os canais têm largura mínima; nenhuma ilha encosta na outra.
- Nada visível muda no jogo ainda.

### 1. Oceano do mundo

- O mar passa a cercar as três ilhas, inclusive o deserto. Margens e espuma vêm das curvas.
- Testes: os de `test_harbor_ocean.gd` e `test_ocean_edge_equivalence.gd` adaptados à nova forma;
  save parado perto da costa carrega em terra.
- Desempenho: o oceano já é em pedaços; medir a rota da ponte e a do deserto.

### 2. Deserto ilha

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

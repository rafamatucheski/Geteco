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

**Como entra (26/10):** `world/shape/HarborCoast.gd` lista os bairros prontos, cada um com uma zona. A
parte da ilha da forma dentro da zona vira chão natural, que entra no fim de `NativeRegion.extra_land`.
Com isso o chão físico (com colisão), o mar de Harbor, os muros da costa, a espuma, o mapa, o mar do
mundo e a cidade vista do mirante seguem juntos, sem mexer nos retângulos da V1. A faixa ganha mata
(`HarborCoastWoodland`), com as malhas e os materiais da mata do Lago Sereno. `GETECO_HARBOR_COAST=0`
volta à terra de antes. Contratos: `tests/test_harbor_coast.gd`; fotos:
`tests/capture/capture_harbor_coast.gd`.

- **Feito: mata a oeste e Lago Sereno** (zona a oeste de x = −80, o lado leste da mata). Fica um corte
  reto de 74 m na divisa com a cidade (23 m ao norte e ~50 m ao sul da mata), que some quando os
  bairros vizinhos entrarem.
- **Atenção para o porto:** a curva da forma passa por cima da bacia entre os quarteirões, onde fica o
  navio (x 200–274), e cobre a frente de cais do porto sul. Antes do bairro do porto, o gerador precisa
  recortar a bacia e seguir os retângulos como cais reto onde rua e porto encostam no mar.
- **Feito: baía norte** (do lado leste da mata até o lado oeste da cabeceira da ponte norte, x = 356).
  A zona segue as bordas norte dos quarteirões. A bacia do navio fecha ao norte num cais reto em
  z = −6,2 (estilo industrial) e continua aberta para o mar pelo sul. A coluna da ponte norte depois da
  cabeceira fica livre (`NORTH_BRIDGE_CLEAR`), e as pegadas das pontes nunca recebem chão natural. O
  corte de 23 m ao norte da mata sumiu. Fica a borda leste da cabeceira da ponte e, ao sul da mata, os
  ~50 m de antes. A costa curva nova ganha muro de pedra em vez do concreto de rodovia e da alvenaria
  urbana (`CoastalProtection`).
- **Feito: leste e parque** (da ponte norte para leste: cabeceira x = 394, quarteirão x = 422,5). A
  zona pega o lado leste do parque e o sul dele a partir de x = 480, onde a faixa até a costa é mais
  estreita. A pegada da ponte leste sai do chão natural, como a da norte. Fica uma divisa reta de ~50 m
  em x = 480, ao sul do parque, até a frente sul entrar.
- **Feito: frente sul e porto (cais reto).** O gerador ganhou zonas de cais (`QUAY_ZONES`: a frente sul
  da cidade, o porto, o canal e a boca dele). Dentro delas a costa é a borda da terra jogável (mais 0,6 m
  de folga, para duas terras com borda em comum não virarem água na emenda). A `QUAY_RAMP` (50 m) da
  zona, a curva natural volta aos poucos. A bacia do navio (x 200–273,8) é recortada (`CARVES`). O jogo lê as
  mesmas zonas (`WorldShape.quay_zones`) e não põe chão natural na frente do cais. Com isso a costa da
  mata e a do parque descem até os cantos do cais, e as divisas retas de ~50 m sumiram. A única beira reta
  fora dos bairros é o cais da bacia (74 m, de propósito). Contratos de `test_world_shape`: no cais
  basta estar em terra (tolerância de 3 m do contorno). As passarelas de 4 m sobre o canal ficam fora (mais
  finas que a grade). `foundry_avenue` conta como ponte (cruza a bacia na ponte da fundição).
- **Etapa 3 concluída.** Achado de passagem: um chão movido no editor de mundo
  (`EditorPiece_unit_harbor_-3_1_Land`, deslocado para x −173…−109, z 160…224) fica no mar ao sul da
  mata, chapado e sem muro. Existia antes da etapa 3 e está no documento do editor, não no código.

### 4. Serra ilha

**Feita em 26/10.** O que entrou:

- **Forma:** a serra pode recuar até 40 m onde não há nada, então o canal até o deserto faz curva
  (mínimo de 43 m). Trilhas, estradas e lugares da serra ficam a 14 m ou mais da costa (contrato
  novo), o que garante espaço para o muro.
- **Distância até a costa:** o gerador grava uma grade de 4 m (`distance_fields` no `world_shape.json`),
  lida por `WorldShape.field_distance`. O terreno, que roda em trabalhadores, consulta sem percorrer
  polígono.
- **Terreno (`MountainTerrain3D.shore_height`):** baixa a −0,8 m nos últimos 10 m antes da costa e
  afunda até −12 m depois dela. Célula inteira mar adentro não tem terreno; antes ele seguia sem fim
  para leste e norte.
- **Muro de pedra (`ScenarioBoundary3D.build_mountain_coast`):** acompanha a costa 5 m para dentro, com
  colisão, e abre onde passa via. Na costa só a ponte leste passa; as duas retas antigas saíram.
- **Árvores:** nenhuma a menos de 10 m da costa.
- **Comparação:** `GETECO_MOUNTAIN_ISLAND=0` volta ao terreno e aos muros antigos.

Verificação:

- `tests/test_mountain_island.gd`: 9/9.
- Foto de cima: `tests/capture/capture_mountain_island.gd`.

- Costa com pedras e penhascos em volta do terreno da serra, mais a margem da ponte leste.

### 5. Mapa

**Feita em 26/10.** O que entrou:

- **Mapa 2D (`WorldMapData`, `MapRelief`, `PaperAtlas`):** a terra do deserto e da serra é a ilha da
  forma (a serra, só com `GETECO_MOUNTAIN_ISLAND` ligado), sem o envoltório convexo de antes. O papel
  ganhou duas faixas de água rasa em volta da costa. Harbor continua com os retângulos até a etapa 3.
- **Mapa 3D (`ui/hud/MapView3D.gd`):** maquete inclinada embaixo da camada de ícones; abre em 3D e os
  botões 2D/3D do cabeçalho trocam (escolha guardada no mundo). Botão direito gira. Mar, chão-base e anel
  são as malhas do `WorldSea`, as cordilheiras são as do `DesertHorizonRelief`, o relevo da serra vem do
  terreno (altura ×6) e estradas e prédios do `WorldMapData`. Só materiais que o jogo já usa.
- **Ícones, clique e destino** continuam no `MapUI`, que troca `project`/`unproject` pelos do 3D.
- **Maquete publicada** (`docs/design/mapa-3d-tecla-m-20261026.html`) lê a costa do `world_shape.json`
  no lugar das curvas desenhadas à mão.

Verificação: `test_ui_map_contract` 62/62 (abre em 3D, girar move a projeção, arrasto segue a rotação,
2D restaura as camadas), `test_world_map_atlas` 285/285, fotos em `capture_world_map_design.gd`.

Pendente:

- **Primeira abertura do mapa:** monta o cache das malhas do 3D num quadro só. Na captura de debug,
  183 ms na primeira abertura contra 33 ms com o cache montado. O jogo está pausado com o mapa aberto,
  mas ainda falta medir em release e, se pesar, montar o cache sob a cortina.
- **Arenito:** em sessão que começa em Harbor, o material das cordilheiras pode compilar na primeira
  abertura do 3D se o deserto ainda não apareceu.

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

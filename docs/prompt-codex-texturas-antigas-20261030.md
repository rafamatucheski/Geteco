# Prompt para o Codex: prédios e pisos com textura antiga (30/10/2026)

Cole o bloco abaixo no Codex. Ele faz **um lote por vez** e para. Para seguir, mande
"continue com o lote N".

---

Você vai trabalhar no repositório `D:\geteco\game` (Godot 4.7.2 .NET, ramo `jolt`). Antes de tudo, leia
`CLAUDE.md`, `AGENTS.md` e `docs/HOW-TO-DEVELOP.md`. Siga as regras deles: Godot só pela fila
`tools/run_godot_locked.sh`, material novo entra no pré-aquecimento (`PaintedFacadePrewarm` ou
equivalente), textura nova em BC7 com mipmaps, nada pesado num quadro só, commit com stage explícito
e mensagem em português, sem push.

## Objetivo
Trocar o visual antigo (material de cor lisa, ladrilho procedural 64×64 gerado em código, modelo da V1)
pelo padrão novo do jogo, e corrigir escala e pisos ruins. **Não mude jogabilidade, portas, entradas,
interiores jogáveis nem colisão, exceto onde o item pedir.**

## Padrão novo a copiar (referências)
- Fachada de lugar com porta: `world/places/bars/PaintedBarFacade.gd`, usado em `HarborBarFacade.gd:11-15`
  (`PAINTED.available(style)`, depois `PAINTED.build`).
- Prédio do catálogo: `PaintedHarborHouses.gd` (HARBOR/LOWRISE) e `PaintedFacadeKit.build`. Prédio alto:
  `PaintedTallBuildings.gd`.
- Interior: `world/mountain_detail/MountainInteriorFinish.gd`, como em `FireStationArt3D.gd` (commit bc30494d).
- Piso: `world/urban_detail/HarborPaving.gd` (PNGs em `assets/materials/harbor_paving/`),
  `HarborStreetWear.gd`, `SidewalkFill.gd`.
- Posto de escala correta: `runtime/desert/roadside/RoadsideBuild.gd:227` (Posto Sol Poente). Cobertura de
  14×9 m, pilares em 12×6 m, altura livre de 4,6 m, loja pintada, pátio de concreto com juntas.
- Estilos de fachada pintada ficam em `assets/facades/` (`*.json` + atlas). Para estilo novo, gere a arte
  como foi feito para os bares (c6130b3f) e registre no catálogo.
- Toda troca fica atrás de um interruptor `GETECO_PAINTED_*` ou similar já existente, para A/B (o
  padrão é o visual novo ligado).

## Lotes (faça só o lote pedido)

### Lote 1: posto gigante e piso do parque
1. **Posto do Tonico, na Vila dos Caminhoneiros** (oeste do Harbor, `ORIGIN (-330,0,108)`):
   `gameplay/urban_v1/TruckersVillageVisuals.gd:143-196`, com `STATION_BASIS` na linha 11 (escala não
   uniforme 0,78/0,8/0,74).
   - Hoje: pilares de ≈25×13,3 m, cobertura de ≈27,3×15,5 m, 2 bombas a 13,3 m, pátio de ≈32×21,5 m.
   - Refazer em escala real: cobertura de ~14×9 m, bombas a ~5 m, altura livre de 4,5–4,8 m, escala
     uniforme 1 (não achatar bombas, banco e Label3D).
   - Ajustar junto: pátio, `_solid` "CanopyPost" e "MechanicalPump", `set_cutaway` (`Rect2(-48,-27,41,29)`,
     linha 94) e a loja `PaintedTonicoShop` (18,7 m de largura → proporcional à cobertura nova).
   - A colisão "TonicoShop" (2,56 m) precisa cobrir a altura da parede pintada (2,9 m).
   - Cobertura, pilares, bombas e placa: material/estilo pintado como o Sol Poente.
2. **Piso do Parque Lume** (`world/places/amusement_park/ParkLumeGround.gd`, `ORIGIN (-176,0,78)`).
   - Hoje: o piso é a textura procedural "stone" de `ShopInteriorMaterials`, posto por cima do mato sem
     recorte, com a borda a 1 mm do chão (`MEADOW_TOP = .001`), arriscando z-fight.
   - Trocar pelos PNGs de `HarborPaving`.
   - Furar o chão do Harbor sob o parque, como a skate faz (`SkateParkLayout.outside` em
     `NativeRegion.gd:1606`), para o mato não ficar desenhado por baixo.
   - Dar à borda uma transição de verdade, sem plano a 1 mm do chão.

### Lote 2: rua North Frontage (a avenida mais vista; z≈9, x 40–175)
Cada um ganha estilo pintado próprio, montado como `HarborBarFacade`:
- Curitiba Cellar: `world/places/curitiba_cellar/CuritibaCellarFacade.gd` + `CellarGeometry.gd`. O letreiro
  Label3D vira letreiro pintado.
- Posto/Conveniência "Fuel": `UrbanLandmarkFrontage3D.gd:141-166`, prédio NorthFrontage4. Crie um estilo
  como `posto-deserto` (`DesertArchitecture.gd:15-38`). As bombas V1 (`_build_v1_fuel_pump`, linha 248)
  viram as bombas do padrão novo.
- Union, a loja de roupas: `UrbanLandmarkFrontage3D.gd:98`.
- Ammu-Nation do Harbor: NorthFrontage2, modelo V1 `AmmunationFacade3D.gd`. Faça a versão do porto a
  partir do `ammunation-serra`.
- Boa Praça: `world/places/supermarket/SupermarketFacade.gd` + `MarketGeometry.gd`.
- Fagulha, o fliperama: `world/places/arcade/ArcadeFacade.gd`.

### Lote 3: pisos antigos do Harbor e da vila
- Piso do porto sul: `NativeRegion.gd:1872-1904` (`_authored_surface` "OriginalPortSurface",
  `Color("737b69")`) → `HarborPaving.material(..., "quay")`.
- Pisos do editor em concrete/asphalt/pavers: `WorldGroundFactory.gd:38-52` (procedural 64×64) →
  PNGs de `HarborPaving` com o mesmo UV de mundo. Inclui o calçadão `paving/5` (53,108).
- Pátio da Vértice: `gameplay/urban_v1/VerticeCompany.gd:92-94`, 100×108 m de cor lisa a y .014 →
  pátio com textura de concreto/asfalto industrial, juntas e faixas pintadas.
- Pisos da vila (`TruckersVillageGround.gd`): o pátio e o chão da borracharia usam o concrete procedural;
  os retalhos de terra estão em y fixo sobre o mato.
- Os PNGs de `harbor_paving` estão em BC1 (`compress/high_quality=false`). Passe para BC7.

### Lote 4: prédios do editor e outros prédios antigos do Harbor
- Prédios do editor sem estilo (`world/editing/world_edits.json` → `UrbanSkylineBuilding.gd`). Dê estilo
  por id em `PaintedTallBuildings`/`PaintedHarborHouses`:
  - `new_1790426066…` (-0.1,92)
  - `new_1790426877…` (-2.6,109)
  - `new_1790432139…` (5,30)
  - `new_1790432236…` (278.8,-84)

  Atenção: esses prédios agora estão no cache de registros (`NativeRegion._is_static_editor_skyline`,
  commit e0b641c62). Confira que o visual pintado entra no cache.
- FoundryLofts: `UrbanLShapedBlock.gd:20`.
- Eastgate Hotel (NorthbankFront3): cena assada antiga.
- MotorWorkshop: `UrbanServiceBuilding.gd:53,274`. Já existe o estilo `oficina-mecanica`.
- Residências compráveis: `ResidenceExterior3D.gd` + garagens em `ResidenceParking.gd`.
- Casa do Zelador / cemitério: `CemeteryHouseExterior3D.gd`.
- Porto sul V1: PortBuilding4, Santa Mare Wheelhouse, guindastes e paletes (`OriginalSouthPort.gd:13-24`).
- Vila dos Caminhoneiros: borracharia do Zeca (`TruckersVillageVisuals.gd:209-243`, copie o
  `rust_sheet` do Sol Poente), ferro-velho, carroça e cercas.
- Parque: barracas, cerca e trilho (`ParkGeometry.gd:25-31`) e a fachada externa da casa Umbra. O
  interior da Umbra, com JPGs, é a referência.

### Lote 5: interiores antigos
Troque as caixas de cor lisa por `MountainInteriorFinish` com textura real, como em `FireStationArt3D.gd`:
- Fuel: `FuelStoreArt3D.gd`
- Bay Medical: `HospitalRoom3D.gd`
- Delegacia: `HarborPoliceStation3D.gd`
- Residências: `ResidenceInterior3D.gd`
- Curitiba Cellar: `CuritibaCellarInterior.gd`
- Fagulha: `ArcadeInterior.gd`
- Boa Praça: `SupermarketInterior.gd`
- Paredes e chão dos bares (`HarborBarModel.gd:8-12`)

Não mude layout, móveis interativos, balcões nem pontos de interação.

## Limites (obrigatórios)
- **Só o lote pedido.** Ao terminar o lote, **pare** e entregue o relatório. Não comece o próximo sozinho.
- **Tempo:** no máximo 3 h por lote.
- **Testes:** só estes, cada um no máximo 2 vezes por lote:
  - `tools/run_core_suite.sh`, uma vez no fim do lote;
  - os 4 da seção "Verificação" do CLAUDE.md;
  - testes já existentes que citem os arquivos tocados (procure com grep).
- **Capturas:** no máximo 1 por prédio ou piso alterado, antes e depois, em `evidence/` (fora do Git).
- **Medição:** nenhuma bancada de desempenho, nenhuma matriz A/B e nenhum export, salvo se o usuário
  pedir. Só confira que nenhum material novo ficou fora do pré-aquecimento (grep dos materiais criados
  contra `PaintedFacadePrewarm`).
- **Parada:** se algo falhar 2 vezes do mesmo jeito, ou se um item exigir mudar jogabilidade ou
  colisão fora do que está escrito, **pare** esse item, siga com os outros e explique no relatório.
- **Arquivos:** só os arquivos dos itens do lote, mais os estilos/atlas novos em `assets/facades/` e o
  pré-aquecimento. Arquivo que você não criou e tem timestamp recente é de outra sessão: não toque.
- **Commit:** um por item, ao fim do item, só com os arquivos dele.

## Relatório (formato fixo, no fim de cada lote)
1. Itens feitos: arquivo:linha, o que era, o que ficou e o hash do commit.
2. Itens não feitos e por quê.
3. Testes rodados e resultado, com a saída das falhas.
4. Capturas: caminhos.
5. O que o usuário deve olhar no jogo, com o lugar e as coordenadas.

# Migração de modelos e mecanismos do cenário — V1 → V2

Estado desta rodada: implementação parcial e inspeção estática. Godot, testes e benchmark não foram executados por restrição explícita da rodada; colisão, oclusão, comportamento e desempenho permanecem sem validação em runtime.

## Fontes V1 produtivas confirmadas

- `project.godot` → `ui/MainMenu.tscn` → `ui/MainMenu.gd` → `world/harbor/HarborGame.tscn`: confirma a entrada produtiva V1.
- `world/harbor/HarborPreview.tscn`: fonte efetiva dos prédios registrados em `geteco_v2/world/regions/OriginalWorldData.json`.
- `world/harbor/HarborWaterfront.gd` e `world/harbor/HarborPortModel3D.gd`: guindastes, armazéns, contêineres e cargueiro produtivos. O V2 já os conecta por `OriginalSouthPort.records()` → `NativeRegion._prepare()` → `OriginalSouthPort.mount()`; não foram duplicados.
- `world/harbor/ContinuousWorld.gd` → `MountainPass.tscn` → `MountainPass.gd`: confirma a serra como região produtiva conectada.
- `world/mountain_pass/MountainSceneryBuilder.gd:build_detailed_sawmill()`: fonte da serraria e da picape de trabalho em `(120, 30)`, rotação `-0.25`, cor `#576574`.
- `world/mountain_pass/MountainSkiArea.gd:_build_lift()`, `MountainSkiLayout.gd`, `MountainChairliftTower3D.gd` e `MountainChairliftChair3D.gd`: fontes das quatro ancoragens do cabo, duas torres, duas estações e cinco cadeiras móveis.
- `world/mountain_pass/MountainSettlement.gd`: consultado para conferir o povoado; o V2 já usa `OriginalVillageArchitecture.gd` no registro conectado `mountain_village`, portanto não foi criada uma segunda versão.

## Implementado e conectado

`StaticSawmillWorkTruck3D.gd` reutiliza o modelo V2 preparado `assets/fleet/lumber_pickup_4x4.scn`, aplica a cor original e cria um sólido estático sem instanciar `Vehicle.gd` nem simulação. A cadeia efetiva é:

`ProductionWorld.build()` → `NativeRegion.build_region("mountain")` → registro `sawmill_yard` → `MountainDetailFactory.populate_sawmill_chunk()` → `build_sawmill()` → callback `ready` → `EnvironmentalParityFactory.attach_sawmill()`.

O objeto acompanha o lifecycle do chunk da serraria e não executa trabalho por frame.

## Implementado, aguardando integração autorizada

`MountainChairliftParity3D.gd` contém o teleférico nativo: cabo duplo, duas torres com sólidos apenas nas bases, duas estações com sólidos nos postes e cinco cadeiras nos mesmos progressos/direções do V1. `set_animation_active(false)` suspende o processamento; o chunk deve chamar essa API quando ficar dormente. `set_operating(false)` preserva a regra operacional sem avançar cadeiras.

`MountainDetailFactory.get_environmental_records()` e `populate_environmental_chunk()` já expõem o contrato. Para conectá-lo, o integrador deve editar exclusivamente `geteco_v2/world/regions/NativeRegion.gd`:

1. Em `_prepare()`, dentro de `if region_id == "mountain":`, depois dos registros `sawmill_yard` e `mountain_village`, adicionar:

   ```gdscript
   for record in MOUNTAIN_FACTORY.get_environmental_records():
       _record(record.position, record)
   ```

2. No `match record.kind` da população de chunks, junto de `sawmill_yard` e `mountain_village`, adicionar:

   ```gdscript
   "environmental_parity": MOUNTAIN_FACTORY.populate_environmental_chunk(chunk, record)
   ```

3. No controlador que já possui `session.weather`, ajustar a operação somente em mudança de faixa horária, usando o contrato produtivo V1 (aberto das 08:00 às 18:00):

   ```gdscript
   lift.set_operating(hour >= 8.0 and hour < 18.0)
   ```

Não foi feita essa edição porque `NativeRegion.gd`, `ProductionWorld.gd` e o controlador de sessão estão fora do escopo exclusivo desta rodada.

## Diferenças não transformadas automaticamente em obrigação

- Cenas legadas que não aparecem na cadeia `MainMenu → HarborGame → ContinuousWorld/MountainPass` foram ignoradas.
- O porto V2 já monta as fontes originais por registro; uma segunda camada de guindastes ou armazéns causaria duplicação.
- Não foram criados estabelecimentos, slogans, categorias ou placas descritivas. Os nomes próprios existentes continuam sob `UrbanBuildingFactory`/`UrbanSignage`.
- Não foram alterados personagens, combate, terreno, vegetação, `NativeRegion.gd`, `ProductionWorld.gd` ou arquivos do Claude.

## Validação pendente

- Confirmar em Godot que a picape aparece uma única vez, na pose original, sem bloquear a entrada, pilhas de madeira ou circulação de trabalhador.
- Validar separadamente colisão física e oclusão da picape, bases das torres e postes das estações.
- Depois da integração, percorrer base, torres e cume para conferir escala, altura do cabo, movimento, inversão de sentido, suspensão fora de operação e descarregamento/reentrada do chunk.
- Comparar frame time antes/depois na cena real renderizada da serra, com a mesma rota, câmera, clima, população e configuração. Registrar p50/p95/p99, máximo e frames acima de 33,3/66,7 ms. Sem essa medição, desempenho não está aprovado.
- Executar validação funcional proporcional após a integração. Nenhum teste foi executado nesta rodada.

## Rodada urbana conectada — fileira norte acessível

Em 21/09/2026, uma rodada independente completou três substituições que já podiam usar os registros produtivos existentes, sem editar `NativeRegion`, `ProductionWorld`, terreno ou interiores compartilhados.

`UrbanBuildingFactory` agora seleciona `UrbanLandmarkFrontage3D` para:

- `NorthFrontage0` / `harbor_bank`: fachada North Pier derivada de `BankFacade.gd`, com quatro colunas, duas ATMs, glazing, pedimento e claraboia;
- `NorthFrontage3` / `harbor_clothing`: fachada Union derivada de `UnionClothingFacade.gd`, com porta recuada e dois manequins vestidos completos;
- `NorthFrontage4` / `harbor_fuel`: loja e duas bombas derivadas de `HarborRobberies.gd`, preservando offsets `(-70,140)` / `(70,140)` pixels.

O modelo usa somente quatro sólidos arquitetônicos por prédio. Detalhes pequenos permanecem visuais. A execução de `NativeRegion("harbor")` confirmou os três nós especializados, `place_id`, entrada autorada e aproximação livre; oclusão com controle positivo também passou nos três. Capturas isoladas e integradas estão em `C:/Users/rafae/.codex/visualizations/2026/09/21/01a0c59c-dd86-7e80-affd-f22d2af9af60/`.

Ammu-Nation foi corrigida atomicamente pelo integrador: V1 e V2 agora usam `NorthFrontage2` em `(1550,140)`, e catálogo, `place_ids`, seleção de modelo, placa, entrada e retorno concordam. `NorthFrontage1` voltou a ser Foundry Flats. O contrato dirigido passou 14 verificações; falta comparação renderizada equivalente.

O teste urbano agora monta os 61 prédios sem falhas: as alcovas são verificadas até a porta real e a contagem distingue os três modelos próprios do JSON da casa do zelador, que é somente catálogo. Desempenho não foi medido porque outra instância Godot já estava ativa; permanece não aprovado.

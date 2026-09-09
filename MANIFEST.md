# GETECO — manifesto da consolidação estrutural

Data da consolidação: 2026-09-03  
Escopo: Parte 0 — árvore estável, referências e boot.  
Gameplay: não alterado intencionalmente.

## Origem

A árvore foi criada por cópia de
`D:\geteco\qa_gameplay_snapshot` para `D:\geteco\game`, sem substituir nem
remover nenhuma árvore anterior.

Base escolhida porque é a única árvore inspecionada em que o entrypoint reúne o
mundo expandido, campanha e restrições de distrito. A cena principal permanece
idêntica à origem; `project.godot` recebeu somente a correção estrutural de
entrypoint documentada abaixo:

| Arquivo | SHA-256 da origem | SHA-256 consolidado |
| --- | --- | --- |
| `project.godot` | `7A0D638CC3358B817A529861B1D5969593BF2D9948BB6ECCD831318FAA22B6FD` | `24354CC3418E40E395CF132CD6B26E9B00A68FE01AF0D5ED6FBC9E003D5CD2B7` |
| `Main.tscn` | `0D763B5CA8D8EBDD72BBB56E63EFAF948C0125D8B039BF337FE9DE0C0FE4EC5A` | `0D763B5CA8D8EBDD72BBB56E63EFAF948C0125D8B039BF337FE9DE0C0FE4EC5A` |

Inventário consolidado antes deste manifesto e sem `.godot`: 423 arquivos, 103
scripts GDScript, 46 cenas e 82 assets visuais/sonoros.

## Exclusões deliberadas da cópia

Os itens abaixo continuam preservados na árvore de origem e não fazem parte do
produto estável:

- cache `.godot` e `__pycache__`;
- subpasta `tests` e scripts `Qa*.gd`/`.uid`;
- scripts Python de auditoria, busca, limpeza e teste;
- `BAIRRO_1_POPULATION_REPORT.md`;
- imagens de recorte sem referência no runtime: `door_crop_test.png`,
  `v5_crop.png` e seus sidecars `.import`;
- o projeto independente `prototypes/dante_3d`, que causava aviso de projeto
  Godot aninhado durante o reimport;
- a cópia duplicada `scenes/ShopInterior.tscn`. Ela tinha o mesmo hash e UID de
  `interiors/ShopInterior.tscn`; todas as referências executáveis usam a cena em
  `interiors`.

## Deltas integrados

### Entrypoint independente do cache de UID

O QA reproduziu em execução fria o alerta
`Main scene's path could not be resolved from UID`, que não aparecia no log e
podia encerrar com código 0. A causa era
`run/main_scene="uid://cy8k5f4n8g7e"` em `project.godot`.

O entrypoint agora é `run/main_scene="res://legacy/Main.tscn"`. Assim, a cena inicial não
depende do mapeamento de UID em `.godot`. A alteração não troca a cena nem muda
gameplay.

### UID do poste

O reimport frio revelou que `StreetLamp.tscn` declarava o UID fictício
`uid://d3m0lamp4912` para `StreetLamp.gd`. Ele foi alinhado ao sidecar real,
`uid://dpexv0kdelf08`.

Hash final de `StreetLamp.tscn`:
`ADFC35D82BB5A799ED8411FF4C91F2C921C24041A1B55AC2162925D704BC8935`.

### Referências de veículo de missão

Origem da evidência:
`D:\geteco\qa_audit_snapshot_20260902\MissionManager.gd`, que usa a cena real
`res://world/shared/traffic/TrafficVehicle.tscn`.

Alterações mínimas em `MissionManager.gd`:

- duas referências incorretas a
  `res://legacy/city_demo/scripts/TrafficVehicle.tscn` passaram para
  `res://world/shared/traffic/TrafficVehicle.tscn`;
- o fallback para `res://PlayerCar.tscn`, que não existe, foi substituído por
  erro explícito e retorno. Com a estrutura válida, esse ramo não é executado.

Hash final: `92E548AC402B1EFD55EA9C943D8113AB3C8C05B8ADD65B7FCFCAB5D1A440118E`.

### Boot headless do Jäger

Origem do delta:
`D:\geteco\qa_audit_snapshot_20260902\JagerNPC.gd`.

O primeiro smoke da árvore consolidada reproduziu
`Parameter "scenario" is null` em `JagerNPC.gd:78`. Foi incorporada exatamente a
proteção já auditada: o `World3D` exclusivo só era atribuído quando o display não
era `headless`.

O QA independente então executou Vulkan e provou que essa guarda apenas ocultava
o erro do gate técnico: a atribuição manual de um novo `World3D` também invalidava
o cenário no renderer visual. A correção final mantém `own_world_3d = true` e
configura o `Environment` no mundo válido já pertencente ao `SubViewport`, obtido
por `find_world_3d()`. Não há mais substituição do mundo depois que o viewport
entra na árvore.

Hash final de `JagerNPC.gd`:
`D53FE67B18F6C25313B1A5ADC803963995E9230BBAD6E880724BB20873D71211`.

Nenhum outro delta de código foi incorporado.

## Validação executada

Engine: Godot `4.7.2.stable.official.ed1daf0bf`.

1. Remoção validada somente de `D:\geteco\game\.godot`.
2. Reimport frio em modo editor/headless:
   `--headless --editor --path D:\geteco\game --quit`.
3. Execução normal do entrypoint por 180 frames:
   `--headless --path D:\geteco\game --quit-after 180`.
4. Busca explícita nos dois logs finais por `ALERT`, falha de resolução da Main,
   `Aborting`, `SCRIPT ERROR`, `Parse Error`, falha de recurso/script e avisos
   estruturais de UID: zero ocorrências.
5. Varredura estática de `preload`, `ext_resource`, ícone e autoload:
   `HARD_RESOURCE_REFS_MISSING=0`.

Logs:

- `D:\geteco\runtime_audit\part0\canonico\game-reimport.log`;
- `D:\geteco\runtime_audit\part0\canonico\game-smoke-before-boot-fixes.log`;
- `D:\geteco\runtime_audit\part0\canonico\game-reimport-after-boot-fixes.log`;
- `D:\geteco\runtime_audit\part0\canonico\game-smoke-after-boot-fixes.log`;
- `D:\geteco\runtime_audit\part0\canonico\game-smoke-exitcheck.log`;
- `D:\geteco\runtime_audit\part0\canonico\game-smoke-verbose.log`;
- `D:\geteco\runtime_audit\part0\canonico\game-cold-normal-entrypoint-after-path-fix.log`;
- `D:\geteco\runtime_audit\part0\canonico\game-final-cold-reimport.log`;
- `D:\geteco\runtime_audit\part0\canonico\game-final-normal-entrypoint.log`;
- `D:\geteco\runtime_audit\part0\canonico\game-jager-own-world-headless.log`;
- `D:\geteco\runtime_audit\part0\canonico\game-jager-own-world-vulkan.log`;
- vídeo Vulkan: `D:\geteco\runtime_audit\part0\canonico\game-jager-own-world-vulkan.avi`.

Resultado: `Main.tscn` carrega e instancia Centro, estacionamento das docas,
expansão, rede viária, conexões, densidade, serviços e população do Bairro 1 sem
erro de script ou recurso. O comando encerrou com código 0.

Uma execução normal sem nenhum reimport prévio confirmou que o novo caminho da
Main elimina o alerta, mas também confirmou que este projeto-fonte precisa de uma
etapa de importação para registrar `class_name` e converter assets. Sem essa etapa,
Godot não cria `.godot` automaticamente em modo headless e produz erros de classe
e texturas. Esse teste reprovado foi preservado no log
`game-cold-normal-entrypoint-after-path-fix.log`; ele não é contado como passe.
Após o reimport frio, o smoke normal passou. O cache gerado pelo reimport foi
mantido para o reteste independente do QA.

Após a correção final do Jäger, foram executados 180 frames headless e 30 frames
com Vulkan Forward+ em 1280×720. Ambos encerraram com código 0, e a busca nos
dois logs retornou zero ocorrências de `scenario is null`, `SCRIPT ERROR`, erro de
parse/carregamento, alerta, abort ou aviso estrutural de UID. O vídeo local é
somente evidência do executor; a aprovação visual continua reservada ao QA
independente.

O log ainda contém dois fatos que não devem ser apresentados como aprovação
limpa:

- `Failed to read the root certificate store`, limitação do ambiente isolado;
- 2 instâncias `AudioStreamGeneratorPlayback` vazadas durante o encerramento
  forçado do smoke. Não impedem o boot, mas devem continuar abertas para QA.

Este smoke comprova estrutura e inicialização, não qualidade de IA, física,
tráfego, escala ou visual final.

## Recursos do runtime antigo ainda não migrados

Comparação: exclusivos de `D:\geteco\.godot-migration-staging` em relação a
`D:\geteco\game`, omitindo somente sidecars `.uid`. São 81 arquivos e nenhum foi
copiado automaticamente.

### Arte de normal map

- `city_demo/art/building-atlas-normal.png`
- `city_demo/art/building-atlas-normal.png.import`
- `city_demo/art/vehicle-atlas-normal.png`
- `city_demo/art/vehicle-atlas-normal.png.import`

### Perfis de bairro

- `city_demo/data/bairros/centro.tres`
- `city_demo/data/bairros/colinas.tres`
- `city_demo/data/bairros/docas.tres`
- `city_demo/data/bairros/industrial.tres`
- `city_demo/data/bairros/residencial.tres`

### Encomendas

- `city_demo/data/encomendas/centro_coupe_neon.tres`
- `city_demo/data/encomendas/centro_executivo_preto.tres`
- `city_demo/data/encomendas/centro_importado_centro.tres`
- `city_demo/data/encomendas/centro_taxi_fantasma.tres`
- `city_demo/data/encomendas/colinas_coupe_dourado.tres`
- `city_demo/data/encomendas/colinas_rival_numero_um.tres`
- `city_demo/data/encomendas/colinas_supercar_falcao.tres`
- `city_demo/data/encomendas/colinas_suv_blindado.tres`
- `city_demo/data/encomendas/docas_cavalo_aco.tres`
- `city_demo/data/encomendas/docas_container_azul.tres`
- `city_demo/data/encomendas/docas_exportacao_zero.tres`
- `city_demo/data/encomendas/docas_van_alfandega.tres`
- `city_demo/data/encomendas/industrial_carga_fria.tres`
- `city_demo/data/encomendas/industrial_mula_cinza.tres`
- `city_demo/data/encomendas/industrial_turno_noturno.tres`
- `city_demo/data/encomendas/industrial_van_ferrugem.tres`
- `city_demo/data/encomendas/residencial_carro_domingo.tres`
- `city_demo/data/encomendas/residencial_hatch_vizinho.tres`
- `city_demo/data/encomendas/residencial_perua_escolar.tres`
- `city_demo/data/encomendas/residencial_suv_quadra.tres`

### Mapa autoral e população

- `city_demo/data/mapa/AuthoredNeighborhoodData.gd`
- `city_demo/data/mapa/AuthoredNeighborhoodDataValidation.gd`
- `city_demo/data/population/centro.tres`
- `city_demo/data/population/colinas.tres`
- `city_demo/data/population/docas.tres`
- `city_demo/data/population/industrial.tres`
- `city_demo/data/population/residencial.tres`
- `city_demo/population/NeighborhoodPopulation.gd`
- `city_demo/population/NeighborhoodSecurity.gd`
- `city_demo/population/SecurityFallbackVehicle.gd`
- `city_demo/scripts/BairroStreamer.gd`
- `city_demo/scripts/FixedMapDefinition.gd`

### Rivais

- `city_demo/data/rivais/01_rei_do_asfalto.tres`
- `city_demo/data/rivais/02_dama_de_aco.tres`
- `city_demo/data/rivais/03_mare_baixa.tres`
- `city_demo/data/rivais/04_estivador.tres`
- `city_demo/data/rivais/05_taximetro.tres`
- `city_demo/data/rivais/06_neon.tres`
- `city_demo/data/rivais/07_sem_placa.tres`
- `city_demo/data/rivais/08_chave_mestra.tres`
- `city_demo/data/rivais/09_ferro_velho.tres`

### Perfis de veículo

- `city_demo/data/vehicles/cargo_van.tres`
- `city_demo/data/vehicles/city_taxi.tres`
- `city_demo/data/vehicles/executive_sedan.tres`
- `city_demo/data/vehicles/family_hatch.tres`
- `city_demo/data/vehicles/family_sedan.tres`
- `city_demo/data/vehicles/family_suv.tres`
- `city_demo/data/vehicles/family_wagon.tres`
- `city_demo/data/vehicles/heavy_truck.tres`
- `city_demo/data/vehicles/light_truck.tres`
- `city_demo/data/vehicles/luxury_suv.tres`
- `city_demo/data/vehicles/sports_coupe.tres`
- `city_demo/data/vehicles/utility_pickup.tres`

### Contrato de recursos e entrega

- `city_demo/missions/DeliveryZone.gd`
- `city_demo/missions/DeliveryZone.tscn`
- `city_demo/resources/Bairro.gd`
- `city_demo/resources/Encomenda.gd`
- `city_demo/resources/NeighborhoodProfile.gd`
- `city_demo/resources/Rival.gd`
- `city_demo/resources/VehicleProfile.gd`
- `OrderBoard.gd`
- `OrderBoard.tscn`
- `RankingManager.gd`

### Validações antigas preservadas apenas na árvore anterior

- `city_demo/tests/campaign_ui_validation.gd`
- `city_demo/tests/combat_scale_validation.gd`
- `city_demo/tests/map_streaming_validation.gd`
- `city_demo/tests/mission_validation.gd`
- `city_demo/tests/navigation_validation.gd`
- `city_demo/tests/population_validation.gd`
- `city_demo/tests/ranking_rivals_validation.gd`
- `city_demo/tests/traffic_validation.gd`
- `city_demo/tests/ValidationHelpers.gd`

## Estado de promoção

`D:\geteco\game` é agora a árvore estável para continuar a Parte 0, mas os
launchers permanecem deliberadamente inalterados. A promoção para o usuário só
deve ocorrer depois do novo reteste independente do runtime consolidado e decisão
explícita sobre os 81 arquivos antigos ainda não migrados. Este manifesto não
marca a promoção como aprovada.

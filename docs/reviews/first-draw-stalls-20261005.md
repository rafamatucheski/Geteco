# Draws de 47–68 ms na primeira passagem/eventos — 05/10/2026

## Resumo

Os draws de 55–60 ms com CPU principal ~0 das capturas rec2/rec3 (f651, f1284; f748, f2065, f11673)
são **compilação de versões novas de `SceneForwardMobileShaderRD` com cache ShaderRD frio**, em
variantes de material de **veículo** que só passam a existir em jogo. A thread principal espera os
workers da compilação dentro do desenho (`_compile_version_end`), por isso a CPU contabilizada é ~0.
Não é pipeline/ubershader (contador `draw` de pipelines não sobe nesses quadros; sobem só `surface`
/`specialization`, que acompanham a versão nova), nem upload de textura/malha.

Correção: `gameplay/vehicle_effects/VehicleMaterialVariantPrewarm.gd` desenha sob a cortina, durante
três quadros, cópias das variantes reais (mesmas flags) e as retém. No A/B renderizado com cache frio,
**os draws ≥25 ms depois de READY foram 18 nos 4 braços sem preparo e 0 nos 2 braços com a correção
completa**. Custo deslocado para o loading: 0,46–0,47 s de wall nessa etapa (cache frio).

Isto não aprova FPS global: ver "O que não foi medido".

## Atribuição

O cache ShaderRD grava `<chave>.vulkan.cache` ao terminar a compilação, dentro do quadro que trava.
Comparando o mtime das chaves com o `unix_seconds` do READY (`evidence/first-draw-stalls-20261005/analyze_first_draw_ab.py`):

| Captura | Draw (READY +s, ms) | Chave gravada (READY +s) |
|---|---|---|
| rec2 f651 / f1284 | 0,588 / 56,4 · 3,341 / 58,0 | `0af590d5` 0,662 · `502cb30b` 3,405 |
| rec3 f748 / f2065 / f11673 | 1,312 / 55,3 · 8,454 / 59,7 · 73,128 / 55,8 | `502cb30b` 1,396 · `0af590d5` 8,521 · `f24a1c0a` 73,189 |

As duas capturas eram frias (`shader-cache-preparation.json`: `cold_fresh_user`, 0 arquivos), como as
do protocolo antigo sem seed. Com o seed congelado (`shader-cache-b1/b2`) esses draws já sumiam; o
problema real é a primeira execução / cache invalidado (driver ou versão do motor nova).

Para saber **qual material** gera cada chave criei `tests/measure/ShaderFirstUseProbe.gd`
(`HARBOR_SHADER_PROBE=1` no runner): lista o diretório do cache a cada quadro e, quando aparece chave
nova, mostra as assinaturas de material (bools/enums/presença de textura, que formam a MaterialKey)
vistas pela primeira vez nos 3 quadros anteriores. É só diagnóstico: a listagem custa ~1,7 ms/quadro
(21 s somados em cada execução de 150 s), então essas execuções não servem para frame time.

| Chave | Material | Origem |
|---|---|---|
| `502cb30b` | pintura `paint` com `detail_enabled`, `detail_albedo`, `uv2_triplanar` | `VehicleUsage.apply` (sujeira de uso, carro civil) |
| `0af590d5` | mesma pintura com `detail_enabled=false` mas textura+triplanar mantidos | carro reaproveitado: sujo e depois identidade limpa |
| `10b0b8ea` | pintura com desgaste (coberta pelas variantes; gravada no loading do braço B) | `VehicleDamage._stall_apply_wear` |
| `f24a1c0a` | vidro `glass` translúcido (`transparency=ALPHA`, textura, clearcoat) do arctic_jeep | `VehicleInterior.see_through` via o `WarmUp` de runtime |
| `3d4ae273` | brasa da carcaça (`albedo`+`emission` com textura, `EMISSION_OP_MULTIPLY`, `uv1_triplanar`) | `VehicleDamage._stall_wreck` |
| `bdce03ad` | não atribuída (recuperação; draws ≤27 ms quando apareceu) | — |

Evidência: `first-draw-diag-01` (projeto vivo, sem correção: `502cb30b` f611 draw 58,6 ms;
`0af590d5` f1999 draw 56,7 ms), `first-draw-diag-02` (`3d4ae273`, f10085 draw 45,0 ms) e
`first-draw-diag-03` (`f24a1c0a`, f8727 draw 62,4 ms). As duas últimas rodaram já com a preparação da
pintura e mostraram o que sobrava. Pastas em `evidence/intermittent-stalls-20261004/first-draw-*`
(locais, fora do Git).

## Correção

- `VehicleMaterialVariantPrewarm.collect(model, id)` é chamado no laço que já cria e desenha cada
  modelo decorado da frota (`ProductionWorld._prewarm_fleet_shaders`): liga um `VehiclePaint` ao
  modelo descartável e guarda as pinturas base (3 assinaturas distintas) e os vidros translúcidos via o
  próprio `VehicleInterior.see_through` (4), que já tem cache. Nenhum modelo extra é criado.
- `run()` (depois de `PoliceVisualPrewarm`, sob a cortina, com as mesmas guardas de
  `EffectsPrewarm`) gera, por base: suja, suja→limpa, sem verniz (desgaste ≥40%) e amassada (estágio
  2+, só pintura sem textura); acrescenta os vidros e os materiais de `VehicleDamage.wreck_materials()`.
  Deduplica por assinatura, desenha 15 caixas de 0,5 m a 9 m da câmera por 3 quadros, libera os nós e
  **retém os materiais** (sem isso o shader do StandardMaterial3D sai do mapa do motor quando a última
  cópia é liberada).
- `VehicleDamage.wreck_materials()` é a receita que já existia em `_stall_wreck`, extraída para ser a
  mesma usada pela preparação. Cada destroço continua recebendo instâncias novas (a brasa esfria por
  carro).
- Controle A/B: `HARBOR_VEHICLE_VARIANT_PREWARM=0` desliga só esta etapa; `--no-prewarm` também.

Sem atores, RNG, população, colisão ou alteração visual: só materiais com as mesmas flags e caixas
temporárias cobertas pela cortina.

## A/B renderizado

Runner `tests/measure/RunIntermittentStalls.ps1`, snapshot do projeto, cache ShaderRD **frio** nos
dois braços (APPDATA isolado novo), Mobile 1920×1080, MSAA 2×, população 40, física 60 Hz/cap 3,
VSync/limitador desligados, mesma rota/seed. Toggle em runtime pela variável de ambiente; mesmos
arquivos nos dois braços. Percentis empíricos inferiores sobre **todos** os quadros de cada fase
(nada descartado como aquecimento). Draw = wall pre_draw→post_draw (não é GPU exclusiva).

Grupos: A = sem preparo (`first-draw-a1..a4`); B1 = só pintura (`b1`, `b2`, versão intermediária);
B = correção completa (`b3`, `b4`). JSON: `evidence/first-draw-stalls-20261005/ab-pooled.json`.

| Grupo / fase | Quadros / s | p50 | p95 | p99 | Máx | >33,3 | >66,7 |
|---|---:|---:|---:|---:|---:|---:|---:|
| A primeira passagem | 18301 / 120,1 | 5,094 | 11,735 | 16,924 | 115,289 | 52 | 14 |
| B primeira passagem | 11293 / 60,0 | 4,204 | 8,928 | 10,698 | 72,340 | 12 | 3 |
| A retorno | 14853 / 120,0 | 6,482 | 15,123 | 21,364 | 83,130 | 51 | 5 |
| B retorno | 8270 / 60,0 | 5,448 | 11,711 | 13,251 | 36,974 | 1 | 0 |
| A eventos | 10680 / 120,0 | 12,437 | 16,834 | 30,376 | 113,807 | 91 | 20 |
| B eventos | 6341 / 60,0 | 11,024 | 13,852 | 15,720 | 29,637 | 0 | 0 |
| A recuperação | 13383 / 120,0 | 10,127 | 14,197 | 15,744 | 73,646 | 12 | 1 |
| B recuperação | 4729 / 60,0 | 13,001 | 19,084 | 46,705 | 73,266 | 84 | 5 |
| A gameplay | 57217 / 480,1 | 6,960 | 15,029 | 19,794 | 115,289 | 206 | 40 |
| B gameplay | 30633 / 240,0 | 6,135 | 14,391 | 18,596 | 73,266 | 97 | 8 |
| B1 gameplay | 30050 / 240,0 | 6,209 | 13,561 | 16,217 | 1579,363 | 59 | 8 |

(ms; >33,3/>66,7 em contagem de quadros.)

Draws ≥25 ms depois de READY e chaves de cena gravadas em gameplay:

| Braço | Draws ≥25 ms (READY +s: ms) | Chaves gravadas depois de READY |
|---|---|---|
| a1 | 0,707: 55,9 · 21,854: 54,2 · 62,002: 51,6 · 69,654: 68,5 · 88,775: 68,4 · 113,743: 47,0 | 502cb30b, 0af590d5, f24a1c0a, 10b0b8ea, 3d4ae273 |
| a2 | 0,613: 55,1 · 1,359: 53,4 · 71,686: 47,9 | 0af590d5, 502cb30b, bdce03ad |
| a3 | 0,611: 64,3 · 8,444: 57,5 · 70,483: 75,5 · 115,264: 26,7 | 502cb30b, 0af590d5, f24a1c0a, bdce03ad |
| a4 | 0,606: 65,6 · 20,417: 67,6 · 40,430: 35,3 · 42,376: 56,6 · 92,371: 26,3 | 502cb30b, 0af590d5, bdce03ad |
| b1 (pintura) | nenhum | bdce03ad |
| b2 (pintura) | 35,721: 52,2 · 67,913: 97,5 · 68,040: 90,1 · 99,880: 65,4 | 3d4ae273 (brasa, ainda não coberta) |
| **b3** | **nenhum** | nenhuma |
| **b4** | **nenhum** | bdce03ad (sem draw ≥25 ms) |

Os draws de 55–60 ms da primeira passagem (chaves de pintura) se repetem em todos os 4 braços A e não
aparecem em nenhum dos 4 braços B. Os de vidro/brasa/desgaste dependem do que acontece no evento
(tiros, carro explodindo, porta/vidro), então aparecem em parte dos braços A; nos dois braços B
completos não houve draw ≥25 ms. Três draws de b2 (35,7/67,9/68,0 s, 52–98 ms) **não** têm chave
gravada nem pipeline novo: não são compilação de shader e não foram explicados (ver pendências).

### Custo no loading

| Braço | Etapa de variantes (wall) | Variantes desenhadas | Loading até READY |
|---|---:|---:|---:|
| b1 / b2 (só pintura) | 1,414 s / 0,399 s | 10 | 19,8 s / 19,5 s |
| b3 / b4 (completo) | 0,475 s / 0,463 s | 15 | 21,2 s / 19,0 s |
| a1..a4 | — | — | 22,9 / 18,9 / 20,8 / 22,7 s |

A etapa custa ~0,46 s de wall com cache frio (inclui 3 quadros desenhados sob a cortina; b1 teve
1,4 s em uma única medição). O loading total varia ±2 s entre execuções, mais que o custo da etapa;
não dá para afirmar que o loading ficou mais lento ou mais rápido. Com cache quente a etapa deve
custar só os 3 quadros e a geração do shader do StandardMaterial3D — **não medido**.

## O que não foi medido / ressalvas

- **Foco:** a1–a4 perderam o foco da janela em 69–97% da rota (`validity=lost_focus`); b1 em 8%;
  b2–b4 ficaram em foco. Algo externo (outra sessão/usuário) roubou o foco nas execuções A. A
  compilação de shader independe disso e as chaves gravadas são evidência separada do frame time,
  mas os percentis A vs B **não** são condições equivalentes. Retorno/eventos melhores no B podem ter
  parte de foco/cenário.
- **Recuperação pior no B (p99 46,7 vs 15,7 ms; 84 vs 12 quadros >33,3):** os quadros lentos são
  passos físicos de 10–16 ms com 2–3 passos por quadro (`physics_steps≥2` em 65/90 quadros nos
  braços b3/b4). Essa espiral já existia antes desta mudança, com cache seed e sem seed: nas
  capturas `shader-cache-a1/b1/a2/b2` (05/10, sem este código) foram 40/56/57/51 quadros com
  ≥2 passos e p95 do tick 9,2–12,9 ms. Os a1–a4 (sem foco) e b1/b2 ficaram em 2–6. A mudança só
  troca materiais desenhados no loading; não toca física. Não está provado que é independente: com
  2 braços B completos, fica como **variação de cenário não resolvida**, não como ganho nem como
  regressão demonstrada.
- Só 2 braços B completos e 2 B só-pintura; outros dois braços planejados (a5/b5) não rodaram porque o
  script do lock na pasta temporária compartilhada foi sobrescrito por outra sessão.
- Cobertura das variantes: frota de `FleetCatalog.all()` e as transições de flag conhecidas de
  `VehicleUsage`, `VehicleDamage` (desgaste/amassado/carcaça) e `VehicleInterior` (vidro). Outras
  combinações (liveries Cobra, materiais de porta, `bdce03ad`) não foram atribuídas; a cobertura
  vale para o que foi observado, não para todo material do jogo.
- Pipeline/driver: o cache de pipelines do driver não foi isolado; com ubershader os contadores de
  pipeline `draw` não subiram nesses quadros.
- Cache quente (jogador que já jogou): sem regressão esperada, mas não medido nesta rodada.

## Achados fora do escopo (não corrigidos)

- **b2, f4253 (READY +23,109 s): quadro de 1579,4 ms** com o desenho em 2,6 ms e um callback físico
  de 6 ms terminando em +11 ms; o resto (~1568 ms) fica **depois do último callback físico e antes do
  próximo process_frame**, mesma assinatura da trava de 1,7 s em aberto (`shader-cache-a1` f16083).
  Um CharacterBody3D foi removido no quadro; 21 pessoas/26 veículos, 0 estrelas. Reproduziu em
  primeira passagem e em uma captura sem WPR. Em `first-draw-diag-02` houve outro de 1833,8 ms
  (f10086), mas com 1773 ms **antes** do processEnd (outra localização). Encaminhar para a
  investigação da trava/SDL.
- **b1, f4191: 529,9 ms** em `contact_audio.pool_bus` (dentro de `vehicle.effects.impact`), CPU
  principal ~0: família da pausa de áudio, não de desenho.
- Draws sem chave de shader e sem pipeline novo de 47–98 ms (a1 62,0 s; a2 71,7 s; b2 35,7/67,9/68,0 s).
- `RunIntermittentStalls.ps1` com `-Project` no projeto vivo hasheia também `evidence/` (≈9 min antes
  e depois da captura); use snapshot.

## Verificação

Projeto vivo, `dotnet build Harbor.csproj` sem erros, Godot 4.7.2 .NET console:

- `test_regions` PASS; `test_native_driving -- --no-save` PASS; `cold/test_admission` exit 0.
- `test_vehicle_damage_look` 170 checks, 0 falhas (exercita a carcaça, que agora usa
  `wreck_materials()`); `test_vehicle_usage` e `test_destroyed_cleanup` exit 0.
- `test_bridge_approach_terrain` **FALHA** (3): "mountain east of tunnel" — morro fora da via, malha e
  colisor de MountainTerrain. O teste carrega só `NativeRegion`/`WorldConnection3D`, nenhum arquivo
  alterado aqui; passava em 01/10. Não confirmei em HEAD (não troco arquivos de trabalho); fica como
  pendência do mundo, não desta mudança.

O A/B carregou o `Main.tscn` real renderizado
(C# ativo: `router_native=true` no fim, Harbor.csproj compilado pelo runner) em 6 execuções sem erro
de script.

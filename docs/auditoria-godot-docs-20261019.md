# Auditoria: documentação oficial do Godot 4.7 × Geteco (19/10/2026)

**Pergunta:** estamos aplicando as boas práticas da documentação oficial e estamos à frente dela,
comparando com o último relatório ([perf-exe-20261018.md](perf-exe-20261018.md) e
[perf-roadside-20261019.md](perf-roadside-20261019.md), com as regras de
[HOW-TO-DEVELOP.md](HOW-TO-DEVELOP.md) e a revisão
[performance-architecture-20261002.md](reviews/performance-architecture-20261002.md))?

## Como foi feito e o que não foi

- Documentação `stable` = **4.7**, a mesma linha do projeto (4.7.2). Fonte: os 1.596 `.rst` do
  repositório `godotengine/godot-docs`, ramo `stable`.
- **Manual (517 páginas):** 12 fatias, cada uma lida por inteiro e conferida no código por grep e
  leitura (UI/i18n/2D, shaders, C#/GDExtension/depuração, animação/áudio/entrada, 3D luz/pós,
  3D culling/LOD/geometria, desempenho/renderização/IO, física/navegação/matemática, sobre/arquitetura/
  rede/XR, boas práticas/GDScript, editor/plugins/migração, assets/export/plataformas).
  **Não lidas (~94 páginas):** `getting_started/`, `engine_details/development/`, `engine_details/engine_api/`
  e `community/` (tutorial de iniciante e contribuição ao motor; leitura interrompida para poupar custo).
- **Referência de classes (1.078 páginas):** processada inteira por script — 3.972 notas, 133 avisos,
  490 depreciações e 171 itens experimentais. O código cita **310** classes; as 3.768 notas delas
  foram separadas, e cada depreciação foi casada com o código. Leitura completa por pessoa/agente
  só de `ProjectSettings`; as outras páginas foram consultadas sob demanda.
- **Nada foi medido.** Nenhum Godot rodou. "Verificado" = conferido no código, no git ou nos logs;
  "inferência" = deduzido da doc ou do código-fonte do motor, sem execução.

## Resposta curta

- **Engenharia de desempenho, streaming, compilação de shader, diagnóstico e save: à frente da
  documentação.** O projeto resolve, com medição e teste, problemas que a doc nem menciona (§2).
- **Recursos do motor que pressupõem o fluxo de editor/importação** (LOD automático, occlusion culling,
  Theme global, tradução padrão, AnimationTree, `uid://`, global uniforms): **atrás ou com caminho
  próprio.** Parte é escolha medida (Jolt, TAA/FSR2, GI); parte é lacuna (§4).
- **A doc é contrariada em poucos pontos concretos e baratos** (§3): API depreciada, curvas cortadas
  pela regra da 4.4, autoload liberado em runtime, export levando `artifacts/`, duas pendências de 02/10.
- **A comparação com o último relatório não se sustenta como está** (§1): o renderizador mudou sem
  commit, o benchmark não fixa as opções gráficas e a resolução registrada não é a do relatório.

**Veredito:** na curva, com bolsões claramente à frente em desempenho e diagnóstico. Não dá para
afirmar que o estado atual cumpre o critério do último relatório até medir de novo com a base fixada.

## 1. O último relatório não mede o estado atual

| Fato | Evidência | Consequência |
|---|---|---|
| Renderizador trocado de **Mobile** para **Forward+** na árvore de trabalho, sem commit | `git diff HEAD -- project.godot`: saem `"Mobile"` e `renderer/rendering_method="mobile"`; arquivo gravado em 19/10 16:00 | As rotas de 18–19/10 e a revisão de 02/10 são do Mobile. Pré-aquecimentos e `sync_pipeline_msaa` foram validados no Mobile (comentários citam `RenderForwardMobile`). Forward+ muda HDR, glow, luzes em cluster e quais pipelines existem |
| Benchmark lê as opções do jogador | `tools/perf_cross_bench.sh:25` não passa `--isolated-save-root`; `Settings.gd:132-136` cai em `user://settings.cfg`, alterado em 19/10 16:34 (`ssao=true`, `volumetric_fog=true`, `render_scale=0.95`, `msaa=2`, `shadow_quality=2`) | Rodadas antes e depois dessa troca não medem o mesmo jogo; o JSON só grava resolução, MSAA e vsync |
| Resolução diferente da relatada | JSON do benchmark de 19/10: `viewport_pixels=(3440, 1440)`, `resolution=(1720, 720)`, MSAA 4x; o relatório diz 1280x720 | Corrigir o relatório e fixar a janela na bancada |
| A sonda cria um segundo pico | Logs de 19/10 (lidos por agente): no quadro N+1 após um quadro > 33 ms, `frame_spike`/`RuntimeSnapshot`/`JSON.stringify` custam 11–21 ms; 6 casos passaram de 33 ms (36–52 ms) numa sessão | Infla a contagem de > 33 ms; não explica o pico de 220–250 ms. Os dois quadros dos sobrados (125 s e 146 s) **não** vêm da sonda |
| A alta de 0,5–2 ms no p50 cabe no ruído | Mesmo export de 17/10: serra com p50 de 4,89 a 7,30 ms entre rodadas (JSONs). O `project.godot` não muda em commit desde 14/10 e os 29 logs `export_release` recentes são todos `mobile` | Sem A/B no mesmo dia, nenhuma causa pode ser atribuída; a alta **não** vem das configurações do projeto |
| Com Forward+, o `settings.cfg` atual passa a valer de verdade | `GraphicsOptions.forward_plus()` só aplica SSAO e névoa volumétrica no Forward+ | A próxima rodada vai subir o p50 por configuração, não por código, se a bancada não usar um `settings.cfg` próprio |
| O pacote muda de um export para outro | Dois PCKs do mesmo dia: 1,52 GB e 1,20 GB, conforme o que estava em `artifacts/` (§3 item 5) | Tamanho e tempo de carga não se comparam entre exports; o A/B dentro do mesmo export continua válido |

**Antes de qualquer conclusão nova:** decidir e commitar o renderizador; rodar a bancada com
`--isolated-save-root` e um `settings.cfg` de bancada, gravando todas as opções no JSON; separar os
quadros N+1 com `previous_probe_ms` alto; refazer as rotas, incluindo noite e chuva.

## 2. Onde estamos à frente da documentação (verificado no código)

- **Compilação de pipeline:** a regra contra `hint_depth_texture` com MSAA, o `sync_pipeline_msaa`
  (`Settings.gd:301-315`) e o teste `test_occluded_silhouette` tratam um efeito que a doc não avisa.
  Os pré-aquecimentos cobrem variante MultiMesh e passada de sombra (`BridgeLookPrewarm.gd:47-58`);
  `StallLog` grava os monitores de pipeline por quadro.
- **TAA/FSR2/SSR bloqueados** depois de medir ~5 GiB de memória que não volta (`GraphicsOptions.gd:18-20`).
- **Streaming:** conta em `WorkerThreadPool` e commit no thread principal (`is_task_completed` antes do
  `wait`), fatias de ~2 ms, `MeshArrayCache`, fusão por célula e família (`ChunkCellMerge`), objetos
  estacionados em vez de recriados, LOD de passo físico no trânsito (`Vehicle.gd:309`).
- **Diagnóstico:** `Logger` em C# (recurso da 4.5) com fila em thread própria, spans `StallWorkTrace`,
  amostrador de pilha nativa (`StallStackSampler.cs`), contadores de GC, JIT do C# pré-aquecido sob a
  cortina, `build_kind` separando editor/debug/release.
- **Save:** escrita atômica com `.tmp`/`.bak`, validação antes da troca, teto de tamanho e nunca carrega
  `Resource` de `user://` (`SaveStore.gd`) — a doc só mostra o caso básico.
- **GDScript:** 99,85% das funções com tipo de retorno, 97% de `var` tipadas, 564 scripts `RefCounted`
  (objetos leves, como a doc recomenda).
- **Entrada:** remapeamento salvo com migração versionada, hotplug que pausa, área segura no Android,
  `screen_relative` no mouselook.
- **Tradução só na apresentação:** IDs e saves nunca mudam, com teste e auditoria de catálogo.
- **Decisões medidas contra o "padrão" da doc:** Jolt (A/B de 13/10: p50 12,6 ms contra 8,98 ms,
  1 rodada), GI desligado (streaming + câmera alta), .NET 10 no desktop e .NET 9 no Android.
- **Migrações 4.5–4.7 já absorvidas:** ID de dispositivo por tipo de evento, `naming_version=2`,
  `hinting=3`, AStar com ponto inicial livre, glow explícito, sem APIs removidas.

## 3. Onde o código contraria a doc (verificado, correção barata)

| # | Item | O que a doc diz | Evidência | Correção |
|---|---|---|---|---|
| 1 | API depreciada | `Image.create` depreciada | 62 linhas (ex.: `runtime/atmosphere/WeatherParticleTextures.gd:12`, `world/city_look/BuildingLife.gd:259`) | `Image.create_empty` |
| 2 | API depreciada | `Skeleton3D.force_update_all_bone_transforms`: "should only be called internally" | `runtime/ResidencePresentation.gd:196` e 1 teste | Ler a pose depois do processamento do esqueleto, sem forçar |
| 3 | Curvas cortadas | 4.4: `Curve` impõe a faixa; pontos fora de [0,1] exigem `max_value` | `BuildingLife.gd:379-380` (2,2), `world/urban_detail/HarborManholeSteam3D.gd:25-26` (1,6), `gameplay/vehicle_effects/VehicleDamage.gd:337-338` (2,2) sem `max_value`; `gameplay/emergency/Fire.gd:124-126` ajusta depois dos pontos | `max_value` antes do `add_point`; conferir no jogo (o visual atual pode ter sido ajustado com o valor cortado) |
| 4 | Autoload liberado | "Autoloads must **not** be removed using free() or queue_free() at runtime, or the engine will crash" | `runtime/StallLog.gd:73` e `:89`: `queue_free()` em toda sessão sem `HARBOR_STALL_LOG=1` | Desligar processamento em vez de liberar |
| 5 | Export levando lixo | Excluir não-recursos do export; `.gdignore` em pastas fora do jogo | Preset Windows sem `artifacts/**, builds/**, output/**, tmp/**` (o Android tem); `artifacts/` sem `.gdignore`. Diretório do PCK de 19/10 01:44 (1,52 GB): **562 MB de `artifacts/`**, 479 MB só de `flashlight-fix-20261017` (2.223 capturas); no de 12:29 (1,20 GB), 48,6 MB | Copiar o exclude do Android; `.gdignore` em `artifacts/`; passo na suíte que falhe se o PCK tiver `artifacts/` |
| 6 | Carga em background bloqueando | `load_threaded_get` espera se não terminou | `audio/EngineBankCache.gd:55-58` chama com `THREAD_LOAD_IN_PROGRESS` — **pendência de 02/10, inalterada** | Só consumir banco pronto, como `EngineDesignBanks` já faz |
| 7 | Chão transparente | Escrever `ALPHA` põe o material no pipeline transparente | `world/regions/natural_ground.gdshader:114` — **pendência de 02/10, inalterada** | Variante opaca + variante de borda, ambas no pré-aquecimento |
| 8 | Furo na catraca | Malha visual fica na GPU; lê-la trava o RenderingServer | `tools/check_frame_rules.py` só procura `surface_get_arrays(`. Pastas de jogo: 62 `append_from(`, 14 `create_trimesh_shape(`, 13 `get_faces(` — que leem a malha por dentro (inferência do código-fonte). Três rodam por trecho no streaming da serra: `MountainTerrain3D.gd:217`, `MountainBridgeShore.gd:156`, `ScenarioBoundary3D.gd:83`. O deserto já faz certo (`set_faces` com arrays da CPU) | Montar a colisão dos arrays do worker; estender a catraca |
| 9 | Roteamento de bus | Envio só da direita para a esquerda | `gameplay/urban_v1/SecretTunnelAudio.gd:72-87` cria o bus no fim e manda o SFX para ele | `add_bus(sfx_index)` ou `Area3D.reverb_bus` (reverb provavelmente inaudível hoje — inferência) |
| 10 | Erros sem pilha no release | `always_track_call_stacks` é preciso para o `Logger` ter pilha GDScript em release | Erros das sessões `export_release` chegam com `backtraces ['','']` | A/B do custo e ligar ao menos no export de diagnóstico |
| 11 | Argumento inexistente | Argumento desconhecido é ignorado em silêncio | `WorldEditor.gd:785` passa `--minimized` | Remover |
| 12 | Texto corrompido | — | Dupla codificação em `runtime/StallLog.gd:77-78` (`fÃ­sica`), `StallWorkTrace.gd:2`, `SessionDiagnostics.cs:118` | Regravar em UTF-8; `.gitattributes` com `eol=lf` |
| 13 | Doc interna errada | O projeto usa `GodotPhysics3D` | `docs/perf-serra-picos-20261017.md:106` atribui o passo nativo ao "Jolt"; `docs/EXPORT_READINESS.md` ainda dá como bloqueio os WAVs já resolvidos e diz que `export_presets.cfg` não é versionado | Corrigir os textos |
| 14 | Overrides `.mobile` anulados | O `.mobile` das sombras (2048, filtro duro) é o "override para aparelhos fracos" | No Android, `Settings.gd` reaplica 4096 por cima | Respeitar o `.mobile` no preset do Android |
| 15 | Configurações sem uso | `enable_object_picking` liga o picking físico no viewport raiz | `true` (padrão), com 0 `_input_event`/`input_ray_pickable` no código | Desligar |
| 16 | Texturas fora da regra 10 | Em 3D: VRAM comprimida + mipmaps; "Detect 3D" só percebe uso que o editor vê | 6 texturas de `digo_workshop` sem perda e **sem mipmaps** (2 normal maps; material montado em código, então o Detect 3D nunca dispara); 10 texturas de mãos Meshy 2048² sem perda; 28 albedos Meshy em S3TC sem `high_quality` | Regravar com o gravador de `build_painted_facades.py`; checar `.import` de imagem na catraca |

## 4. Onde estamos atrás da doc (lacunas, cada uma com o A/B que provaria)

| Lacuna | Doc | Estado | Próximo passo |
|---|---|---|---|
| Occlusion culling | [occlusion_culling](https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html) | Não usado (só no baker do Terrain3D) — **pendência de 02/10** | `GETECO_OCCLUSION` + `ArrayOccluder3D` por trecho com as caixas do `ChunkShadowShell`; medir túnel, cidade e Mobile |
| LOD de malha procedural | [mesh_lod](https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html) | LOD só nasce na importação; ~78 arquivos com `add_surface_from_arrays` sem LOD; com câmera ortográfica o LOD varia só com o zoom (inferência) | `ImporterMesh.generate_lods` offline/sob a cortina nas malhas fundidas, com cache |
| Postes da serra | [optimizing_3d_performance](https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html) | 4 MultiMeshes para a região (`MountainRoadside3D.gd:153-167`) — **pendência de 02/10** | Células de 64 m como `TerrainDressing3D` |
| Sombra do sol | [lights_and_shadows](https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html) | Splits e `fade_start` no padrão com câmera ortográfica a ~36 m; possível que `shadow_max_distance` seja ignorado em ortográfica (código-fonte, não está na doc) | Teste de 5 min com distância 5 m; depois splits para a faixa 25–55 m e o A/B `GETECO_SUN_SPLITS` |
| Luzes com sombra fora do orçamento | [pipeline_compilations](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html) | 5 `OmniLight3D` com sombra cúbica no túnel da ponte (`WorldConnection3D.gd:815-821`), sem fade nem `LightBudget`; nenhum pré-aquecimento cria omni/spot com sombra; faróis com sombra | Omni e spot com sombra no 1º pré-aquecimento; `distance_fade_shadow`; Dual Paraboloid no túnel |
| SubViewports com MSAA fixo | idem | 4x/2x fixos em `HarborAmmunationCatalog.gd:152`, `HarborWeaponWorkbench.gd:144`, `ResidencePresentation.gd:264`, `TuningShowroom.gd:36` | Seguir `get_viewport().msaa_3d` |
| Shader baker e D3D12 | [pipeline_compilations](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html), [driver.windows](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-rendering-rendering-device-driver-windows) | Não usados; a doc recomenda trocar para `d3d12` em projeto antigo; o export roda `--headless`, que o baker não suporta; não há Agility SDK junto do editor nem dos templates | A/B por `override.cfg` (duas cópias da mesma pasta de export), 1–2 rodadas de aquecimento por braço e ≥ 6 rodadas intercaladas de serra/travessia. `--rendering-driver` não passa pelo `BENCH_EXTRA` (entra depois do `--`) |
| Staging buffer | [staging_buffer/max_size_mb](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-rendering-rendering-device-staging-buffer-max-size-mb) | 128 MB (padrão); acima disso "a GPU para e espera os quadros anteriores" | A/B com 512 MB por `override.cfg`, medindo VRAM |
| Teto de FPS com VRR e swapchain | [max_fps](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-application-run-max-fps) | Menu 30/60/120/144; a doc sugere ~59/~138 com VRR; `swapchain_image_count=3` com vsync (a doc sugere 2) | Ajuste de ritmo de quadro percebido; a bancada não mede isso (vsync desligado) |
| Android | [time_rollover_secs](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-rendering-limits-time-time-rollover-secs) | 3.600 s (mobile pede < 64); `swappy_mode=2` pode travar em 30 fps | `time_rollover_secs.android`, avaliar `swappy_mode` e `agile_event_flushing` |
| Global uniforms | [shading_language](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html#global-uniforms) | `wetness`/`night`/`rain`/`snowfall` gravados material a material; `TIME` reinicia a cada 3.600 s em 22 shaders | Globals de clima e um tempo próprio |
| Tema e fontes | [gui_skinning](https://docs.godotengine.org/en/stable/tutorials/ui/gui_skinning.html), [gui_using_fonts](https://docs.godotengine.org/en/stable/tutorials/ui/gui_using_fonts.html) | 706 `add_theme_*_override` em código, 0 type variations; fontes sem pré-render, MSDF ou mipmaps com Label3D de 48–96 px | Theme `.tres` com variações; pré-render ou MSDF nos Label3D |
| Tradução | [internationalizing_games](https://docs.godotengine.org/en/stable/tutorials/i18n/internationalizing_games.html) | Caminho próprio em JSON; 0 `tr_n`; idioma inicial fixo em `pt_BR`; custo nunca medido em release | `measure_localization` em release com e sem tradução |
| Mixagem | [audio_effects](https://docs.godotengine.org/en/stable/tutorials/audio/audio_effects.html) | Vozes no bus SFX com +10 dB de pre-gain; sem compressor nem sidechain | Bus `Voice` + compressor com sidechain |
| Entrada fora do InputMap | [controllers](https://docs.godotengine.org/en/stable/tutorials/inputs/controllers_gamepads_joysticks.html) | `DesertDrag.gd`, `MiningMachine.gd`, `DesertHandling.gd` com teclas/controle fixos | Ações em `GameInput` |
| Tipagem não imposta | [warning_system](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/warning_system.html) | Sem `[debug]` no `project.godot` | `untyped_declaration` como aviso |
| Dados em JSON relidos | [resources](https://docs.godotengine.org/en/stable/tutorials/scripting/resources.html) | `OriginalWorldData.json` (54 KB) lido e parseado em ≥ 5 lugares | Um cache estático |
| Memória e objetos | [objectdb_profiler](https://docs.godotengine.org/en/stable/tutorials/scripting/debug/objectdb_profiler.html) | 0,95–1,49 milhão de Objects em 2 de 6 sessões de 19/10; ~5,2 GB privados | Snapshots antes/depois da travessia |
| Licenças | [complying_with_licenses](https://docs.godotengine.org/en/stable/about/complying_with_licenses.html) | Nenhuma tela com `Engine.get_license_text()` | Antes de qualquer distribuição |
| Ícone e assinatura | [changing_application_icon_for_windows](https://docs.godotengine.org/en/stable/tutorials/export/changing_application_icon_for_windows.html) | Sem `application/config/icon`; `codesign/enable=false` | Antes de qualquer distribuição |
| Animações Mixamo no pacote | [import_configuration](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/import_configuration.html) | 13 FBX e 1 GLB só de animação importados como cena e exportados, mas o jogo usa os `.res` do retarget | Importar como Animation Library ou excluir do export |

## 5. Pico isolado de 220–250 ms: o que a doc sugere testar

Nenhuma hipótese está provada. Fatos já registrados: ~1 pico por processo na serra/travessia,
thread principal presa numa trava dentro de `nvoglv64` enquanto outra thread do driver destrói
alocações, não reproduz no editor, segurar as malhas não resolveu.

1. **Primeira ativação de "omni shadow cubemap"** pelas 5 luzes do túnel da ponte, na emenda
   ponte–serra (z ≈ −285). Teste: interruptor que desliga a sombra delas + `pipelines_delta`.
2. **Salvamento do cache de pipelines** (134 MB hoje no release, 9 MB no editor — explicaria "não
   reproduz no editor"; inferência). Teste: `--verbose` procurando a gravação do cache no instante do
   pico; `override.cfg` só na pasta do export com `save_chunk_size_mb` alto.
3. **Leitura de malha escondida** no streaming da serra (§3 item 8).
4. **Driver e staging buffer:** A/B D3D12 × Vulkan e 128 × 512 MB de staging, por `override.cfg`
   no mesmo export.
5. **Trabalho sem span:** `EngineBankCache._fetch`, `MixamoDeath.library()` (`load()` síncrono na
   1ª morte), `AudioServer.add_bus/remove_bus` em jogo, ~59 `load(variável)`.
6. **Terrain3D carregado sem uso:** a DLL vai no export e é carregada; tirá-la exclui um suspeito.

Ferramentas da doc ainda não usadas: Visual Studio/ETW com símbolos, ObjectDB profiler, Tracy
(exige compilar o template).

## 6. Pendências da revisão de 02/10

| Item | Hoje |
|---|---|
| MultiMesh por trecho e família | Resolvido na cidade (CityPropKit, árvores) e pela fusão por célula |
| Postes da serra em 4 MultiMeshes | Aberto |
| LOD visual parcial | Avançou (faixas P5, proxy de 50 m, dither no deserto); sem LOD de malha nas procedurais |
| Occlusion culling | Aberto |
| `natural_ground` com `ALPHA` | Aberto |
| `EngineBankCache` bloqueante | Aberto |
| Espiral de 8 passos | Aberto: o release roda com 8; `HARBOR_MAX_PHYSICS_STEPS` só é lido com `HARBOR_STALL_LOG=1` (`StallLog.gd:72-80`). A/B 3 × 8 por `override.cfg` em caos, travessia e serra |
| Jolt como experimento | Feito em 13/10 e descartado por medida |

## 7. Ordem sugerida

1. Fixar a base de medição (§1) e remedir todas as rotas.
2. Correções baratas da §3 (itens 1–5 e 11–16), cada uma com a suíte central.
3. Testes das hipóteses do pico (§5), começando pelos itens 1, 2 e 6.
4. Lacunas da §4, sempre por A/B em release.

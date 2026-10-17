# Integração dos motores autorais

**Estado: ativo nos quatro adaptadores; performance em investigação, não aprovada.**
O pacote `audio/engine_design/` contém
17 perfis de síntese original e 253 WAVs. A associação explícita cobre 66
veículos atuais de combustão; quatro motos, o tanque e a empilhadeira elétrica
mantêm seus bancos dedicados. Existem ainda três aliases de compatibilidade.
Os nomes 2JZ, RB26, EA888 e VQ35 indicam referências de design; não comprovam
gravação real, fidelidade acústica ou troca de motor nos veículos fictícios.

## Catálogo e cobertura

`audio/FleetEngineDesign.gd` concentra `VEHICLE_PROFILES`, `DEDICATED_PROFILES`
e `PROFILE_META`. As funções `profile(archetype)`, `all_profile_ids()`,
`has_profile(profile_id)`, `rpm_bands(profile_id)`, `metadata(profile_id)` e
`dedicated_profile(archetype)` consultam constantes. `profile` retorna uma
string vazia para um identificador desconhecido ou atendido por banco dedicado.
Não há leitura do manifesto, varredura de diretórios ou carga de WAV por frame.

O inventário inclui o catálogo base de frota, as adições policiais, o tanque,
os catálogos de deserto, mineração e recompensas, o ônibus biarticulado,
blindado e veículos de Jessica e Digo. O 72º identificador é
`desert_cargo_truck`: sua especificação pertence a `DesertHeistTruck` e não
aparece em `FleetCatalog.all()`. `personal_monaliza`, `maciota_350z` e
`maciota_m8` são aliases além dos 72 identificadores atuais.
A Monaliza recebe a classe I6 turbo; a empilhadeira mantém a classe elétrica.
O V12 de carga tem banco diesel próprio, diferente do esportivo do Porto Rosso.

| Grupo | Perfis |
|---|---|
| Turbo a gasolina | `jz2_i6_turbo`, `rb26_i6_turbo`, `ap_i4_turbo`, `ea888_i4_turbo`, `v8_twin_turbo` |
| Aspirados | `v8_crossplane`, `v12_gt`, `vq35_v6_na`, `city_i4_na`, `utility_v6_na`, `sport_i4_na`, `classic_i4_na` |
| Turbodiesel | `tdi_i4_diesel`, `truck_i6_diesel`, `bus_i6_diesel`, `work_i4_diesel`, `truck_v12_diesel` |

A associação escolhe uma classe sonora coerente com o veículo autorado; não
altera torque, combustível ou mecânica de seus demais sistemas. Divergências
de nomenclatura dos catálogos antigos devem ser tratadas separadamente, sem
inferir uma configuração de fábrica a partir do nome do sample.

## Contrato dos arquivos

`manifest.json` usa `schema_version: 2`, `sample_rate: 22050`, `channels: 1`,
`pcm_bits: 16` e `guard_frames: 8`. Cada perfil declara
`architecture: piston_four_stroke`, `cylinders`, `fuel`, `turbo`,
`bypass_valve`, sete `rpm_bands` crescentes e sete caminhos em cada uma das
listas `loaded` e `coast`. `band_frames` informa a duração útil de cada âncora:
132.300 frames até 1.500 RPM e 44.100 frames acima disso.

Todos os loops são mono PCM16 e acrescentam oito frames iguais aos oito
primeiros. O cache define o fim do laço antes da guarda. A taxa de ciclo de um
motor quatro tempos é `rpm / 120`; a frequência de combustão é essa taxa
multiplicada pelo número de cilindros. O pitch usa a razão entre RPM alvo e
RPM nominal, sem multiplicar novamente pelo número de cilindros.

Os 253 `.wav.import` usam `compress/mode=0`, `edit/trim=false`,
`edit/normalize=false`, `force/8_bit=false`, `force/mono=false`,
`force/max_rate=false` e `edit/loop_mode=0`. Isso evita que a compressão QOA
padrão substitua o PCM aprovado ou altere as guardas. O cache configura os
limites de loop em recursos compartilhados preparados. O gerador cria ou
atualiza somente os imports dentro de `audio/engine_design`, conserva UIDs
existentes e deixa previews e bancos legados intactos. Uma segunda aplicação
dos parâmetros não modifica os arquivos. A importação PCM já foi executada;
o teste de contrato em Godot verificou formato, duração e exclusão das guardas
nos recursos carregados pelo runtime.

Os cinco turbos a gasolina incluem `effects.turbo_spool` (dois segundos,
oito guardas) e `effects.bypass_release` (0,68 segundo, sem guarda, extremos
zero). Os cinco turbodiesel têm apenas enchimento; os aspirados não têm esses
efeitos. São 238 faixas de motor e 15 efeitos. O mapa `sha256` de cada perfil
cobre todos os seus arquivos. O campo `status` do manifesto é
`fleet_runtime_enabled`; a avaliação de performance é registrada separadamente.

## Cache, mistura e adaptadores

`audio/EngineDesignBanks.gd` prepara os 17 bancos e compartilha seus recursos
entre veículos. A leitura e decodificação ocorrem em uma thread de preparação;
o resultado só é publicado após sua conclusão. A síntese permanece offline.
O payload PCM soma **36.492.308 bytes, ou 34,80 MiB**, aproximadamente 35 MiB
para o conjunto compartilhado. O total dos arquivos WAV, com cabeçalhos,
é cerca de 34,81 MiB. Esses números não incluem overhead de recursos, cópias
temporárias de importação, bancos legados ou outras alocações do processo;
não substituem medição de memória do jogo.

`audio/EngineDesignVoice.gd` usa até **quatro vozes de motor por instância**:
duas âncoras adjacentes de RPM em cada estado, carga e alívio. A mistura usa
ganhos de potência constante e uma fase comum de virabrequim para iniciar as
vozes. O RPM ajusta pitch, a carga ajusta a contribuição dos dois estados e
os loops de baixa conservam seus seis segundos úteis. Turbo e alívio podem
acrescentar até duas vozes de efeitos no veículo em primeiro plano. Esses
efeitos não são ativados para tráfego distante; diesel nunca toca bypass.

Os quatro pontos de integração são:

| Adaptador | Responsabilidade |
|---|---|
| `audio/WorldAudio.gd` | Motor do veículo dirigido pelo jogador |
| `audio/vehicle_ambience/NearbyVehicleAudio.gd` | Veículos próximos e suas vagas de áudio espacial |
| `audio/desert_cars/DesertCarAudio.gd` | Veículos com áudio específico do deserto |
| `audio/service_vehicles/ServiceVehicleAudio.gd` | Veículos de serviço e seus estados de motor |

Os quatro adaptadores estão ativos por padrão. Os testes funcionais verificaram
associação de bancos, vagas espaciais, desligamento e transições de motor,
incluindo os caminhos dedicados. O fallback legado continua disponível enquanto
o cache prepara um banco. Essa cobertura funcional não equivale a dirigir todos
os veículos em cada região; o alcance real de gameplay está registrado abaixo.

O argumento de usuário **`--legacy-engine-design`** desabilita os bancos novos
para permitir comparação com o caminho anterior no mesmo código. A comparação
renderizada usa esse controle com a mesma configuração de cena, câmera, clima,
resolução, renderer e limitador. Já existem seis execuções completas em
`Main`, três com cada caminho. As populações e trajetórias observadas variaram,
por isso os resultados ainda não isolam o custo dos motores.

## Evidência offline e preservação

```powershell
python tools/audio/validate_engine_design_pack.py --pack audio/engine_design --baseline artifacts/engine-sound-design-20261016/baseline-v1 --report artifacts/engine-sound-design-20261016/validation-fleet-pack.json
```

Resultado em 16/10/2026: **PASS, 253 WAVs, zero erros**. A verificação cobre
hashes, formato, duração, guardas, faixa de pico, DC, RMS, ordem de RPM e
emendas circulares comparadas às variações naturais da onda. O baseline
histórico também comprova a preservação das 40 faixas altas e quatro efeitos
da primeira versão. Isso não mede realismo, repetição perceptível ou FPS.

A expansão de nove para 17 perfis preservou os **135 WAVs já aprovados byte a
byte**. Uma leitura independente comparou esses arquivos ao snapshot
`approved-nine-before-fleet.json` e os metadados do GDScript ao manifesto:
nenhuma mudança e nenhuma divergência. Os relatórios ficam em
`artifacts/engine-sound-design-20261016/`:

- `validation-fleet-pack.json`: propriedades de todos os WAVs e baseline inicial.
- `validation-fleet-preservation.json`: preservação dos nove aprovados e metadados.
- `fleet-authoring-validation.json`: inventário estático e cobertura dos veículos.

O usuário aprovou os nove perfis após a revisão da lenta. Os oito perfis de
expansão podem ser ouvidos em `demos/compare_fleet_expansion.wav`.
`compare_new_engines.wav` continua contendo os cinco perfis da expansão
anterior. Demos são simulações offline e não comprovam a mixagem no Godot.

## Estado das validações e próximos resultados

Registro em 16/10/2026, no **Godot 4.7.2 .NET**. Os logs ficam em
`artifacts/engine-fleet-integration-20261016/`:

| Verificação | Resultado | Evidência |
|---|---|---|
| Contrato da frota e dos bancos | 1.673 checks, 72 IDs, 17 perfis; zero falhas | [contract.log](../artifacts/engine-fleet-integration-20261016/contract.log) e [contract-optimized.log](../artifacts/engine-fleet-integration-20261016/contract-optimized.log) |
| Mixers e transições | 48 checks; zero falhas | [mixers.log](../artifacts/engine-fleet-integration-20261016/mixers.log) e [mixers-optimized.log](../artifacts/engine-fleet-integration-20261016/mixers-optimized.log) |
| Áudio dedicado do tanque | 38 checks; zero falhas | [tank.log](../artifacts/engine-fleet-integration-20261016/tank.log) |
| Build C# final | Sucesso; zero avisos e zero erros | [build-final.log](../artifacts/engine-fleet-integration-20261016/build-final.log) |
| Seis execuções renderizadas de Main | 20 checks em cada relatório; zero falhas; captura `engine.wav` em cada pasta | Relatórios abaixo |
| Microbenchmark renderizado ABBA | Oito fases; zero falhas; fontes estáveis | [report.json](../evidence/engine-audio-cost-abba-450140-11752577/report.json) |
| Preservação dos nove aprovados | 135 WAVs idênticos | [validation-fleet-preservation.json](../artifacts/engine-sound-design-20261016/validation-fleet-preservation.json) |

Os logs de contrato e mixers, inclusive após as otimizações, não registram
erros de script. O build final passou após excluir `artifacts/**` da busca
automática de fontes C# por `DefaultItemExcludes` em `Harbor.csproj`; as cópias
de diagnóstico que causavam definições duplicadas foram preservadas.
Os testes funcionais incluem Desert/Service e casos dedicados
em fixtures controladas. A medição em `Main` usou **`sport_coupe`**, com
`WorldAudio` e `NearbyVehicleAudio` ativos, renderer Mobile, 1280×720, RTX 4060
Laptop e i7-13650HX. Cada relatório guarda checks, intervalos de frame,
população, vozes e uma captura real do bus em `engine.wav`:

| Execução | FPS por frames/tempo | p95 de frame | Distância | Relatório |
|---|---:|---:|---:|---|
| Design A | 67,29 | 29,64 ms | 144,62 m | [report.json](../evidence/engine-design-a-344504-11487492/report.json) |
| Legado A | 70,26 | 25,75 ms | 138,83 m | [report.json](../evidence/engine-legacy-a-338560-12626026/report.json) |
| Design B | 74,67 | 24,76 ms | 95,47 m | [report.json](../evidence/engine-design-b-349936-11016252/report.json) |
| Legado B | 84,69 | 18,73 ms | 137,35 m | [report.json](../evidence/engine-legacy-b-354988-10621972/report.json) |
| Design C, após otimizações | 54,14 | 32,471 ms | 136,40 m | [report.json](../evidence/engine-design-c-430952-13103651/report.json) |
| Legado C, após otimizações | 76,65 | 22,662 ms | 137,20 m | [report.json](../evidence/engine-legacy-c-370776-14305069/report.json) |

**Performance: em investigação, não aprovada.** A/B antecedem as otimizações;
o par C foi executado após elas. O caminho novo teve FPS menor e p95 maior
nos três pares. No par C, mesmo com distâncias próximas, a discrepância de
`Main` persistiu; os logs dessa rodada não registram erros. NPCs, tráfego e
outros estados da cena variaram entre processos. Os dados não comprovam
equivalência ou ganho nem isolam quanto da diferença vem do áudio.
O [comparativo consolidado](../artifacts/engine-fleet-integration-20261016/runtime-comparison.json)
preserva os dados dessas execuções.

`Performance.TIME_PROCESS` e `TIME_PHYSICS_PROCESS` são **máximos periódicos do
último segundo**, repetidos nas amostras de frame; não representam custo médio
por frame nem tempo exclusivo de GDScript. Não somar ou interpretar suas médias
como decomposição do frame. A avaliação principal usa os intervalos reais,
com p50/p95/p99, máximo e contagens acima de 33,3/66,7 ms. O comportamento dos
monitores está no [código oficial do Godot](https://github.com/godotengine/godot/blob/master/main/main.cpp).

Foram aplicadas otimizações conservadoras: `area_mask=0` nos emissores novos
(o projeto não usa roteamento de áudio por Area3D), cache da flag e de metadados,
parada idempotente e remoção de arrays e atualizações espaciais redundantes.
Permanecem quatro vozes de motor, as mesmas faixas, estados carga/alívio e
cadência de atualização. Os testes funcionais passaram novamente, mas o par C
renderizado não resolveu a discrepância. **Nenhum ganho foi concluído.**

O [microbenchmark ABBA encerrado](../evidence/engine-audio-cost-abba-450140-11752577/report.json)
completou oito fases, sem falhas ou erros no stderr e com hashes de fontes
estáveis. Executou legado–novo–novo–legado em dois cenários: 12 fontes espaciais
e uma fonte em primeiro plano. Cada fase teve três segundos de aquecimento e
cerca de 31 segundos medidos, com todos os bancos e nós residentes, câmera fixa,
sem NPCs, tráfego ou turbo, VSync desligado e sem limite de FPS.

As médias abaixo são ponderadas pelo número de chamadas/amostras das duas
fases de cada modo. Os intervalos entre parênteses são as médias das fases,
não mínimos e máximos de chamadas individuais:

| Cenário e modo | Atualização do mixer em µs: média ponderada (médias das fases) | Intervalo de frame médio ponderado |
|---|---:|---:|
| 12 fontes, legado | 58,18 (56,06–60,46) | 0,571 ms |
| 12 fontes, novo | 140,85 (132,13–150,97) | 0,650 ms |
| Uma fonte em primeiro plano, legado | 20,89 (20,53–21,29) | 0,517 ms |
| Uma fonte em primeiro plano, novo | 27,32 (26,78–27,90) | 0,539 ms |

O trecho de atualização cronometrado apresentou acréscimo de **82,67 µs para
12 fontes** e **6,43 µs para uma fonte em primeiro plano**. Esse custo local
não explica sozinho toda a queda de `Main`. O experimento não atribui CPU à
thread de áudio, não reproduz a carga do mundo e não aprova performance de
gameplay ou qualidade perceptiva. Os buffers de telemetria também crescem
entre fases; seus FPS não devem ser apresentados como FPS do jogo.

O [diagnóstico ABBA estacionário de Main](../evidence/engine-fixed-abba-388040-12822074/report.json)
terminou após o build final com **37 checks e zero falhas**, C# ativo, fontes
estáveis e stderr vazio. O mesmo carro ficou exatamente na mesma posição,
segurado apenas pelo comando normal de freio de mão, com câmera normal,
população viva, ambos os caches residentes e três segundos de aquecimento
antes de cada janela de 31 segundos. A flag de áudio foi alternada somente
na memória do processo e restaurada ao terminar; os saves permaneceram isolados.

| Fase, na ordem executada | FPS por frames/tempo | p95 de frame | Frames acima de 33,3 ms |
|---|---:|---:|---:|
| Legado 0 | 75,55 | 20,512 ms | 13 |
| Novo 1 | 91,20 | 17,933 ms | 0 |
| Novo 2 | 93,70 | 17,766 ms | 1 |
| Legado 3 | 72,63 | 21,497 ms | 11 |

**A queda não se reproduziu nesse cenário de lenta.** Isso não comprova ganho
global: tráfego e população continuam vivos, e o teste parado não reproduz
carga e deslocamento pela cidade. As três comparações em condução ficaram
piores com o novo caminho e permanecem registradas; a causa dessa diferença
não foi isolada. A integração funcional está validada no escopo descrito,
mas **performance em condução e aprovação global de FPS continuam pendentes**.

Limites atuais: ainda falta comprovar o regime de `Main` para Desert/Service e
os dedicados nas respectivas regiões, além de escuta humana das capturas e dos
oito perfis adicionais. Os checks aprovados não certificam ausência perceptiva
de estalos, fidelidade a motores reais ou toda a frota em gameplay. A aprovação
dos nove demos anteriores permanece válida apenas para aquele material.

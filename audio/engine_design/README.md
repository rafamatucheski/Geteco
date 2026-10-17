# Motores autorais para Geteco

**Estado: ativo nos quatro adaptadores; performance em investigação, não aprovada.**
O pacote contém 17 identidades de áudio
criadas por síntese offline em 16/10/2026, com associação explícita à frota.
Os nomes de motores indicam referências de design; não são gravações de motores
reais nem certificam a configuração de fábrica dos veículos do jogo.

| Perfil | Caráter pretendido | Faixas de RPM |
|---|---|---|
| `jz2_i6_turbo` | I6 turbo encorpado, inspiração 2JZ | 840–6.960 |
| `rb26_i6_turbo` | I6 turbo com admissão e brilho, referência R34/RB26 | 960–7.800 |
| `v8_crossplane` | V8 aspirado; cadência irregular em cada banco de escape | 720–6.480 |
| `v12_gt` | V12 aspirado esportivo, pulsos densos | 840–8.400 |
| `ap_i4_turbo` | I4 turbo preparado, proposta para o Gol do Digo | 960–6.720 |
| `ea888_i4_turbo` | I4 turbo moderno, referência Jetta GLI | 840–6.600 |
| `vq35_v6_na` | V6 aspirado esportivo, referência 350Z | 840–6.720 |
| `tdi_i4_diesel` | I4 turbodiesel de picapes e vans | 840–4.320 |
| `city_i4_na` | I4 aspirado pequeno para compactos urbanos | 840–6.240 |
| `v8_twin_turbo` | V8 turbo para o identificador de compatibilidade M8 | 720–7.080 |
| `truck_i6_diesel` | I6 turbodiesel pesado, caminhões e resgate | 600–2.400 |
| `bus_i6_diesel` | I6 turbodiesel com rotação contida, ônibus | 600–2.280 |
| `work_i4_diesel` | I4 turbodiesel industrial, trator e retroescavadeira | 720–2.640 |
| `truck_v12_diesel` | V12 turbodiesel de carga pesada | 600–2.400 |
| `utility_v6_na` | V6 aspirado de utilitários e sedãs | 720–6.000 |
| `sport_i4_na` | I4 aspirado esportivo, hatches e buggies | 960–7.200 |
| `classic_i4_na` | I4 aspirado de sedãs e peruas clássicos | 720–5.760 |

Cada perfil contém sete loops sob carga e sete no alívio: **238 faixas de motor**.
Cinco perfis turbo a gasolina têm enchimento e válvula de alívio; cinco
turbodiesel têm somente enchimento. O total é **253 WAVs: 238 loops de motor e
15 efeitos**. Aspirados não recebem efeitos de turbo; diesel não recebe BOV.
Nenhum sample foi baixado, copiado de vídeos ou extraído dos protótipos antigos.

## Cobertura e reprodução no jogo

[`FleetEngineDesign.gd`](../FleetEngineDesign.gd) associa 66 veículos atuais a
perfis de combustão. Quatro motos, o tanque e a empilhadeira elétrica mantêm
seus bancos dedicados, totalizando 72 identificadores atuais cobertos. A conta
inclui `desert_cargo_truck`, cuja especificação pertence à missão do deserto.
Há ainda três aliases de compatibilidade: `personal_monaliza`, `maciota_350z` e
`maciota_m8`. O catálogo contém apenas constantes; não busca arquivos por frame.

A integração usa `EngineDesignBanks.gd` como cache compartilhado e
`EngineDesignVoice.gd` como voz de motor. Cada motor utiliza até quatro vozes:
duas faixas adjacentes de RPM multiplicadas pelos estados carga/alívio. Efeitos
de turbo usam vozes adicionais apenas no veículo em primeiro plano. Os quatro
adaptadores atendem o áudio principal, tráfego próximo, carros do deserto e
veículos de serviço. O payload PCM de todos os bancos soma **34,80 MiB**,
aproximadamente 35 MiB compartilhados; isso não mede a RAM total do jogo.

O argumento `--legacy-engine-design` seleciona o caminho anterior para comparação
A/B. O manifesto registra `fleet_runtime_enabled`: os bancos estão ativos por
padrão nos quatro adaptadores, com fallback enquanto o cache termina de carregar.
Contrato, adaptadores e critérios de entrega estão na
[documentação de integração](../../docs/engine-sound-integration.md).

## Demonstrações

Os arquivos em `artifacts/engine-sound-design-20261016/demos/` incluem:

- `compare_all_engines.wav`: os 17 perfis na ordem da tabela.
- `compare_original_engines_revised.wav`: os quatro primeiros, com lenta revista.
- `compare_new_engines.wav`: os cinco perfis seguintes já aprovados pelo usuário.
- `compare_fleet_expansion.wav`: os oito perfis acrescentados para a frota.
- `*_idle_to_1500.wav`: 13 segundos de lenta, subida até 1.500 RPM e retorno.

As montagens separam motores por um segundo de silêncio. Cada arrancada dura
16,1 segundos, com carga parcial, três marchas, duas trocas e freio-motor.
Os JSONs acompanham trajetória e ganho comum. São simulações offline feitas
com os samples entregues; não são capturas de gameplay.

## Formato e preservação

Todos os WAVs usam PCM16 mono a 22.050 Hz. As âncoras até 1.500 RPM têm seis
segundos úteis; as superiores e o enchimento do turbo têm dois. Os loops
acrescentam oito amostras-guarda iguais às oito primeiras, excluídas da região
repetida pelo leitor. O sopro de alívio dura 0,68 segundo e não tem guarda.
O manifesto registra RPM, cilindros, combustível, duração e hashes SHA-256.
Os 253 arquivos `.wav.import` fixam `compress/mode=0` (PCM), sem normalização,
trim, redução para 8 bits ou mudança de taxa. O gerador mantém esses parâmetros
somente nesta pasta e preserva UIDs existentes; o runtime define os loops.

O usuário aprovou os nove primeiros perfis após a revisão da lenta. Os **135
WAVs desses nove perfis foram preservados byte a byte** durante a expansão.
A revisão anterior da lenta já preservava os 40 WAVs superiores e quatro
efeitos da primeira versão. A transição entre a segunda e a terceira âncora
ainda recebe parte da lenta revista; não se promete áudio idêntico a partir de
1.500 RPM. Os quatro comparativos `*_idle_before_after.wav` mudam para a versão
revista em 13,8 segundos, com o mesmo ganho nas duas metades.

## Reproduzir e verificar

Na raiz do projeto, usando Python com NumPy e SciPy instalados:

```powershell
python tools/audio/build_engine_design_pack.py
python tools/audio/validate_engine_design_pack.py --pack audio/engine_design --baseline artifacts/engine-sound-design-20261016/baseline-v1 --report artifacts/engine-sound-design-20261016/validation-fleet-pack.json
```

A validação offline dos 17 perfis passou: 253 WAVs, zero erros. A conferência
separada dos 135 hashes aprovados e dos metadados do catálogo também passou.
Relatórios: `validation-fleet-pack.json`, `validation-fleet-preservation.json`
e `fleet-authoring-validation.json`, na pasta de artefatos acima.
Esses resultados cobrem os arquivos e a preservação do material aprovado.

Referências e decisões: [pesquisa original](../../artifacts/engine-sound-design-20261016/research.md)
e [pesquisa da expansão](../../artifacts/engine-sound-design-20261016/research-expansion.md).

## Estado das validações e próximos resultados

No Godot 4.7.2 .NET, o contrato passou com **1.673 checks, 72 IDs e 17 perfis**;
os mixers passaram com **48 checks** e o tanque com **38 checks**, sem falhas.
Contrato e mixers também passaram após as otimizações, com logs sem erros de
script em `artifacts/engine-fleet-integration-20261016/` (`contract-optimized.log`
e `mixers-optimized.log`). A importação PCM e os limites de loop foram verificados
nos recursos do runtime.
O [build C# final](../../artifacts/engine-fleet-integration-20261016/build-final.log)
passou com zero avisos e zero erros, após excluir `artifacts/**` da busca
automática de fontes sem apagar as cópias de diagnóstico.

Há seis relatórios completos de `Main` renderizada, com **20 checks aprovados
em cada um** e captura real `engine.wav`. O cenário medido usa `sport_coupe`,
`WorldAudio` e tráfego próximo; Desert/Service e os dedicados têm verificação
funcional em fixtures, sem equivaler à medição de cada região em `Main`.
Os caminhos dos relatórios, métricas e capturas estão na
[documentação de integração](../../docs/engine-sound-integration.md#estado-das-validações-e-próximos-resultados).

**Performance continua em investigação.** Nas quatro execuções A/B anteriores
às otimizações, o caminho novo apresentou FPS menor e p95 maior, com variação
também de NPCs, tráfego e trajetória. O par C, após `area_mask=0` e remoção de
trabalho redundante, registrou **54,14 FPS / p95 32,471 ms** no novo contra
**76,65 FPS / p95 22,662 ms** no legado, com distâncias de 136,40/137,20 m.
Ambos passaram nos 20 checks e não registraram erros, mas a discrepância de
performance em `Main` persistiu. Não há aprovação nem conclusão de ganho.
Foram preservadas quatro vozes, qualidade dos samples e cadência de atualização.
Os monitores de CPU são máximos periódicos, não custos médios por frame;
a comparação usa os intervalos reais de frame.

O [microbenchmark ABBA final](../../evidence/engine-audio-cost-abba-450140-11752577/report.json)
completou oito fases sem falhas, com fontes estáveis e sem erros no stderr.
Para 12 fontes, a média ponderada de atualização do mixer foi **58,18 µs no
legado** (médias das fases: 56,06–60,46) e **140,85 µs no novo** (132,13–150,97).
Para uma fonte em primeiro plano, foi **20,89 µs** (20,53–21,29) contra
**27,32 µs** (26,78–27,90). O custo adicional local não explica sozinho toda a
queda em `Main`; a cena fixa sem tráfego não aprova desempenho de gameplay.
O [ABBA estacionário em Main](../../evidence/engine-fixed-abba-388040-12822074/report.json)
terminou com **37 checks e zero falhas**, sem deslocamento do carro e com
ambos os bancos residentes. Na ordem legado–novo–novo–legado, mediu
**75,55 / 91,20 / 93,70 / 72,63 FPS**. A queda não se reproduziu em lenta,
mas isso não comprova ganho global nem resolve os resultados em condução.
A integração funcional passou; **desempenho dirigindo permanece inconclusivo**.
Escuta humana das capturas e dos oito perfis novos continua pendente; a
aprovação dos nove primeiros demos não certifica automaticamente a mixagem
no jogo ou toda a frota.

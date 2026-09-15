# Loading — 13/09/2026

## Alterações

- O Novo jogo solicita recursos durante o cartão do estúdio; a montagem da cidade continua depois do início da CGI.
- Preparações curtas compartilham uma fatia de 6 ms durante o loading. Fora do loading, continua a espera por frame anterior. Um item individual ainda pode exceder a fatia.
- Todos os 19 modelos comuns, veículos residentes, 13 veículos de emergência, reserva de 70 policiais e áudio continuam preparados antes de liberar os controles.
- A barra distribui marcos entre recursos, mundo, veículos, trânsito, emergência e áudio.
- GameLoading.phase_times_ms registra tempos por etapa. tests/measure_loading_time.gd reproduz o loading real e amostra os primeiros 30 segundos dirigindo.

## Comparativo renderizado

Godot 4.7.2, Vulkan Mobile, RTX 4060 Laptop GPU, 1280×720, VSync ligado e limite de 60 FPS. Processo novo por cenário, mesma semente e estado de campanha, saves isolados; a importação e o cache do sistema já existiam. O editor estava aberto. Este é um comparativo local, não uma distribuição estatística nem certificação de todas as rotas.

| Etapa | Antes (ms) | Depois (ms) |
|---|---:|---:|
| audio | 1407.4 | 961.5 |
| before_resources | 152.9 | 144.2 |
| emergency | 2405.1 | 2453.3 |
| resident_vehicles | 2880.7 | 2641.6 |
| resources | 4716.6 | 4583.3 |
| scene_ready | 6949.7 | 6925.6 |
| total | 31785.1 | 29838.0 |
| vehicle_models | 3335.1 | 2723.5 |
| world_build | 9488.8 | 9002.7 |

| Primeiros 30 s dirigindo | Antes | Depois |
|---|---:|---:|
| fps | 59.265 | 59.120 |
| p50 | 16.654 | 16.649 |
| p95 | 18.243 | 18.278 |
| p99 | 19.828 | 20.122 |
| max | 198.734 | 168.049 |
| over33 | 6.000 | 7.000 |
| over66 | 3.000 | 4.000 |
| frames | 1778.000 | 1774.000 |
| seconds | 30.001 | 30.007 |

Loading: redução de 6.1%. A cena tinha 32208 nós nas duas execuções. p95/p99 variaram menos de 5%; os picos de primeira visita continuam presentes, portanto não se certifica 60 FPS constantes.

No teste de Novo jogo, a CGI começou em 5,605 s, os recursos já estavam disponíveis ao iniciar a construção (espera restante de 0,031 ms), e a entrada com CGI pulada terminou em 30,862 s. Não houve baseline de Novo jogo nesta tarefa, portanto não se atribui um percentual de ganho a esse fluxo.

## Validação

- test_vehicle_geometry_cache.gd: passou; geometria compartilhada com materiais e dano independentes.
- test_officer_reserve.gd: passou; tiers, saúde, armas, colisão, reutilização e esgotamento da reserva.
- test_emergency_pool_preparation.gd: passou; 13 apresentações preservadas e reutilizadas.
- test_continue_skips_opening.gd: passou; saves continuam sem repetir abertura.
- test_opening_loading.gd renderizado: passou; abertura, skip aguardando mundo e transição para desembarque.
- Uma alteração paralela de PlayerCombatPose causou erros de compilação/compatibilidade durante validação. Após a correção nessa alteração, os testes afetados passaram; esta tarefa não editou poses/armas.
- Aviso de 29 objetos retidos ao encerrar o benchmark apareceu antes e depois; não foi introduzido pela otimização.

Evidências: D:/geteco/artifacts/loading-0913/{before,batched}/result.json e logs no mesmo diretório. As amostras individuais de frame estão em frames_ms.

## Reproduzir

```powershell
$env:APPDATA='D:/geteco/artifacts/loading-check/userdata'
& 'D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --path D:/geteco/game --script res://tests/measure_loading_time.gd -- D:/geteco/artifacts/loading-check/result
```

## Verificação final

O benchmark permanente também passou com as verificações de mundo pronto, apresentações dos veículos residentes, 13 veículos de emergência e reservas de 14 policiais por grupo. Loading: 30.596 s; primeiros 30 s dirigindo: 59.26 FPS, p95 18.268 ms, p99 20.346 ms, máximo 179.966 ms, 6 frames acima de 33,3 ms e 3 acima de 66,7 ms. Resultado em `D:/geteco/artifacts/loading-0913/final/result.json`.

Os dois resultados após a otimização ficaram entre 29,8 e 30,6 s, contra 31,8 s antes. A segunda execução validou o benchmark permanente e a integração após as alterações paralelas de armas; não deve ser tratada como uma repetição estatística de código idêntico.

# Performance — revisão do vídeo de 24/09/2026

Estado: **pendente de comparação renderizada isolada**. Meta provisória: 60 FPS / 16,67 ms. Aumento superior a 5% no p95/p99 exige confirmação equivalente; a tolerância não aprova descumprimento da meta absoluta.

Antes do início das correções, a inspeção identificou Godot 4.7.2, renderer Mobile, viewport do projeto 1280×720, limite 60 FPS e VSync configurável por `user://settings.cfg`.

A consulta read-only de processos confirmou duas instâncias preexistentes:

- PID 76560: editor Godot, iniciado às 14:52:34.
- PID 86396: jogo filho do editor, iniciado às 18:29:54, com `--remote-debug`, `--scene res://ui/MainMenu.tscn`, `--wid` e `--resolution 1280x720`.

Esses processos pertencem ao usuário e não foram encerrados. Sua presença impede afirmar que uma amostra nova seja isolada. Nenhum resultado headless comprova FPS. As correções críticas podem prosseguir, mas não serão apresentadas como aprovadas em performance sem comparação equivalente.

Protocolo de medição: Main.tscn real, semente/população/clima/câmera fixados, salvamento desativado, pelo menos 30 segundos por cenário, aquecimento separado, amostras de intervalos reais entre frames e métricas FPS médio (frames/tempo), p50, p95, p99, máximo e contagens acima de 33,3 e 66,7 ms. Registrar GPU, versão, renderer, VSync, MSAA e resolução efetivos. Não rodar benchmarks simultâneos.

Cenários de interesse: aproximação/primeira entrada na Ammu-Nation, interior da loja e banco, travessia do porto com tráfego, roubo/saída de veículo e explosões. Capturas comprovam apresentação; colisão e oclusão são verificações separadas.

## Instrumentação entregue

`tests/measure/video_review_probe.gd` estende os medidores existentes, sem alterar runtime. Usa Main real, registra primeira admissão da sala separadamente, depois 5 segundos de aquecimento e 30 segundos de amostras. Produz `<label>.json`, `<label>-context.json` e `<label>.png`. Os JSON contêm intervalos individuais, estatísticas, CPU/physics disponíveis no Godot, população/veículos, posição, câmera, tempo/clima e informações efetivas de GPU/renderer/resolução.

Configuração fixada apenas no processo: janela 1280×720, VSync ligado, limite 60 FPS, MSAA 2×, dia claro iniciado em 0,45. O relógio do jogo continua evoluindo. A semente real de `scripts/World.gd` é 21092026; `--seed=7` não é interpretado por esse código. O probe exige `--no-save`, não grava configurações e não usa o save do jogador. O limite atual de produção é 40 pedestres; os exemplos antigos com `--population=100` são limitados pelo runtime a 40, e o JSON deve informar a população realmente alcançada.

Limites: cenários `ammunation`/`bank` usam `enter_place`, com a admissão e construção reais, mas não medem a caminhada nem o zoom da fachada. `port` é uma amostra estacionária numa via próxima a (299, 0, 183), não a rota do vídeo. `street --drive` reutiliza a direção física e rota do benchmark existente. Não representa o roubo de moto, nem certifica colisão/oclusão. A comparação precisa repetir o mesmo cenário e argumentos num estado de código estável, sem teste, editor em atividade ou jogo concorrendo por CPU/GPU.

Validação da ferramenta: Godot 4.7.2 `--headless --check-only --script res://tests/measure/video_review_probe.gd` retornou 0, sem erro de parser. O primeiro check em sandbox informou impossibilidade de gravar o log padrão em `user://logs`; isso não é evidência de FPS nem execução do cenário. O probe **ainda não foi executado renderizado**. Cabe validar sua execução antes de tratá-lo como resultado.

## Comandos de comparação

Somente depois de fechar normalmente o jogo existente e de garantir que nenhuma outra sessão está medindo/testando o projeto. Não encerrar processos alheios automaticamente. As correções já começaram; portanto, `before` de uma próxima comparação representa o código antes da próxima alteração, **não** uma reconstrução do código do vídeo.

Exemplo PowerShell (um processo de cada vez):

```powershell
$godotReview = 'D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
$argsReview = @('--path','D:/geteco/game','--script','res://tests/measure/video_review_probe.gd','--log-file','D:/geteco/game/evidence/video-review-20260924/before-ammunation.engine.log','--','--no-save','--skip-arrival','--population=40','--scenario=ammunation','--trace-runtime','--label=before-ammunation','--evidence-dir=res://evidence/video-review-20260924')
$processReview = Start-Process -FilePath $godotReview -ArgumentList $argsReview -WindowStyle Hidden -PassThru -RedirectStandardOutput 'D:/geteco/game/evidence/video-review-20260924/before-ammunation.stdout.log' -RedirectStandardError 'D:/geteco/game/evidence/video-review-20260924/before-ammunation.stderr.log'
$processReview.Id
```

Esperar o término e verificar saída/JSON/imagem antes de iniciar outro cenário. Repetir com `--scenario=bank`, `--scenario=port` e `--scenario=street --drive`, usando labels e logs distintos. Para o comparativo depois da alteração, manter os argumentos e trocar somente os nomes `before-*` para `after-*`. Registrar hashes de código e inventário de processos nos dois momentos; `source-inventory.json` desta revisão apenas registra o início da investigação, não é um projeto congelado.

Para explosões, reaproveitar `tests/measure/measure_vehicle_wreck.gd` (câmera fixa, três explosões em 30 segundos) com o mesmo diretório/label, população e ambiente. Para roubo de viatura, existe `tests/measure/measure_dispatch_theft.gd`. Nenhum desses ensaios substitui a rota completa com moto e portas do vídeo.

## Hipóteses encontradas na inspeção (sem causa medida)

- `NativePlace._ready` carrega o modelo do lugar sincronicamente, percorre malhas várias vezes e monta sólidos. `FullSession.enter_place` acrescenta a sala à árvore antes das esperas de física. São pontos candidatos para separar custo de carga/instanciação, colisão, NPC e primeiro desenho na entrada da loja.
- `NativeRegion._run_build_job` já tem orçamento por frame, porém cada operação de superfícies, record e acabamento é indivisível. Um record ou `CityChunkDressing.build_chunk` caro ainda pode ultrapassar o orçamento. Isso é uma hipótese de investigação, não comprovação do congelamento do vídeo.
- O código local **já continha**, antes desta frente, aquecimento de regiões/frota/grafos, orçamento de 3 ms e duas buscas para spawn de tráfego, e streaming de chunks por etapas. Comentários locais citam medições anteriores de 1,6 s na busca de tráfego e 8–219 ms por chunk. Esses comentários não são novas medições e essas mudanças não devem ser atribuídas a esta revisão.
- `--trace-runtime` habilita custos existentes de spawn de população/tráfego acima de 2 ms. Os registros têm tempo de início/duração; devem ser correlacionados aos intervalos de frame. Ausência de evento nessa instrumentação não absolve os demais subsistemas.

Resultado desta frente: ferramenta reexecutável e escopo de medição preparados; **nenhuma melhoria de FPS comprovada, nenhum benchmark antes/depois obtido e nenhuma aprovação de performance**. Hardware lido: Intel Core i7-13650HX. A captura funcional posterior identificou NVIDIA GeForce RTX 4060 Laptop GPU / Vulkan 1.4.341 / Mobile; a GPU de um futuro benchmark ainda precisa ser registrada no próprio JSON.

Foram executadas separadamente capturas **funcionais**, sem afirmação de FPS, usando `tests/capture/video_review_interiors.gd`. Elas não são uma baseline de performance: 8 pedestres solicitados, despacho externo suspenso, câmera de gameplay e configurações já salvas do usuário. A opção CLI de resolução não anulou a configuração de fullscreen existente, por isso a resolução deve sempre ser conferida no artefato e no processo. A ferramenta de benchmark fixa janela/resolução apenas no próprio processo para evitar essa diferença.

# Esqui da montanha — V2

## Fluxo implementado

No balcão do Summit, o aluguel de R$ 250 fornece roupa, skis e bastões. Saves antigos que têm apenas a roupa continuam oferecendo retirada do equipamento. O serviço funciona das 08h às 18h; a devolução permanece disponível fora desse horário.

As três provas preservam os percursos V1, os portões em ordem, a contagem de três segundos, os pagamentos repetíveis e o bônus por recorde. Pista da Sombra exige as três pistas da expedição. A ação de largada tem prioridade sobre retirar skis; o equipamento reaparece ao reequipar. O marcador ativo recebe a altura do chão do destino. Arcos e bandeiras identificam largada, portões e chegada, com cores por dificuldade. HUD funcional mostra velocidade, tempo, portões, recorde, freio e impulso. A pose mantém os pés nos skis em vez de reproduzir corrida a pé.

Na base (coordenadas V1 7100, -4890), a interação embarca no teleférico. O trajeto segue os quatro pontos do cabo durante seis segundos e permite adiantar. A sessão bloqueia transições e salvamento enquanto o jogador está no ar. O destino prepara colisão e procura uma cápsula livre sobre piso real. Cancelamento retorna à origem; morte, resgate e teleporte externo não são sobrescritos. A viagem libera o estado transitório e a física do jogador.

## Validação

`tests/test_ski_runtime.gd`, com `--no-save --skip-arrival --population=8 --seed=7`: **41 verificações aprovadas** na cena Main real, via Godot 4.7.2 headless. Inclui balcão real, débito e equipamento, três descidas dirigidas por input com `move_and_slide`, contagem parada, arma possuída bloqueada, prêmios, recordes, snapshot, horário do teleférico, desembarque físico, cancelamento, reinício e teleporte externo. Log: `evidence/ski/runtime.log`.

`tests/capture/capture_ski.gd`: captura renderizada de largada/equipamento e passageiro. Imagens em `evidence/ski/ski-equipped.png` e `ski-lift.png`. Ajustes finais de apresentação: alinhamento inicial, passageiro orientado para o assento, postes sustentando as travessas. Não houve alteração de interiores, arquivos de combate ou câmera compartilhados.

## Performance: pendente

Meta provisória: 60 FPS / 16,67 ms; aumentos superiores a 5% em p95/p99 exigem confirmação. Hardware observado: RTX 4060 Laptop, Vulkan Mobile, 1280×720, Godot 4.7.2. Marcadores são um conjunto fixo (17), sem luzes, partículas ou sombras próprias; sondagens de chão são limitadas por proximidade e executadas a 2 Hz. Existe apenas uma cadeira adicional durante a viagem; a pose de esqui é preparada ao equipar e reutilizada.

A primeira tentativa de baseline foi impedida por erro de compilação concorrente em UrbanRoutineActor, depois corrigido pela sessão responsável. Uma execução diagnóstica usou a cópia original de MountainProgression, capturada do HEAD porque o arquivo estava limpo antes desta tarefa, e a mesma cena restante. Amostra de 30,007 s / 794 frames: 26,46 FPS, p50 33,36 ms, p95 100,37 ms, p99 145,73 ms, máximo 160,47 ms; 412 frames acima de 33,3 ms e 81 acima de 66,7 ms. **Não é baseline aceitável**: foram identificados benchmarks de clima e porto e outros testes simultâneos. Nenhum processo alheio foi encerrado. Não foi executado um comparativo posterior concorrente como se comprovasse regressão ou aprovação.

Para concluir, executar `tests/measure/measure_ski.gd` sequencialmente com `--baseline --label=ski-before-isolated` e `--label=ski-after-isolated`, sem outros jogos/benchmarks, mesmos argumentos e estado. Complementar com descida ativa e viagem renderizadas: a rota do harness atual mede o entorno das pistas caminhando. A cópia original está em `evidence/ski/MountainProgression.before.gd.txt`; os JSONs contêm amostras reais, aquecimento, resolução, renderer, VSync e limite de FPS. As capturas emitiram avisos de liberação de textura no encerramento, também presentes no diagnóstico original; não se atribui a causa ao esqui sem investigação.

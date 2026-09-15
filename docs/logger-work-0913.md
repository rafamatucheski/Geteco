# Lenhador: contato e posições laterais — 13/09/2026

O lenhador agora alterna posições de trabalho à esquerda e à direita do toco, chega usando a navegação física e alinha o corpo antes de cortar. O toco e a pilha de lenha têm colisão. A pilha foi afastada para liberar os dois lados. A saída da rotina espera a recuperação do machado; conversa, perigo, combate e deslocamento interrompem o corte.

`LoggerWorkRoutine.gd` sincroniza o ciclo com o impacto. `LoggerChopPose.gd` posiciona as duas mãos no cabo com cotovelos articulados, preparação lenta, descida acelerada, contato e retirada. Os pés permanecem no chão, separados e escalonados. A superfície da peça permanece apoiada no toco, com lascas reutilizadas a cada golpe.

Durante o trabalho, o modelo da madeira é transferido para o mesmo SubViewport do personagem, preservando a estação e suas colisões no mundo 2D. Isso permite oclusão 3D entre corpo, mãos, ferramenta e madeira. A projeção e a escala são calibradas em 13 pixels por metro; a renderização independente da estação volta quando o trabalho para. A aparência do morador e as rotinas das demais profissões foram preservadas.

## Validação

- `--headless --path D:/geteco/game --check-only --script res://world/mountain_pass/WinterResident.gd`: aprovado.
- `--path D:/geteco/game --script res://tests/test_logger_work.gd -- --motion`: 22 verificações aprovadas. Cobrem aproximação nos dois lados, colisão, contorno do toco, ciclo completo, geometria da ferramenta fora da lenha, alcance das mãos (máximo 0,672 m), evento único de impacto, interrupção e recuperação após deslocamento.
- Renderização Vulkan/Mobile do modelo de produção: duas laterais, preparação, levantamento, contato e retirada. Prévia isolada em `D:/geteco/artifacts/logger-0913/lenhador.mp4`; capturas `side*-phase*.png`.
- `D:/geteco/artifacts/logger-0913/integration.gd`: os dois lados passaram em HarborGame com navegação, colisão e impacto nativos. Erro do alvo no contato: 0,0 em ambos. Capturas `integrated-side0.png` e `integrated-side1.png`. A execução também registrou erro externo em `PlayerCombatPose.gd:107`, propriedade `torso_node` ausente em `NPCCombatRig.gd`; não representa aprovação global da cena.
- `test_mountain_bench_rest.gd`: encontrou falha de reserva do banco e falhas derivadas; execução interrompida após diagnóstico. A falha inicial foi reproduzida com o `WinterResident.gd` anterior à alteração, em `baseline-bench-repro.log`. A fixture registra apenas `mountain_bench_seat`, enquanto a rotina já exigia `mountain_bench`. O teste global de bancos não foi aprovado nem alterado nesta tarefa.

## Performance: medição exploratória, não certificada

HarborGame, serra em (8030,895), mesma câmera, seed 912, clima limpo, 1280×720, Godot 4.7.2 Mobile, RTX 4060 Laptop, VSync desligado, limite de 60 FPS. Saves isolados em artifacts. Aquecimento de 120 frames e amostra de 30 segundos. Alvo provisório: 60 FPS / 16,67 ms; aumento maior que 5% em p95/p99 exigiria investigação.

| Métrica | Antes | Depois |
|---|---:|---:|
| Frames | 1424 | 1748 |
| FPS médio | 47,45 | 58,24 |
| p50 (ms) | 17,80 | 16,66 |
| p95 (ms) | 35,41 | 23,49 |
| p99 (ms) | 49,08 | 31,45 |
| Máximo (ms) | 178,64 | 198,49 |
| Frames >33,3 ms | 105 | 13 |
| Frames >66,7 ms | 4 | 3 |

Não se atribui a melhora ao código: havia outros processos Godot de trabalhos distintos abertos, e a carga concorrente não foi controlada. A meta de 60 FPS não foi sustentada; performance permanece pendente de medição sem concorrência. Os JSONs preservam amostras individuais. O ajuste final da posição da lâmina ocorreu depois da medição, mantendo a mesma quantidade de meshes e o mesmo processamento.

Evidências e logs em `D:/geteco/artifacts/logger-0913/`. O diretório contém também cópias dos dois scripts originais desta tarefa para comparação com as alterações locais preexistentes.

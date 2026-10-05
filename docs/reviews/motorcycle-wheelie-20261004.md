# Empinada de moto — 04/10/2026

Implementado em motos de rua (`bike_urban`, `bike_sport`, `bike_cruiser`) e no motocross, por Shift/L3 ou botão de toque, com remapeamento. Pivô no contato traseiro, piloto e mãos acompanham o visual, direção reduzida e descida suave ao soltar/frear. Limite de 35,5°; o casco físico continua apoiado e bloqueia sólidos.

Correção necessária na cadeia de entrada: `FullSession` consumia os dedos antes do overlay no motocross. Agora deixa esses eventos chegar ao overlay, que emite as ações; as ações traduzidas continuam sendo consumidas pela atividade. L3 na moto de rua não alterna corrida do pedestre.

## Validação funcional e apresentação

Godot **4.7.2 .NET**, variante console; `Harbor.csproj` compilado antes de executar. Build final: zero avisos e erros. Não houve fallback para GDScript de sistemas C#.

| Teste | Resultado |
|---|---|
| `test_motorcycle_wheelie.gd` | 62/62 |
| `test_motorcycle_wheelie_flow.gd`, Main renderizada com toque | 16/16 |
| `test_motorcycle_handlebar_pose.gd` | 30/30 |
| `test_dualsense_controls.gd` | 26/26 |
| `test_motocross_launch.gd` | 4/4 |
| `test_motocross_raceday.gd` | 28/28 |
| `test_android_controls.gd` | 51/51 |

**Total: 217 verificações aprovadas.** Cobertura: motos de rua e motocross, aceleração/sustentação/descida, freio, ré, entrada bloqueada, reposicionamento, queda, atitude no ar, carros/IA, contato com parede, pose do piloto e manoplas. Na Main: embarque/desembarque públicos, toque simultâneo, pausa e menu, aluguel e devolução. O teste integrado primeiro expôs o bloqueio dos dedos (duas rodadas falhas); a mudança em `FullSession` corrigiu a causa e a rodada seguinte passou.

Evidências em `C:/Users/rafae/.codex/visualizations/2026/10/04/01a107a0-dd34-7ea1-93bf-369a212b3c7f/wheelie/`. `flow-touch-fixed/` contém capturas e sequências de 20 frames de rua e 10 de motocross, além de GIFs para revisão. Essas capturas têm leitura da GPU e não servem como benchmark. A câmera próxima é instrumentação de revisão; o benchmark usa a câmera de gameplay. Logs dos testes ficam no mesmo diretório. A sandbox emite um erro do armazenamento de certificados na inicialização do motor; não houve erro de script nas rodadas finais.

Nenhum save pessoal foi gravado. Não foram auditados todos os lugares, noites/climas, perseguições, combate ou restauração de saves: a mudança é de estado transitório de pilotagem.

## Performance

GPU RTX 4060 Laptop, Vulkan/Mobile, 1920×1080, preferências normais locais com VSync desligado e FPS sem limite. Cena `Main.tscn`, dia seco. Cada amostra: 8 s de aquecimento e pelo menos 30 s medidos, intervalos reais entre frames. Referência provisória: 60 FPS/16,67 ms; aumento acima de 5% em p95/p99 exigiria confirmação equivalente.

| Rua, roteiro inicial | FPS médio | p50 ms | p95 ms | p99 ms | Máximo ms | >33,3 / >66,7 ms |
|---|---:|---:|---:|---:|---:|---:|
| Antes | 66,49 | 13,76 | 30,32 | 49,98 | 90,38 | 69 / 6 |
| Depois, diagnóstico | 68,64 | 14,09 | 30,74 | 44,92 | 102,75 | 67 / 5 |
| Final, sem concorrência renderizada | 67,68 | 15,17 | 20,50 | 47,02 | 372,10 | 42 / 6 |

**Comparação de regressão inconclusiva; performance global não aprovada.** A baseline coincidiu com trabalho/execuções de outras sessões, e a primeira rodada após a mudança pegou uma dependência de `ClassicMeetController` temporariamente indisponível durante uma edição concorrente. A população e o tráfego também variaram: 35/45 antes, 36/48 no diagnóstico e 38/49 na final. Os números não isolam o custo desta implementação. A rodada final de rua registrou 56 snapshots de processos, sem outra execução renderizada, e 76 frames com a frente elevada; continua com p95/p99 acima de 16,67 ms e um hitch de 372 ms. Não foi demonstrada a causa desse hitch.

A primeira medição final de motocross percorreu a pista renderizada, mas o controle de velocidade usava pouco acelerador e não sustentou empinadas na janela. Está preservada em `final/motocross.json` como diagnóstico sem cobertura da manobra (p95 2,44 ms, p99 3,06 ms). O roteiro foi corrigido para manter torque nos períodos de empinada. Essa rodada foi interrompida quando outra execução renderizada apareceu, após 30 snapshots; somente os processos da própria medição foram encerrados. Logs e snapshots estão em `final-active/`, sem JSON de amostra completa. **Performance de empinadas no motocross permanece não medida**, e também falta uma baseline equivalente.

Métricas brutas, aquecimento, configuração, hashes dos scripts afetados e logs estão nos JSONs da medição; snapshots de concorrência nas rodadas finais em `*-processes.json`. Pendência: comparação antes/depois com estado de fontes, população, tráfego e rota equivalentes e investigação dos picos já presentes na rua. A funcionalidade está validada nos cenários acima; isso não certifica FPS universal ou o restante do jogo.

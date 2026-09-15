# Efeitos veiculares, contato e recarga — 13/09/2026

Fogo e fumaça dos três tipos de veículo usam uma textura radial compartilhada com filtragem linear, transição de cor, tamanho e transparência. A emissão de fumaça densa caiu de até 65 para 20 partículas; o fogo usa 18. Explosões deixam de recalcular fogo, poeira e fragmentos após suas respectivas durações e evitam redesenho fora da câmera. Danos, contagem para explosão e atendimento dos bombeiros permanecem nos sistemas existentes.

A viatura verifica o espaço ocupado pelos cantos ao girar. O teste reproduziu sobreposição com um veículo estacionado antes da correção e nenhuma sobreposição depois. O movimento também preserva a velocidade própria projetada nas normais, sem acumular velocidade transferida pelo solucionador de contato. O arrasto exato relatado pelo usuário não foi reproduzido na cena real; o caso de contato simples passou também antes da mudança. Portanto, a correção comprovada é a prevenção da sobreposição durante giro.

A recarga instantânea do jogador foi substituída por uma ação cancelável. Munição é transferida apenas ao concluir; tiro fica bloqueado durante a ação; troca de arma, entrada no veículo e estados de morte/diálogo cancelam. O rig existente apresenta a recarga e os sons se ajustam à duração compartilhada por arma. Policiais a pé e o passageiro da viatura consomem um carregador real e respeitam a mesma duração. Pausas táticas entre rajadas são independentes; não prolongam a recarga do carregador vazio. Armas corpo a corpo não recarregam.

| Arma | Recarga (s), jogador e polícia |
| --- | ---: |
| pistol | 1.692 |
| magnum | 2.526 |
| smg | 1.481 |
| shotgun | 2.830 |
| sawed_off | 2.626 |
| ak47 | 1.707 |
| m4a1 | 1.802 |
| rpg | 2.738 |
| flamethrower | 2.566 |
| grenade | 0.974 |
| hunting_rifle | 2.726 |

## Validação

Godot 4.7.2. Testes com resultado aprovado:

- `test_manual_weapon_reload.gd`: reserva parcial, HUD, cancelamento/bloqueios de entrada.
- `test_reload_sync.gd`: mãos e arma, som, pausa, cancelamento e bloqueio de tiros.
- `test_reload_audio.gd`: 11 armas, variações de som, recarga automática, transferência única e ausência de vozes acumuladas. A expectativa foi atualizada para duração comum por arma, substituindo a antiga duração variável de cada gravação.
- `test_police_reload_parity.gd`: capacidades de todas as armas, limite temporal, policial real e rotina de tiro do passageiro.
- `test_vehicle_contact_no_drag.gd`: contato, estacionamento, giro bloqueado com obstáculo e liberado sem obstáculo. O caso de giro falha com a versão anterior preservada.
- `test_vehicle_damage_particles.gd`: instâncias reais de tráfego, carro do jogador e emergência; textura, transparência, limites e descarte da explosão. Executado com renderer e capturas inspecionadas.
- `test_vehicle_crash_and_explosion.gd`: deformação, combustão, saída voluntária e explosão.
- `test_police_pursuit_safety.gd`: despacho, perseguição e retorno.

Logs e capturas: `D:/geteco/artifacts/combat-vehicles-0913/`. Alguns testes legados ainda emitem avisos de recursos vivos no encerramento apesar das verificações aprovadas; a captura de partículas e os testes novos encerraram sem esse aviso.

## Performance: pendente de medição comparável

A inspeção renderizada usou Mobile/Vulkan, NVIDIA GeForce RTX 4060 Laptop GPU, janela 1280×720. É uma cena isolada de revisão visual, não uma medição de HarborGame.

Havia benchmarks renderizados de outras tarefas em execução (primeiro estação policial, depois bueiro/esgoto), além do editor e do jogo do usuário. Não foram interrompidos. Não foi iniciado benchmark concorrente, e não há baseline/resultado de FPS, p50/p95/p99 ou máximo para aprovar desempenho. Os arquivos anteriores foram preservados em `before/`, mas isso não constitui baseline medido.

Critério pendente: HarborGame real, mesma máquina/câmera/população/clima/save isolado, aquecimento separado e pelo menos 30 segundos de explosões/danos por variante; 60 FPS / 16,67 ms como alvo existente; aumento acima de 5% em p95/p99 requer investigação. Registrar também frames acima de 33,3/66,7 ms e o custo das novas consultas de giro. A redução de partículas é verificável; eliminação dos travamentos ainda não está comprovada.

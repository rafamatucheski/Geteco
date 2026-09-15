# Machado: empunhadura, golpes e efeitos — 13/09/2026

Implementado no Player e nas apresentações compartilhadas: cabo arredondado com região de pegada, cabeça de aço perfilada e fio separado; duas mãos apoiadas no cabo durante preparação, corte e recuperação. Os ataques alternam vertical e lateral. Ambos completam a animação em 0,72 s, aplicam contato em 0,28 s e preservam intervalo de 0,85 s, alcance de 66 pixels e dano 52 do catálogo. Trocar a arma ou ocultar o jogador cancela o golpe pendente. Paredes impedem dano através do obstáculo.

O rastro segue a lâmina, usando um MultiMesh de seis segmentos reutilizáveis, sem luz nem sombra, com amostras de 0,09 s. Impactos reutilizam os efeitos e o pool de áudio por material do combate. O rastro não tem processamento independente por frame: recebe as atualizações da pose enquanto o machado está equipado.

## Validação

Finalização lateral ajustada para manter o cabo apontado para fora e a cabeça à frente do tronco até retornar à guarda. Validados os limites de toda a cabeça durante a recuperação, direção do fio, amplitude lateral e ambas as mãos; `test_axe_swing.gd` passou. Revisão renderizada em três ângulos: `D:/geteco/artifacts/axe-0913/machado-ponta-para-fora.mp4`. Alteração apenas nos alvos da pose, sem novos nós ou processamento; desempenho no mapa continua não medido.

Correção posterior do swing lateral: rotação da cabeça invertida durante o corte para o fio conduzir o movimento. A regressão de direção do fio falhou antes e passou depois da correção nas duas variantes; a empunhadura continua validada. Prévia atualizada: `D:/geteco/artifacts/axe-0913/machado-fio-corrigido.mp4`.

- `test_axe_swing.gd`: aprovado, duas variantes alternadas, ambas as mãos no cabo em todo o movimento, trajetórias distintas, lâmina acima do piso, descarte do rastro, dano somente no contato, impacto visual, cancelamento e parede.
- `test_player_combat_pose.gd`: aprovado, 16 armas. A verificação de cano apontado para frente foi substituída apenas para o machado pela postura de guarda com cabeça levantada; empunhadura e suporte continuam verificados.
- `test_knife_single_target.gd`: aprovado; o caminho de facadas conserva os contratos anteriores.
- `capture_axe_motion.gd`: Player e modelos de produção renderizados em Vulkan/Mobile, três ângulos e duas variantes, com revisão dos quadros. Captura isolada, não uma execução do interior completo mostrado pelo usuário. A geração manual dos quadros desativa interpolação na fixture e aquece os materiais antes de capturar; houve quadros incompletos durante aquecimento de shaders nas primeiras tentativas. A filmagem final tem 96 quadros a 30 FPS de reprodução; isso não mede desempenho real.

Evidências: `D:/geteco/artifacts/axe-0913/machado.mp4`, `poses.png`, `before-poses.png`, logs e scripts anteriores em `before/`. Alguns testes anteriores emitiram avisos de recursos em uso no encerramento; o teste final do machado encerrou sem esses avisos.

## Performance

Estado: não medido no mapa completo. Havia benchmark renderizado de outra tarefa (`measure_dante_gait.gd`), editor e jogo abertos; esses processos foram preservados e não foi iniciado benchmark concorrente. A revisão visual usou Godot 4.7.2, Mobile/Vulkan e RTX 4060 Laptop. Não há comparação válida de FPS ou p95/p99, nem certificação do custo de primeira utilização dos shaders. Critério pendente: mesma cena HarborGame, condições equivalentes e pelo menos 30 s por variante, com aquecimento separado; alvo existente 60 FPS/16,67 ms e investigação de piora acima de 5% em p95/p99.

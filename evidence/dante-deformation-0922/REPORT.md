# Dante: deformação de braços e armas — 22/09/2026

## Causa demonstrada

A referência obrigatória foi inspecionada em 18, 20, 23, 26, 28, 33, 35 e 38 segundos (`reference-sheet.jpg`). O mesmo defeito foi reproduzido na **Main.tscn produtiva**, começando com SMG, mira em oito direções, movimento para trás/lateral, corrida e troca para pistola/magnum/escopeta.

O IK bilateral regravava transformações globais completas de coluna, braço, antebraço e mão, até oito vezes por frame. A decomposição dessas matrizes de volta para posição/rotação/escala locais introduzia pequenos desvios de escala; os desvios alimentavam as iterações e frames seguintes. As trilhas de rotação das animações e o cache/mistura de poses que guardava somente posição/rotação não eliminavam essa escala residual. O resultado era alongamento crescente, separação aparente das mãos/armas e triângulos atravessando a tela. O motor também reportava bases não normalizadas em `set_bone_global_pose`.

Evidência quantitativa:

- Regressão isolada, 600 frames: erro de escala chegou a **0,171113**, enquanto o desvio do comprimento local permaneceu em **0,00000714 m**. Ver `before-regression.log`.
- Main original: primeiro erro de escala de braço >0,1 no passo **236**. Crescimento posterior até **9,6113 × 10¹⁰**. Ver `before-capture/report.json` (captura, **não benchmark**).
- Após a correção, a Main inicial completou a sequência instrumentada com erro máximo de escala de braços **0,000000253**, sem violação desse limite. O percurso inicial acabou passando pelo modal de resgate; por isso esse vídeo não comprova sozinho a execução produtiva de todas as armas e não serve para comparar desempenho.

Hipóteses verificadas: conversão mundo/esqueleto e a escala uniforme 1,03 do modelo foram mantidas; a regressão cobre ator transladado e girado. Comprimentos locais praticamente constantes antes do defeito descartam o alvo de IK ou o comprimento de repouso como causa do crescimento. A ordem existente animação → IK → montagem foi preservada. Não houve mudança do GLB, malha, sombras, modelos de armas ou alvos de empunhadura.

## Correção

`scripts/Actor.gd` passa a converter somente a orientação desejada do espaço do esqueleto para o espaço local do osso, ortonormalizando as bases e normalizando o quaternion. O IK escreve **apenas rotação local**, preservando translações e escalas autorais. Captura, aplicação e mistura de poses agora também carregam escala.

`gameplay/WeaponRigPose.gd` e `gameplay/WeaponPoseData.gd` foram investigados e permaneceram intactos. As coordenadas de cabo/apoio, recuo, recarga, bases e proporções das armas não mudaram. Na V1, `MeshyDanteRig.prepare_pose` já restaura transformações completas antes de resolver os braços; a V2 passa a manter essa estabilidade sem substituir suas animações.

`Gameplay.gd` não foi editado. Nenhum patch de integração é necessário para corrigir o crescimento. Arquivos de polícia, iluminação e materiais urbanos não foram alterados por esta frente.

## Validações

| Verificação | Resultado |
|---|---|
| `tests/test_dante_deformation.gd` | PASS: 600 frames da reprodução + 30.720 frames (16 armas × 8 direções × 240) + 960 frames de trocas durante recuo/recarga/corrida |
| Invariantes da regressão | Posição e escala locais, alcance das palmas, contato da mão de apoio, matrizes finitas; não se limita à finitude |
| Maior desvio posição/escala nos ossos | 0,000000253; erro máximo de apoio 0,05556 m, dentro do contrato existente de 0,080 m |
| `test_weapon_presentation_contract.gd` | PASS: 148 checks |
| `test_actor_locomotion_idle.gd` | PASS: 13 checks, incluindo parede, repouso, corrida e saída de golpe |
| `test_combat_flow.gd` | PASS: 67 checks na Main, incluindo combate, recarga/transições e garagem V2 |
| V1 `tests/test_garage_weapon_restrictions.gd` | PASS: 30 checks / zero falhas / exit 0; houve avisos de recursos retidos no encerramento headless, preservados no log |

Comandos: motor `D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`, `--headless --path D:/geteco/game/geteco_v2 --script res://tests/<teste>.gd`. Combate: `-- --no-save --skip-arrival --population=8 --seed=7`. Garagem V1: `--path D:/geteco/game --script res://tests/test_garage_weapon_restrictions.gd`; a fixture usa diretório temporário de save.

A revisão visual reutilizou o atlas V1 em `artifacts/combat-parity/arsenal-v1/arsenal-v1-ready.png` e gerou imagens V2 em `arsenal-v2/`. A ferramenta de atlas existente apresentou incompatibilidade RGB/RGBA no `blit_rect`; os PNGs individuais estavam corretos e foram recompostos em `arsenal-ready-reassembled.jpg`. O teste de captura recebeu conversão explícita para RGBA8 para futuras execuções. Essa composição não é evidência de FPS.

Vídeos finais:

- [Antes/depois lado a lado — 16 s](before-after-final.mp4): baseline à esquerda, correção à direita, na Main real.
- [Reprodução anterior — 16 s](before-demonstration.mp4): recorte da reprodução com o Actor congelado anterior. A execução longa foi interrompida após deformação conclusiva e valores não finitos em cascata.
- [Todas as armas após a correção — 64 s](after-all-weapons.mp4): 640 quadros da Main, 99 ataques aceitos, sem erros/avisos, sem modal de resgate, erro máximo de escala de braço de 0,000000253. Log e dados em `after-verified-capture.log` e `after-verified-capture/report.json`.

Os vídeos são sequências do viewport real, codificadas a 10 quadros/s (um PNG a cada seis passos do roteiro); a captura adiciona custo e sua duração de reprodução não representa tempo real de benchmark. As primeiras gravações `before-main.mp4`, `after-main.mp4` e `comparison-main.mp4` são exploratórias e foram substituídas pelos vídeos finais acima. A fixture final mantém vida elevada para impedir que o resgate interrompa a apresentação, sem alterar o código de dano do produto.

## Arquivos desta frente

- `scripts/Actor.gd`: correção produtiva.
- `tests/test_dante_deformation.gd`: regressão multiframe.
- `tests/capture_dante_deformation.gd`: roteiro na Main, captura e amostragem de frame time.
- `tests/measure_dante_deformation.ps1`: monitoramento de concorrência, timeout e logs do benchmark.
- `tests/capture_arsenal_presentation.gd`: duas conversões de formato no compositor do atlas.
- `evidence/dante-deformation-0922/`: vídeos, imagens, logs, cópia congelada do Actor anterior e este relatório.

A fixture `Actor.before.gd` é a cópia anterior exata; é registrada no cache de recursos antes de carregar a Main apenas com `--dante-baseline`. Isso permite medir a versão anterior sem reverter nem sobrescrever arquivos compartilhados. O hash do código carregado é impresso em `DANTE_ACTOR_SOURCE`.

## Performance e limitações

Alvo provisório: **60 FPS / 16,67 ms**. Critério definido antes da comparação: aumento >5% em p95/p99 requer confirmação finita equivalente. Hardware: NVIDIA GeForce RTX 4060 Laptop GPU, Godot 4.7.2, Mobile/Vulkan, 1280×720, limite 60 FPS, VSync desativado na configuração efetiva. Main produtiva com população 24 e tráfego; nenhum save do usuário é gravado.

Os tempos nos diretórios `*-capture` incluem leitura da GPU e gravação de PNGs e **não aprovam performance**. O primeiro benchmark foi interrompido quando iniciou a captura dos policiais; `before-processes-aborted.json` documenta a concorrência. Outra captura complementar foi interrompida por erros de compilação transitórios nos arquivos de efeitos de veículos editados por outra frente. Esses arquivos não foram corrigidos por esta tarefa.

O teste alheio `test_v2_walk.gd` permaneceu ativo sem timeout e chamava um método inexistente na sessão atual. Após autorização explícita do usuário, somente seus PIDs 59804 e 45956 foram encerrados para liberar a janela de medição. O editor permaneceu aberto nas duas condições.

## Comparativo isolado concluído

Comandos aceitos: `tests/measure_dante_deformation.ps1 -Label before-final -Baseline` e `tests/measure_dante_deformation.ps1 -Label after-isolated`. A primeira tentativa corrigida (`after-final`) foi interrompida quando apareceu uma prévia externa do modelo do Maciota; essa amostra foi descartada. A baseline válida foi reutilizada porque os hashes de código de integração permaneceram iguais. Os manifests excluem testes, evidências, cache e assets; o modelo produtivo `assets/maciota/MaciotaModel.gd` permaneceu com modificação de 21/09, anterior ao par.

| Métrica | Antes | Depois |
|---|---:|---:|
| Frames renderizados amostrados | 2.983 | 3.357 |
| Duração da amostra | 62,584 s | 55,996 s |
| FPS médio (frames / tempo) | 47,66 | 59,95 |
| Frame time p50 | 16,659 ms | 16,663 ms |
| Frame time p95 | 21,112 ms | 18,321 ms |
| Frame time p99 | 157,141 ms | 22,888 ms |
| Máximo | 2.021,489 ms | 66,922 ms |
| Frames >33,3 ms | 88 | 5 |
| Frames >66,7 ms | 50 | 1 |
| Erro máximo de escala dos braços | 126,712 | 0,000000253 |
| Primeiro passo com erro >0,1 | 534 | nenhum |
| Ataques aceitos pelo gameplay | 70 | 71 |

As execuções usam o mesmo roteiro de 3.840 passos, mesma câmera (tamanho 12), semente do combate 7, população 24, tráfego e horário 0,36. A gravação de PNGs está desativada. Os 480 passos iniciais são aquecimento; o restante inclui as transições e os primeiros usos das armas seguintes, portanto os máximos não são descartados como outliers. As durações reais diferem porque o motor não mantém a cadência de física/renderização diante dos travamentos da versão anterior; cooldowns resultaram em diferença de um ataque aceito. Não se trata de um microbenchmark puro de IK nem de um teste estatístico de equivalência de eventos de combate.

Os logs de processos registram **nenhum runtime concorrente** durante as amostras aceitas (59 observações antes, 53 depois); apenas o mesmo editor ficou aberto. Os tempos são intervalos reais entre frames, não o contador suavizado de FPS; não há instrumentação separada de CPU/GPU/espera. Amostras completas: `before-final-measure/report.json` e `after-isolated-measure/report.json`.

**Resultado:** sem regressão observada nesse cenário, p95 reduzido em 13,22% e p99 em 85,43%, com média próxima de 60 FPS. A meta estrita de 16,67 ms em todos os frames **não foi atingida**: p95 de 18,321 ms e um pico de 66,922 ms permanecem. Não há aprovação universal de performance, nem atribuição desses picos remanescentes a um subsistema sem perfil adicional. A deformação e a estabilidade multiframe foram corrigidas e verificadas; otimização global da cidade está fora desta frente.

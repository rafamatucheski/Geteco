# Dante — avaliação das animações e plano de correção

24/09/2026. Avaliação do código e dos recursos atuais em D:/geteco/game. Nenhum arquivo produtivo foi alterado por esta avaliação. Foram criados apenas roteiros de diagnóstico, imagens, dados e este relatório nesta pasta.

**Conclusão:** a base funciona, mas a apresentação ainda tem descontinuidades reais nos braços, pouca participação do corpo nos golpes, giro sem passos e locomoção direcional incompleta. O problema de braços crescendo não reapareceu no teste atual; isso não impede os estalos de rotação demonstrados abaixo.

**Evidências e alcance.** Foram amostrados visualmente os 17 clipes do GLB, o controlador de repouso/caminhada/corrida/giro, as ações dos 16 perfis de combate, os dois socos, as quatro variantes de soqueira, as três de faca e recargas das dez armas de fogo. As imagens de estúdio usam o Actor e o solucionador de braços produtivos. Na Main renderizada, foram aceitos e observados dois socos, um golpe de machado e um disparo de SMG. A Main usou --no-save --skip-arrival --population=8 --seed=7, vida elevada para evitar interrupção e câmera aproximada. Veículos e integração da escada foram inspecionados no código; não receberam validação visual integrada nesta avaliação.

As pranchas são sequências de poses, não vídeos em tempo real. As recargas isoladas percorrem o progresso normalizado em um segundo para inspecionar poses; essa duração não representa o áudio/tempo de recarga do jogo. No estúdio não foram reproduzidas as peças móveis das armas, projéteis nem a segunda malha de soqueira da mão esquerda. Não inferir defeitos desses elementos por essas imagens. A Main tem observação separada em cada passo de física; os números de rotação abaixo não são diferenças entre capturas espaçadas.

**Problemas em ordem de prioridade**

| Prioridade | Movimento | Problema e evidência | Correção proposta |
|---|---|---|---|
| P1 | Socos — braços | Na Main, salto local de **109,13° no antebraço esquerdo** e **117,56° no direito** em um único passo de física no retorno. Não são medidas de hiperextensão anatômica: incluem a torção do osso. O estado observado logo após a troca tinha idade 0,35 s. No isolado ocorreram saltos de 100,12°/109,06°. | Corrigir a continuidade do plano de dobra do cotovelo. O término de `punching` troca `right_free`/`left_free` de forma binária. Misturar a solução de golpe para a solução livre preservando o lado do cotovelo e a rotação do antebraço. |
| P1 | Machado e taco — punhos | **141,69° no punho direito do machado**, reproduzido também na Main. Taco: 146,66° no isolado. A posição da mão pode permanecer próxima enquanto a orientação estala. | Rastrear orientação desejada versus orientação realizada, continuidade da torção e entrada do apoio bilateral. Rever distribuição de torção entre antebraço e punho; não mascarar o defeito apenas filtrando a posição da mão. A causa exata do salto do machado ainda requer esse isolamento. |
| P1 | Socos, soqueira e faca — movimento completo | Soco sem arma sai de junto do quadril e retorna para baixo; a outra mão fica baixa. Tronco, quadril e pés quase não participam. Soqueira tem guarda e quatro trajetórias, mas falta transferência de peso; a faca também fica concentrada no braço. Confirmado nas sequências de frente, lado e três quartos. | Criar preparação, contato e recuperação com guarda, rotação coordenada do tronco/quadril e resposta dos pés. Preservar diferenças entre direto, gancho e golpe ascendente. Avaliar o `Punch_Combo` como referência, não ativá-lo indiscriminadamente. |
| P1 | Orientação do punho fechado | O caminho `not gripping` do IK restaura a rotação local da mão e retorna antes de aplicar a orientação desejada da palma. A soqueira calcula bases diferentes por golpe, mas esse caminho não as aplica à mão. | Separar os estados mão livre, punho de combate e empunhadura. Dar ao punho fechado controle de orientação, com limites coerentes e sem alterar comprimento/escala dos braços. |
| P1 | Giro parado e mudança brusca de mira | A rotação da mira é atribuída diretamente a `visual.rotation.y`. Os pés conservam a mesma pose: o personagem gira como uma peça inteira. Não existe estado de passos de giro. | Criar giro parado para esquerda/direita, começando por 90°/180°, separando orientação de mira e base. Manter o pé de apoio até a troca e limitar a diferença de orientação do tronco. |
| P1 | Deslocamento lateral e para trás mirando | A 3,5 m/s, os três clipes armados são recusados pelo limite de velocidade. O deslocamento lateral usa passada para a frente; para trás usa o ciclo comum invertido. A amostra confirmou `Walking` lateral e para trás em velocidade normal. | Locomoção direcional com frente/trás/esquerda/direita e diagonais misturadas, velocidades compatíveis e fase de apoio contínua. Os clipes lentos existentes não devem apenas ser acelerados sem limite. |
| P2 | Repouso | Não existe Idle. A pose é média de dois momentos de Walking e fica estática, com joelhos flexionados e postura herdada da caminhada. A volta ao repouso funciona, mas falta naturalidade. | Criar repouso autoral com base confortável, respiração discreta e pequenas transferências de peso; separar repouso livre e guarda de combate. |
| P2 | Caminhar/correr, arrancar e parar | A velocidade muda imediatamente; a pose leva aproximadamente 0,143 s para entrar/sair da caminhada e 0,222 s para trocar caminhada/corrida. O corpo não tem preparação/frenagem. A 3,5 m/s, a caminhada de 1,8 m/ciclo resulta em aproximadamente 233 passos/min, se considerados dois apoios por ciclo: sensação apressada. | Calibrar passada, velocidade e cadência em conjunto, preservando resposta dos controles. Acrescentar entrada/saída e pequenos ajustes de apoio; evitar fazer os pés voltarem ao repouso deslizando pelo chão. Quantificar deslizamento na implementação. |
| P2 | Corrida com analógico parcial/obstrução parcial | `_run_weight` usa velocidade solicitada >4,0, não a real. Foi reproduzida pose Running com velocidade real de 1,0 m/s e corrida solicitada: corrida em câmera lenta. | Misturar caminhada/corrida pela velocidade real, com transição estável; alinhar o critério das pernas ao dos braços, que já usa velocidade real no Gameplay. |
| P2 | Costura dos ciclos | Diferença máxima de rotação local entre fim/início do controlador: Walking 3,02°, Running 6,07°. Indício de costura a polir, menor que os defeitos dos braços. | Ajustar trecho e fase dos ciclos, verificando pés e braços na passagem; comparar com velocidade angular normal da animação. |
| P1/P2 | Recargas e granada | No isolado, várias recargas trocam abruptamente orientação do braço/punho; SMG teve salto local de 110,18° na entrada. Granada: 106,88° no antebraço na entrada. O booleano de empunhadura muda o ramo do IK. A Main não foi usada para validar essas recargas. | Reproduzir com temporização real; misturar soltar/pegar, orientação da palma e apoio. Sincronizar lançamento visível da granada com criação do projétil: hoje o projétil nasce em `fire_at`, enquanto o gesto mantém a granada até 0,20 s. |
| P2 | Contato dos golpes | O dano de corpo a corpo é resolvido em `fire_at`, antes do pico visual do soco/golpe procedural. | Definir janela de contato coerente com o gesto. Se mudar o momento do dano, testar cooldown, cancelamento, troca de arma e evitar aplicação dupla. |
| P2 | Morte e reação a dano | A queda produtiva procura membros Node3D; no Dante com Skeleton3D encontrou **zero articulações**. A sequência gira o corpo inteiro sem animar os ossos. Há `dying_backwards` no GLB com queda articulada. Dano não fatal no jogador aciona voz, sem a reação visual `_flinch`, que exclui o jogador. | Adaptar a apresentação ao esqueleto real ou integrar trecho do clipe de morte, respeitando contato com chão. Criar reação breve de impacto que possa coexistir com locomoção. |
| P2 | Entrada em veículos | O código de carro aplica a pose parada e baixa/translada o visual; não anima a flexão prometida pelo comentário. Moto/buggy também aplicam pose parada, sem levantar a perna. | Criar poses de alcance da porta, agachar/sentar e passar a perna; sincronizar mãos/pés com pontos do veículo. Confirmar visualmente por classe de veículo antes de fechar. |
| A verificar | Escada | `Fast_Ladder_Climb` movimenta o quadril verticalmente e a transição também translada o ator. A integração precisa de conferência de raiz e de contato com degraus. Não foi demonstrado aqui um defeito integrado. | Medir deslocamento combinado, evitar dupla aplicação do movimento vertical e conferir mãos/pés na escada real. |

Código relevante: [Actor — locomoção](D:/geteco/game/scripts/Actor.gd:231), [Actor — IK](D:/geteco/game/scripts/Actor.gd:446), [poses de soco](D:/geteco/game/gameplay/WeaponRigPose.gd:186), [recarga](D:/geteco/game/gameplay/WeaponRigPose.gd:244), [queda](D:/geteco/game/gameplay/CharacterFallPresentation3D.gd:100), [veículos](D:/geteco/game/gameplay/VehicleBoardingPresentation.gd:166).

**Inventário completo dos clipes importados**

| Clipe | Duração | Uso encontrado / leitura da amostra |
|---|---:|---|
| Walking | 1,033 s | Locomoção principal; também serve de matéria-prima para a pose parada. |
| Running | 0,700 s | Corrida principal; amplitude distinta, transição controlada por velocidade solicitada. |
| Attack | 2,867 s | Golpe amplo de corpo inteiro. Ainda existe suporte/teste de `combat_clip`, mas o ataque produtivo normal usa o caminho procedural. |
| Fast_Ladder_Climb | 0,833 s | Escada e entrada em veículos altos; contém deslocamento vertical. |
| Punch_Combo | 2,533 s | Guarda, rotação e base mais completas que o soco procedural. Não encontrei acionamento no gameplay pesquisado. |
| Punch_Forward_with_Both_Fists | 3,533 s | Sequência ampla de socos; excluída do golpe produtivo normal. Não é substituição direta sem ajuste de tempo e locomoção. |
| Rifle_Charge | 0,567 s | Corrida com braços em postura de arma; sem acionamento encontrado. |
| Rifle_Charge_inplace | 0,567 s | Variante da anterior; sem acionamento encontrado. |
| Spartan_Kick | 1,500 s | Chute com inclinação de tronco; sem acionamento encontrado. |
| Swim_Forward | 4,600 s | Nado com corpo horizontal; sem acionamento encontrado. A existência do clipe não implica que nado seja mecânica disponível. |
| Walk_Backward | 0,967 s | Passada para trás disponível, mas não selecionada pelo controlador atual. |
| Walk_Backward_While_Shooting | 1,333 s | Recuo armado disponível, sem seleção encontrada. |
| Walk_Backward_with_Grenade | 1,300 s | Usado apenas em recuo lento mirando com granada. |
| Walk_Backward_with_Gun | 1,067 s | Usado apenas em recuo lento mirando com arma de fogo. |
| Walk_Left_with_Gun | 1,300 s | O controlador o mapeia para direita pelo movimento do recurso, apesar do nome. Só cobre um lado e baixa velocidade. |
| dying_backwards | 2,300 s | Queda articulada disponível, não usada pelo caminho atual de morte do Dante. |
| restpose | 0,067 s | T-pose técnica, não animação de repouso. |

Ausência de uso, por si só, não é bug. Não proponho habilitar chute, nado ou investida fora das mecânicas desejadas.

**Ordem de implementação recomendada**

1. **Braços e continuidade:** corrigir primeiro socos e punhos de machado/taco; depois entrada/saída de recarga e granada. Separar intenção de mão livre/punho/empunhadura, manter continuidade do cotovelo e distribuir torção. Preservar a correção existente de escrita apenas de rotação local e os comprimentos do esqueleto.
2. **Qualidade dos golpes:** guarda, preparação, contato e recuperação; participação de ombro, tronco, quadril e base. Incorporar animação autoral onde o alvo de mão por código não consegue produzir um gesto convincente. Misturar por partes do corpo para permitir atacar andando sem congelar ou deslizar pernas.
3. **Locomoção:** repouso próprio, giro com passos, deslocamento direcional e mistura por velocidade real; em seguida calibrar cadência, entrada/saída, curvas e costura dos ciclos.
4. **Interações e reações:** morte articulada, reação a dano, entrada/saída de cada classe de veículo e contato na escada. Revisão de terreno inclinado e apoio dos pés faz parte dessa etapa.
5. **Aceitação:** comparar sequências antes/depois em vista frontal, lateral, três quartos e câmera normal. Exercitar socos dos dois lados, quatro variantes de soqueira, três de faca, todas as armas, trocas durante ataque/recarga, repouso, corrida, giros 90°/180°, oito direções e bloqueio por sólidos. Exigir ausência de estalos e interpenetração perceptível; medir continuidade angular/posição, deriva dos pés durante apoio e contato das palmas. Não basta verificar finitude/escala dos ossos. Validar garagem sem armas e proteção permanente de Maciota/mecânico se combate ou transições forem alterados.

Antes e depois da implementação, medir Main renderizada em condições equivalentes, ao menos 30 segundos por cenário crítico, sem captura de PNG durante benchmark: FPS médio, frame time p50/p95/p99/máximo e frames >33,3/>66,7 ms. Preservar limites de custo do IK e evitar trabalho adicional por NPC não afetado. Nesta avaliação **performance não foi medida nem aprovada**.

**Verificações executadas nesta avaliação**

- `tests/test_actor_locomotion_idle.gd`: **13 checks aprovados**, incluindo parede, parada, interrupção automática e saída de golpe.
- `tests/test_dante_idle_return_independent.gd`: **8 checks aprovados** na Main, com entrada real: caminhar/correr, parar sem deriva e voltar à pose de repouso.
- `tests/test_dante_deformation.gd`: **aprovado**, com 600 frames iniciais, 30.720 frames de transições e 960 de trocas. Erro máximo de posição/escala nos casos multiframe: 0,000000253. A mão esquerda chegou a 0,07784 m de erro no apoio da AK47, dentro do limite existente de 0,080 m; esse contrato é permissivo para avaliar contato visual fino.
- Main renderizada: quatro ações aceitas; saltos dos dois socos e machado confirmados pelos dados em `main-review.json`. SMG não apresentou salto comparável nessa sequência de disparo (máximo 3,84°).
- Ambiente: Godot 4.7.2, Vulkan Mobile, RTX 4060 Laptop. A captura Main efetiva tem 2560×1440. Avisos de permissão de log/certificados ocorreram nos testes headless sandboxados; os testes executaram e encerraram com código 0. A primeira captura não conseguiu gravar e foi descartada; a captura autorizada gravou as evidências com sucesso.

As execuções headless usaram o motor `D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`, `--headless --path D:/geteco/game --script res://tests/<nome>.gd`; a integração de repouso recebeu `-- --no-save --skip-arrival --population=8 --seed=7`.

Hashes ao término: Actor `6BB37D661B56700B830B1BD7A59E75C736C1F5212E8C2B1E037B9FA2ED992EE6`; WeaponRigPose `FFCC9708CD00C42C00ED38B84E8F29AB9FBB59C571234AE30AA12455E2FBEF69`; dante.glb `8BD9F8C9E26573ACB63572948D078F1A05E98624119883786E4F2DF185CDE281`. Há outras sessões modificando o repositório; as conclusões se referem a essa versão e às amostras registradas.

**Pranchas e dados**

- [Socos: dois lados, frente e perfil](D:/geteco/game/evidence/dante-animation-review-0924/punches.jpg)
- [Quatro golpes de soqueira](D:/geteco/game/evidence/dante-animation-review-0924/knuckles.jpg)
- [Faca, machado, taco e granada](D:/geteco/game/evidence/dante-animation-review-0924/melee.jpg)
- [Repouso, caminhada, corrida, lateral, giro e morte](D:/geteco/game/evidence/dante-animation-review-0924/locomotion.jpg)
- [Recargas 1](D:/geteco/game/evidence/dante-animation-review-0924/reload1.jpg) e [recargas 2](D:/geteco/game/evidence/dante-animation-review-0924/reload2.jpg)
- [Disparos 1](D:/geteco/game/evidence/dante-animation-review-0924/attack1.jpg) e [disparos 2](D:/geteco/game/evidence/dante-animation-review-0924/attack2.jpg)
- [Clipes 1](D:/geteco/game/evidence/dante-animation-review-0924/clips1.jpg), [clipes 2](D:/geteco/game/evidence/dante-animation-review-0924/clips2.jpg), [clipes 3](D:/geteco/game/evidence/dante-animation-review-0924/clips3.jpg)
- [Dados isolados](D:/geteco/game/evidence/dante-animation-review-0924/review.json), [dados na Main](D:/geteco/game/evidence/dante-animation-review-0924/main-review.json) e [log Main](D:/geteco/game/evidence/dante-animation-review-0924/main-render.log).

# Noite de Acerto — opção 1 no jogo

Implementação de 18/10/2026 em Godot 4.7.2 .NET, dividida entre três agentes: ambiente/fila, pilotagem/HUD/áudio e progressão. Integração e validação coordenadas no mesmo workspace, preservando as alterações concorrentes de outras sessões.

**Registro da primeira rodada.** A [continuação de 18/10](continuidade.md) acrescenta música própria, acabamento do corredor, desafios e peças dos rivais, categorias, empréstimos, telemetria e perfil separado. Também contém a correção posterior do descarte no encerramento e a revisão compacta da HUD. Os resultados, falhas e números abaixo permanecem como evidência histórica dessa primeira rodada.

## O que está jogável

O quadro dos rivais agora abre a **Noite de Acerto**: o mesmo carro faz 201 m, duas passadas de 402 m e um duelo de 800 m. Vencer os 201 m e os 800 m vale um ponto por prova; comparar o melhor tempo de cada lado nas duas passadas de 402 m decide o terceiro ponto. Dois pontos vencem a noite. A diferença entre as passadas aparece como feedback de consistência, sem alterar a pontuação. Perder uma prova permite continuar. O resultado oferece continuar, ver a noite ou ficar no local.

Entre provas, o jogador reinstala peças possuídas ou aplica seus ajustes salvos. A segunda passada de 402 m exige a mesma preparação mecânica da primeira. A inscrição mantém a identidade do carro; os recordes distinguem perfil mecânico, distância e peças, sem criar categorias por pintura ou identidade individual do veículo. Cancelar a tentativa ou apenas o ticket da fila preserva a passagem pendente. Encerrar a noite elimina a inscrição incompleta e cancela seu ticket, caso ainda esteja na fila.

Concluir as quatro passadas paga R$ 600; vencer a noite acrescenta R$ 300. Os recibos impedem pagamento duplicado. Carteira cheia preserva o saldo pendente, inclusive quando só uma parte foi paga. A primeira noite vencida acrescenta um único mérito ao desbloqueio de peças: somada às seis vitórias ranqueadas da arrancada, permite atingir os sete méritos exigidos pelo nitro profissional sem usar vitórias de campanha. Repetições pagam o prêmio, mas não acumulam novos méritos. Corridas ranqueadas e campanha mantêm seus estados próprios; a ponte continua dependente da última missão.

## Detalhes de experiência

- **Pátio com atividade:** corpos atuais de NPC, seis visitantes com seis modelos mecânicos distintos, variedade nos carros expostos, grupos com ferramentas, tenda e público atrás da barreira junto à largada. Reaproveita as quantidades existentes, sem povoamento ilimitado.
- **Som do lugar:** alto-falantes, público, atividade de oficina e três falas canônicas próximas de seus personagens, com intervalo e prioridade de diálogo. Música e gravações foram reaproveitadas; ainda não há trilha original inédita.
- **Fila física:** corrigida a borda elevada da entrada. Inscrição permanece ao sair a pé; troca ou perda do carro cancela com motivo. Uma bateria obstruída espera e retoma quando o obstáculo físico sai. Os NPCs retornam dirigindo pela via própria, sem substituir o carro; o botão de retorno do jogador reposiciona seu carro após verificar apoio e espaço livre.
- **Largada e câmbio:** pedal digital progressivo, faixa boa mais acessível e penalidade contínua. Trocas passam por desacoplamento e retorno de torque/RPM; pressionar de novo durante a troca não apaga o feedback. O comportamento fora da corrida permanece separado.
- **HUD:** conta-giros semicircular compacto em âmbar, marcha e faixa de troca legíveis, informações da prova e rival. Teclas literais, como SHIFT, não passam pela tradução de ações. Painéis já comprados continuam disponíveis.
- **Motor próprio:** papel local de primeiro plano para o jogador; rival mantém som espacial com alcance e ganho reduzidos. A configuração anterior é restaurada ao sair da corrida.
- **Horizonte e percurso:** silhuetas de mesas mais amplas, seção corrigida para evitar faces dobradas e retenção de 26 células do corredor visto pela câmera. Preparação usa o orçamento incremental existente e libera a área ao se afastar.

## Defeito físico adicional encontrado na validação

A revisão da prova longa detectou perdas súbitas de velocidade próximas a emendas de 96 m. O [probe anterior](../../../output/drag-seam-probe-20261018.log) confirmou cinco ocorrências nos dois carros: contatos horizontais com normal `(-1, 0, 0)` na borda de `WeatheredAsphalt`/`DesertGround`, sobre superfícies coplanares. Essas colisões físicas interrompiam a aceleração.

[DragTrackSupport](../../../world/desert/DragTrackSupport.gd) substitui somente a colisão plana dentro da reta por um suporte finito e contínuo, com x de −936 a 90 e z de −1325 a −1315. Os triângulos originais são recortados exatamente na faixa, preservando a geometria desenhada, as barreiras, o acesso e a via de retorno. O corpo pertence à região e acompanha seu descarregamento.

A prova de perímetro também encontrou contato indevido na saída x=90. Corrida, chegada e retorno agora seguem o contrato já usado por `Vehicle`: velocidade vertical zero quando apoiado, deixando o floor snap manter contato; gravidade continua no ar. A fixture revelou ainda um afundamento transitório de 2,39 cm no sentido inverso com dois triângulos muito alongados. O suporte mantém um único corpo, agora com faces conectadas de 32 m em coordenadas locais, sem mudar extensão ou altura. As quatro travessias de 1.014 m a 60 m/s, as quatro bordas a 8 m/s, a barreira e a reconstrução passaram: 17 verificações, sem falhas; desvio vertical máximo de aproximadamente 1,094 mm. Esses casos são registrados separadamente da integração anterior.

## Validação

O build inicial de `Harbor.csproj` passou sem erros ou avisos. As execuções usam o motor .NET local, backend C# confirmado e checkpoints isolados com `--no-save`.

| Cobertura | Resultado e evidência |
| --- | --- |
| Simulação de pedal/câmbio em 30, 60 e 120 Hz, seis rivais, vantagem de peças e penalidades | 129 verificações, zero falhas — [log](../../../output/drag-final-test_drag_control_feel.log) |
| Progressão, save, recordes, recibos, pagamento parcial e validação de resultado | 58 verificações, zero falhas — [log](../../../output/drag-final-test_drag_night_progress.log) |
| Painel, retorno, botões e restrições de preparação | 14 verificações, zero falhas — [log](../../../output/drag-final-test_drag_night_panel.log) |
| Encerrar enquanto inscrito e retomar após cancelar só a fila | 13 verificações, zero falhas — [log](../../../output/drag-final-abandon-20261018.log) |
| Progressão antiga dos rivais | 49 verificações, zero falhas — [log](../../../output/drag-final-test_desert_drag_progress.log) |
| Integração dos adaptadores de áudio | 48 verificações, zero falhas — [log](../../../output/drag-final-mixers-correct-20261018.log) |
| Entrada no pátio, bloqueio físico e remoção, fila a pé, corpo atual, variedade e suspensão/retomada real da animação | 20 verificações, zero falhas — [log final](../../../output/drag-final2-test_drag_meet_redesign.log) |
| Piso contínuo, duas faixas nos dois sentidos, quatro bordas, barreira, preservação visual e reconstrução | 17 verificações, zero falhas — [log final](../../../output/drag-final2-test_drag_track_support.log) |
| Fila completa em Main: chegada, espera, 800 m, frenagem, retorno, cancelamento e saída | 29 verificações, zero falhas — [execução renderizada](../../../output/drag-open-final-20261018.log); [confirmação funcional headless após os últimos ajustes físicos](../../../output/drag-open-release-20261018.log) |
| Noite completa em Main: cancelamento e retomada, quatro passadas reais, botões disponíveis, checkpoint e pagamento | 58 verificações, zero falhas — [log final](../../../output/drag-night-seams-fixed-20261018.log) |

A primeira integração completa da noite passou 53 verificações, mas a revisão revelou perdas de velocidade nas emendas e botões desabilitados mascarados pelo acionamento direto de sinais. A execução final, após as correções, passou 58 verificações: confirmou os botões antes das ações, cancelou e retomou a primeira passagem, completou as quatro passadas e não detectou desaceleração física abrupta. O jogador fez 19,939 s nos 800 m, venceu por 3/3 pontos e recebeu R$ 900, com saldo pendente zero. Ranking e campanha permaneceram intactos.

Os oito screenshots finais dos quadros e resultados foram inspecionados em PT-BR, em 1280 × 720: textos sem sobreposição, preparação bloqueada somente na segunda passada de 402 m e resultados coerentes com os tempos. Exemplos: [quadro da segunda passada de 402 m](../../../evidence/drag-night-session-43108-7127425/night-board-3.png) e [resultado da noite](../../../evidence/drag-night-session-43108-7127425/night-result-4.png). A galeria completa está no [relatório de progressão](implementacao-progressao.md).

O teste de mixers inicialmente encerrou com código 2 por falta de `--no-save`; a invocação corrigida executou as 48 verificações. As execuções que encontraram defeitos permanecem nos logs, junto às correções e novas provas.

A última confirmação funcional da fila passou as 29 verificações, com espera de 71,189 s, backend C# ativo e código de saída zero. Depois de `OPEN_DRAG_DONE`, o encerramento headless emitiu erros de liberação do `RasterizerSceneDummy`, 386 instâncias e dois recursos ainda em uso. Esses diagnósticos de teardown permanecem sem atribuição ou correção nesta entrega; essa execução não é apresentada como log limpo nem como prova de desempenho. As execuções renderizadas citadas da fila e da noite não emitiram esses erros.

## Desempenho renderizado

Mesmo runner em `Main.tscn`, Godot 4.7.2 .NET, RTX 4060 Laptop, Vulkan Mobile, 1280 × 720, MSAA/configuração do projeto, noite fixa em 0,9, VSync desligado e FPS livre somente no processo de medição. Capturas são feitas fora das janelas amostradas. Pátio e quadro têm aproximadamente 30 s cada; a corrida tem duas passagens equivalentes, somando 41,4 s. As amostras brutas registram frames, duração, p50/p95/p99, máximos e contagens acima de 33,3/66,7 ms.

| Cenário | Antes: FPS / p95 / p99 (ms) | Primeira implementação: FPS / p95 / p99 (ms) | Após otimização: FPS / p95 / p99 (ms) |
| --- | --- | --- | --- |
| Pátio | 328,4 / 5,177 / 5,951 | 220,4 / 7,106 / 8,386 | 279,0 / 5,560 / 6,114 |
| Quadro aberto | 432,0 / 3,707 / 4,597 | 348,0 / 4,439 / 5,413 | 426,4 / 3,777 / 4,212 |
| Corrida 1 | 288,1 / 5,649 / 7,982 | 236,8 / 6,206 / 7,765 | 286,7 / 5,377 / 6,308 |
| Corrida 2 | 285,2 / 5,555 / 7,566 | 255,1 / 5,872 / 6,940 | 288,1 / 5,237 / 6,270 |

Evidências: [baseline](../../../evidence/drag-design-32352-7342303/metrics.json) e [primeira implementação](../../../evidence/drag-design-43472-7115622/metrics.json). Ambas tiveram zero frames acima de 33,3 ms nas janelas. Isso não elimina o aumento de custo: o limite de regressão adotado foi 5% nas caudas e exige confirmação. O pátio anterior tinha seis carros presos fora do enquadramento; agora eles circulam na cena. A população autorada não pertence a `world.people`, por isso seu campo histórico zero não significa ausência de NPCs. A confirmação acrescenta contagens explícitas após cada janela.

A investigação encontrou callbacks de `PoseDriver` ainda rodando quando seu modelo já havia sido congelado pela distância. O helper local agora suspende ambos, mantendo o corpo visível e restaurando animação para ameaça, impacto e queda. Não reduz população, distâncias ou qualidade visual. A [confirmação após o ajuste](../../../evidence/drag-design-45440-7360929/metrics.json) recuperou o quadro e as duas corridas; todas essas caudas estão dentro da tolerância adotada. Nas corridas, p99 melhorou cerca de 17–21% frente à base.

**Pátio: custo adicional permanece registrado, sem aprovação de equivalência ao baseline.** P95 está 7,4% acima da base e p99, 2,7%; média de 279 FPS contra 328 FPS. A janela atual contém circulação real, diferente da fila antiga bloqueada. A meta absoluta provisória de 60 FPS foi atendida nesse hardware, mas isso não substitui o critério de regressão. Os snapshots também abrangem alterações concorrentes do workspace, portanto os números não isolam causalmente cada arquivo. Não se declara a performance de todo o encontro aprovada.

Na confirmação, o pátio/quadro tinham 27 residentes efetivamente admitidos, 24 espectadores, 26 células reservadas e 14 modelos/14 drivers ativos; durante a corrida, 24 espectadores e 4 modelos/4 drivers ativos. O limite autorado de residentes é 34, não uma afirmação de que todos foram admitidos nessa fixture. O total de carros em `transit` não inclui os que já estão na bateria.

| Janela final | Frames / duração | p50 (ms) | Máximo (ms) | Frames >33,3 / >66,7 ms |
| --- | --- | --- | --- | --- |
| Pátio | 8.370 / 30,002 s | 3,194 | 10,915 | 0 / 0 |
| Quadro | 12.757 / 29,915 s | 2,142 | 17,862 | 0 / 0 |
| Corrida 1 | 5.940 / 20,716 s | 3,253 | 13,158 | 0 / 0 |
| Corrida 2 | 5.961 / 20,693 s | 3,265 | 12,876 | 0 / 0 |

Pré-aquecimento regional: 21,681 s antes, 21,902 s na primeira implementação e 21,114 s na confirmação. Esses valores não medem o carregamento total. A captura temporal separada usa a configuração normal com VSync e cap original de 144 FPS antes de limitar a gravação a 30; não serve para concluir desempenho nesse cap.

## Áudio, aparência e limites

A [gravação real de 29,323 s](../../../evidence/open-drag-37200-7534534/race-audio.wav) tem pico de −8,54 dBFS, RMS de −20,21 dBFS e nenhuma amostra saturada ([análise](../../../artifacts/rachas-implementation-20261018/race-audio-analysis.json)). Isso comprova folga digital nessa captura, sem certificar preferência de timbre ou mascaramento entre motores. A audição subjetiva do conjunto permanece pendente.

A [captura temporal após a redistribuição da largada](../../../evidence/drag-night-session-43108-7127425/temporal/sequence.json) registrou 95,146 s e 2.771 frames, sem frames renderizados pulados, porém com 28 intervalos maiores que 100 ms. O [vídeo real, sem áudio](../../../artifacts/rachas-implementation-20261018/noite-de-acerto-final.mp4) preserva os intervalos capturados; a gravação de som está no arquivo separado acima. A inspeção de 17 imagens e pares/trios adjacentes confirmou tenda e público visíveis desde a largada e não encontrou desaparecimento abrupto nos recortes examinados. Não certifica ausência universal de flicker nem FPS: gravar limitou esse processo a 30 FPS. Há ainda trechos esparsos e manchas de vegetação ao fundo que pertencem ao acabamento visual do mapa.

O recorte implementado é a categoria Livre. Classes com orçamento, carro emprestado, desafios exclusivos de preparação por rival, telemetria detalhada de pós-prova, música inédita e entrada por perfil separado continuam fora desta entrega. Não há atalho que libere a ponte da campanha.

Detalhes por eixo: [ambiente](implementacao-ambiente.md), [pilotagem](implementacao-pilotagem.md), [progressão](implementacao-progressao.md). A [opção 1](conceitos/01.png) é referência de direção; as evidências de Main são as imagens do jogo real.

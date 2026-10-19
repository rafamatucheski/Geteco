# Rachas: diagnóstico de pilotagem, instrumentos e áudio

Data: 17 de outubro de 2026.

Escopo: arrancada do deserto; preparação da largada, troca de marchas, HUD, prioridade sonora e aprendizado para quem deseja jogar repetidamente esse modo.

**Este documento é um diagnóstico por leitura do código. Este agente não executou o jogo, não compilou o projeto, não realizou benchmark nem avaliação auditiva. As propostas abaixo ainda não são comportamento implementado ou validado.** Nenhum arquivo de runtime foi alterado por este agente. Foram lidas as instruções do projeto e as skills `testes-com-criterio` e `performance-do-jogo` nos caminhos indicados pelo usuário.

## Síntese

As queixas sobre controle do giro e brusquidão das trocas encontram causas específicas no código atual. A preparação exige pulsar uma tecla binária dentro de uma faixa atravessada em cerca de 221 ms. A troca muda marcha e RPM instantaneamente, corta toda a força por um intervalo fixo e depois devolve a força sem uma fase de reacoplamento. O painel replica fielmente esse degrau.

O áudio já mantém o ouvinte junto ao carro de Dante e protege seu motor da distância da câmera. Existe, porém, uma hipótese concreta de desequilíbrio: o rival usa atenuação inversa com escala de 12 m a aproximadamente 4 m do ouvinte; Dante usa áudio sem atenuação e não recebe o mesmo ganho de proximidade. A confirmação exige medir e ouvir os bancos realmente ativos.

O objetivo proposto é tornar a primeira corrida compreensível e agradável, mantendo espaço para dominar largada, relações de marcha, preparação e momento do nitro. A melhoria deve atingir os controles e sua resposta, além da aparência do painel.

## Fatos do código e suas implicações

### 1. Preparação desfavorável ao teclado

- Em [DesertDrivetrain.gd](../../../gameplay/desert_cars/DesertDrivetrain.gd), linhas 59–64, `stage()` usa `move_toward` com velocidade de `redline × 0.95` por segundo tanto ao subir como ao descer o giro.
- Nas linhas 66–81, a largada ideal ocupa a faixa de `0.43` a `0.64` da redline. Acima dela, o fator inicial de tração passa a `0.63`; abaixo, passa a `0.56`.
- Em [DesertDrag.gd](../../../activities/desert_drag/DesertDrag.gd), linhas 509–513, W/seta para cima fornecem somente zero ou um. O gatilho fornece uma posição analógica.

A faixa inteira representa `0.21 × redline`; dividida pela velocidade de resposta de `0.95 × redline/s`, sua travessia dura aproximadamente **221 ms**. O teclado não oferece uma posição estável intermediária: o jogador precisa alternar acelerador ligado/desligado. No controle, é possível segurar o gatilho numa posição que produza giro ideal.

Isso é uma diferença objetiva entre dispositivos. A dificuldade percebida ainda depende da taxa de frames, latência e experiência da pessoa, que não foram medidas aqui.

### 2. A troca contém três descontinuidades

Em [DesertDrivetrain.gd](../../../gameplay/desert_cars/DesertDrivetrain.gd), linhas 83–91:

1. `gear` aumenta imediatamente;
2. `rpm` passa imediatamente para `_coupled_rpm()` da nova relação;
3. `shift_remaining` recebe 120 ms para troca ideal, 300 ms para antecipada ou 240 ms para atrasada.

Na linha 136, a força é zerada enquanto `shift_remaining > 0`; depois volta a ser calculada integralmente. A suavização inicial em linhas 120–125 só vale para o engate da largada, não para as trocas seguintes.

A queda de RPM entre relações é esperada. No Faísca, por exemplo, a passagem da relação 3.42 para 2.12 reduz o giro acoplado em aproximadamente 38%, mantendo a velocidade. O problema de apresentação é concentrar a queda em um tick e usar um corte/restabelecimento binário de força. Esta leitura demonstra o degrau; a contribuição exata para o desconforto depende de reprodução renderizada e auditiva.

### 3. O painel expõe o degrau da simulação

Em [DesertDragHUD.gd](../../../activities/desert_drag/DesertDragHUD.gd), linhas 64–78, os instrumentos copiam diretamente o estado físico. As linhas 247–255 desenham o ponteiro sem interpolação. As faixas de largada e troca são coerentes com o drivetrain, tanto no painel em barras quanto no circular.

Não há evidência de um erro de leitura dos números. A correção recomendada é modelar melhor a transição física da embreagem/RPM e continuar mostrando esse estado verdadeiro. Atrasar somente o ponteiro pode criar divergência entre o momento válido de troca e o que a pessoa vê.

### 4. Pressões repetidas podem apagar o retorno visual

Em [DesertDrivetrain.gd](../../../gameplay/desert_cars/DesertDrivetrain.gd), linha 84, `shift_up()` retorna uma string vazia se a troca ainda está em andamento ou se o carro já chegou à última marcha.

Em [DesertDrag.gd](../../../activities/desert_drag/DesertDrag.gd), linhas 340–349, `request_shift()` substitui o feedback pelo retorno recebido mesmo quando vazio. Pressionar novamente durante o intervalo da troca pode apagar o aviso anterior. O controller prevê a tradução de `max` para “Última marcha”, mas esse retorno não é emitido pelo drivetrain atual.

O tratamento deve distinguir comando aceito, comando temporariamente indisponível e última marcha. Preservar feedback relevante em entradas ignoradas; avaliar um buffer curto de comando somente se ele não conceder duas marchas com uma pressão nem mascarar a habilidade exigida.

### 5. A largada visual e a ação medida não estão plenamente alinhadas

Em [DesertDrag.gd](../../../activities/desert_drag/DesertDrag.gd), linhas 342–344, apertar o botão de trocar durante a preparação provoca queima. Nas linhas 359–370, a largada acontece automaticamente quando termina a contagem de três segundos, usando o RPM daquele instante.

A habilidade efetivamente medida é preparar o giro no instante da largada automática. Não existe atualmente uma ação própria de soltar a embreagem ou medir reação humana ao verde. O adversário tem um atraso de reação configurado, aplicado ao acelerador em linhas 375–379.

É necessário escolher e comunicar uma regra consistente: manter largada automática com preparação clara, ou introduzir uma ação de largada com reação e queima correspondentes. Não acrescentar uma ação nova apenas para aumentar complexidade. A primeira opção é a mudança menor para uma primeira entrega.

### 6. A IA controla o giro com informação privilegiada

Em [DesertDrag.gd](../../../activities/desert_drag/DesertDrag.gd), linha 363, o rival liga/desliga o pedal a cada tick para permanecer ao redor de `0.57 × redline`, dentro da faixa ideal. Os erros e a reação configurados não mudam essa precisão de preparação.

Para o jogador de teclado, a mesma etapa exige pulsos manuais. Essa diferença é relevante no primeiro rival. Eventual revisão de dificuldade deve preservar a preparação real dos veículos e a ausência de velocidade artificial para recuperar distância.

### 7. Legibilidade funcional está parcialmente ligada a cosmético

Em [DesertDragHUD.gd](../../../activities/desert_drag/DesertDragHUD.gd), linhas 260–265, cinco luzes progressivas de troca aparecem somente nos estilos Pro e Campeão. Os outros instrumentos têm faixa ideal e avisos, mas não a mesma antecipação luminosa.

Todos os estilos devem oferecer informação equivalente para executar bem uma troca. O cosmético pode mudar forma, material, cor e personalidade, sem reservar a melhor leitura para um painel comprado.

## Áudio: fatos e hipótese a confirmar

### O que já está implementado

- [DesertDrag.gd](../../../activities/desert_drag/DesertDrag.gd), linhas 269–275: `AudioListener3D` é filho do carro de Dante e passa a ser o ouvinte da prova.
- [DesertCarAudio.gd](../../../audio/desert_cars/DesertCarAudio.gd), linhas 87–115: o motor controlado pelo jogador usa foreground, sem atenuação de distância ou pan; os dois carros da prova permanecem elegíveis mesmo com câmera afastada.
- No mesmo arquivo, linhas 130–145, RPM audível e corte de áudio já recebem suavização. Portanto, áudio e ponteiro têm respostas temporais diferentes hoje.
- O mixer antigo e o novo compartilham ganho base calculado sem uma prioridade explícita de “jogador versus rival”.

### Hipótese mais concreta para o rival dominar

O grid coloca os carros a 4 m um do outro ([DesertDrag.gd](../../../activities/desert_drag/DesertDrag.gd), linhas 155–156). O mixer antigo utiliza `unit_size = 12`, `max_distance = 85` e `max_db = 1` ([DesertCarAudio.gd](../../../audio/desert_cars/DesertCarAudio.gd), linhas 252–259). O novo também recebe `spatial_unit_size = 12` nas linhas 194–204.

[EngineDesignVoice.gd](../../../audio/EngineDesignVoice.gd), linhas 53–65 e 112–116, aplica essa escala aos players e usa atenuação inversa para fontes fora do foreground. Não altera `max_db` dos players do novo banco.

Assim, o rival próximo pode receber ganho espacial que o motor próprio, sem atenuação, não recebe. O resultado também depende do conteúdo e normalização dos bancos, escapamento instalado, carga do motor e instante da troca. **Não há medição de loudness ou confirmação auditiva nesta auditoria; não tratar a hipótese como causa única comprovada.**

A [documentação oficial do AudioStreamPlayer3D](https://docs.godotengine.org/en/stable/classes/class_audiostreamplayer3d.html) descreve o listener, os modelos de atenuação, `unit_size`, `max_distance` e `max_db`. Ela sustenta a investigação do mecanismo, mas não substitui medir esta versão e estes bancos no jogo.

### Contrato de mixagem proposto

- Motor de Dante fornece a referência para decidir a troca.
- Rival permanece espacial e reconhecível, inclusive aproximando-se e ultrapassando, sem encobrir continuamente essa referência quando lado a lado.
- Público, música e anúncio pertencem à atmosfera; sua intensidade se adapta à preparação, corrida e resultado.
- Sons de troca e mudança de carga devem corresponder ao mesmo estado do drivetrain.
- A correção deve cobrir banco antigo e banco novo durante aquecimento/fallback. Aumentar todo o barramento SFX não resolve hierarquia.

Os valores finais devem ser escolhidos por amostra medida e escuta comparável. Um alvo inicial de motor próprio perceptivelmente dominante pode orientar protótipo; ainda não existe margem em dB validada neste documento.

## Proposta de experiência

### Primeira corrida

Preparar o carro deve ser confortável no teclado e no gatilho. Adotar resposta progressiva do pedal digital e uma faixa boa legível, com um centro ótimo para quem quer extrair o melhor tempo. A perda de tração por erro deve variar gradualmente, evitando que um RPM praticamente idêntico receba resultado muito diferente por estar um ponto além do limite.

A troca deve ter fases curtas e contínuas de desacoplamento, ajuste de RPM e reacoplamento. Manter a física como origem dos instrumentos e do som. A aceleração não pode receber bônus de velocidade por acertar a troca; o ganho deve vir de perder menos tempo de transmissão e usar melhor a curva do motor.

Marcha, sinal de antecipação e aviso de troca devem ficar próximos, com formas além de cores para distinguir aproximação, faixa boa e limite. Textos funcionais curtos são suficientes. A direção não exige legendas decorativas sobre carros, fachadas ou objetos.

### Profundidade para quem joga apenas rachas

- Aprendizado de cada carro: relações, resposta do turbo, aderência e nitro realmente mudam a passagem.
- Recordes separados por carro, preparação ou classe para que melhorar um carro modesto continue significativo.
- Fantasma próprio opcional e comparação por parciais, sem poluir a primeira corrida.
- Desafios de consistência em três passadas: a habilidade inclui repetir um bom tempo, além de um acerto isolado.
- No resultado, destacar uma oportunidade concreta de melhoria, como a largada ou uma troca, a partir da telemetria real. Não inventar um motivo de derrota.

O resultado atual mostra vitória, diferença, tempos e recorde ([DesertDragResults.gd](../../../activities/desert_drag/DesertDragResults.gd), linhas 77–103), mas não explica onde houve perda de tempo. Esse é um ponto de alto valor para encorajar uma revanche com intenção.

### Peças: aprofundar um sistema existente

[DesertTuning.gd](../../../gameplay/desert_cars/DesertTuning.gd), linhas 16–35, já libera ECU, comandos, turbos, câmbio, pneus, nitro e suspensão por vitórias distintas. Linhas 90–100 verificam requisito, preço e propriedade, permitindo reinstalar peça possuída sem nova compra.

Não apresentar desbloqueio de peças como função inédita. A oportunidade é dar identidade e antecipação à progressão: rival ou oficineiro associado a uma família de preparação, desafio que demonstra sua utilidade e próxima recompensa visível antes da inscrição. Preservar peças adquiridas, recibos, preços coerentes e progressão da campanha.

## Validação necessária para uma implementação

### Lacuna encontrada nos testes atuais

[test_desert_drag_runtime.gd](../../../tests/test_desert_drag_runtime.gd), linha 266, e [test_desert_drag_board_session.gd](../../../tests/test_desert_drag_board_session.gd), linha 88, fornecem `_throttle_override = .54` durante a preparação. Esse pedal intermediário perfeito valida o caminho analógico simulado e contorna justamente a dificuldade do teclado. Passar esses testes não comprova que uma pessoa consegue manter o giro com W.

### Conjunto proporcional de verificação

1. **Preparação real:** usar entradas de teclado e gatilho, sem override analógico nos cenários que avaliam teclado. Cobrir primeiro rival, carro inicial e um carro rápido preparado. Registrar sucesso de largada boa/ótima, ações exigidas e recuperação após erro.
2. **Transmissão:** registrar RPM, marcha, força, aceleração e duração de cada fase. Confirmar continuidade pretendida, ausência de bônus instantâneo de velocidade, limites, comando repetido e última marcha. Preservar a diferença de tempo entre boas e más trocas sem punições arbitrárias.
3. **Áudio:** capturar motor próprio e rival isolados e juntos em mesma configuração de câmera/listener, carga e distância. Comparar os bancos antigo e novo, largada, troca simultânea, rival ao lado e afastado. Ouvir a sequência em velocidade normal; valores de volume de nós não bastam.
4. **Instrumentos:** rever 960×540 e 1280×720, teclado e controle, todos os estilos. Confirmar que faixa válida, feedback e estado físico concordam, e que as informações críticas não cobrem carros ou largada.
5. **Integração:** reaproveitar os testes de corrida real, resultados, revanche, pausa, retorno e cancelamento. Verificar restauração de listener, áudio, input e física após interrupção. Se mudar progressão, cobrir aquisição, reinstalação e persistência de peças.
6. **Performance:** comparar antes/depois na mesma cena real renderizada, sem outras execuções concorrentes na GPU; pelo menos 30 s por cenário crítico, separando aquecimento. Registrar frame time p50/p95/p99, máximo e frames acima de 33,3/66,7 ms. Seguir Godot 4.7.2 .NET, com `Harbor.csproj` compilado. Nenhuma alteração de performance foi aprovada aqui.

Reutilizar [desert_cars_powertrain.gd](../../../tests/desert_cars_powertrain.gd) para contratos de motor, nitro e ausência de bônus de velocidade; [test_desert_drag_rival_balance.gd](../../../tests/test_desert_drag_rival_balance.gd) para preparação e progressão dos rivais; os testes integrados acima para fronteiras reais. Os testes devem ser adaptados somente às expectativas explicitamente escolhidas, sem afrouxar limites apenas para obter aprovação.

## Estado da entrega

Diagnóstico e proposta documentados. Runtime, conforto dos controles, qualidade auditiva, aparência em movimento e performance **não foram validados por este agente**. Implementar as propostas exige preservar o trabalho concorrente e delimitar um lote antes de editar os sistemas compartilhados.

# Rachas — Noite de Acerto

Proposta de Product Design para Geteco, 17/10/2026.

**Estado em 18/10/2026: opção 1 implementada e fluxos dirigidos validados; desempenho permanece pendente.** O [relatório da primeira implementação](implementacao.md) preserva suas evidências e limites. A [continuação](continuidade.md) registra ambiente, música própria, categorias por orçamento, carros emprestados, desafios dos seis rivais, telemetria e perfil separado, além da HUD compacta solicitada pelo usuário. As doze provas foram concluídas fisicamente com carro original, mas o comparativo renderizado ainda mostra regressão frente à base; isso não está aprovado. Consulte o registro para a cobertura e suas limitações. As três imagens continuam sendo conceitos, não screenshots. O texto abaixo preserva a proposta original de 17/10, inclusive alternativas e metas que não correspondem exatamente à implementação final.

## O que precisa mudar

O encontro deve ser um destino que dá vontade de frequentar e a arrancada precisa recompensar conhecer o carro. Hoje há conteúdo autorado, mas isso não se traduz numa experiência viva: personagens legados, repertório sonoro emprestado, variedade concentrada em poucas bases, fila sem recuperação confiável e controles que exigem pulsação desconfortável no teclado.

O objetivo é permitir três formas de aproveitar o lugar: entrar e correr rapidamente, passar uma noite competindo e ajustando o carro, ou circular e acompanhar os rivais. A ambientação, a fila e a progressão precisam apoiar as três.

## A proposta central

**Noite de Acerto:** um carro, três exigências diferentes, rivais que reconhecem o que Dante fez. A cada sessão, o jogador escolhe um carro e um objetivo de preparação. Pode usar suas peças e trocar presets entre provas. Ganhar uma corrida é bom; descobrir uma configuração melhor e conseguir repetir uma boa passada também precisa valer.

1. **Saída, 201 m:** reação e tração. Uma passada curta para aprender o comportamento da largada.
2. **Marca, 402 m:** duas passadas para buscar tempo e consistência. O próprio recorde oferece uma vitória pessoal mesmo quando o rival chega antes.
3. **Desafio, 800 m:** fôlego, relação de câmbio e decisão de nitro. Um duelo conclui a noite.

Meta inicial de duração: 5–8 minutos, sujeita a teste de uso. São três etapas e quatro passadas, sem exigir que o jogador vença todas para continuar. A ordem inicial é fixa para ensinar; depois, contratos podem variar a combinação. As distâncias curtas e a pontuação por noite são conteúdo novo proposto; a prova atual é de 800 m.

O encontro continua existindo entre as passadas. Uma ação inicia a próxima prova e outra volta ao pátio. Quem deseja só praticar tem treino gratuito e repetição rápida. Quem quer imersão vê o adversário voltar pela pista de retorno e preparar o carro seguinte.

### O diferencial

Cada rival ensina uma forma de preparar. Vencer ou cumprir o desafio técnico correspondente libera uma família de peças e um acerto associado a essa pessoa. A peça tem função e origem reconhecíveis: o jogador lembra em qual duelo a conquistou e onde ela ajuda.

Exemplo proposto: depois de observar Lívia dominar a saída, Dante experimenta um carro emprestado e precisa repetir três boas largadas. Conquista acesso ao conjunto de tração e pode levá-lo ao próprio carro. O desafio aceita equipamento fornecido, para não exigir a peça que pretende liberar.

Essas especialidades são propostas, não novas biografias já aprovadas. Preservar os personagens, os carros e o prêmio opcional de Takeshi existentes.

## Pilotagem e interface

### Largada

O teclado deve ter um pedal progressivo com estabilização previsível; gatilho mantém controle analógico. Uma faixa boa confortável e um centro ótimo criam espaço para iniciantes e especialistas. A curva de perda por largada deve ser contínua: um pequeno erro produz pequena diferença, não uma queda súbita de desempenho.

A semântica precisa ser coerente: preparar giro, aguardar sinal, executar a largada e receber feedback de reação. Se for adotada embreagem manual na preparação, a tecla de troca passa a ter função explícita de largada nesse estado. A queima só ocorre ao realmente largar cedo. Não punir uma troca sem movimento como se o carro tivesse cruzado o sinal.

### Troca

Modelar desacoplamento, transição do giro e reacoplamento com envelope contínuo de torque. A queda de RPM pela relação de marcha continua existindo; a entrega de força, a carroceria e o áudio devem contar a mesma transição. Não acrescentar impulso fictício à velocidade nem apenas esconder o degrau no ponteiro.

Aceitar um comando por troca, preservar feedback quando uma tecla extra não produz ação e indicar claramente a última marcha. A dificuldade vem de escolher o momento e entender o carro, não de adivinhar se o botão funcionou.

### HUD

Hierarquia: pista e adversário → faixa de giro e marcha → distância/tempo → nitro. Concentrar a decisão de troca numa área compacta e estável. Mostrar uma única instrução contextual por vez. Usar forma, intensidade e texto curto além de cor; luz de troca funcional disponível também no painel básico.

Preservar as fontes Barlow e a base atual: tinta `#11161c`, papel `#f4f3ef`, coral `#ff633b`, âmbar `#ffbe63`, ciano `#58d7ec`. As alternativas visuais exploram hierarquia e atmosfera mantendo a escala de jogo do Geteco.

Resultado: tempo, comparação relevante e **uma dica verificável** extraída da telemetria. Exemplo de conteúdo funcional: “2ª → 3ª: troca 280 rpm depois da faixa”. Não gerar diagnóstico sem amostrar o evento correspondente. Ações: repetir, ajustar, voltar ao encontro.

## Encontro vivo

Compor cinco focos visíveis no trajeto: chegada e inscrição, preparação, largada, torcida, retorno. Aproximar atividades importantes e variar silhuetas/gestos; aumentar o total de carros ou pessoas não é a primeira solução.

- Aplicar corpos atuais de NPC por identidade/função sem criar e apagar modelos desnecessariamente. Acessórios devem preservar a leitura dos mecânicos, organizadores e pilotos.
- Grupos têm propósito: examinar motor, comparar um resultado, aguardar chamada, acompanhar a largada. Evitar dezenas de pessoas fazendo a mesma animação.
- Organizador chama uma inscrição, rival responde, torcida reage à disputa e ao resultado. Falas curtas autoradas, legendas opcionais e intervalo entre repetições.
- Música própria do encontro, ligada a uma fonte plausível no pátio. Definir identidade musical original; não reutilizar um loop genérico de outro lugar como solução final.
- Seleção de carros deve variar carroceria, tração, motor, som e papel competitivo. Hatch, sedã, cupê e muscle têm classes em que continuam úteis; versões de pintura não contam como variedade mecânica.
- Uma parte dos visitantes alterna por visita; os rivais importantes permanecem reconhecíveis. Rotação deve preservar lotação plausível e orçamento de entidades.

Fachadas recebem somente nomes próprios. Não usar placas explicativas, slogans ou textos decorativos para contar o que o ambiente deveria mostrar.

### Fila utilizável

Separar espetáculo da espera obrigatória. Inscrição pertence a Dante e ao carro registrado, permitindo caminhar pelo encontro. Trocar de carro pede nova inscrição com motivo claro. A chamada informa a vez e oferece apresentação à largada; o jogador pode optar por assistir à bateria anterior.

Estados explícitos: inscrito → em preparação → chamado → na pista → retorno. Obstrução tem recuperação: interromper a bateria, liberar posse da pista, preservar inscrição ou devolver a vez, e retomar quando houver condição física segura. Nenhum estado terminal silencioso.

Não teletransportar carros sobre obstáculos nem retirar bloqueadores visíveis para “consertar” a fila. A causa física deve ser identificada. Recuperação técnica não cobra inscrição nem concede vitória.

## Som e horizonte

Motor próprio é a referência da mixagem. Rival permanece espacial e inteligível, sem encobrir o feedback de giro do jogador quando lado a lado. Chamadas e fala próxima têm prioridade sobre música; música/público voltam gradualmente após a prova. Testar com os bancos novos e antigos de motor ainda suportados.

O corredor visual da prova precisa permanecer coerente desde a largada até a frenagem. Proposta: manter residente uma representação estática do trecho que a câmera enxerga, com terreno e silhuetas médias/distantes contínuos. Física detalhada e NPCs seguem ativação local. Não ampliar globalmente o streaming do deserto nem esconder cortes com neblina densa.

A composição deve dar escala e direção: asfalto e barreiras próximas, grupos e estruturas médias, relevo distante reconhecível. Capturas estáticas não aprovam popping; validar deslocamento e retorno em sequência temporal.

## Progressão e economia

Classes propostas: **Original** com preparação fixa/carro emprestado, **Preparado** com orçamento técnico e escolhas, **Livre** com preparação completa. Calibrar por desempenho real e peças permitidas, não só velocidade final.

Desbloqueios atuais e recibos são preservados. A corrida já libera peças por vitórias; a novidade é a rota de domínio com identidade e alternativas suficientes dentro da modalidade. O `nitro_pro` hoje exige sete vitórias distintas e só seis vêm da arrancada normal, criando dependência da campanha.

Treino registra recorde por carro, distância, configuração e assistência. Eventos pagam conclusão válida, com bônus por vitória e marcos únicos. O recibo de primeira vitória continua único; pagamentos recorrentes precisam de contrato e identificação próprios. Repetir não pode duplicar recompensa de campanha.

Sem eliminação por uma derrota, perda do carro, peça aleatória, calendário diário obrigatório ou aposta necessária. Reinstalar peças possuídas continua gratuito. Valores e ritmo de aquisição dependem de comparação com a economia existente; nenhum valor novo está aprovado por este documento.

Para quem joga somente rachas, propor futuramente entrada dedicada com perfil separado e carro inicial, sem alterar os saves da campanha. A ponte da cidade 1 continua fechada até a última missão. Não liberar acesso físico antecipado ao mapa 2 para viabilizar um menu de modalidade.

## Referências e adaptação

- [GTA Online / LS Car Meet](https://support.rockstargames.com/articles/7a5MsGMCeLTCp3ek6LEWrA/gtav-title-update-1-54-notes-ps4-xbox-one-pc): encontro reúne preparação, teste e competição. Adaptar a função social do espaço para um lugar autorado de Geteco.
- [NFS Unbound / Drift & Drag](https://www.ea.com/games/need-for-speed/need-for-speed-unbound/news/vol7-drift-and-drag-update): troca manual, nitro e duelos com rivais reconhecíveis. Adaptar domínio e personalidade, sem copiar sua arte ou progressão sazonal.
- [Forza Motorsport / Rivals](https://forza.net/news/forza-motorsport-multiplayer): melhorar tempos em combinações de carro/pista e comparar desempenho. Adaptar repetição rápida e metas pessoais a passadas curtas.

O formato de noite com três exigências e peças ligadas ao aprendizado é uma proposta para este projeto. Não é uma alegação de ineditismo absoluto no mercado.

## Ordem de implementação

| Etapa | Entrega jogável | Critério para avançar |
|---|---|---|
| 1. Confiança | Fila recuperável, giro jogável no teclado, troca contínua, mix do motor | Fluxo completo real, sem controles presos; entrada digital validada |
| 2. Identidade | NPCs atuais, composição do encontro, sons autorados e corredor visual estável | Revisão renderizada temporal, audição e frame time antes/depois |
| 3. Repetição | Treino com recordes por configuração, dica pós-prova, retorno/revanche rápidos | Recordes corretos, cancelamento/retorno sem vazamento ou recompensa duplicada |
| 4. Noite de Acerto | Distâncias curtas, presets entre etapas, classes e pontuação | Balanceamento por perfis, duração/clareza testadas com teclado e controle |
| 5. Progressão | Desafios dos rivais, peças com rotas alternativas e perfil dedicado | Migração de save, economia e ponte preservadas |

Não alterar o conteúdo das corridas de rua ou da montanha nesta primeira etapa. O sistema de resultados, identidade e preparação pode servir a essas modalidades depois de sua própria avaliação.

## Validação necessária para implementação

Usar Godot 4.7.2 .NET com Harbor.csproj compilado. Seguir testes-com-criterio, performance-do-jogo e guardiao-do-jogo; validar-iluminacao quando luzes forem alteradas. Não validar conforto no teclado usando apenas `_throttle_override=.54`.

Cobertura mínima dirigida: fila normal, acesso obstruído/removido, saída a pé, troca de carro, cancelamento, retorno e reentrada; largada fria/ideal/excessiva; troca cedo/ideal/tarde e botão repetido; derrota/vitória/revanche; pausa; carro destruído; save isolado antes/depois; primeira compra e reinstalação; recorde por preparação.

Performance: mesma GPU, renderer, resolução, câmera, hora, população e configuração, com pelo menos 30 s por cenário estável de pátio e corrida, e primeira visita separada. Registrar frames/tempo, p50/p95/p99, máximo e frames >33,3/66,7 ms. Meta provisória 60 FPS/16,67 ms; piora >5% nas caudas exige confirmação finita equivalente. Não executar benchmarks concorrentes nem chamar screenshots de prova de FPS.

## Diagnósticos e evidências

- [Ambiente, personagens, fila e streaming](ambiente.md)
- [Pilotagem, HUD e mixagem](pilotagem.md)
- [Progressão, peças, referências e save](progressao.md)
- [Capturas e resultado da execução desta rodada](auditoria.md)

As três alternativas foram geradas com ImageGen e apresentadas uma vez cada no chat. A ordem exibida, que define a escolha, é [1](conceitos/01.png), [2](conceitos/02.png), [3](conceitos/03.png). Os [prompts e limites das imagens](conceitos/prompts.md) ficam junto dos arquivos. Esta etapa não certifica áudio, performance nem ausência de popping.

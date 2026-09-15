# GETECO — Missões em ordem cronológica

Planejamento de autoria, 10/09/2026, com nova primeira missão em 11/09/2026. Não são missões implementadas por esta entrega.

Base: [história](CAMPAIGN_STORY_BIBLE.md). Execução e testes: [produção](CAMPAIGN_PRODUCTION.md).

São 37 missões principais, incluindo a nova chegada à delegacia e as seis bases do porto, mais três preparações finais opcionais e cadeias paralelas. Quantidade é orçamento de escrita; a validação pode fundir missões. Alvo inicial de teste: 5–7 horas de caminho principal, sem promessa de duração. Medir sessão humana; não aumentar deslocamentos e esperas para preencher tempo.

Cada missão recebe aceite/objetivo claro, checkpoint antes de sequência longa e consequência persistente. IDs abaixo são novos IDs de planejamento, não nomes de flags existentes. Para Harbor, mapear aos contratos existentes em vez de recriá-los.

## Mapa 1 — Harbor: a promessa

### M00 — Atrás do irmão [nova primeira missão; decisão do autor em 11/09]

Implementada no início do jogo em 11/09: ver [escopo, controles e testes](ARRIVAL_V2_IMPLEMENTATION.md). Na versão jogável, a proposta na garagem conduz ao Primeiro giro existente; detalhes futuros da campanha continuam em autoria.

- Ordem: primeira missão jogável, antes de Primeiro giro. M00 é apenas o ID de planejamento para preservar as referências M01–M36 nos demais documentos; o título é de trabalho.
- Motivo: Dante chega à cidade procurando o irmão e vai à delegacia buscar informações. A missão não começa recebendo uma ligação.
- Jogar: ir à delegacia, entrar, falar com o chefe da polícia ou a atendente e sair depois da conversa.
- Revelação: o irmão foi solto há alguns meses, está envolvido em contrabando de mercadorias para carros e rachas ilegais, e a polícia está procurando por ele.
- Reação: Dante fica assustado e não entende a situação. Dar espaço ao silêncio e à reação antes de sair.
- Continuação: alguns segundos depois de sair confuso, Dante recebe uma ligação pedindo que encontre uma pessoa no ferro-velho do Neko.
- Encontro: Maciota espera com seu sedã preto de alto desempenho, inspirado no M8 Competition, bem cuidado e preparado. Os dois se apresentam. Dante pergunta se Maciota ligou; ele confirma e diz “Vamos dar uma volta”.
- Passeio: Maciota entra como motorista e Dante como passageiro. Maciota dirige pela cidade explicando algumas coisas, até sua garagem. O passeio integra M00; não é uma prova de direção de Dante.
- Garagem: os dois entram. A Monaliza ainda não está lá, conforme a interpretação registrada na bíblia. Maciota oferece ajuda para encontrar o irmão, mas precisa de alguns favores.
- Saída: proposta de favores feita dentro da garagem; detalhes do primeiro favor e apresentação posterior da Monaliza ainda a escrever.
- Limite: não revelar o clã nem a liderança do irmão. Chefe ou atendente, falas finais, trajeto, assuntos do passeio e origem do contato telefônico de Maciota continuam em aberto.

### M01 — Primeiro giro [base existente]

- Entrada: depois da proposta de Maciota na garagem, ao fim de M00; deixa de ser a primeira missão da história.
- Motivo: Maciota oferece trabalho enquanto procura notícias de Vicente.
- Jogar: a entrega existente (recolher/enviar o pacote e voltar) é base para adaptação aos favores; o autor ainda não definiu qual será o primeiro favor.
- História: a liberação da Monaliza e a apresentação de seu porta-malas ficam para momento posterior a definir; ela não aparece na chegada à garagem. Comentário sobre uma viagem dos irmãos permanece proposta de escrita.
- Saída: vínculo com Maciota e acesso ao quadro Cobra. Falha/retry seguem a implementação existente.

### M02 — Dentro do território [base existente]

- Jogar: levar peça à oficina Cobra e conversar com o contato.
- História: oficina paga por proteção; um veículo do circuito do deserto aparece no ambiente como prenúncio, sem acusar Vicente.
- Saída: convite para a prova de rua. Reusar cenário/atores existentes.

### M03 — Prova de rua [base existente]

- Jogar: corrida curta no trajeto da praça, com controle real do carro.
- História: Dante precisa conquistar acesso por habilidade, não pelo passado de policial.
- Saída: confiança do contato e indicação de uma moradora pressionada.

### M04 — A conta chega [base existente]

- Jogar: proteger a moradora dos cobradores e ouvir o relato.
- História: apresentar a diferença entre ajuda e cobrança, tema que reaparece com Vicente.
- Saída: localização dos registros. A moradora continua no mundo após o encontro.

### M05 — Cortar o abastecimento [base existente]

- Jogar: alcançar os registros físicos e vencer oposição localizada.
- História: descobrir pagamentos a um intermediário de corridas.
- Saída: acesso à liderança Cobra; não transformar o encontro existente em comboio sem nova produção.

### M06 — A última cobrança [base existente; expansão narrativa proposta]

- Jogar: confronto com a liderança Cobra, preservando sua identidade atual.
- História: mensagem “Primeiro a gente chega. Depois vê o estrago”, atribuída a alguém da rota do deserto. Maciota reconhece o destino, não o comando de Vicente.
- Saída: liberar viagem ao deserto. Transição é epílogo da missão, não tarefa extra para contar número.

## Mapa 2 — Deserto: o preço da entrada

### M07 — Poeira no rádio

- Motivo: a pista aponta para o circuito de Roleta.
- Jogar: chegar ao posto de encontro, transportar equipamento de cronometragem numa volta de reconhecimento e conhecer pontos da pista.
- Variação: dirigir com carga exige evitar colisões, sem falha instantânea por um toque.
- História: ouvir corredores discutindo pagamentos; Vicente foi visto no evento principal.
- Saída: acesso à qualificatória. Local: posto habitado e circuito curto.

### M08 — Uma volta limpa

- Jogar: qualificação contra poucos rivais, usando as curvas conhecidas.
- História: Roleta concede acesso; uma competidora, Nina, acusa cobrança indevida.
- Saída: convite principal. Repetir corrida normal é permitido; esta não é a derrota armada.

### M09 — O preço do convite

- Jogar: ajudar Nina a recuperar seus pertences num pátio de cobrança, por conversa encenada e fuga curta se intimidadores atacarem.
- História: mostrar que Roleta manipula dívidas. Nina aponta onde Vicente chegará.
- Saída: encontro de M10. A missão permite questionar o evento; Dante aceita seguir pela necessidade de falar com o irmão, não por ignorância total.

### M10 — Seis anos

- Jogar: chegar ao encontro, caminhar com Vicente e escolher a ordem de duas perguntas, ambas disponíveis.
- CGI: prisão, proteção e entrada no Pacto. O flashback pertence a Vicente; não acrescentar tudo ao conhecimento de Dante.
- História: Vicente confirma a mensagem e acusa abandono. Sai para resolver um problema. Roleta apresenta a aposta e Dante assume o risco em cena.
- Saída: checkpoint antes da corrida; mostrar claramente que a Monaliza foi apostada.

### M11 — A casa ganha

- Jogar: corrida principal, com desempenho real até o fechamento autorado da rota; a chegada é manipulada. Em seguida, controlar Dante no posto depois que levam o carro.
- História: Roleta toma a Monaliza em nome de uma dívida inventada. O destino do veículo fica oculto.
- Estado: remover instância, GPS, recuperação e acesso remoto ao porta-malas; guardar carro e carga em estado sequestrado, não apagar patrimônio.
- Saída: ligar para Maciota, caminhar até parada próxima e viajar como passageiro para Santa Brasa. Perder a prova é conclusão, não tela de falha. Morte anterior ao evento é retry normal.

## Mapa 3 — Santa Brasa: a oficina nasce

### M12 — É meu irmão

- Jogar: conversar na revenda, assistir à CGI da foto, comparar três carros e comprar um.
- Foto: Vicente com usado original, após a soltura ocorrida há alguns meses, sem data exata definida, Cromo refletido na vitrine. “É meu irmão.” Vendedor envia cópia ao telefone.
- Economia: crédito de Maciota cobre ao menos uma opção original e revisão; saldo não pode bloquear a campanha. Sem dívida com juros recorrentes.
- Saída: carro próprio persistente. Test drive é numa área curta; desistir volta à seleção sem cobrança.

### M13 — O homem que faz andar

- Jogar: levar o carro à Célia para inspeção e transportar uma caixa de ferramentas até seu depósito.
- História: ela explica a transferência ameaçadora de Biela e apresenta o pedido dele. Maciota confirma a relação, sem pedir resgate de um desconhecido só para conseguir turbo.
- Saída: Dante aceita ajudar. Ganho: revisão básica que garante dirigibilidade; tuning avançado continua fechado.

### M14 — Antes da transferência

- Jogar: buscar Célia, receber a informação de contato dela e reconhecer em jogo dois acessos fictícios do anexo da prisão; deixar um veículo de extração na área de missão.
- Limite: geometria e gatilhos autorados, sem sistemas de investigação gigantes. A planta do nível é um recurso de jogo entregue pela missão.
- História: Biela é útil à rede e virou um risco por recusar trabalho. Há urgência narrativa, mas aceitar inicia a janela; exploração anterior não o mata.
- Saída: equipamento de missão e checkpoint preparados. Veículo de extração tem assentos para Dante e Biela, independentemente do modelo comprado.

### M15 — Pedra Seca

- Jogar: entrar no anexo de manutenção, atravessar duas áreas de oposição e alcançar Biela. A primeira metade permite aproximação discreta; descoberta altera o encontro, não exige reinício automático.
- Virada: o alarme dispara de forma autorada quando a retirada começa. Biela acompanha Dante por caminhos com pontos seguros e entra no veículo.
- História: Biela se recusa a sair sem um caderno que comprova serviços impostos; recolhimento acontece na própria sala, sem backtracking longo.
- Saída: checkpoint com Biela no veículo e perseguição iniciada. Sua morte durante a missão é falha clara, nunca desaparecimento permanente da oficina.

### M16 — Não leva eles pra casa

- Jogar: escapar com Biela por pátio, avenida industrial e via externa; trocar pressão imediata por busca e despistar antes do último acesso ao galpão.
- Polícia: muitos sinais de cerco e grupos em etapas, com quantidade ativa limitada pelo desempenho. Reforços não nascem diante da câmera nem sobre o carro.
- Maciota: “Se tão vendo você, não entra. Esse lugar precisa continuar existindo.”
- Saída: galpão só aceita entrada segura após perder rastreamento por condição explícita. Se o jogador levar perseguidores até lá, retorna à fase de fuga com orientação, sem perder a base para sempre.

### M17 — Primeira chave

- Jogar: estacionar, entregar ferramentas e escolher primeira modificação visual e funcional. Passagem de uma noite mostra Célia e Biela montando a oficina.
- Cenário: mesmo galpão escuro agora tem elevador, iluminação, bancada e ferramentas; nada surge instantaneamente no quadro diante do jogador.
- História: Biela reconhece Cromo na foto, ligando a revenda à busca. Decide ficar porque também precisa de abrigo e quer trabalhar por conta própria.
- Saída: tuning permanente e teste de estrada para sentir a peça instalada. Primeiro pacote cabe no orçamento garantido.

### M18 — Acerto fino

- Jogar: circuito curto de avaliação com frenagem, curva e reta; voltar para um ajuste gratuito e disputar a classificatória de Cromo.
- Mecânica: vencer é viável com qualquer um dos três modelos usando preparação inicial. Categorias caras oferecem opções, não pedágio de progressão.
- História: Cromo exibe a Monaliza num anúncio do evento final. Dante sabe onde procurar.
- Saída: acesso ao complexo rival e dinheiro de progressão.

### M19 — Reconheço esse motor

- Jogar: entrar numa área de visitação do evento, seguir o som até a garagem de exposição e fotografar a identificação da Monaliza; retirar um registro na sala anexa durante um encontro pequeno.
- História: documento sugere que Vicente foi informado do carro tomado. A prova é parcial; Cromo dará contexto depois.
- Coerência: carro está em baia trancada e preparado para apresentação; objetivo imediato é conseguir acesso e localizar a chave, não ignorar uma porta aberta.
- Saída: rota de recuperação pronta. Objetivo essencial não depende de zoom livre ou reconhecimento visual minúsculo.

### M20 — De volta, Monaliza

- Jogar: vencer corrida/desafio contra Cromo para atraí-lo ao pátio; sobreviver à recusa dele em entregar o prêmio, abrir a garagem e fugir na Monaliza. Checkpoints separam prova, pátio e fuga.
- História: Cromo admite que o golpe foi de Roleta, financiado por ele, e que Vicente depois impediu uma devolução imediata. Registro aponta Vilar em Vegas.
- Estado: recuperar exatamente uma Monaliza, sua identidade e carga preservada; alterações cosméticas do inimigo são reversíveis. Célia leva o segundo carro para a base.
- Saída: ligação difícil com Vicente e viagem a Las Vegas. Cromo é derrotado e deixa de controlar o circuito; destino detalhado pode ser captura/fuga sem criar bifurcação extra obrigatória.

## Mapa 4 — Las Vegas: alguém no banco ao lado

### M21 — Quem dirige hoje

- Jogar: conhecer Helena, acompanhá-la até um ponto de coleta, executar a coleta a pé e retornar ao carro dela para a fuga.
- Implementação: trecho como passageiro deve ser curto; não pressupor combate veicular novo. Dante pode apenas acompanhar e escolher entre duas rotas autoradas pelo rádio.
- História: competência e humor de Helena aparecem antes do passado trágico.
- Saída: contato recorrente e acesso a um espaço de manutenção em Vegas, abastecido pela oficina de Biela.

### M22 — Porta errada

- Jogar: retirar documentos de um estacionamento de serviço de Vilar; uma mudança de destino obriga a buscar um funcionário que ficaria exposto.
- História: Helena insiste em voltar por ele, contrapondo o erro do passado.
- Saída: funcionário identifica a sobrevivente Lia e uma casa de retenção. Objetivo mudou por informação, não por traição aleatória.

### M23 — Uma noite sem serviço

- Jogar: consertar dano simples na oficina por interações curtas, escolher música e dirigir até um mirante urbano.
- História: romance, destino de viagem combinado e lembrança boa de Vicente. Helena pergunta o que Dante quer depois de encontrá-lo.
- Saída: aproximação explícita, sem sexo obrigatório nem minigame de afeto. Cena pode ser revista pelo diário; conteúdo principal não exige atividade opcional.

### M24 — A passageira que ficou

- Jogar: tirar Lia da casa de retenção e levá-la ao contato de Célia, com percurso que evita um encontro armado já sinalizado.
- História: Helena assume que conduziu um serviço ligado ao desaparecimento. Lia não é obrigada a perdoá-la por ter voltado.
- Saída: testemunha viva e registros complementares; base para o canal de custódia. Falha na escolta permite retry, não bloqueia escondido o final de todos vivos.

### M25 — O sobrenome entre nós

- Jogar: encontro de conversa com Helena; depois acompanhar a entrega protegida de uma cópia dos registros a uma defensora.
- História: Helena confessa ter trabalhado para Vicente e ter reconhecido a ligação familiar. Dante pode confrontá-la e ouvir todas as explicações. Ela escolhe continuar o plano, não apenas o romance.
- Saída: contato com Elisa Moura e indicação do arquivo de Vilar. Vicente telefona demonstrando conhecer a relação.

### M26 — A casa guarda tudo

- Jogar: entrar como equipe de transporte no setor de serviço do cassino, recuperar o arquivo e escapar pela garagem após confronto com Vilar e seguranças.
- Boss: Vilar controla portas e reforços locais; a missão interrompe esse controle, sem boss com resistência absurda. Interior compacto, três zonas reaproveitáveis.
- História: cruzar registros revela armação original e crimes posteriores de Vicente. Os dois fatos recebem cenas/resumos próprios.
- Saída: Vilar perde o arquivo e seu poder de negociação; cópias ficam fora do carro, evitando anular história por explosão incidental.

### M27 — Ainda dá tempo de ir

- Jogar: ajudar a retirar Lia de um abrigo comprometido e levar o grupo até Célia.
- História: Helena recebe oferta de fuga individual, mas retorna por iniciativa própria. Vicente exige o arquivo e convoca Dante para Lastro.
- Saída: viagem final; relacionamento continua tenso e escolhido. Helena participa do planejamento, sem ser sequestrada para motivar o capítulo inteiro.

## Mapa 5 — Lastro: contas de família

### M28 — O bairro dele

- Jogar: chegar, entregar remédios a um alojamento a pedido de um morador e ouvir um comerciante impedido de sair.
- História: mostrar apoio popular real e coerção lado a lado. Uma antiga oficina ligada à família ancora uma lembrança.
- Saída: contato local e localização de um posto de cobrança; Dante entende que uma ofensiva cega atingiria civis.

### M29 — Proteção tem preço

- Jogar: retirar uma família de um imóvel usado como garantia de dívida; preparar embarque e fugir de um grupo finito do Pacto.
- História: Vicente chama a retirada de roubo de algo que “deve a ele”.
- Saída: abrigo fora da área final e testemunho sobre o centro de despacho.

### M30 — O arquivo inteiro

- Jogar: buscar a última testemunha documental e cruzar a informação em encontro com Maciota e Helena; deslocamento seguido de uma cena curta, sem puzzle documental obrigatório.
- História: Dante admite o que fez e o que não conseguiu fazer quando era policial. O jogador recebe cronologia completa antes do final.
- Saída: três preparações P01–P03 abertas com consequências explícitas. São opcionais para concluir o jogo e necessárias para a alternativa de contenção.

### M31 — Quem paga os homens

- Jogar: interromper um pagamento de Vilar aos dissidentes do Pacto, proteger o mensageiro que aceita falar e recuperar o local da ofensiva planejada.
- História: uma facção pretende eliminar Vicente e destruir provas. Helena insiste em copiar o arquivo antes de seguir.
- Saída: reduzir oposição autorada do final; a informação mantém a ameaça externa compreensível.

### M32 — Antes de entrar

- Jogar: reunir Maciota, Helena e Biela por rádio na base, escolher veículo/loadout e revisar o plano.
- UI: informar “contenção disponível” ou quais preparações faltam; permitir voltar e executá-las. Criar checkpoint/snapshot antes do ponto sem retorno.
- História: conversa particular do casal, sem promessa garantida de sobrevivência. Dante assume que precisa de ajuda.
- Saída: iniciar missão final somente por aceite explícito.

### M33 — O que você construiu

- Jogar: atravessar pátio industrial e retirar trabalhadores da zona de conflito, usando acessos liberados antes. Helena cumpre objetivo paralelo de preservar a saída.
- História: atravessar os símbolos de poder do irmão; moradores não são inimigos só por defendê-lo em diálogo.
- Saída: centro de despacho acessível e checkpoint. Reforços externos limitados por M31, sem ondas infinitas.

### M34 — Irmão contra irmão

- Jogar: boss em fases de cobertura e deslocamento, com Vicente usando o ambiente; vitória incapacita e abre confronto verbal.
- História: “Eu perdi tudo tentando tirar você de lá.” / “Mas saiu pela porta da frente. Eu fiquei.” Vicente precisa ouvir também suas próprias decisões recentes.
- Saída: disputa final pelas provas e ameaça a Helena. Sem aplicar dano letal acidental a Vicente antes da escolha narrativa.

### M35 — Quem sai daqui

- Jogar: decisão explícita da matriz de finais, seguida de extração curta com elenco correspondente.
- Saídas: força letal salva Helena e mata Vicente; contenção preparada salva todos; negociação exposta causa morte de Helena e abre escolha de entregar ou matar Vicente.
- Regras: sem relógio oculto; apresentar o risco concreto; preparar todos vivos nunca é missão secreta. Dante morrer na extração é retry do checkpoint já consistente, não final novo.
- Estado: fixar resultado uma vez, preservar patrimônio e registrar quem vive/morre/é preso.

### M36 — Depois da estrada

- Jogar: epílogo curto específico, retomando garagem ou destino combinado; transição explícita de algumas semanas.
- História: cena do resultado, primeira conversa de pós-game e liberação das três missões exclusivas descritas na bíblia.
- Saída: mundo persistente pós-final, sem reset da história.

## Preparações finais opcionais, antes de M32

| ID | Missão | Ação | Consequência visível |
|---|---|---|---|
| P01 | Fora do alcance | Levar Lia e pessoas ameaçadas a um abrigo externo com Célia | Vicente perde a capacidade imediata de ameaçar testemunhas; aliada fica livre para apoiar a saída |
| P02 | Porta de entrada | Entregar cópias e testemunho à equipe externa em encontro protegido | Custódia fiscalizada disponível; Dante pode prometer uma entrega diferente da prisão original |
| P03 | Segunda saída | Biela e Helena testam veículo de apoio e caminho médico numa volta curta | Cobertura, retirada e atendimento viabilizam a contenção de M35 |

As três são apresentadas juntas; nenhuma exige repetir corridas, comprar upgrade máximo ou achar colecionáveis. Missões falhadas são repetíveis antes do ponto sem retorno.

## Histórias paralelas e atividades

| Cadeia | Janela | Conteúdo | Ganho narrativo/mecânico |
|---|---|---|---|
| Célia — Peças com procedência | Depois de M17 | Buscar equipamento comprado, transportar sem dano excessivo, preparar bancada | Novas peças visuais e história profissional de Biela; primeira oficina já funciona sem esses serviços |
| Nina — Corrida sem dono | Depois de M11/M18 | Reencontrar piloto, organizar prova justa, enfrentar cobrança de Roleta | Encerra história do organizador e oferece circuito repetível; não toma o lugar de Cromo |
| Maciota — O que eu sabia | Depois de M20 | Conversa durante entrega curta, recuperar caixa de cartas guardadas | Contexto do silêncio entre irmãos; informação essencial permanece na campanha |
| Biela — Nome limpo | Depois de M20 | Obter recibos e localizar ex-cliente disposto a depor | Base para defesa no pós-game; sem anistia automática pelo resgate |
| Helena — Outra rota | Entre M23 e M27 | Corrida amigável, passeio e ajuda a uma conhecida | Cenas de personalidade e foto do casal, sem gate oculto de final |
| Oficina — Acerto de rua | Depois de M18 | Tempos em reta, circuito e frenagem com ranking local | Dinheiro e comparação de builds; sem aposta obrigatória do carro próprio |

Atividades existentes como desmanche e serviços urbanos continuam independentes. Não reescrever sistemas atuais para encaixar cada um numa conspiração. Evitar dez chamadas simultâneas ao liberar o mapa: uma principal e até duas sugestões laterais visíveis.

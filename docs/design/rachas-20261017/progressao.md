# Progressão dos rachas — diagnóstico e proposta

Data: 17/10/2026. Escopo: pesquisa e leitura do código, sem alterar runtime, saves ou economia.

Este documento separa o que foi encontrado no código da direção proposta. A leitura não comprova que os fluxos estejam funcionando na cena atual. Nenhum Godot ou teste foi executado nesta análise.

## Diagnóstico

O jogo já libera peças por vitórias em corridas. O problema é que o ciclo atual termina cedo: seis rivais em sequência, prêmio apenas na primeira vitória e baterias livres sem remuneração ou livro persistente de recordes/progressão. A modalidade ainda não sustenta, por si só, quem quer continuar correndo e preparando carros.

| Estado observado no código | Consequência para o design |
|---|---|
| [DesertDragProgress.gd](../../../activities/desert_drag/DesertDragProgress.gd) define Digo, Lívia, Raul, Jessica, Nadir e Rauhz, nessa ordem. Uma vitória libera o rival seguinte; adversários vencidos permitem revanche. | A carreira existente pode ser preservada como espinha autoral. A repetição precisa ganhar outros objetivos. |
| O mesmo arquivo paga apenas primeiras vitórias: R$ 4.000, 5.000, 6.000, 7.000, 8.000 e 9.000, totalizando R$ 39.000. Há recibos idempotentes e recuperação de prêmio pendente. | Preservar os recibos e valores históricos. Remuneração recorrente deve ter contrato separado. |
| Recordes são indexados por rival, sem separar carro, preparação, distância ou assistências. | Não oferecem comparação justa para experimentar veículos baratos e preparações diferentes. |
| [RaceWins.gd](../../../systems/campaign/RaceWins.gd) soma seis rivais de arrancada e duas missões da campanha, `cobra_race` e `cobra_finale`. O máximo calculado é oito; o comentário ainda fala em cinco rivais e sete provas. | O comentário está desatualizado. Não inferir o estado da implementação pela descrição. |
| [DesertTuning.gd](../../../gameplay/desert_cars/DesertTuning.gd) libera peças com requisitos de uma a sete vitórias distintas. `nitro_pro` exige sete. Takeshi não entra em `RaceWins`. | Quem vence somente os seis rivais da arrancada não pode comprar essa peça sem uma vitória de campanha. |
| [DesertDrag.gd](../../../activities/desert_drag/DesertDrag.gd), em `_finish`, gera resultado transitório `casual` para a bateria livre e não chama o registro de progressão. | A bateria livre é prática, mas não constitui uma carreira longa. |
| [DesertGarageState.gd](../../../runtime/desert/DesertGarageState.gd) já guarda peças instaladas, propriedade e até três presets por carro: rua, drag e terra. | A preparação entre provas pode aproveitar infraestrutura existente. |
| Cada peça comprada exige recibo com preço exato. A exceção de presente existente é explícita e específica para o Supra de Takeshi. | Não inserir peças diretamente em `owned` nem simular compra para distribuir prêmio. Criar contrato próprio de recompensa. |
| [DesertSaveContract.gd](../../../runtime/desert/DesertSaveContract.gd) cruza carteira, progressão, garagem, instrumentos, frota e prêmio de Takeshi. | Novos modos precisam de estado versionado e migração explícita, preservando os históricos existentes. |
| [RaceReceipts.gd](../../../systems/economy/RaceReceipts.gd) reconhece eventos recorrentes de motocross/esqui no codec atual. | Pagamento recorrente de arrancada precisa de identidade e contrato próprios. |
| [DesertCarCatalog.gd](../../../gameplay/desert_cars/DesertCarCatalog.gd) contém dez IDs, incluindo edições que compartilham carroceria/mecânica de base. | Variedade deve aparecer na silhueta, tração, som e comportamento; só mudar pintura não resolve a impressão de repetição. |
| [TakeshiHonor.gd](../../../runtime/TakeshiHonor.gd) implementa duelo opcional e escolha permanente entre carro e katana. | Preservar essa identidade e a escolha já feita nos saves. Não transformar o duelo em requisito obrigatório da nova carreira. |

### Fila e encontro se contradizem

[DragOpenMeet.gd](../../../activities/desert_drag/DragOpenMeet.gd) cancela a inscrição quando Dante sai do carro ou troca de veículo. A inscrição permite próxima largada ou uma bateria adicional à frente. O [registro de validação anterior](../../drag-open-meet-validation-20261012.md) relata espera de 71,034 segundos na segunda posição.

Isso prende o jogador ao carro justamente quando o encontro deveria convidar a conversar, ver outros carros e preparar a próxima prova. É um conflito de fluxo constatado na leitura, não uma reprodução do defeito de fila relatado agora pelo usuário.

Proposta: a ficha fica vinculada a Dante e ao carro inscrito; ele pode circular a pé. A chamada informa posição e prazo de apresentação, com ação para avançar à largada. Trocar de carro pede uma nova inscrição de forma clara. Obstrução ou cancelamento técnico devolve a ficha sem punição. O acesso rápido à próxima corrida deve coexistir com a fila física para quem quer permanecer no encontro.

## Referências oficiais

As referências fundamentam as mecânicas indicadas abaixo. Não justificam copiar suas interfaces, assets ou modelos de monetização. O conceito da próxima seção é uma proposta para Geteco.

| Fonte | Mecânica documentada | Aplicação proposta |
|---|---|---|
| [GTA Online — LS Car Meet, notas oficiais 1.54](https://support.rockstargames.com/articles/7a5MsGMCeLTCp3ek6LEWrA/gtav-title-update-1-54-notes-ps4-xbox-one-pc) | O encontro reúne exposição, teste, modificação, corridas e reputação. | Fazer do encontro um destino e ponto de preparação com atividades conectadas. |
| [NFS Unbound — Drift & Drag](https://www.ea.com/games/need-for-speed/need-for-speed-unbound/news/vol7-drift-and-drag-update) | Troca manual, nitro estratégico e duelos contra rivais com carros reconhecíveis. | Personalidade e domínio do carro fazem parte da progressão. |
| [NFS Unbound — notas do Vol. 7](https://www.ea.com/security/news/vol7-0-1-patch-notes) | Distâncias variadas, encontros especializados, eventos de desempenho igualado e carro emprestado para experimentar modalidade. | Variar a exigência das provas e permitir entrada sem compra obrigatória de equipamento. |
| [Forza Motorsport — Rivals](https://forza.net/news/forza-motorsport-multiplayer) | Competição por tempo em combinação de carro e pista, classes de preparação, reinício rápido e diagnóstico por trechos. | Sustentar o prazer de melhorar e compreender onde o tempo foi perdido. |

## Conceito proposto: Noite de Acerto

Dante chega com um carro e disputa uma pequena noite com três tipos de prova. O objetivo é conhecer e acertar aquele carro, enfrentando pessoas reconhecíveis no pátio. Esta estrutura ainda não está implementada.

| Prova | Estrutura proposta | Habilidade e preparação |
|---|---|---|
| Saída | Uma passagem de 201 m | Reação, tração e primeira troca. Hatch leve continua competitivo. |
| Marca | Duas passagens de 402 m | Melhorar o próprio tempo e manter consistência. Há conquista pessoal mesmo quando o rival vence. |
| Desafio | Um duelo de 800 m | Fôlego, relação de marcha e escolha do momento do nitro. |

São três provas e quatro passagens físicas. O carro permanece o mesmo durante a noite, mas Dante pode trocar livremente entre peças já possuídas e presets entre provas. Cada prova dá pontos; perder uma não elimina a noite. Uma ação inicia a próxima prova e outra permite voltar ao encontro. Meta inicial de duração: aproximadamente cinco a oito minutos, a validar no fluxo real depois da correção da fila.

A particularidade é preparar o mesmo carro para três demandas diferentes, acompanhando rivais que fazem o mesmo. Um carro forte na saída pode perder no trecho longo. O hatch preparado continua relevante. A IA usa seus perfis e acertos, sem aumento artificial de velocidade para recuperar posição.

As distâncias são uma proposta de conteúdo e precisam de configuração, percurso, área de frenagem, resultados e validação próprios. Não contar esta tabela como prova jogável.

### Classes

- **Original:** preparação fixa e carro emprestado disponível. Permite competir sem compra e aprender sem risco econômico.
- **Preparado:** limite de preparação, com escolhas que têm vantagens e perdas reais.
- **Livre:** preparação completa, recordes e rivais mais fortes.

Não classificar somente por velocidade final: relação curta, nitro e turbo tornam esse número insuficiente. A classificação deve considerar o regulamento de peças e o desempenho físico por distância. Os limites só podem ser fechados depois da comparação de carros representativos.

### Campanha e acesso independente

A ponte e a liberação de mapas preservam integralmente sua condição de campanha. O novo conteúdo não libera passagem para o mapa 2 nem muda restauração de saves ou conclusão de missão.

Na campanha, os rachas entram pelo acesso normal disponível. Um futuro botão de **Rachas** no menu pode abrir um perfil separado, com carro inicial e progressão própria, para quem quer apenas a modalidade. Esse perfil não concede dinheiro, peças, carros, missões concluídas ou acesso a mapas no save da campanha. A infraestrutura de perfil separado não foi verificada nem implementada nesta análise.

## Peças com história de rival

Cada rival ganha uma especialidade que o jogador pode observar, experimentar e conquistar. A tabela abaixo é direção autoral nova; não descreve biografias já verificadas.

| Rival | Especialidade proposta | Aprendizado e família de recompensas |
|---|---|---|
| Digo | Fazer um carro barato render | ECU/comando de rua e primeiro acerto. |
| Lívia | Tração e controle da saída | Demonstrar saídas consistentes; pneus e suspensão. |
| Raul | Torque e escolha de relação | Comparar desafios de duas distâncias; relações curta e longa. |
| Jessica | Giro, turbo e precisão | Sequência de trocas e duelo; ECU esportiva e turbo. |
| Nadir | Eficiência em alta e uso do nitro | Melhorar o trecho final; peso e perfil de descarga. |
| Rauhz | Domínio do carro completo | Completar a noite de três provas; preparação de competição. |

O rival não entrega uma peça aleatória. A família liberada fica conhecida antes do desafio. A recompensa pode ser autorização permanente de compra ou um acerto associado ao rival, com primeira instalação incluída quando o contrato assim determinar.

Desafios de aprendizado podem fornecer carro emprestado. O jogador não deve precisar da própria peça bloqueada para ganhar o desafio que a libera. Liberar uma família também não deve exigir comprar todas as etapas anteriores.

Desbloqueios já conquistados são preservados. Toda peça de corrida ganha uma rota de mérito dentro da modalidade; a campanha continua oferecendo caminhos alternativos. Para isso, mérito e vitória de campanha devem ser condições alternativas explícitas, sem inventar vitórias antigas no livro atual.

Takeshi mantém seu duelo opcional e a escolha de prêmio existente. Não usar sua recompensa como solução obrigatória para o bloqueio atual da sétima vitória.

## Rejogabilidade sem grind injusto

- Treino gratuito, com recordes por carro, preparação, distância e assistência usada.
- Dinheiro por concluir prova válida; bônus por vitória e marcos inéditos.
- Primeira vitória de rival conserva prêmio único. Repetição paga a prova por contrato próprio, sem simular outra primeira vitória.
- Metas pessoais próximas do desempenho observado e alternância de adversários/classes.
- Desafios permanentemente disponíveis, sem calendário diário ou sequência obrigatória de dias.
- Sem perda de prêmio por ausência, fusão aleatória de peças ou aposta necessária para continuar.
- Trocas de configuração gratuitas depois da aquisição. Experimentar não deve criar uma espiral de reparos ou custos.
- Remuneração calibrada para uma melhoria básica surgir após poucas corridas completas; valores finais dependem de comparação com as demais atividades do jogo.

Recordes precisam identificar o acerto usado. Alterar uma peça não pode apagar o recorde anterior nem comparar silenciosamente duas preparações incompatíveis. Assistência de largada/troca deve permanecer disponível para progressão normal, com a condição da corrida registrada para comparações claras.

## Integração proposta

1. Preservar `desert_drag` e os recibos existentes; criar estado versionado separado para noites, méritos, recordes e pagamento recorrente.
2. Reaproveitar motor físico, resultado, revanche e presets existentes, mantendo o mesmo caminho mecânico de jogador e rival.
3. Registrar a conclusão física antes de emitir recompensa; pagamento pendente deve sobreviver ao save e ser idempotente.
4. Criar contrato explícito de presente/cupom se houver instalação incluída. Não burlar `DesertGarageState.valid` com propriedade sem proveniência.
5. Acrescentar a regra de desbloqueio alternativa à camada compartilhada de tuning, usada por Digo e Maciota. Não modificar personagens, armas ou transições de garagem por consequência desta proposta.
6. Separar recordes e recompensas de treino, carreira e desafio. Uma revanche não vira uma nova vitória distinta.
7. Quando o modo independente for aprovado para implementação, usar perfil próprio e restaurar o contexto corretamente ao voltar ao menu; não escrever no save de campanha.

## Ordem de implementação sugerida

1. **Sensação e continuidade:** fila, largada, troca de marchas, áudio do próprio carro, estabilidade visual do horizonte, retorno e revanche.
2. **Núcleo rejogável:** noite com três provas, resultados úteis, recordes por configuração e carro emprestado.
3. **Progressão autoral:** especialidades dos rivais, desafios e liberação alternativa de peças, com economia e migração preservadas.
4. **Acesso dedicado futuro:** perfil separado para quem quer apenas a modalidade.

O primeiro marco precisa funcionar e ser agradável antes de ampliar o incentivo de repetir. Os documentos anteriores registram verificações e lacunas históricas, mas não substituem validação da versão atual na cena real.

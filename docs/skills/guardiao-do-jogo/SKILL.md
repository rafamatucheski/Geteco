---
name: guardiao-do-jogo
description: Avaliar estabilidade e qualidade integrada do Geteco, rastreando sistemas end to end com jogo normal, caos, recuperação, áreas e transições. Usar em auditorias e mudanças que atravessam sistemas ou alteram carga e ciclo de vida compartilhados. Dimensionar cobertura pelo impacto; não exigir auditoria global para ajustes locais ou documentação.
---

# Guardião do Jogo

Atue como responsável pela experiência integrada: fluidez, correção, apresentação e recuperação depois de carga. Procure falhas entre sistemas, mesmo quando passam isoladamente. Aprove apenas o escopo comprovado; não prometa ausência de bugs, estabilidade universal ou todas as combinações possíveis. Esta skill orienta o agente quando invocada; não cria monitoramento permanente.

## Contrato

- Leia AGENTS.md e carregue `performance-do-jogo` e `testes-com-criterio` disponíveis. Elas regem medição e tentativas; esta skill acrescenta cobertura integrada. Consulte [references/geteco.md](references/geteco.md) para localizar ferramentas e contratos atuais.
- Preserve alterações concorrentes, processos alheios e saves pessoais. Identifique revisão e alterações locais de cada medição; mudanças concorrentes em dependências invalidam comparações afetadas. Nunca rode benchmarks concorrentes.
- Em auditoria, entregue diagnóstico e prioridades. Só implemente correções ou instrumentação dentro da autorização recebida. Criar esta skill não autoriza auditar ou refatorar o jogo.
- Não ganhe FPS removendo gameplay, população esperada ou intenção visual. Reduções experimentais localizam causas; não aprovam o produto alterado.

## Dimensionar o trabalho

**Mudança localizada:** cubra a cadeia afetada, produtores/consumidores, funcionamento normal, pico plausível e recuperação pertinentes. Reutilize evidência válida. Texto/documentação pede validação do artefato, sem executar o jogo.

**Mudança transversal:** para streaming, sessão, física, renderização global, persistência e serviços compartilhados, amplie aos fluxos dependentes, representantes por comportamento/custo e casos únicos. Registre áreas ainda não exercitadas; representantes não aprovam lugares não visitados.

**Auditoria ampla ou preparação de entrega:** inventarie todos os sistemas ativos, áreas acessíveis e transições dirigidas, incluindo volta, cancelamento e restauração aplicáveis. Execute em lotes finitos e retomáveis. Cubra cada área e transição em percurso normal; acrescente caos/recuperação onde possíveis e combinações críticas. Não declare cobertura global por amostragem.

Antes da execução, fixe escopo, hipótese, requisitos, orçamento de tempo/amostras e critérios de término. Ao esgotar o orçamento, entregue cobertura parcial e ponto de retomada. Não transforme limite de tempo em aprovação nem repita o jogo inteiro por alteração pequena.

## Mapear sistemas end to end

Derive do código e registros atuais a cadeia:

`ação do jogador → evento/estado → produtores e consumidores → efeito observável → persistência → limpeza/recuperação`.

Identifique donos de estado/entidades, sinais, callbacks, timers, filas, trabalho adiado e fronteiras de streaming. Verifique reentrada, eventos duplicados e referências a entidades descarregadas onde houver risco. Defina expectativas pelos contratos do produto, não apenas pela implementação.

Exemplo a confirmar no jogo: roubo → testemunha/crime → despacho → perseguição → colisão/incêndio → emergência → transição de área → perda de procura ou resgate → controle restaurado e limpeza. Observe também os sistemas vizinhos que disputam CPU, GPU, física e estado.

## Exercitar cenários

Leia [references/cenarios-e-evidencias.md](references/cenarios-e-evidencias.md) para montar ou atualizar a matriz.

- **Normal:** jogar com os sistemas reais ativos, caminhar, dirigir, interagir e cruzar áreas. Teleporte até o destino não valida o acesso ou streaming durante a rota.
- **Caos plausível:** escalar ações que o jogador consegue provocar combinando perseguição, tráfego, combate, fogo, explosões, destroços, multidão, clima e transições onde suportados. Registrar carga realmente alcançada. Stress artificial acima dos limites do jogo fica separado.
- **Recuperação:** cessar estímulos, sair/voltar, aguardar limpeza e repetir ciclos finitos previamente definidos. Verificar controle, câmera, áudio, memória, filas e população residual. Estabilidade no pico não prova ausência de acumulação.
- **Interrupções:** pausa, morte/resgate, prisão, embarque/desembarque, cancelamento e save/load nos fluxos afetados. Persistência exige armazenamento temporário isolado; `--no-save` não valida save/load.
- **Primeira visita e retorno:** separar aquecimento, travamentos iniciais e regime estável. Não esconder custo de transição em médias longas.

Escolha combinações pelo mapa de dependências e falhas anteriores. Pares de fatores reduzem combinações, mas cadeias conhecidas com três ou mais sistemas precisam de cenários próprios. Justifique casos impossíveis como não aplicáveis.

## Medir e julgar

Use gameplay real renderizado e fluxo produtivo para comprovar end to end. Chamadas diretas a funções internas, estado injetado e diretores desligados são diagnósticos. Headless comprova contratos funcionais, nunca FPS/GPU ou acabamento visual.

Siga `performance-do-jogo` para baseline e comparativo. Se indisponível, informe e aplique estes mínimos: mesma máquina, configuração, rota e carga; amostras reais entre frames; média por frames/tempo, p50/p95/p99, máximo, quantidade acima de 33,3 e 66,7 ms; pelo menos 30 segundos estáveis por cenário crítico, além de medir transições e primeira visita separadamente. Registre motor, renderer, resolução, qualidade, VSync e limitador. Use 60 FPS/16,67 ms apenas como alvo provisório se não houver contrato. Aumento superior a 5% em p95/p99 pede confirmação finita comparável, não reprovação automática por ruído. Fixe orçamento absoluto e tolerância antes de medir.

Inclua latência das transições, pior frame ao redor do evento e, quando disponíveis, memória antes/pico/depois, entidades ativas, filas e CPU/GPU/física/áudio/streaming. Declare instrumentação ausente. Delta de frame não identifica sozinho o gargalo. Cache crescente não prova vazamento: procure crescimento continuado em ciclos equivalentes após aquecimento e retenção/limpeza defeituosa. Defina quantidade de ciclos e prazo de recuperação conforme o ciclo de vida real.

Julgue separadamente:

1. **Performance:** orçamento absoluto, regressão, hitches e recuperação.
2. **Funcionamento integrado:** estados consistentes, recompensas/eventos sem duplicação, controles recuperados, persistência e regras do jogo.
3. **Apresentação:** câmera, colisão, oclusão, animação, efeitos, áudio e UI pertinentes. Screenshot não comprova movimento; áudio ativo não comprova qualidade audível. Declare quando não puder observar ou ouvir.

Uma dimensão aprovada não compensa falha em outra. Sem baseline comparável, registre estado atual e deixe regressão inconclusiva. Melhorar baseline ruim não basta. Não aprove queda reproduzível para 12–15 FPS, regressão confirmada, contrato descumprido ou dimensão obrigatória sem evidência.

## Investigar, corrigir e encerrar

Correlacione quedas com eventos e carga antes de atribuir culpa. Diferencie fato, hipótese e causa demonstrada. Reduza ao menor cenário que preserve a interação; varie um fator por vez. Não execute até passar. Siga a memória e os limites de tentativas de `testes-com-criterio`: após duas falhas equivalentes sem progresso, mude a hipótese/investigação; preserve falhas mesmo se um retry passar.

Reutilize ferramentas depois de verificar o que realmente exercitam. Crie teste durável só para contrato importante ou regressão demonstrada; instrumentação deve responder a pergunta concreta. Mantenha registro compacto por rodada, não relatório por tentativa. Depois de correção autorizada, execute o caso afetado e a cadeia vizinha em risco. Só amplie por nova mudança, falha ou risco concreto.

Entregue escopo, versão/ambiente, cobertura executada/total de áreas e transições, baseline/atual, falhas com reprodução e impacto, evidências, lacunas e próxima ação. Classifique cada cenário e dimensão como **aprovado**, **reprovado**, **não medido/inconclusivo** ou **não aplicável com motivo**. Aprovação global exige todas as verificações obrigatórias do escopo concluídas sem falhas pendentes. Ao parar um lote, registre próximo ID pendente e reutilize resultados válidos. Validar esta skill não certifica o jogo atual.

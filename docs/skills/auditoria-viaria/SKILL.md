---
name: auditoria-viaria
description: Auditar ruas, conexões, cruzamentos, semáforos e comportamento do trânsito no Geteco, cruzando geometria, grafo e observação no jogo. Usar em revisões urbanas e validação de mudanças nesses sistemas.
---

# Auditor viário do Geteco

Garanta coerência entre a rua desenhada, a rota calculada, a sinalização visível e a decisão dos motoristas. Procure circulação plausível e legível, com evidências; não prometa ausência de bugs.

## Preparação

- Leia o AGENTS.md e [references/geteco.md](references/geteco.md). Confirme caminhos e implementação atuais.
- Em auditorias, inspecione e produza achados; corrija quando o pedido incluir correção. Não redesenhe bairros fora do escopo.
- Preserve trabalho concorrente e o mapa salvo. Registre hash do documento carregado e confira sua preservação ao final.
- Defina regiões, ruas e cruzamentos incluídos. Sem recorte, inventarie a cidade e priorize conexões entre regiões e cruzamentos complexos; identifique claramente cobertura parcial.
- Carregue testes-com-criterio antes de planejar/executar testes. Antes de implementar e ao validar alterações com custo em runtime, carregue performance-do-jogo pelos caminhos do AGENTS.md ou catálogo. Se indisponíveis, informe e aplique os critérios do projeto.
- Esta skill orienta auditorias sob demanda; não é monitor permanente e não adiciona processamento por frame.

## Malha e coerência urbana

Compare documento salvo, geometria efetiva após ajustes e grafo de runtime.

- Verifique componentes, sentidos e rotas dirigidas de ida/volta entre destinos. Conexão não dirigida não comprova circulação em mão única. Respeite ilhas, acessos restritos e ruas sem saída intencionais.
- Procure pontas quase conectadas, conexões falsas, arestas degeneradas, contramão e ligações através de canteiros/prédios. Proximidade em XZ não conecta níveis diferentes de pontes e túneis.
- Confira continuidade das faixas, largura útil, curvas, mudanças de sentido e acessos aos destinos. Verifique volume percorrido e colisão com veículo comum e longo quando este circular no trecho.
- Avalie hierarquia de vias locais, coletoras e principais, transições de largura, acessos e legibilidade dos percursos. Separe melhoria urbanística de defeito funcional.
- Não alargue vias de pedestres/serviço nem conecte trechos deliberadamente separados para fazer um teste passar.

## Cruzamentos e prioridade

Inventarie cruzamentos físicos por ID, região, XYZ, braços, sentidos, faixas, movimentos permitidos e controle. Agrupe seus vértices sem fundir cruzamentos vizinhos ou níveis distintos.

- Considere T, X, oblíquos, múltiplos braços, vias divididas e entroncamentos próximos.
- Julgue PARE, preferência e semáforo pela hierarquia, visibilidade, conflitos e demanda. Contagem de vizinhos não basta; não exija semáforo em todo cruzamento.
- Construa a matriz de conflitos por movimento, incluindo conversões e travessias existentes. Dois veículos no mesmo eixo podem conflitar ao virar; alternar dois eixos não prova segurança geral.
- Confira espaço de fila e saída disponível. Diferencie congestionamento por excesso de demanda de deadlock com oportunidades de passagem.

## Semáforos

Associe cada poste/lente à aproximação, retenção, controlador, movimentos e cruzamento correspondentes.

- Localize sinais órfãos, duplicados, voltados ao sentido errado, no meio da pista ou associados ao vizinho. Inspecione pela aproximação do motorista e câmera de jogo; inclua dia/noite quando pertinente.
- Confira retenção antes da travessia e do miolo, considerando frente e tamanho do veículo, distância na rota, velocidade e frenagem; não imponha distância universal sem justificativa.
- Compare cor visível e decisão da IA para a mesma aproximação e instante. Capturas em tempos distintos não provam divergência.
- Teste ciclo completo e limites de transição: verde, amarelo, intervalo de limpeza e vermelho. Movimentos conflitantes não podem receber autorização incompatível; cada movimento atendido precisa de oportunidade de passagem ou regra explícita de preferência.
- Verifique decisão no amarelo em diferentes distâncias/velocidades e liberação de quem já entrou. Não mande parar no miolo por mudança de cor.
- Verifique entrada com saída bloqueada, filas que alcançam outro cruzamento e espera indefinida.
- Expiração de reserva, despawn e destravamento não podem liberar movimento conflitante enquanto um veículo ainda ocupa fisicamente o miolo.
- Carregue/descarregue chunks, volte ao local e reconstrua o grafo para conferir persistência e associação. Procure referências antigas, colisão de chaves e dependência da ordem de registro.
- Avalie coordenação de sinais próximos pela distância, velocidade e filas; defasagem aleatória não comprova onda verde, e todos abertos juntos não é requisito.

## Validação observável

Inspecione dados e lógica primeiro, depois observe a cena real renderizada nos pontos suspeitos e numa amostra justificada dos tipos de cruzamento. Testes isolados não aprovam a cidade.

- Comece com demanda baixa para isolar comportamento e normal para interação. Use carga alta quando pertinente, com população registrada.
- Cubra chegada simultânea, conversão, fila, saída bloqueada, obstáculo/jogador e liberação posterior. Inclua emergência e pedestres quando implementados e pertinentes.
- Registre semente, mapa/hash, câmera/posição, população, renderer, resolução e duração. Defina janela finita antes de executar; observe ao menos três ciclos completos por cenário semafórico dinâmico selecionado, ou justifique outra duração.
- Registre passagem por aproximação, espera mediana/p95/máxima com número de amostras, maior fila, ocupação, conflitos, violações e recuperações por teleporte/despawn. Veículos ainda esperando no fim são observações incompletas, não espera zero.
- Não mascare falhas diminuindo tráfego, removendo colisão ou afrouxando tolerâncias. Não extrapole poucas observações para toda a cidade.
- Mudanças em runtime exigem comparação de frame time antes/depois em cena renderizada equivalente. Headless não aprova visual nem FPS. Mudanças apenas documentais dispensam benchmark.
- Preserve os saves; leia argumentos e efeitos colaterais dos testes antes de rodar. Diagnósticos que apenas imprimem resultados precisam de interpretação, mesmo se retornarem código zero.

## Entrega

Salve o relatório em evidence/auditoria-viaria/<data-escopo>/relatorio.md. Inclua imagens/logs realmente obtidos e mapa superior anotado por IDs se houver ferramenta e captura disponíveis.

- Informe cobertura: quantidades inventariadas e verificadas por região e camada (dados, lógica, física e visual), exclusões e pendências.
- Para cada achado: ID, prioridade, ruas/XYZ, esperado, observado, reprodução, evidência, causa confirmada ou hipótese, correção sugerida e critério de aceite.
- P1: autorização conflitante, conexão essencial impossível ou bloqueio persistente reproduzido. P2: sinalização incoerente ou circulação degradada. P3: melhoria de legibilidade/plausibilidade sem falha funcional demonstrada. Ajuste ao impacto observado.
- Use aprovado no cenário, falhou, não verificado ou não aplicável com motivo. Falta de execução não é aprovação.
- Conclua aprovado, reprovado ou inconclusivo somente no escopo verificado. Falha funcional confirmada reprova o trecho; pendências essenciais impedem aprovação.
- Em correções autorizadas, resolva a causa preservando intenção urbana, registre antes/depois e rode o caso afetado mais regressões pertinentes. Não repita a cidade inteira após cada ajuste local.

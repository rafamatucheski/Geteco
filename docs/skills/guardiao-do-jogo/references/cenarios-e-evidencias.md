# Matriz de cenários e evidências

Use uma matriz por rodada para planejar, retomar e declarar cobertura. Adapte o formato aos artefatos existentes; não crie catálogo paralelo se já houver um mantido. Não preencha resultados sem execução.

## Inventário

Extraia do mundo atual áreas, interiores distintos, entradas, saídas e transições especiais. Diferencie lugar, interior e portal: dois acessos ao mesmo interior são duas transições. A→B e B→A têm riscos diferentes.

Vincule cada sistema ativo a pelo menos um fluxo na auditoria ampla: sessão/entrada, jogador/input, câmera, veículos/ocupantes, tráfego, pedestres, combate, crime/polícia, emergência, missões/economia/inventário, interiores, streaming, clima/iluminação, física, animação, áudio, UI e persistência, conforme existam. Sistemas sem cenário vinculado permanecem pendentes.

Associe cada área/transição a normal, caos aplicável, recuperação e condições especiais. Registre execução como executado, pendente, bloqueado ou não aplicável com motivo, além do resultado. Conte IDs únicos executados sobre o inventário atual, separadamente para áreas, transições e regimes. Não conte várias visitas como lugares diferentes. Atualize o denominador quando o mundo mudar.

Evite produto cartesiano horário × clima × população × missão × veículo × região. Escolha fronteiras, risco/custo e casos únicos, explicitando combinações descobertas. Rotas devem cruzar fronteiras; iniciar após o carregamento não as valida.

## Ficha de cenário

| Campo | Conteúdo verificável |
|---|---|
| ID/objetivo | Propriedade que pode falhar e motivo da seleção |
| Cadeia | Ação, produtor, evento, consumidores, resultado, limpeza |
| Ambiente | Revisão + alterações locais, motor/build, hardware, renderer, resolução, qualidade, VSync/limitador |
| Estado inicial | Save isolado, seed se disponível, missão, horário/clima, região e população |
| Procedimento | Rota/entradas reais; identificar atalhos e injeções de diagnóstico |
| Carga | Normal, caos plausível ou stress artificial; carga realmente observada |
| Expectativas | Estado correto, orçamento de frame/transição, limpeza e prazo |
| Amostra | Aquecimento, janela/ciclos finitos, timeout e término |
| Evidência | Frames brutos, eventos com tempo, contagens/memória, logs e vídeo/captura pertinentes |
| Resultado | Baseline/atual, julgamento por dimensão, lacunas e reprodução da falha |

Seed ajuda a reproduzir, mas não garante determinismo da física/GPU. Ao confirmar ruído, fixe antes o número finito de repetições e preserve todas as amostras, inclusive falhas.

## Percursos a adaptar ao inventário real

| Percurso | Interação a observar |
|---|---|
| Iniciar/continuar → explorar → missão → salvar/carregar isolado | Entrada produtiva, foco, progresso e efeitos únicos |
| Caminhar → embarcar → cruzar regiões → desembarcar → retornar | Ocupante, câmera, streaming, física, áudio e posse |
| Crime → testemunha → despacho → perseguição entre áreas | Propagação, navegação, orçamento conjunto e continuidade |
| Colisão → fogo/explosão → destroços → emergência → dispersão | Picos adiados, disputa de recursos, limpeza e população residual |
| Exterior → interior → interação/cancelamento → exterior | Armas, perseguição permitida, spawn, colisão, profundidade e câmera |
| Caos → morte/resgate ou prisão → retomada | Encerramento de estados, controle, inventário e entidades órfãs |
| Rota diurna/noturna com clima relevante → retorno | Luz/efeitos, primeira visita, cache e fluidez |
| Ciclos equivalentes de visita/caos/retorno | Tendência de memória, filas, timers, sons e entidades retidas |

## Registro e retomada

Mantenha plano/resultados/pendências num relatório compacto junto das evidências, em diretório exclusivo conforme a convenção do projeto. Não sobrescreva históricos. Preserve configuração, cenário, dados brutos, resumo e falhas. Vídeos longos/telemetria pesada somente quando necessários; registre custo da instrumentação e mantenha-o igual no comparativo.

Reutilize evidência se código/dependências, cenário e ambiente relevantes não mudaram. Edição de texto não invalida tudo; alteração de dependência compartilhada invalida fluxos afetados. Rodada interrompida mantém resultados válidos e indica próximo ID pendente.

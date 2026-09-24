# Geteco V2 — integração da migração completa

## Atmosfera regional — 22/09/2026

Perfis originais de porto/floresta/neve, tratamentos de cemitério e resort,
marcos de amanhecer/entardecer, névoa por profundidade e mistura geográfica de
chuva/neve integrados à iluminação 3D. A luz noturna deixou de ser rasante.
Relógio térmico e IDs de clima persistidos preservados. Contratos e integração
com Main: 45 checks aprovados. [Implementação, fotos, medições e limites](regional-atmosphere-migration.md).
Não encerra a migração geral; estilhaços de gelo no chão continuam pendentes.

Atualização: 21/09/2026. Trabalho em andamento. A cena principal agora inicia o mundo nativo de Harbor; `--slice` abre o primeiro trecho anterior e `--sandbox` conserva o laboratório urbano.

## Lote atual — implementação, validação adiada pelo usuário

Atualização de integração: as fachadas `urban_detail` agora substituem os registros urbanos no streaming nativo; o despacho foi conectado à sessão com exclusividade sobre o envio de equipes. Seis estações e a rodoviária foram conectadas às posições originais, sem duplicar ônibus ou passageiros da chegada. [Integração e limites](INTEGRATION_NATIVE_MODULES.md). A seção de revisão externa mais abaixo é histórica; os módulos receberam correções posteriores.

O controlador de cessão de passagem também foi conectado ao tráfego, incluindo restauração de rotas na troca de região, carregamento e resgate. A entrega de ultrapassagem das viaturas recebeu conexão explícita ao grafo de ruas; passagem em ruas estreitas e recuperação com tráfego contrário continuam limitadas e não validadas. A apresentação térmica ganhou reconciliação entre fontes originais do mapa e fallback, sem duplicar corpos durante streaming. [Contrato de calor](heat-streaming-integration.md). Histórico das tarefas de Claude e Antigravity: [prompts e áreas de trabalho](NEXT_EXTERNAL_TASKS.md).

Madeireira e vilarejo conectados ao streaming com modelos e posições originais: cabana, madeira empilhada, terreno, terminal e mobiliário. As cinco fachadas do catálogo permanecem únicas; as fogueiras/braseiros reconstruídos e construções sem fonte foram omitidos. Física, acessos, aparência e desempenho deste acréscimo permanecem sem validação.

As alterações abaixo foram escritas após a instrução de implementar agora e testar/medir depois. **Nenhum teste, execução no Godot, captura ou benchmark deste lote foi realizado.** Resultados históricos nas seções seguintes se referem à versão anterior e não aprovam estas alterações.

- Pintura visual: materiais de carroceria independentes por veículo, preservando vidro, pneus e acabamento; cores originais, garagens e veículos de missão usam o mesmo setter. Save comum passa a guardar cor, identidade e motorista, aceitando arquivos antigos sem esses campos. [Detalhes](vehicle-paint-migration.md).
- Corrida Cobra: largada de três segundos, falsa largada, percurso angular dirigido, quatro portões e retorno à pista, com estado de prova persistido. O objetivo exibe contagem/portão/tempo e a largada usa a interação existente com o carro alinhado.
- Retomada do motorista: carros comuns carregam a região do destino e procuram porta/casco livres antes de embarcar; hóspedes de garagem usam seu registro próprio. A corrida aguarda a restauração física. Bloqueios reais mantêm a restauração a pé, sem forçar passagem por sólidos.
- Água: som original, ondulações, gotas e seis pegadas úmidas após sair; respeito às áreas secas e ao avião, sem introduzir natação. [Detalhes](water-cold-migration.md).
- Clima da montanha: apresentação usa o mesmo relógio de 240 s persistido pelo frio, com os limiares originais de céu frio, neve leve, nevasca e granizo. Neve/granizo coexistem, intensidade altera vento e luz do dia; abrigos interrompem precipitação. Harbor mantém seu clima independente. Naquele lote, neblina e estilhaços de gelo no chão ainda não haviam sido portados; a névoa foi integrada em 22/09, conforme seção acima.

Antigravity e Claude continuam corrigindo seus diretórios. Não foram alterados nem ativados neste lote. A revisão externa anterior retrata a cópia daquele momento, não certifica nem reprova automaticamente as correções em andamento.

## Integrado e verificado

- Inicialização da cena principal, tarefa física de Maciota, entrada/saída, banco com Helena, inventário e roundtrip do estado: `tests/test_full_session.gd`, PASS.
- Garagem sem armas/ataques, arma guardada na entrada e restauração; Maciota e mecânico continuam sem rotinas de dano/morte.
- Economia/campanha: 158 verificações do módulo; seis missões Harbor com regras e diálogos originais. Isso não certifica as seis missões jogadas de ponta a ponta no mapa integrado.
- Combate, polícia, emergências, acessórios e onze roupas: 199 verificações do módulo. Folha de roupas renderizada em `evidence/outfits-v2.png`.
- Atividades e persistência do guincho: 65 verificações do módulo. Não equivalem a todas as rotas dirigidas no mapa real.
- 28 interiores adicionais, dois mapas, navio, ferro-velho e avião: testes físicos dirigidos aprovados pelo bloco de mundo. Somados à garagem, são 29 interiores distintos; fachadas compartilhadas não aumentam essa contagem.
- 49 modelos originais de veículos exportados em recursos independentes, com catálogo original preservado.

## Integrações posteriores à primeira medição

- Chegada: filme original de 28 quadros, desembarque, delegacia, telefonema e passeio físico de 201 m aprovados nos testes dirigidos. Conectados à sessão e ao save; cancelamento seguro do passeio e tratamento do Escape do filme integrados. Filme e passeio renderizados mediram 60 FPS; [evidências e limitações](arrival-migration.md).
- Serviços: hospital com coleta física e intervalo de 180 s, atendimento dos bombeiros, cinco policiais com diálogos originais e oficina automática com preço/tempo da fonte. Aproximação física e diálogos dos oito residentes, coleta hospitalar e intervalo aprovados na sessão integrada.
- Assaltos: banco e posto com ameaças, fechadura original, saque e fechamento temporário; 32 verificações do módulo. Viaturas em perseguição/despacho ficam no lote externo.
- Garagens: cinco carros, Ironback e hóspedes comuns persistidos. 37 verificações do módulo, 11 de transferências físicas e 26 de restauração do motorista aprovadas; duas garagens, câmera, casco completo, inventário e ausência de duplicação. Dois guardas originais integrados com 18 verificações físicas e comparação renderizada neutra aprovada; [evidências](garage-reward-migration.md). Prensa e pintura visual ainda pendentes.
- Salvamento: publicação, backup, recuperação de arquivo interrompido, rejeição de estado inválido, inventário e estado térmico aprovados em `test_full_save.gd`. O roundtrip compara valores numéricos, pois JSON pode restaurar inteiros como floats.
- Corrida: tempo decorrido e exposição fora da pista persistidos; pausa não consome tempo; limite de 100 s, corte interno e abandono por 4 s fora do anel. Campanha/economia: 158 verificações aprovadas. Regras angulares completas e contagem regressiva seguem identificadas como paridade pendente.
- Frio: cálculo original, roupas, sete fontes térmicas, abrigo, veículo, dano sem absorção pelo colete e persistência integrados. Resgate recupera temperatura para evitar ciclo imediato de mortes, uma melhoria deliberada do V2. Clima visual ainda precisa sincronização integral com o ciclo térmico original.
- Admissão física dos saves na montanha: fontes próximas instaladas e sincronizadas antes da consulta de casco/cápsula. Carros distantes aguardam terreno. Onze verificações isoladas e sete com Main real aprovadas; carro sobre braseiro recusado, pose livre aceita. Raio de 8 m cobre a frota atual e deve ser revisado para modelos maiores.
- Interiores: 31 acessos / 29 interiores; [56 capturas e quatro salas povoadas](interior-visual-review.md) inspecionadas. Não certificam toda rota nem performance de todas as salas.

Primeira entrega externa: `urban_detail` por Antigravity e `dispatch` por Claude. A primeira execução encontrou erros e gerou a [revisão histórica](EXTERNAL_REVIEW.md). Após correções dos autores, ambos foram conectados à cena principal, conforme o lote atual acima, ainda sem nova execução ou aprovação. Os trabalhos externos agora reservados são `mountain_detail` e `traffic_yield`.

## Medição integrada inicial

`full-native-before-isolated-population24`: Harbor nativo, 24 moradores, 9 veículos, Vulkan Mobile, RTX 4060 Laptop, 1280 × 720, MSAA 2×, VSync e limite de 60 FPS. Cinco segundos de aquecimento e 30 segundos medidos: 60,000 FPS; p95 17,307 ms; p99 18,437 ms; máximo 22,898 ms; nenhum quadro acima de 33,3 ms. Dante percorreu 52,55 m. Inventário de processos registrado junto da medição.

O primeiro trecho anterior mediu 60,003 FPS e p95 17,555 ms antes da integração. Como a geografia é diferente, esses valores não são uma comparação controlada de custo do mesmo cenário. A medição nativa acima é a referência para as próximas alterações nesse cenário.

## Medições finais deste lote

Mesma configuração de hardware/renderização e janela de 5 s de aquecimento + 30 s medidos. Arquivos em `evidence/`, exceto montanha em `tests/cold/evidence/`. FPS limitado a 60; estes ensaios não medem a capacidade máxima da GPU.

| Cenário / evidência | FPS médio | p95 / p99 (ms) | Máximo (ms) | Quadros >33,3 ms |
| --- | ---: | ---: | ---: | ---: |
| Maciota, `full-native-interior-final-isolated-population24` | 60,002 | 17,839 / 19,020 | 21,164 | 0 |
| Maciota, confirmação `full-native-interior-confirm-isolated-population24` | 60,001 | 17,583 / 18,082 | 18,713 | 0 |
| Rua 96 moradores / 9 veículos, `full-native-city-final-isolated-population96` | 59,905 | 18,725 / 20,209 | 88,027 | 1 |
| Rua 96, diagnóstico `full-native-city-diagnostic-isolated-population96` | 60,004 | 17,394 / 18,478 | 22,451 | 0 |
| Combate ativo, `full-native-combat-live-isolated-population24` | 60,025 | 18,841 / 20,935 | 46,265 | 5 |
| Combate, diagnóstico `full-native-combat-diagnostic-isolated-population24` | 60,032 | 17,497 / 18,241 | 36,369 | 1 |
| Garagem chefe sem guardas, `garage-guards-control` | 60,002 | 17,460 / 18,019 | <33,3 | 0 |
| Garagem chefe com dois guardas, `garage-guards-product` | 60,002 | 17,615 / 18,309 | <33,3 | 0 |

A variação inicial do p99 do Maciota não se confirmou na repetição dirigida. Oclusão nativa medida separadamente: 85,23% da silhueta visível atrás da mesa, aproximadamente 100% nos controles à frente/ao lado (`native-v2-depth.json`). Braços do elevador recolhidos fisicamente e visualmente liberam baia e passagem do escritório.

O pico de 88 ms na rua não se reproduziu; sua causa continua sem confirmação. Combate ainda teve engasgos pontuais nas duas amostras. Instrumentação não encontrou busca de caminho acima de 2 ms nem evento instrumentado correspondente ao pico de 36 ms: não atribuir o problema ao A*. Entrada inicial da garagem do chefe teve pausas de 1,36–1,45 s, também presentes no controle. Não declarar ausência de travadas pelo FPS médio.

A captura antiga `full-native-combat-isolated-population24.png` revelou Dante morto e painel de resgate aberto, portanto não aprova combate sustentado. As novas execuções mantêm saúde apenas na fixture e registram tiros/tempo ativo; a amostra `combat-live` disparou 138 tiros ao longo de 35 s ativos. Artefatos inválidos anteriores foram preservados. O ensaio neutro dos guardas não certifica combate deles.

Montanha após correções do terreno: 60,003 FPS, p95 17,516 ms, p99 18,091 ms, máximo 20,460 ms e zero quadros >33,3 ms; 685 verificações de terreno aprovadas. [Condições, controles e limites](water-cold-migration.md).

## Pendências que impedem declarar migração integral

- Concluir fluxos dos serviços/interiores integrados e suas validações; manter oclusão separada da física.
- Tráfego já usa ruas/interseções reais e veículo do jogador já tem persistência; falta validar todos os percursos e cargas no mapa real.
- Executar as seis missões completas e recuperar estados intermediários; conferência de inimigos, residentes, corrida, guincho e recompensas.
- Fechar paridade dos serviços ainda incompletos, drops/corpos dos guardas, prensa e sequência integral de recompensas.
- Concluir fachadas especiais, lagos/relevo e ambientação que não possuíam malha 3D original. Arte 2D reconstruída não é identidade visual automaticamente certificada.
- Medir interiores, direção, combate e novas regiões com os sistemas ativos. Um resultado em Harbor não aprova todos os cenários.
- Completar apresentação climática sincronizada, efeitos dos passos aquáticos e transporte entre regiões; [auditoria da fonte](water-cold-migration.md) distingue regras originais de funcionalidades novas.
- Diagnosticar avisos de recursos de áudio ainda observados em alguns encerramentos headless. Não foram suprimidos.

Campanhas e percursos antigos que não fazem parte do fluxo de produção ficam identificados como conteúdo legado. O catálogo preservado não significa que cada cena legada já foi encenada ou instalada no mundo atual.

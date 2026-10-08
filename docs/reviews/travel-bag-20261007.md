# Mala de viagem do Maciota — 07/10/2026

## Conteúdo entregue

Depois de vencer **Prova de rua** (`cobra_race`), Dante recebe uma mala reforçada do Maciota para levar suprimentos na busca por Vicente. A conversa de pista já existente ganhou uma fala antes da orientação sobre Ashbend, em PT/EN, com os mesmos perfis de voz do personagem. Não altera a ordem ou os objetivos das missões, a revelação do ato 2 nem o bloqueio da ponte norte.

A retirada é opcional no porta-malas físico da Monaliza. O botão do inventário sinaliza a oferta também para saves que já concluíram a corrida. Iniciar, perder, cancelar ou apenas ter uma missão marcada como pulada não libera a recompensa.

- Com mochila: **Trocar mochila por mala** mantém os itens nas mesmas células da grade ampliada, preserva os bolsos e deixa a mochila vazia em solo livre. A interface informa a troca e o bloqueio de armas longas.
- Sem bagagem: equipa a mala diretamente. Com outra mala: pede para soltar a atual, preservando seu conteúdo.
- Revalida proximidade, obstrução do porta-malas, carro parado, vida, transição e capacidade antes da publicação. Sem solo livre ou com limite de bagagens atingido, não altera itens nem registra retirada.
- Publica mala, mochila vazia e recibo `monaliza_travel_bag` juntos no inventário existente; a sessão usa seu save normal. Não cria um segundo sistema de inventário ou save.
- A mala usa os 24 espaços, visual, mão esquerda, drop/recuperação e restrições de combate existentes. Não pode ser recebida novamente depois de salvar/carregar ou soltá-la.

## Verificação funcional

Motor: Godot **4.7.2 .NET**, `Harbor.csproj` compilado antes da execução (zero erros/avisos). Nenhum slot pessoal usado; save em disco exclusivo em `user://travel_bag_tests/`.

| Verificação | Resultado |
|---|---|
| `tests/test_travel_bag.gd`, Main renderizada | 54 checks, zero falhas |
| `tests/test_inventory_grid.gd` | 36 checks, zero falhas |
| `tests/test_inventory_panel.gd` | 11 checks, zero falhas |
| `tests/test_campaign_economy.gd` | 169 checks, zero falhas |
| `tests/test_travel_bag_voice.gd` | 4 combinações legenda PT/EN × voz PT/EN, zero falhas |

O cenário integrado monta uma progressão válida até a corrida e uma Monaliza real; não refaz a corrida completa dirigindo. Exercita abrir porta-malas, botão da troca, transferência de suprimentos, distância com painel aberto, carro em movimento, morte, limite de 512 bagagens, solo obstruído, publicação única, visual aberto/fechado, save/load real em disco, drop e recuperação. Entra na garagem para conferir bloqueio de armas e ausência de rotinas de dano dos moradores.

As primeiras tentativas corrigiram fixtures: dois tipos de alimentos cabiam nos bolsos; a atualização visual de acesso ocorre a 4 Hz; coordenadas JSON requerem comparação aproximada; obstáculos baixos ofereciam uma superfície válida para apoiar a mochila. A execução final usa suprimentos efetivos na mochila e obstáculos altos. Esses diagnósticos não foram contados como testes aprovados. O teste de voz também recebeu anotação explícita de tipo após um erro de parsing inicial.

Evidência em `evidence/travel-bag-20261007/`: `flow-complete.log`, `flow/offer.png`, `flow/received.png`, `flow/carried.png`, logs das regressões e `voice-fixed.log`. Capturas revisadas: botão e consequências legíveis, mala equipada e mochila separada. A importação concluiu com avisos de recursos/RID e EditorSettings no encerramento do editor headless; não houve erro de script no fluxo aprovado.

## Vozes

Uma nova tomada por idioma, 24 kHz mono PCM16, usando `pt-BR-AntonioNeural` (perfil Maciota existente) e `en-US-ChristopherNeural`. Durações: 12,302 s e 11,830 s. Manifestos e aliases adicionados sem substituir as gravações anteriores. A geração é externa; o jogo usa os arquivos locais, sem serviço de voz em runtime. Verificados duração, ausência de silêncio/clipping e resolução de idioma/legenda no motor. Entonação e audição humana não foram certificadas.

## Desempenho e limites

Risco local: consulta curta de disponibilidade ao mostrar a ação/abrir o painel; troca aloca a apresentação de uma mala e uma mochila vazia. Reutiliza o streaming e as consultas físicas existentes, sem adicionar loop ou luz.

Baseline capturada antes da mudança em Main, Monaliza estacionada no exterior, dia, 1280 × 720, Vulkan Mobile, RTX 4060 Laptop, VSync 1 e limite efetivo 144 FPS das configurações locais. Editor permaneceu aberto. Cada cenário tem 8 s de aquecimento e pelo menos 30 s de amostras reais; progressão e veículo montados por fixture. Alvo provisório: 60 FPS / 16,67 ms; aumento maior que 5% em p95/p99 exigiria confirmação finita equivalente.

| Antes | FPS médio | p50 ms | p95 ms | p99 ms | máximo ms | >33,3 / >66,7 ms |
|---|---:|---:|---:|---:|---:|---:|
| Inventário fechado | 107,02 | 9,444 | 14,818 | 17,347 | 44,722 | 2 / 0 |
| Porta-malas aberto | 97,46 | 11,956 | 14,874 | 17,138 | 19,798 | 0 / 0 |

**Comparativo posterior pendente:** uma tentativa inicial foi bloqueada por execução concorrente; a espera limitada seguinte, de 90 segundos, também terminou com outras sessões usando o motor (`capture_coastal_lookout.gd` e `test_sewer_network_session.gd`). Os processos foram preservados e registrados em `evidence/travel-bag-20261007/comparison-processes.json`. A medição posterior não foi iniciada; não se considera performance aprovada apenas pelos números anteriores. A medição usa `tests/measure/measure_travel_bag.gd`, com variantes e diretórios separados. Trabalho concorrente fora deste escopo também limita a atribuição de qualquer diferença global.

Cobertura restrita ao desktop e à cadeia da recompensa; não certifica toda a campanha, todos os dispositivos, a qualidade artística das vozes ou todos os cenários de desempenho.

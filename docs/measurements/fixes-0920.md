# Correções de jogabilidade — 20/09/2026

Trabalho dividido entre três agentes e integração principal. Alterações locais anteriores preservadas.

| Pedido | Alteração |
| --- | --- |
| Duas sombras no jogador | Removida a malha circular; preservada a silhueta. |
| Sirenes altas de longe | Atenuação por distância mais forte, alcance limitado e volume no canal SFX. |
| Faca | Braço esquerdo baixo e relaxado, incluindo postura de ataque. |
| Granada e socos | Repouso com mãos baixas; granada usa braço direito e socos alternam o braço ativo. |
| Árvore diante do hospital | Corrigida a oclusão das copas desenhadas; troncos continuam sólidos. |
| Guindastes Northstar e porto sul | Estrutura elevada separada do piso/água, oclusão e bases físicas calibradas. |
| Sirenes em carros explodidos | Desligamento na explosão e proteção contra reativação em estados antigos. |
| Bombeiro e caminhão | Mangueira curva conectada, jato no bico da mão, proporções e nitidez melhoradas. |
| Bombeiros presos após atendimento | Retorno/embarque idempotente; porta alternativa bloqueada; colega morto não impede retorno. |
| Personagem estranho nos tubos | Iluminação pessoal preservada e proporção calibrada nos eixos da câmera. |
| Personagem estranho no carro da primeira missão | Escala pela altura completa e resolução temporária compartilhada, liberada ao sair. |
| Quadrado recarrega | Recarga válida recebe prioridade e não dispara interação simultânea; arma cheia permite interação. |
| Motoqueiros caídos | Sorteio entre retornar, fugir ou confrontar; paredes bloqueiam o ataque. |
| Fragmentos permanentes | Prazo de 90 s + fade de 5 s; descarrega fragmentos e modelo oculto, mesmo com atendimento pendente. |
| Conversas fora de contexto | Multidão depende de pessoas próximas, vivas e sem pânico; paredes bloqueiam; café/mercado têm alcance reduzido. |

## Evidência funcional e visual

- `test_remains_and_local_chatter.gd`: passou sem erros de script; ausência de multidão em beco vazio, pessoa isolada, distância, parede e pânico; fade, descarregamento e compatibilidade com registro persistente quando disponível.
- `test_fragment_models.gd`: passou; 3 padrões anatômicos, atlas, repouso físico, coleta e descarregamento.
- Poses/controle contextual, DualSense, braço livre e restrições de armas da garagem passaram.
- Continuidade dos tubos passou com Dante e cinco tipos de passageiros, quatro orientações e giros, circulação, portão e restauração.
- Profundidade do embarque Maciota: 8 checks renderizados passaram; iluminação e ciclo de vida da resolução temporária também passaram.
- Bombeiros: cooperação, atendimento, contorno de parede e retorno de ambos passaram. Teste de sirenes/reações de motoqueiros: 10 checks passaram; retorno à moto preservado.
- Hospital/guindastes: 22 checks renderizados passaram. Árvores: 30 checks renderizados passaram.
- Hospital integrado: 512 movimentos varridos; jogador/NPC, oclusão com controles positivos, entrada/saída, cura e suspensão passaram.
- Porto sul: 4.686 passos, 32 trabalhadores e carregamento/partida de três caminhões passaram.

Fotos do hospital e porto: `docs/measurements/hospital-cranes-0920/`.
Fotos de poses, transferências e bombeiros: `_codex_diag/fixes0920/`.

## Limites da validação

O teste geral legado `test_responder_routines.gd` apresentou falhas adicionais em polícia, ambulância e pedestre; os casos de bombeiros passaram. Não foi estabelecida a origem das demais falhas nesta tarefa.

O teste antigo `test_living_city_soundscape.gd` expirou durante a montagem do mundo; ele também contém expectativas antigas de quantidade de rádios e de conversa constante no terminal. A nova regra de conversas foi validada diretamente com física real em `test_remains_and_local_chatter.gd`.

`test_coroner_custody.gd` não é compatível com a configuração atual: pressupõe o autoload CoronerCare, ausente no projeto antes das alterações desta tarefa. Ele não foi reintroduzido.

Algumas execuções restritas não puderam ler novos recursos de áudio/gravar caches. Execuções com acesso ao ambiente e dados isolados carregaram os recursos corretamente. Fixtures integrados também reportaram recursos retidos ao encerrar; isso não é aprovação de ausência de vazamentos no jogo.

Durante a última rodada apareceu uma falha da edição paralela: `ProceduralAudio.gd` referenciava `AcousticBank.SKIDS`, ausente no banco gerado naquele instante. A integração recebeu uma correção pontual: consulta o banco novo quando disponível e usa `_generate_skid_stream` já existente como fallback enquanto ele estiver incompleto. O gerador e o banco não foram alterados. A rodada final de poses/recarga passou os 16 checks **sem erros de script/autoload**; somente o aviso de interpolação da câmera. Registro: `_codex_diag/fixes0920/poses-final.log`.

O teste existente `test_vehicle_skid_audio.gd` inicialmente falhou na distinção de timbre entre coupé e sedã durante a geração paralela. Uma inspeção posterior confirmou que o banco recebeu `SKIDS` e passou a fornecer `skid_sport.wav` e `skid_street.wav` com dados distintos; a compatibilidade utiliza automaticamente os sons novos. A rodada final passou sem erros. Registro: `_codex_diag/fixes0920/skid-compatibility.log`.

Após o usuário confirmar o Northstar, os três guindastes tiveram bases e duas longarinas verificadas em 30 pontos com água ligada/desligada: diferença RGB zero, metal não encoberto pela água. Verificação dirigida: 26 checks passaram; fotos `after-northstar-full0.png` a `full2.png` e `northstar-water-layer.log` na pasta de hospital/guindastes. Confirma o estado corrigido; não estabelece retrospectivamente a causa de cada ocorrência anterior.

Desempenho não aprovado: a tentativa inicial em Godot 4.7.2 Mobile, RTX 4060 Laptop, 1280×720, limite normal de 60 FPS ficou sem foco e foi rejeitada pelo próprio benchmark. Sem baseline comparável válido, não é possível certificar ausência de regressão. A tentativa final com `tests/measure_requested_fixes.gd` solicitou explicitamente foco, mas reteve somente 69,4% (mínimo exigido: 90%) e também foi rejeitada no aquecimento de 10 s, antes da janela estável de 30 s. Não foi repetida novamente.

Telemetria **não válida como benchmark** do último aquecimento: 422 frames, média 42,03 FPS, p50 17,094 ms, p95 48,978 ms, p99 59,025 ms, máximo 208,158 ms. Há picos durante construção de residentes; estes números não demonstram regressão nem aprovação das correções. Dados brutos: `_codex_diag/fixes0920/before/` e `_codex_diag/fixes0920/after/`. Continua necessária comparação focada antes/depois nos cenários afetados.

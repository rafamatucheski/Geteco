# Zoológico: animais, guarita e atendente — 10/10/2026

Pedido: melhorar anatomia/animação dos animais, acabamento da bilheteria e permitir morte do atendente com reposição somente após afastamento/retorno. Continuação das correções registradas em `session-lifecycle-20261010.md`. Trabalho dividido entre dois agentes e coordenação; preservadas alterações concorrentes.

## Implementação

- `ZooAnimal.gd` e `ZooAnimalAnatomy.gd`: malhas próprias com perfis anatômicos por espécie, ombros/quadris, focinhos, orelhas, cascos/patas e juba; membros superiores/inferiores articulados e caudas segmentadas. Recursos compartilhados entre exemplares. Filhotes mantidos.
- Marcha acompanha distância percorrida; girafas usam fase lateral e os demais alternância diagonal. Caminhada com aceleração/desaceleração, pausas, respiração e movimentos pequenos de cabeça/cauda. Percurso permanece dentro dos recintos.
- `animal_coat.gdshader`: coordenadas anatômicas estáveis para manchas/listras, preservando comportamento antigo por padrão.
- `ZooTicketBooth.gd` e `booth_surface.gdshader`: madeira pintada, postes de madeira, tampo de pedra e telhado metálico com materiais compartilhados. Cobertura mais alta e curta permite enxergar o caixa pela câmera do jogo. Balcão/tampo/postes/telhado possuem colisores; piso e corredor mantidos. Sem letreiros explicativos, novas luzes ou alterações globais de qualidade.
- `ZooAdmission.gd`: Actor mortal com física normal e integração combate/emergência. Atendimento exige caixa vivo e válido; ingressos pagos continuam válidos. Morto/removido permanece ausente perto do jogador; ao sair do raio de residência de 65 m do centro do zoo e retornar nasce um único atendente. Ausência pausa a fila e pagamentos dos visitantes.

## Validação executada

Godot 4.7.2 .NET; Harbor.csproj compilado com sucesso antes dos testes. Dados de teste isolados e `--no-save`.

| Validação | Resultado | Evidência em `evidence/zoo-refresh-20261010/` |
| --- | --- | --- |
| Anatomia, recursos, marcha e limites | 289 checks, zero falhas; 210 instâncias de desenho, 43.572 triângulos nos 12 animais | `animal-test-final.log` |
| Zoológico: recintos, colisão e streaming | MOUNTAIN_ZOO PASS | `mountain-zoo-final.log` |
| Caixa: disparo real, morte, vendas, remoção e reposição | 31 checks PASS | `cashier-test-window.log` |
| Main.tscn: chão real, atendimento, combate/emergência, afastamento/retorno, único caixa | 14 checks, zero falhas | `cashier-session.log` |
| Guarita renderizada: colisão separada de oclusão, jogador/NPC | 24 checks, zero falhas | `depth-test-stable.log`, `depth/results.json` |
| Visual antes/depois e amostras temporais | Capturas Mobile/Vulkan RTX 4060; modelos e materiais inspecionados | `before/`, `after/`, `capture-motion-final.log` |

Oclusão: frente/lado mantêm 100% da máscara visível; atrás o balcão oculta parte inferior, preservando 93% da região da cabeça do jogador e 100% da do NPC na fixture. Sweeps bloqueiam frente/trás/lado do balcão; corredor e spawn livres. Capturas naturais disponíveis em `depth/*-cashier-natural.png`.

O teste Main emitiu um aviso de uma instância ObjectDB retida ao encerrar; não houve falha funcional nem erro de script nessa execução. A origem desse aviso de encerramento não foi isolada. Logs de tentativas anteriores de fixtures foram preservados; os resultados acima apontam às execuções finais.

## Desempenho: pendente de aprovação

As capturas e testes headless não comprovam FPS. Não foi obtida comparação antes/depois de frame time da sessão real em condições exclusivas: vários motores, testes e benchmarks de outras sessões estavam ativos (`concurrent-processes.txt`). Nenhum processo alheio foi encerrado. O limite de geometria/recursos é uma verificação de orçamento, não substitui benchmark.

Falta medir as versões antes/depois no Main renderizado, com câmera/carga/clima/resolução iguais, chegada ao zoo, observação dos animais e retorno após morte do caixa. Não declarar desempenho aprovado ou atribuir melhoria de FPS com estes resultados. O snapshot anterior foi preservado em `before-source/`, sem restaurar/descartar arquivos de trabalho.

# Cobras: uniformes e patrulhas — 02/10/2026

## Escopo

Uniformes dos integrantes dos Cobras, população ambiente de veículos no porto e resposta a roubo/agressão. Não altera ruas, calçadas, semáforos ou o grafo. O mapa salvo conserva SHA256 `A349AC113D3E2D3A98870E444F65158E9C6204A7D354A7E7C44ECE2A9E53B1B5`.

Os modelos antigos mantinham rotações de braços/punhos da exportação e, no integrante mais robusto, uma camada verde sobre a camiseta. A apresentação agora normaliza a pose, reduz a largura excessiva desse torso, escurece as roupas e aplica o mesmo emblema no peito e nas costas. Modelos originais permanecem intactos.

O spawner normal substitui parte dos veículos civis por Cobra V8, sem um spawner paralelo. Há presença inicial garantida e limite de três patrulhas, duas pessoas por carro. As rotas normais usam `NativeTrafficRoutes` e a física/sinalização existentes. A perseguição usa `DispatchDriver`, sem teleporte. Carros recebem pintura escura e marca no capô; o prefixo da identidade permite reaplicar a marca a um veículo restaurado.

Dano com origem no jogador ou em seu carro ocupado provoca a patrulha e aliados já próximos. Roubo passa pelo fluxo normal de embarque: dois integrantes armados saem em lugares livres, em vez de um civil genérico. Não surgem reforços extras a cada agressão. A pé, usam combate e navegação dos Cobras. No carro, tiros fazem raycast e respeitam obstáculos. Perseguição termina após afastamento prolongado, morte do jogador ou transição para interior/região; o grafo de outra região não é aplicado ao carro antigo. Derrota da gangue bloqueia novas patrulhas.

## Evidências e cobertura

Ambiente: Godot 4.7.2 .NET, C# compilado com zero avisos/erros. Cena `Main.tscn`, 1280×720, renderer Mobile, RTX 4060 Laptop GPU, `--no-save --skip-arrival`. Saídas em `D:/geteco/artifacts/cobra-neighborhood-1002/` e imagens em `D:/geteco/artifacts/cobra-patrol-1002/`.

- `patrol-test-5.log`: uniformes nos três guardas, geração real de patrulhas, circulação sem agressividade gratuita, dano sem origem sem culpar jogador, roubo pela porta, dois ocupantes armados, transferência de controle, tiros a pé com linha de visão livre e encerramento após fuga aprovados. Verificação curta de movimento da segunda patrulha falhou; investigação separada necessária, sem apagar a falha.
- `patrol-collision.log`: colisão física de um carro realmente ocupado pelo jogador, dano no Cobra, provocação, tiros a partir do carro, identidade no snapshot e encerramento com morte do jogador aprovados. O cenário posiciona os veículos antes do impacto; colisão e resposta são produtivas, não chamadas diretas de dano.
- `patrol-pursuit.log`: caso dirigido com alvo sobre a rota real, em vez de deslocamento lateral não admitido. Carro percorreu 28,797 m, aproximou-se de 5,604 m, freou fisicamente e desembarcou os integrantes; fuga encerrou a reação. Dez observações de um segundo, zero falhas de assertions. O teste anterior de três segundos não isolava obstáculos/destino; sua falha permanece registrada. Esta execução encontrou erros transitórios de compilação em bancos/fogo de outras sessões durante o carregamento, portanto não certifica o projeto inteiro. Depois que essas dependências foram corrigidas, `compile-final.log` verificou o script sem erros e `uniform-final.log` registrou a captura limpa.
- `uniform-preview.png`: revisão visual isolada; não prova comportamento ou desempenho do jogo integrado.
- `patrol-before/frames.json`: baseline renderizado anterior às mudanças, 30,0026 s, 7.087 frames, 236,21 FPS, p50 3,653 ms, p95 7,773 ms, p99 9,474 ms, máximo 78,017 ms; dois frames acima de 33,3 ms e um acima de 66,7 ms. Entrada do bairro, três guardas, população informada de 22, VSync desligado, sem limitador.
- `patrol-after-2/frames.json`: estado final renderizado, 30,0035 s, 7.151 frames, 238,34 FPS, p50 3,623 ms, p95 7,293 ms, p99 8,442 ms, máximo 30,604 ms; zero frames acima de 33,3/66,7 ms. População informada de 27. A execução final terminou sem erros de script. **Comparação inconclusiva:** a população não é idêntica e `patrol-after-2-processes.json` registra uma captura de fogo de outra sessão durante a amostra (64 registros de processos concorrentes). A primeira tentativa final foi interrompida quando outra sessão iniciou; não produz métricas aproveitáveis. Os números atuais são diagnósticos, não aprovação de ausência de regressão.

As tentativas anteriores foram preservadas. Houve falha temporária de compilação em dependência da polícia editada por outra sessão; resolvida nessa sessão, sem sobrescrever seus arquivos. Um cenário inicial media tiros com o carro bloqueando a linha de visão; a fixture passou a escolher posição desobstruída. Outro deixava o jogador morrer antes do segundo cenário; a fixture usa vida maior, mantendo dano e IA ativos. A ausência eventual de patrulha no primeiro sorteio motivou presença inicial garantida no produto.

## Limites

Não é auditoria global do trânsito. Não cobre todos os cruzamentos, colisões em todas as velocidades nem perseguição entre regiões. Snapshot validado não equivale a roundtrip completo em disco. Funcionalidade aprovada nos cenários descritos; comparação de regressão de performance inconclusiva pelos fatores acima, sem aprovação global de desempenho. Uma comparação futura exige janela sem outras execuções, população equivalente e fontes estáveis. Nenhum processo de outra sessão foi encerrado.

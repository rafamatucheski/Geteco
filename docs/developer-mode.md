# Modo desenvolvedor

Abra **Pausa → Desenvolvedor · F10**, ou pressione **F10** durante a partida.
Ative o interruptor do painel. F10 volta ao jogo; Esc volta ao menu de pausa.
O painel usa o tema do jogo, tem rolagem e só é construído quando aberto.

Ferramentas disponíveis:

- Velocidade a pé: 1×, 2×, 5× e 10×, mantendo a colisão normal.
- Invulnerabilidade de Dante, sem alterar NPCs da história.
- Voo sem colisão: WASD, Espaço para subir, Ctrl para descer e Shift para
  acelerar 3×. Velocidade configurável de 5 a 100 m/s. F10 ou Esc abre o painel.
- Pousar restaura gravidade/colisão em chão livre. Se não houver ponto válido,
  o voo continua; use **Voltar ao início do voo** para voltar com segurança.
- Teletransporte por X/Y/Z ou pontos exteriores listados da região. Destinos
  sem suporte físico livre são recusados sem mover o jogador.
- Viagem a Harbor, montanha e deserto pelo fluxo normal de streaming. O deserto
  continua sujeito à conclusão da campanha. No voo, as bordas de região são
  respeitadas: pouse e use a seleção de destino para mudar de mapa.
- Criar civis de teste próximos, remover o último ou limpar todos. Máximo de
  20 simultâneos; são civis parados com corpo/modelo real, fora da população
  ambiente. A remoção atua apenas nos nós criados por esta ferramenta.
- Coordenadas, FPS, copiar posição e abrir a pasta dos logs por sessão.

Voo, criação de civis e teletransporte são ferramentas exteriores e exigem Dante
a pé, fora de transições e atividades que controlam seu corpo. Entradas de lojas
e garagem continuam usando as interações normais, com suas regras de armas.

Ao ativar, a sessão suspende salvamentos manuais e automáticos. Ao desativar,
restaura a política anterior de salvamento, velocidade, colisão e invulnerabilidade,
e remove os civis de teste. Isso não desfaz o progresso em memória: um salvamento
posterior pode registrar o estado atual da partida. O modo não persiste entre
sessões nem marca missões como concluídas para liberar destinos.

As ações são emitidas com prefixo `DEVELOPER` e capturadas no log da sessão.
O controlador não executa física por quadro enquanto o voo está desligado; a UI
atualiza seus números a cada 0,3 s somente enquanto aberta.

## Validação

`tests/test_developer_mode.gd` executa na cena Main real com Godot 4.7.2 .NET e
`--no-save --skip-arrival --benchmark --population=24`. Cobre abertura por F10,
pausa/retomada, bloqueio de save, velocidade real, invulnerabilidade, voo através
de um sólido e recuperação, teletransporte local e Harbor → montanha → Harbor,
destino bloqueado por campanha, criação/remoção e restauração dos estados.
Screenshot e resultados ficam em `evidence/developer-mode-20261010/`.

A comparação renderizada usa `tests/measure/measure_developer_mode.gd` e amostras
de 30 s após aquecimento. `--dev-flight` mede voo estacionário no mesmo local;
sem a opção, mede o custo com o painel fechado. Meta provisória: 60 FPS /
16,67 ms, com aumento >5% em p95/p99 exigindo investigação. Não certifica todos
os mapas, combinações de atividades ou streaming em voo na velocidade máxima.

Resultado em 10/10/2026: 38 verificações funcionais aprovadas, sem erros na
rodada `functional-verified.log`. A colisão após o voo foi exercitada longe da
entrada automática do Maciota, que havia invalidado a primeira fixture.
Painel inspecionado em `panel.png`.

Com o painel fechado, antes/depois: 104,80/109,65 FPS; p95 13,955/13,919 ms;
p99 19,952/18,368 ms; máximo 30,673/59,643 ms. RTX 4060 Laptop, Mobile,
1920×1080, VSync ligado, limite 144 FPS. População/tráfego variaram de 23/45
para 24/47; não é uma comparação determinística nem certificação global.
A amostra adicional de performance em voo foi encerrada a pedido do usuário,
que fará a validação restante. Não há aprovação de performance desse cenário.

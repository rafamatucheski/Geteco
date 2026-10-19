# Revisão da HUD da arrancada — 19/10/2026

Base: HUD compacta da Noite de Acerto que estava **sem commit** na árvore (sessão de 18/10).
As mudanças desta revisão estão em `hud-improvements.patch`, separadas daquele trabalho.

## O que a captura no jogo real mostrou (3440×1440, inglês, Digo, noite)

- Contagem da largada: três pontos de 6 px no topo, longe do conta-giros onde o olhar está.
- Luzes de troca (5) sem sentido na preparação: apagadas em marcha lenta, todas acesas na faixa.
- Veredito da troca anterior (1,2 s) escondia "TROQUE AGORA" se a faixa seguinte chegasse antes.
- Veredito sempre na cor do giro, não da qualidade: "ADIANTOU" saía branco/âmbar.
- Carro sem nitro mostrava barra vazia e a tecla SHIFT acesa.
- Rival só em texto (+1,5 m); a barra de distância mostrava apenas Dante.
- Em 21:9 os painéis iam para as bordas da tela.
- Inglês com sobras em português: ACELERAR, ESPAÇO, SEGURE O GIRO, TROCANDO, ÚLTIMA MARCHA,
  PREPARE A TROCA, BOA LARGADA, objetivos dos desafios, VER PASSAGEM, "0.819 s À FRENTE",
  "4 boas trocas", dicas da telemetria.
- Resultado: unidade "s" numa coluna fixa, ~70 px depois do tempo.

## O que mudou

- Casulo do conta-giros vira semáforo na preparação (1–3 âmbar) e fica verde 0,6 s após largar.
- Título do evento fixo (não desce 24 px na preparação).
- Prioridade: TROQUE AGORA / NO LIMITE > veredito (âmbar bom, coral ruim) > demais avisos.
- "SEM NITRO" quando `spec.nitro_seconds` é 0; barra de nitro de 3 para 4 px.
- Ponto coral do rival na barra de distância.
- HUD contida numa faixa 16:9 centrada em telas mais largas que 16:9.
- `data/localization/drag-hud.en.json` (arquivo novo) e duas montagens no resultado traduzidas
  antes de juntar o número.

## Verificação

- `tests/test_drag_hud_presentation.gd`: 151 checagens, 0 falhas (lógica de instrução e semáforo,
  nitro, textos em inglês incluindo os 12 objetivos de desafio reais, pt_BR inalterado).
- `tests/capture/capture_drag_hud_states.gd`: 42 capturas antes (cópia da HUD de partida) e 42 depois,
  7 estados × en/pt × 1280×720, 960×540, 1720×720. Pranchas `compare-*.png`. O arquivo de tradução
  novo vale para as duas, então o "antes" isolado já sai traduzido; o antes real está em `before/`.
- `tests/test_desert_drag_runtime.gd --drive --capture-out`: antes e depois, 80/81 nos dois. A falha
  "both real headlight sources remain enabled throughout race" já existia antes desta mudança.

## O que não foi verificado

- Desempenho: nada medido em export release. A HUD desenha um retângulo (casulo) e um círculo
  (rival) a mais por quadro, e o semáforo troca 5 círculos por 3; sem medição que confirme o custo.
- Estilos bar/street/pro/champion: só herdam a tradução de ESPAÇO e a faixa 16:9; não foram capturados.
- Controle físico, movimento contínuo e legibilidade em 960×540 numa tela real.
- Textos compostos da Noite de Acerto e dos desafios fora da HUD de corrida (painéis, notas do
  resultado como "%d DE 3", "R$ %d recebidos") continuam sem inglês.

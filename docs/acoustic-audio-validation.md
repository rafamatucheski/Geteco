# Evidências — áudio acústico, 20/09/2026

## Resultado funcional

- Banco: 227 amostras de jogo, mais uma prévia de disparos. Pico máximo medido
  0,78 (PCM normalizado); nenhum sample individual satura. Isso não é prova de
  ausência de clipping na soma de uma cena arbitrária.
- 16 famílias de combustão, sete faixas cada, no máximo duas tocando por motor.
- Sedã com a marcha adicional: trocas em 0,33 / 0,77 / 1,33 / 2,22 / 3,35 s;
  97% da máxima em 5,23 s. O trecho final é mais longo; não é um simulador
  automotivo calibrado.
- 70 arquivos de recarga com SHA-256 idêntico ao início da sessão.
- Passaram: banco acústico, personalidade dos veículos, cache/preparação,
  camadas em carros reais, combate, recarga e restrições de armas da garagem.
- Passaram também os testes de derrapagem e saída/save nos dois controladores:
  saída aceita desliga todas as vozes no início, a animação não retoma o motor,
  carro vazio permanece silencioso e snapshot a pé não inclui veículo ocupado.
- Emendas dos loops na saída real do mixer: `test_engine_loop_seam.gd` terminou
  com `failures=0 inconclusive=0`, sem picos acima do critério do teste.
- Passaram também VQ35/Maciota e a regressão de transmissão/nome do veículo,
  após ampliar o banco para sete faixas e acrescentar a relação final. A marcha
  adicional funciona como sobremarcha a 87% do corte na máxima de rua.

As falhas intermediárias foram corrigidas: enum de importação de loop diferente
do enum de AudioStreamWAV; seleção do pneu esportivo usando catálogo sem fallback;
retorno antecipado da física durante a saída conservando o último som do motor.
Na primeira gravação mixada ocorreram seis amostras saturadas por ganho adicional
do catálogo de armas; os efeitos receberam margem de pico e a gravação seguinte
teve zero amostras saturadas (pico 0,8914, 43,264 s).

## Comparativo renderizado de motores

HarborGame real, Godot 4.7.2, Mobile/Vulkan, NVIDIA RTX 4060 Laptop, 1920×1080,
VSync desativado, sem limite de FPS, semente 20260920, mesma entrada e ação
`move_up` por 30 s após carregar e aguardar 5 s para o embarque. A versão anterior
do controlador foi reconstruída desfazendo somente as edições desta tarefa;
o arquivo final foi preservado e restaurado com verificação de concorrência.
O banco de combate permaneceu igual nas duas execuções, portanto este comparativo
isola a mudança do controlador de motores, não a inicialização de todo o áudio.

| Métrica | Antes | Depois |
|---|---:|---:|
| Frames / duração | 1502 / 29,99 s | 1554 / 30,00 s |
| FPS médio | 50,08 | 51,80 |
| Frame p50 | 18,263 ms | 17,882 ms |
| Frame p95 | 28,816 ms | 29,055 ms |
| Frame p99 | 81,954 ms | 72,623 ms |
| Pior frame | 136,552 ms | 123,066 ms |
| Frames >33,3 ms | 37 | 33 |
| Frames >66,7 ms | 18 | 19 |
| Distância | 1712,9 px | 1702,5 px |

p95 +0,83%, p99 -11,39%: não houve sinal acima da tolerância provisória de 5%
nesta amostra. Porém o alvo absoluto de 60 FPS / 16,67 ms não foi cumprido em
nenhuma versão. **Performance geral pendente**, sem atribuir o déficit ao áudio.
Não foram separados CPU/GPU/espera. A alteração da tração muda ligeiramente o
percurso; clima/população/eventos e streaming não são perfeitamente determinísticos.
Os logs incluem construção de personagens lenta e erros de limpeza de recursos
e de objetos liberados ao encerrar a cena, também presentes no baseline.

Este par foi medido antes dos ajustes de derrapagem/saída e da marcha adicional. Esses ajustes
foram validados funcionalmente, sem comparativo próprio de frame time. Não há
certificação da rota noturna completa, combate intenso ou configuração normal
com VSync. Arquivos brutos: `_codex_diag/audio-redesign/before.json`, `after.json`,
`paired-before.log`, `paired-after.log`.

## Escuta

A prévia de saída SFX do Godot fica em
`_codex_diag/audio-redesign/driving-combat.wav`: sedã, esportivo, disparos,
impactos e derrapagem. Amostras foram geradas com referências acústicas, não
copiadas de gravações. A identidade e qualidade percebida não são certificadas
pelos testes; requerem escuta humana. Veja referências e estrutura em
[acoustic-audio.md](acoustic-audio.md).

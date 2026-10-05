# Introdução: chegada de barco — 03/10/2026

Registro da primeira versão diurna. A revisão posterior solicitada pelo usuário,
com correções de braço/celular, cenário, figurantes e noite chuvosa, está em
[Revisão noturna](opening-ferry-night-20261003.md).

Substituição da montagem de fotografias por filme nativo de 73 s, 1080p/30 fps,
com 13 planos em movimento, onze falas PT-BR e legendas PT/EN. Dante começa
tranquilo a bordo, conversa sobre o irmão, recorda a chamada anônima sobre
Vicente e chega ao terminal que dá início ao desembarque jogável.

- Prévia: `D:/geteco/artifacts/opening-ferry-20261003/Harbor-nova-intro-PT-BR.mp4`.
- Produção, roteiro e reprodução: [README](../../cutscenes/opening/ferry/production/README.md).
- Integração: `runtime/OpeningPresentation.gd` e `cutscenes/opening/ferry/FerryFilm.gd`.
- Arquivo de jogo: `arrival.ogv`, 93.745.066 bytes; voz embutida no vídeo,
  música e ambiente em streams separados. O relógio do vídeo dirige as legendas.
- `timing.json` incluído nos dois presets de exportação. APK/build de distribuição
  não produzido nesta tarefa.

## Validação funcional e visual

Godot 4.7.2 .NET, C# compilado com `dotnet build Harbor.csproj --no-restore`.

1. `tests/test_opening.gd`: 15 verificações passaram, incluindo **EOF real** do
   decoder após a duração inteira, pausa/retomada de vídeo e stems, pulo precoce,
   emissão única, troca de legenda por locale e checkpoint serializado.
2. Após otimizar a renderização oculta, o mesmo teste com
   `--skip-full-playback` passou em 18 verificações, incluindo restituição do
   estado prévio de `Viewport.disable_3d` ao pular e remover a apresentação.
   Essa execução curta não substitui a duração inteira: o final natural também
   é exercitado pelo benchmark integrado `--natural-end`.
3. `tests/test_arrival_flow.gd`: passou o desembarque físico até `police_visit`,
   controles liberados, entrada/saída da polícia, cinco falas da polícia,
   quatro falas do telefone e checkpoint para o encontro no pátio.
4. Capturas dos planos e quadros extraídos do MP4 conferidos. Foram corrigidos
   o caminho de aproximação para passar em água livre, a orientação dos
   passageiros sentados e faces internas/ombros dos modelos civis nas câmeras
   próximas. Overrides de material são locais à direção de captura.
5. ASR local conferiu as onze falas e levou a duas novas tomadas. Picos do PCM:
   voz −6,38 dBFS; ambiente −19,48; música −28,65. Não há clipping na mixagem.
   Não foi feita avaliação auditiva humana; ASR não certifica emoção ou timbre.
6. A sonda anterior `tests/measure/arrival_measure.gd` deixou de tentar buscar
   quadros de ônibus da montagem substituída. Sua análise de sintaxe passou;
   o cenário de tour dessa sonda não foi executado, pois não foi alterado.

Os rigs não têm atuação labial fonética nesta sequência. O filme usa condições
fixas de luz/clima; o gameplay retoma suas próprias condições. Não foram
alteradas colisões do terminal, rotinas ambientais ou regras da campanha.
A revisão não certifica toda a iluminação nem todos os trajetos do porto.

Evidências locais: `evidence/opening-lifecycle.log`,
`opening-lifecycle-render-gate.log`, `opening-arrival-flow.log`,
`opening-movie-1080.log`, capturas `opening-*-film.png` e `opening-*-quay.png`.

## Desempenho

Mesmo Main integrado, novo jogo isolado sem salvar, Godot .NET 4.7.2, renderer
Mobile, RTX 4060 Laptop, 1920×1080, VSync desligado e limite de FPS 0 conforme
configuração existente. Sem outro benchmark/render em paralelo. Cinco segundos
de aquecimento separados e trinta segundos de intervalos reais por amostra.
O mundo está pausado pela apresentação; os inventários registrados nesse ponto
são zero pedestres ativos e um carro. Isso não mede o custo de dirigir pela cidade.

Meta provisória: 16,67 ms; aumento de p95/p99 acima de 5% exige investigação.
A taxa do filme é 30 fps; FPS abaixo é frequência de apresentação do runtime.

| Versão | FPS médio | p50 ms | p95 ms | p99 ms | Máximo ms | >33,3 ms |
|---|---:|---:|---:|---:|---:|---:|
| Fotos anteriores | 616,46 | 1,607 | 1,742 | 1,999 | 4,178 | 0 |
| Vídeo, ainda renderizando a cidade oculta | 513,97 | 1,565 | 3,972 | 8,066 | 18,965 | 0 |
| Vídeo com render oculto suspenso | 2156,77 | 0,387 | 0,516 | 2,614 | 9,119 | 0 |
| Confirmação finita da versão otimizada | 2185,17 | 0,388 | 0,513 | 2,508 | 8,024 | 0 |
| Versão final, com diagnóstico da transição ativo | 2149,30 | 0,391 | 0,512 | 2,571 | 10,276 | 0 |

A primeira medição identificou custo adicional de reprodução, sem separar
decoder/CPU/GPU. A apresentação passou a suspender o render 3D escondido atrás
do filme opaco, com restauração do estado anterior no fim/pulo/remoção.
As duas amostras finais confirmam redução de p50/p95 e máximo abaixo de
16,67 ms durante a reprodução medida. Há custo residual em p99: 2,508–2,614 ms
contra 1,999 ms das fotos. Portanto **não está aprovada ausência de regressão
em todos os percentis**, apesar da folga para a meta absoluta nessa GPU.
Não extrapolar esses números para Android ou hardware diferente.

O final natural devolveu imagem 3D e controles ao jogador no cais; a confirmação
também passou o pulo dentro do Main integrado. A comparação de percentis acima
se refere à reprodução do filme, não à carga do cenário depois dele.

### Encerramento e retomada física

O diagnóstico `opening-handoff-trace.json` reproduziu um intervalo de
**1.788,758 ms ainda com a apresentação ativa e a árvore pausada**. A primeira
tentativa de logger não reconheceu o Main criado pelo teste e só gerou cabeçalho;
isso não foi contado como evidência de ausência de travamentos. A sonda passou
a registrar explicitamente intervalos da transição e, no modo diagnóstico,
a atribuir `current_scene` para o logger existente reconhecer o mundo.

O encerramento foi ajustado para o relógio real do vídeo, 150 ms antes do EOF,
dentro do fade preto de 600 ms já presente no arquivo e após todas as falas.
O player pausa nesse ponto e conclui o fade da apresentação; o sinal nativo de
fim permanece como fallback. A hipótese investigada era o rebobinamento de
Theora no EOF; não houve perfil interno do decoder para identificar a função C++.

Na confirmação dirigida `opening-handoff-final.json`, nenhum intervalo acima
de 33,3 ms ocorreu enquanto o filme permaneceu ativo. O pico de 1,8 s não se
repetiu. Os seis intervalos acima de 33,3 ms ocorreram **depois**, em `disembark`,
com máximo de **89,35 ms**. Render 3D, controles e posição no cais foram
restaurados. Esses picos de retomada permanecem registrados, sem certificação
de ausência de engasgos em todo o gameplay. A captura da base anterior já
mostrava 90,5 ms no contador nessa transição, mas não havia amostras brutas
equivalentes; não atribuir causalidade apenas por essa captura.

As amostras completas e os tempos de aquecimento ficam em
`evidence/opening-before.json`, `opening-after.json` e
`opening-after-render-gate.json` e `opening-after-confirm.json`. As configurações de gameplay e os saves do
usuário não foram sobrescritos.

Logs de diagnóstico: `evidence/opening-handoff-final.log` e
`evidence/stall-logs/stalls-20261003-132050.log`. A versão final não deixa o
logger ligado por conta própria; as variáveis foram restritas aos processos de teste.

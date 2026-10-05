# Revisão da intro: noite e chuva — 03/10/2026

Correção dos defeitos apontados na primeira versão do filme. Duração de 73 s,
1080p/30 fps, mesmas onze falas PT-BR e legendas PT/EN. Sincronização labial
ficou fora do escopo, conforme pedido.

Prévia: `D:/geteco/artifacts/opening-ferry-night-20261003/Harbor-intro-noite-chuva-PT-BR.mp4`.
Arquivo do jogo: Theora de **73.162.167 bytes**; prévia MP4 de **69.333.597 bytes**.
Decodificação completa confirmou 2.190 frames, 30 fps, 73 s e 1920×1080.

## Alterações

- `FerryPhonePose.gd`: pose própria de ombro, antebraço e punho. O aparelho
  acompanha o osso da mão, fora do centro da palma, com dedos curvados e a
  tela voltada para Dante. A pose de combate não dirige mais esse gesto.
- `FerryNightSet.gd`: extensão contínua de água de 1.024 m, independente do
  raio de streaming; o plano original por trechos é ocultado somente na captura.
  Os enquadramentos já não mostram os recortes de água da primeira versão.
- A simulação de fundo inteira fica suspensa durante a gravação. Figuração
  recebe poses dirigidas; os gerenciadores de trânsito também param, evitando
  que continuem movendo corpos suspensos. Nenhuma rota do jogo foi reescrita.
- Passageiro com malha e rig do Dante de produção, aparência mais velha,
  barba grisalha, óculos com armação, gorro com punhos de malha, casaco ocre,
  cachecol e luvas. Ajustes de material e acessórios são locais ao personagem.
- Noite, chuva, luminária no convés, preenchimento frio e materiais molhados
  locais. A mixagem troca as gaivotas pela cama de chuva e gotas do projeto.
- `Arrival.gd`: novos jogos conservam a noite chuvosa ao desembarcar. Retomadas
  preservam horário e clima existentes. O relógio segue o ciclo normal depois.

O cenário dirigido só existe na produção do vídeo; o runtime continua reproduzindo
Theora. Colisões e acessos do barco e do terminal não foram redesenhados.

## Evidências visuais e temporais

Godot 4.7.2 .NET, renderer Mobile, captura nativa 1920×1080. Foram conferidos
os planos abertos, closes e as poses durante subida, sustentação e descida do
celular. Folhas temporais e imagens estão na pasta da prévia.

Nos 2.190 frames da gravação final, a checagem contínua registrou:

- maior variação de osso do braço/punho: **3,239° por frame**;
- maior deslocamento do celular relativo ao barco: **2,163 cm por frame**;
- deslocamento dos **47 corpos de fundo** monitorados: **zero**.

Uma gravação intermediária falhou porque pausar só os corpos deixava os
gerenciadores de trânsito ativos. Foi descartada e a suspensão passou a abranger
o mundo de fundo, mantendo a direção e a chuva ativas. A gravação final concluiu
sem esses erros e sem falhas nas verificações de continuidade.

A análise temporal também detectou gotas perto da lente produzindo faixas
claras de um frame. `ferry_rain.gdshader` faz cada gota desaparecer suavemente
entre 1,8 m e 0,8 m da câmera. A maior mudança de brilho médio entre frames,
excluindo cortes e fades, caiu de **9,590 para 0,327** na escala 0–255 do render
nativo; p99 final **0,210**. Os frames do pico anterior foram conferidos para
identificar a gota como causa. Essa medida complementa a inspeção e não certifica
toda a iluminação do jogo.

Evidências: `render.json`, `temporal_metrics.json`, `temporal-*.jpg`,
`pose-*.png` e `evidence/opening-night-rain-final.log`.

## Fluxo e som

`tests/test_opening.gd --skip-full-playback` passou as **18 verificações**
renderizadas com o arquivo final: relógio do decoder, stems, pausa/retomada,
pulo, legendas, emissão única e restituição de pausa/renderização.

`tests/test_arrival_flow.gd` passou em execução headless: nova noite chuvosa,
estado persistente do clima, pulo, desembarque físico, controle devolvido,
preservação do clima ao retomar, polícia, saída e ligação até o encontro no pátio.
O teste antigo seguia depois de quatro segundos mesmo se o carregamento não
tivesse terminado. A primeira tentativa detectou isso; agora aguarda a condição
real de prontidão com limite de 30 s e falha explícita se ela não chegar.

A mixagem mantém voz −6,38 dBFS, ambiente −18,59 e música −28,65, sem clipping.
As tomadas de voz não mudaram nesta revisão. A verificação automática de texto
anterior continua válida; não foi feita avaliação auditiva humana.

Logs funcionais: `evidence/opening-night-lifecycle.log` e
`evidence/opening-night-arrival-flow-ready.log`. Importação de áudio concluída;
o editor headless emitiu o aviso já observado de `EditorSettings`/Android ao
encerrar, sem erro de importação dos recursos. `git diff --check` passou nos
arquivos rastreados desta tarefa. C# foi compilado antes das capturas.

Produção e comandos: [README](../../cutscenes/opening/ferry/production/README.md).
Medições da versão anterior: [registro diurno](opening-ferry-20261003.md).

## Reprodução integrada e desempenho

O Main real reproduziu até o final natural e entregou `police_visit`, personagem
visível, controles liberados, árvore despausada e render 3D restaurado. Clima no
cais: chuva, horário 0,9411. A imagem do cais confirma a continuidade noturna.

Comparação em Godot .NET 4.7.2, Mobile, RTX 4060 Laptop, 1920×1080, VSync
desligado e limite de FPS 0, com cinco segundos de aquecimento e trinta medidos.
A sonda agora fixa resolução/FPS/VSync apenas no processo de teste, para que
mudanças posteriores nas preferências locais não invalidem a comparação.
Não houve encode, captura ou outro benchmark em paralelo nessa medição.

| Reprodução | p50 ms | p95 ms | p99 ms | Máximo ms | >33,3 ms |
|---|---:|---:|---:|---:|---:|
| Filme diurno anterior, confirmação | 0,388 | 0,513 | 2,508 | 8,024 | 0 |
| Filme noturno, final natural | 0,386 | 0,482 | 2,450 | 102,023 | 1 |
| Filme noturno, confirmação sem limite | 0,390 | 0,519 | 2,631 | 834,031 | 2 |
| Filme noturno, diagnóstico CPU/GPU/foco | 0,391 | 0,491 | 2,420 | 118,089 | 1 |
| Filme noturno, limite normal de 60 FPS | 16,666 | 16,724 | 16,979 | 17,528 | 0 |

Os aumentos de p95/p99 ficaram abaixo de 5% em relação à referência diurna.
A primeira amostra teve um pico de 102,023 ms por volta de 28,6 s. A confirmação
sem limite registrou 834,031 ms em 10,2 s e 123,004 ms em 15,7 s, portanto o
mesmo trecho não explica os picos. Uma amostra diagnóstica registrou 118,089 ms
em 23,6 s, janela em foco, sem troca de foco; monitores nesse registro: processo
6,990 ms, física 0,066 ms, render CPU 0,069 ms e GPU 0,102 ms. Esses monitores
não explicam toda a espera e não provam sua causa.

A hipótese seguinte foi saturação/espera específica da medição sem limite.
Na execução com o limite padrão do produto, **60 FPS**, foram 1.801 frames em
30 s, média **60,002 FPS**, máximo **17,528 ms** e **nenhum intervalo acima de
33,3 ms** durante o filme. Isso comprova o comportamento dessa amostra; não
certifica ausência de engasgos em todas as configurações. Os picos sem limite
continuam documentados e não foram descartados nem atribuídos ao sistema sem
evidência. A regressão histórica de p99 contra a antiga montagem de fotos,
registrada na revisão diurna, também não está apagada por esta comparação.

Na execução com final natural, o maior intervalo da retomada física
foi 93,710 ms em `disembark`, com apresentação já encerrada; a referência diurna
registrara 89,350 ms nessa fase. No pulo com limite de 60 FPS, a retomada atingiu
135,857 ms; controles, render e clima também foram restaurados. Portanto a
transição ao cais ainda tem engasgos breves e não recebeu certificação de
fluidez completa. A medição do filme pausado não equivale ao FPS
de circular pela cidade, e a frequência de apresentação do runtime não altera
os 30 fps do conteúdo.

Evidência integrada: `evidence/opening-night-final.json`, `opening-night-confirm.json`,
`opening-night-diagnostic.json`, `opening-night-normal.json`,
`opening-night-final-film.png` e `opening-night-final-quay.png`.

# Digo Meshy e Amarok — 03/10/2026

## Entrega

O GLB enviado foi preservado em `assets/digo/digo.glb`, com 4.207 triângulos,
74 ossos e as animações originais. O NPC usa pose relaxada e respiração de baixa
amplitude, suspensa fora da tela e sem atualização do esqueleto além de 35 m.
Texturas usam compressão de VRAM e mipmaps: cor 2048, normal/roughness 1024.
A máscara das três camisetas é calculada na importação, sem leitura de imagem
durante gameplay. A rotação usa o dia persistido do mundo.

A Amarok branca 2014 Stage 2 mantém o Gol como segundo registro independente.
Modelo em batches compartilhados, rodas e faróis independentes; xenon reutiliza
o perfil e equipamento do jogo. Dois WAVs originais somam aproximadamente
120 KB e são carregados como recursos, com emissão limitada por motor e distância.

## Validação funcional

Godot 4.7.2 .NET, `dotnet build Harbor.csproj --no-restore`: zero erros/avisos.
Progresso 18/18, aula/roupas 15/15, Amarok/áudio/equipamento 16/16,
sessão real 30/30. A sessão cobre colisão do personagem, apoio dos veículos,
aula e pausa, save/load em arquivo isolado, adoção e retorno sem duplicação.
As três roupas foram renderizadas e inspecionadas nas capturas `meshy-shirt-2`,
`meshy-shirt-3` e `meshy-shirt-4` em `evidence/digo/`.

O teste de sessão registra 16 objetos/recursos ao encerrar; esperar o flush
não eliminou o aviso. Origem não demonstrada e pendência descrita em `docs/digo.md`.
O benchmark seguinte encerrou sem esses avisos.

## Desempenho no pátio

RTX 4060 Laptop, Vulkan Mobile, 1920×1080, VSync desligado e sem limite de FPS,
câmera fixa do gameplay, dia claro, aquecimento separado e amostras de 30 s.
Meta provisória: 60 FPS / 16,67 ms; aumento >5% em p95/p99 exigiria confirmação.

| Métrica | Antes: NPC procedural + Gol | Depois: Meshy + Gol + Amarok |
|---|---:|---:|
| Quadros | 6495 | 8085 |
| FPS médio | 216,48 | 269,50 |
| p50 (ms) | 3,736 | 3,071 |
| p95 (ms) | 8,293 | 6,766 |
| p99 (ms) | 9,758 | 7,549 |
| Máximo (ms) | 14,584 | 12,463 |
| Quadros >33,3 / >66,7 ms | 0 / 0 | 0 / 0 |
| População no fim | 32 | 34 |

Evidências: `evidence/digo/meshy-before.json` e `meshy-amarok-after.json`.
Resultado abaixo do orçamento nesse cenário. Comparação **diagnóstica**:
editor/jogo do usuário permaneceram abertos, população variou e há trabalho
concorrente no projeto. Não atribuir a melhora inteira à troca do personagem
nem certificar ausência universal de regressão. Não mede condução, chuva ou noite.

## Iluminação

A primeira sequência noturna demonstrou o comportamento do carro vazio:
faróis apagados, conforme contrato do equipamento. O cenário foi corrigido
para entrar pela transição real do motorista antes de ligar os faróis.
A captura temporal separada registra cada frame renderizado e timestamps;
seu custo de leitura da GPU/compactação não integra o benchmark acima.

Resultado com motorista: 1.790 frames em 30,015 s, ambos os projetores ativos
em todas as amostras. Capturas em `evidence/digo/xenon-driver-frames.zip`,
manifesto `xenon-driver-timeline.json` e vistas 30/900/1700. Foram cobertos
10 s de câmera fixa, órbita e zoom no pátio real à noite. A análise percorreu
todos os frames; na seção estática após estabilização, a maior diferença
média da região central foi 0,138/255. Vistas inspecionadas mostram feixe
contínuo e alinhado. Maior intervalo de captura: 85 ms, incluindo custo de
leitura da GPU e gravação; não usar esse intervalo como medição de runtime.

Não foram validados com essa captura condução em velocidade, chuva, todos
os limites de streaming ou outros mapas. Ela não certifica globalmente a
iluminação. A comparação de performance registrada acima é diurna.

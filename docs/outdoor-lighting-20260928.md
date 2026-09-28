# Iluminação externa — 28/09/2026

A cidade usava principalmente lâmpadas emissivas e manchas no piso. O novo
controlador acrescenta luz real aos postes próximos, utilizando o registro
espacial existente e descartando postes derrubados e chunks descarregados.
As oito torres do porto e cinco luminárias nas docas/portaria/descanso da
Vértice também participam desse conjunto. Há mais preenchimento ambiente
externo (+0,12 à noite / +0,16 de dia), sem alterar o cálculo de interiores.

O limite de **6 luzes reutilizadas**, seleção de 50 m, fade de câmera em
30–50 m e ausência de sombras locais foram preservados conforme a sessão de
performance e a orientação do usuário. Seleção a 4 Hz, histerese e deduplicação
de globos próximos; dia/interiores/montanha desativam o conjunto urbano.
A montanha conserva suas fontes locais existentes. Não há novos bloqueios
no piso nem mudanças de entrada, câmera ou inventário dos interiores.

Validação funcional: `test_city_local_lighting.gd`, **26 checks aprovados**;
`test_weather_lighting_parity.gd`, aprovado. Incluem teto de fontes, estabilidade,
dia/noite, interiores, montanha, postes destruídos, descarregamento, fontes
transformadas, preservação de sombras e chuva. Revisão visual feita nas
capturas reais de Main em `evidence/outdoor-lighting-20260928/after/`.

## Medição renderizada

Main, Godot 4.7.2, RTX 4060 Laptop, Mobile, 1280×720, VSync desligado,
limite normal de 144 FPS. Mesma seed, câmera, pontos e horário/clima por caso.
8 s de aquecimento separados + 30 s medidos por cenário. Fixture mantém o
jogador vivo, parado fora da pista, sem gravar saves. Tráfego e NPCs continuam
ativos. Uma confirmação finita foi definida após sinais acima de 5% em p95/p99.
A comparação ocorre em repositório compartilhado com trabalho de performance
concorrente; variação ou ganho não é atribuído exclusivamente às novas luzes.

| Cena | Antes FPS / p95 / p99 | Depois FPS / p95 / p99 | Confirmação FPS / p95 / p99 |
|---|---|---|---|
| city-day | 129.67 / 11.656 / 14.574 ms | 121.27 / 13.352 / 15.101 ms | 138.00 / 10.957 / 12.152 ms |
| city-night | 83.46 / 15.493 / 17.775 ms | 77.15 / 16.669 / 19.005 ms | 96.09 / 14.741 / 16.699 ms |
| port-night | 143.71 / 9.987 / 10.519 ms | 130.34 / 10.802 / 13.742 ms | 143.53 / 9.961 / 10.718 ms |
| vertice-night | 144.00 / 8.206 / 8.416 ms | 143.99 / 8.199 / 8.471 ms | 143.94 / 8.659 / 9.350 ms |
| city-rain | 133.96 / 12.798 / 17.177 ms | 110.68 / 14.251 / 16.114 ms | 126.37 / 12.869 / 14.776 ms |

Amostras completas, p50, máximos, quadros acima de 33,3/66,7 ms e aquecimento
ficam nos JSON de cada cenário. A primeira medição após a mudança teve um
pico de 1471 ms no porto; não o excluímos dos resultados. Na confirmação o máximo do porto foi 28,46 ms, sem frames acima de
33,3 ms; o pico não se repetiu, mas permanece registrado como travamento
da primeira rodada. Os sinais iniciais de regressão na cidade/porto/chuva
não se repetiram. Vértice permaneceu no limite de 144 FPS; o p99 oscilou
de 8,47 para 9,35 ms, ambos abaixo de 16,67 ms. O p99 da cidade noturna
ficou em 16,699 ms e houve um frame de 52,668 ms: não se promete 60 FPS
em todos os frames nem ausência de travamentos na primeira visita. Avisos de Texture RID no encerramento também
existem na base. Esta medição não certifica todos os locais, condições ou PCs.

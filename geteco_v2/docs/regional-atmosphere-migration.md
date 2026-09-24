# Atmosfera V1 → V2 — 22/09/2026

## Direção e implementação

Os recursos originais de `systems/atmosphere` da V1 foram copiados para
`runtime/atmosphere`, alterando apenas os caminhos dos recursos. Porto, floresta
e neve voltam a ter suas sombras, saturação, contraste e cor de névoa próprias.
Deserto e costa ficam como recursos de autoria; não são novas regiões jogáveis.

`RegionalAtmosphere3D` converte metros para as coordenadas originais da V1.
A aproximação da serra mistura os perfis ao longo da ponte, independentemente
da troca lógica de região; a altitude geográfica mistura floresta/neve. Cemitério
usa centro e dimensões do lote original. Resort usa a elipse original de autoria,
com áreas claras mais quentes, preservando sombras frias. Os valores têm
suavização temporal e são atualizados junto do clima, aproximadamente a 5 Hz.

O relógio recupera os marcos originais de madrugada, amanhecer, dia, hora dourada,
pôr do sol e crepúsculo de `DayNightWeatherManager`. Luminância controla energia
das luzes; cromaticidade e os perfis controlam áreas claras e preenchimento.
O sol/lua não ficam mais rasantes a −15° durante a noite: a elevação varia de
42° a 70°, evitando as grandes cunhas de sombra registradas na revisão anterior.

Névoa usa profundidade nativa do Environment, com alcance de 18–75 m, densidade
dos perfis e cor que escurece à noite. É uma tradução para geometria 3D, não uma
cópia do antigo ruído de composição 2D. Não há novas luzes, SubViewports,
volumetria ou cópia de tela. [API oficial do Environment](https://docs.godotengine.org/en/latest/classes/class_environment.html).

Chuva e neve possuem emissores independentes, com pesos geográficos. Os flocos
não substituem as gotas já vivas na troca de região. Granizo continua acompanhando
o relógio térmico persistido. Chuva e vento têm volume dependente da região.
Não há segundo relógio, alteração do schema de save ou troca de ID do clima de Harbor.

Interiores suspendem névoa e correção externa de cor; o caminho anterior da luz
interna é preservado. Túneis e abrigos suspendem precipitação e névoa externa.
Não houve alterações de geometria, colisões, câmera, móveis, dano ou armas.

## Evidências e escopo de aprovação

- Contratos: `tests/test_regional_atmosphere.gd`, 25 checks aprovados, incluindo
  perfis originais, marcos de horário, fronteira, cemitério, resort e abrigo.
- Integração: `tests/test_weather_atmosphere_integration.gd` verifica Main real,
  entrada/saída da garagem, restrição de armas, chuva/neve/granizo e restauração
  da atmosfera: 20 checks aprovados. Zero falhas nos dois scripts; logs em
  `evidence/atmosphere-after/contracts.log` e `integration.log`. A última execução
  de integração terminou com aviso de 12 objetos e quatro recursos retidos ao
  encerrar Main; os checks funcionais passaram, mas a limpeza global não está
  certificada por este teste.
- Comparação renderizada: `tests/measure_regional_atmosphere.gd`; dados brutos,
  aquecimento, capturas e logs em `evidence/atmosphere-before` e
  `evidence/atmosphere-after` (primeira rodada) e `evidence/atmosphere-final`
  (rodada completa após revisão). Oito pontos de observação, não uma rota completa.
- [Comparação visual](regional-atmosphere-review.html).

Meta: 60 FPS / 16,67 ms. Critério definido antes da comparação: aumento acima
de 5% em p95/p99 exige uma confirmação dirigida. Cada cenário tem oito segundos
de aquecimento e pelo menos 30 segundos medidos. Main real, população 24, trânsito
e despacho ativos, save desativado, seed 22092026, relógios climáticos fixados;
frio suspenso apenas no harness para não matar o personagem parado na medição.
Tráfego e NPCs não são replays determinísticos. Há um processo Godot alheio aberto
durante ambas as passagens; não foi encerrado. Medição não isola tempo de GPU.

Godot 4.7.2, Mobile/Vulkan, RTX 4060 Laptop, 1280×720, VSync desligado e limite
de 60 FPS. Valores abaixo: referência / rodada completa revisada, em ms quando
aplicável. As imagens da página de revisão pertencem a essa segunda coluna.

| Cenário | FPS médio antes / depois | p95 antes / depois | p99 antes / depois | Quadros >33,3 ms antes / depois |
|---|---:|---:|---:|---:|
| Porto, manhã | 59,95 / 60,00 | 17,592 / 17,482 | 19,821 / 20,269 | 1 / 0 |
| Porto, entardecer | 59,99 / 60,00 | 17,190 / 17,445 | 18,248 / 18,966 | 1 / 0 |
| Rua, crepúsculo | 60,00 / 60,00 | 17,652 / 17,411 | 19,680 / 18,271 | 0 / 0 |
| Rua, chuva | 59,98 / 60,00 | 17,255 / 17,362 | 18,193 / 18,379 | 0 / 0 |
| Cemitério | 59,93 / 59,98 | 17,320 / 17,497 | 18,044 / 19,207 | 2 / 1 |
| Ponte | 60,00 / 59,91 | 20,170 / 17,662 | 22,242 / 20,941 | 0 / 1 |
| Floresta | 59,97 / 59,85 | 17,110 / 17,207 | 17,954 / 17,978 | 1 / 3 |
| Resort, neve/granizo | 60,00 / 60,00 | 17,270 / 17,204 | 18,321 / 18,414 | 0 / 0 |

Não houve quadros acima de 66,7 ms nas janelas estáveis das duas rodadas da tabela. A primeira rodada depois
da mudança (`atmosphere-after`) teve p99 de 17,440 ms no cemitério; a rodada
revisada teve 19,207 ms, 6,45% acima da referência. Uma confirmação dirigida
foi solicitada pelo critério prévio, sem apagar nenhuma dessas amostras.

O aquecimento continua tendo pausas grandes: porto 1.160,785 ms antes e
1.368,841 ms depois; na rodada revisada, floresta 274,411 ms e resort 445,299 ms.
Não atribuí esses picos a GPU, iluminação ou streaming sem um perfil causal.
Este trabalho não aprova fluidez de carregamento/primeira visita. Os 60 FPS
médios também não significam que todos os quadros ficaram abaixo de 16,67 ms.

Confirmação dirigida (`evidence/atmosphere-confirmation`): cemitério voltou a
p95 17,353 / p99 18,044 ms (mesmo p99 da referência), com um pico de 66,858 ms.
Neve: p95 17,469 / p99 19,446 ms, sem quadros acima de 33,3 ms. O p99 da neve,
6,14% acima da referência nessa amostra, motivou uma única confirmação
equivalente adicional; as duas rodadas completas anteriores ficaram dentro do
limite. Não se substituíram amostras desfavoráveis por uma seleção da melhor.

A confirmação adicional (`evidence/atmosphere-confirmation-snow`) registrou
cemitério p95 17,422 / p99 18,191 ms e neve p95 17,267 / p99 18,305 ms. Na neve
houve um quadro de 35,710 ms; médias de 60,00 e 59,98 FPS, respectivamente.
O aumento de p99 não se repetiu em nenhum dos dois casos. **Não foi confirmada
regressão sustentada de p95/p99 nestes cenários**; há variação entre amostras e
pausas isoladas, e não se demonstrou ganho causal de desempenho. A aprovação
é restrita ao comportamento/visual verificado e às janelas estáveis medidas;
carregamento/primeira visita e rotas completas continuam sem aprovação.

Após a rodada completa foram refinados dois ramos: cobertura de abrigo indicada
por metadado e cromaticidade de pôr do sol sob uma frente de neve, independente
do clima de Harbor. Os 45 checks e as confirmações dirigidas usam esse código.
As oito imagens continuam representativas: esses ramos não mudam as condições
capturadas (nenhum abrigo marcado, nevasca fotografada pela manhã).

## Limites restantes

Estilhaços de gelo no chão da V1 ainda não foram portados. A névoa nativa não
reproduz o movimento de ruído da composição 2D. Este lote não certifica todos os
horários, câmeras e rotas, nem desempenho universal, nem encerra a migração geral.

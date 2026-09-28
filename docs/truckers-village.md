# Vila dos caminhoneiros — Posto do Tonico

Na ponta sudoeste do terreno da Vértice, Harbor: centro `(-330, 0, 108)`;
acesso desde a junção asfaltada `(-290, 0, 10)` até o estacionamento externo
`(-286, 0, 55)`. Dali seguem trilhas de pedestres. O conjunto tem posto antigo,
duas bombas mecânicas, compressor, seis casas acessíveis, borracharia aberta,
carroça e sucata. Fachadas exibem somente nomes próprios. As casas têm interiores
no próprio mundo; a vendinha funciona pelo balcão externo. Sete veículos
utilizáveis ocupam vagas de terra fora dos caminhos: duas caminhonetes, dois
jipes, duas motos e uma perua.

## Revisão atual: casas, veículos e posto compacto

O posto foi reduzido horizontalmente para 78% × 74% e verticalmente para 80%,
com piso e acessórios acompanhando a transformação. O balcão permanece em
escala humana. As casas possuem portas físicas automáticas, seis combinações
de móveis, câmera interna e cobertura que se oculta ao entrar. Os objetos
continuam no mesmo espaço físico dos personagens.

Cada casa abriga dois moradores de doze; apenas o par próximo fica ativo.
Invasão provoca uma advertência, tiros com sete projéteis e chama os três
vizinhos para a porta. Paredes e móveis bloqueiam os tiros. Vida e morte dos
ocupantes são persistidas. Cada casa contém dinheiro recolhível uma única
vez por recibo; valores variam, incluindo um esconderijo de R$5.000.

O menu do balcão ocupa 350 × 210 pixels em 1280 × 720, com três botões
inteiramente visíveis. O HUD respeita esse tamanho após atualizar o layout;
fechar o balcão restaura o estilo e as dimensões dos demais menus.

Validação atual: geometria exterior **328 checks**, interiores **137 checks**,
moradores e guardas **47 + 47**, comércio **26** e missão **29**, todos aprovados.
Main validou portas das seis casas, ocupantes, alarme, combate, menu, compra,
assalto e restauração. A frota passou por admissão física, entrada real do
jogador nos sete veículos e restauração sem duplicação. Recompensas das casas:
**67 checks** aprovados, com a economia real e restauração dos recibos.

As copas da vila usam uma camada própria: a câmera interna deixa de desenhá-las
para não encobrir móveis e pessoas. O exterior mantém as 18 copas, galhos,
troncos e colisões. O encerramento das casas não atualiza o áudio após o
descarregamento do clima.

Capturas atuais do Main em `evidence/truckers-village-20260928/homes-final/`:
[conjunto](../evidence/truckers-village-20260928/homes-final/overview.png),
[menu compacto](../evidence/truckers-village-20260928/homes-final/comprar-ou-assaltar.png)
e interiores [1](../evidence/truckers-village-20260928/homes-final/casa-1.png),
[2](../evidence/truckers-village-20260928/homes-final/casa-2.png),
[3](../evidence/truckers-village-20260928/homes-final/casa-3.png),
[4](../evidence/truckers-village-20260928/homes-final/casa-4.png),
[5](../evidence/truckers-village-20260928/homes-final/casa-5.png),
[6](../evidence/truckers-village-20260928/homes-final/casa-6.png).
Arquivos `casa-N-player|npc-front|behind|side.png` registram os 36 controles
de profundidade; os móveis ocultam a parte correspondente do corpo por trás
e deixam o corpo visível à frente e ao lado. Colisão foi verificada em testes
separados, incluindo 18 poses livres usadas nas capturas.

Comparativo final renderizado (Mobile, RTX 4060 Laptop, 1280 × 720, limite
144 FPS, oito segundos de aquecimento e trinta segundos por cenário):

| Cenário | FPS antes/depois | p95 antes/depois | p99 antes/depois |
|---|---:|---:|---:|
| Vila dia | 143,98 / 143,99 | 8,148 / 9,530 ms | 8,452 / 10,054 ms |
| Noite/chuva | 143,95 / 143,79 | 8,002 / 9,575 ms | 8,520 / 9,857 ms |
| Entrada | 143,98 / 143,69 | 8,570 / 11,519 ms | 8,923 / 11,876 ms |

Intervalos brutos em `homes-before-clean/` e `homes-final/`. O resultado final
teve um quadro estável acima de 33,3 ms na chuva (33,38 ms) e nenhum acima de
66,7 ms. Picos de aquecimento antes/depois: dia 811,56/805,21 ms, chuva
452,25/451,22 ms, entrada 630,79/1.053,49 ms. O nome da pasta de baseline
identifica a tentativa sem erro de HUD; não significa isolamento de CPU.
**Performance pendente:** aumentos de percentis excedem 5%; testes headless
externos do canal e motocross começaram durante ambas as execuções. Falta
confirmar o comparativo sem interferência e medir separadamente o combate
dentro das casas. Não atribuir os picos a um sistema sem diagnóstico.

A captura final não teve erro de script durante jogo; permanece o aviso
de textura/RID no desligamento do motor, também presente no baseline.
Prévia do editor regenerada com casas e frota; exportação final concluída.

Os registros abaixo documentam etapas anteriores. Fotos e métricas dessas
etapas não certificam os seis interiores e a frota adicionados nesta revisão.

O jogador conversa com Tonico, procura uma correia na sucata oeste e uma
manivela junto à carroça leste, depois restaura a bomba de ar. Recebe R$450
uma única vez e libera conserto gratuito do último veículo dirigido, desde que
estacionado na entrada, danificado e com admissão física concluída. Bombas de
gasolina são cenário: não introduzimos um sistema de combustível.

A missão usa a interação normal, objetivos no HUD e o estado urbano no save.
A política de checkpoints alterada simultaneamente por outra sessão bloqueia
salvamento enquanto a missão está em andamento. O progresso é serializável,
mas o checkpoint real é gravado após concluir o conserto; coleta intermediária
não dispara tentativa de salvamento rejeitada. O recibo da economia impede
duplicação da recompensa ao restaurar dados antigos.

## Implementação e validação

- `gameplay/urban_v1/TruckersVillageVisuals.gd`: geometria estática agrupada,
  sólidos identificados, NPC, peças, luzes via pool existente e cobertura por
  presença. Sem novos viewports. Desativação ao entrar em outra região/sala.
- `TruckersVillageQuest.gd`: lógica por interação, sem loop contínuo.
- `UrbanOperations.gd`, `FullSession.gd`: integração e HUD.
- `FreightOutskirts.gd`: clareira e acesso livres de árvores.
- `WorldSessionContext.gd` e catálogo gerado: representação do posto no editor.

Verificações e evidências deste trabalho:

- `tests/test_truckers_village_geometry.gd`: 98 checks físicos aprovados;
  movimento varrido de jogador/NPC contra sólidos, aproximações livres e
  espaço para caminhão. Profundidade visual exige inspeção separada.
- `tests/test_truckers_village_quest.gd`: estado, morte, distância, ordem,
  pagamento único, restauração, conversa com NPC vivo e seleção segura do veículo;
  **29 checks aprovados**, log `evidence/truckers-village-20260928/quest-unit.log`.
- `tests/test_truckers_village_integration.gd`: fluxos reais em Main, save
  e serviço; **zero falhas**, log `evidence/truckers-village-20260928/quest-integration.log`.
- `tests/measure/measure_truckers_village.gd`: Main 1280×720, mesma câmera,
  oito segundos de aquecimento e trinta segundos por cenário (dia/noite chuva).
  Meta provisória 60 FPS/16,67 ms; aumento >5% de p95/p99 exige confirmação.
- Baseline real antes da integração: `evidence/truckers-village-20260928/before/`.
  RTX 4060 Laptop, Mobile, configuração efetiva de 144 FPS. Dia p95/p99
  8,042/8,289 ms; noite/chuva 7,822/8,075 ms. Baseline não aprova a alteração.

## Revisão renderizada e limite da evidência de desempenho

Fotos reais em `evidence/truckers-village-20260928/final-visual/`: conjunto,
posto, conversa com Tonico, borracharia e jogador/NPC na frente, atrás e ao lado
da bomba. As coberturas do posto e da borracharia ocultam-se por presença; os
sólidos e os atores continuam no mesmo mundo 3D. Naquela etapa, as casas ainda
ficavam fechadas. Os materiais finais usam albedo explícito por lote, corrigindo a
perda da paleta por instância observada na primeira captura. O chão tem borda
irregular e cascalho texturizado.

O primeiro comparativo (`before/` versus `after/`, antes da correção final de
materiais) mediu:

| Cenário | FPS antes/depois | p95 antes/depois | p99 antes/depois |
|---|---:|---:|---:|
| Pátio dia | 144,00 / 143,94 | 8,042 / 8,449 ms | 8,289 / 8,830 ms |
| Noite com chuva | 144,01 / 144,01 | 7,822 / 7,771 ms | 8,075 / 7,971 ms |

Nenhum quadro estável acima de 33,3 ms nesses quatro períodos de 30 s.
Na primeira visita diurna, o maior quadro de aquecimento passou de 540,569
para 956,057 ms; não foi tratado como regime estável. O aumento diurno de
p95/p99 exige confirmação. **Performance final pendente:** a paleta mudou a
organização dos lotes depois desse comparativo, e testes renderizados alheios
voltaram a ocupar a GPU. Capturas finais são somente revisão visual, não
benchmark. Nenhuma sessão alheia foi encerrada. Não contar como ambiente
integralmente certificado nem atribuir os picos a um subsistema sem diagnóstico.

As capturas de Main encerraram com aviso de liberação de textura/RID no
desligamento do motor; não houve erro de script nas capturas finais. O fluxo
funcional e a validação de snapshot foram aprovados separadamente.

## Revisão rural e vila a pé — 28/09/2026

O acesso usa entidades reais de via no editor: entrada asfaltada de 9 m,
trecho de terra até o estacionamento e trilha interna de 3 m, excluída do
grafo de tráfego. Postes de madeira bloqueiam veículos na passagem, mantendo
vãos para pessoas. A terra é recortada na área do asfalto; vias, quintais e
trilhas compartilham material com textura filtrada e bordas de vegetação.

As seis casas têm posições e rotações próprias, cercas com portões abertos,
varais, hortas, caixas d'água, ferramentas e reparos de fachada. A clareira
recebeu 18 árvores de copa mais cheia, arbustos e até 4.200 tufos de capim
agrupados espacialmente. A vegetação evita sólidos, pisos de concreto,
trilhas, pontos de interação e rotas dos moradores. Sem vento por quadro,
sombras no capim ou novas fontes permanentes de luz.

Tonico e três moradores usam chapéu country, camisas xadrez/coletes, jeans e
botas. Os três vizinhos percorrem circuitos curtos a 1,08–1,32 m/s com pausas,
aceleração e passos ligados ao deslocamento físico. Animação e física ficam
suspensas fora da região ou a mais de 135 m do centro da vila. A cobertura
do posto e o teto da borracharia passam a 9% de opacidade por presença e
voltam ao material opaco ao sair.

No balcão `(-364, 0, 85)`, a interação abre duas ações separadas:

- Comprar bebida: R$20 por até 25 pontos de vida, sem cobrança quando a vida
  já está cheia. Exige Tonico vivo, proximidade e ausência de conflito.
- Assaltar caixa: exige arma empunhada e concede R$180. Os moradores se
  armam por 120 s, o crime é registrado e o caixa leva 600 s de jogo para
  recompor dinheiro. Recibos da economia e snapshot impedem duplicação.

A reação usa corpos físicos, orientação da arma, linha de visão e disparos
limitados a 16 m, com intervalo de 1,4 s. Paredes, outros atores e veículos
bloqueiam tiros; perseguição é limitada à vizinhança. Comprar e assaltar
respeitam a política existente de checkpoints. Agressão do jogador contra
moradores também provoca o conflito. Personagens da garagem não foram alterados.

Validação desta revisão: 267 verificações de geometria, 47 de moradores,
26 de comércio e 29 da missão aprovadas. Main validou menu real, compra,
assalto, pagamento, crime, checkpoint, restauração e tiro causando dano real;
zero falhas. Ligações genéricas e pavimento: 16 e 20 checks aprovados.
As capturas são do jogo real; a versão `country-visual` detectou mato dentro
da borracharia e artefatos na borda das trilhas, corrigidos antes da captura final.

Fotos finais em `evidence/truckers-village-20260928/country-final/`:
[quintais](../evidence/truckers-village-20260928/country-final/quintais.png),
[cobertura transparente](../evidence/truckers-village-20260928/country-final/tonico.png),
[balcão](../evidence/truckers-village-20260928/country-final/balcao.png),
[escolhas](../evidence/truckers-village-20260928/country-final/comprar-ou-assaltar.png)
e [reação ao assalto](../evidence/truckers-village-20260928/country-final/reacao-ao-assalto.png).

Comparativo renderizado desta revisão, mesma câmera 1280×720 e 30 s por
cenário, RTX 4060 Laptop/Mobile, limite efetivo 144 FPS:

| Cenário | FPS antes/depois | p95 antes/depois | p99 antes/depois |
|---|---:|---:|---:|
| Vila dia | 144,00 / 143,99 | 8,171 / 9,046 ms | 8,673 / 9,281 ms |
| Vila noite/chuva | 144,01 / 144,00 | 7,797 / 9,376 ms | 8,023 / 9,637 ms |
| Entrada | 143,28 / 141,95 | 8,808 / 11,080 ms | 9,574 / 11,563 ms |

O antes foi reconstruído em memória usando cópias exatas dos três geradores
e do documento do mapa preservados antes da revisão, sem reverter arquivos.
Pastas `redesign-before/` e `country-final/` contêm os intervalos brutos.
O cenário de entrada anterior teve um quadro de 118 ms; depois, nenhum
quadro estável acima de 33,3 ms nos três cenários. Entretanto, **performance
não aprovada**: p95/p99 aumentaram mais de 5%, e outras sessões iniciaram
testes renderizados do porto e testes headless durante o comparativo.
O resultado é diagnóstico, não isola a regressão. Falta confirmação isolada
e medição específica do evento armado; nenhum processo alheio foi encerrado.

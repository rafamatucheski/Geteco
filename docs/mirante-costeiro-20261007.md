# Farol costeiro voltado ao deserto

## Revisão pedida pelo usuário: farol e horizonte contínuo

Capturas finais reais: [farol de dia](concepts/coastal-lookout/farol-no-jogo.png),
[à noite](concepts/coastal-lookout/farol-noite.png) e
[cidade pelo binóculo](concepts/coastal-lookout/farol-binoculo-cidade.png).

O mirante inicial foi substituído por um farol acessível. O passeio de pedestres
chega à praça existente a 10,2 m; uma escada externa de duas voltas, com apoio
físico contínuo, sobe até a galeria a 24,2 m. A torre tem alvenaria envelhecida,
cintas, janelas, lanterna envidraçada, lente Fresnel e cúpula escura. O binóculo
agora fica nessa galeria e mira a cidade real do deserto em `(-180,8,-900)`.

O desaparecimento da cidade e o término do oceano eram defeitos da primeira
implementação: o horizonte só incluía relevo, os edifícios dependiam dos chunks
próximos ao jogador e o complemento do oceano terminava em limites finitos.
`LookoutDistantCity.gd` agora representa edifícios, ruas e torres d'água a partir
dos dados reais de Desert/Harbor/Santa Lua, respeitando os chunks já prontos.
Não carrega moradores, trânsito, física ou luzes dessas cidades distantes.
O oceano visual se estende a ±8.192 m, além do alcance da óptica, preservando
os recortes do deserto/mina, canal, skate e aberturas subterrâneas. A depressão
da água sob a ponte conserva a triangulação de 4 m do oceano original.

Um recorte de material localizado entre a câmera e Dante permite vê-lo atrás
da torre e sob a volta superior. O recorte não altera colisões nem sombras.
Há uma única OmniLight quente fixa em `(303,26,-198)`, alcance 6,5 m, energia
1,65, com sombras. Vidros e lentes deixam a luz passar. Não há feixe giratório.
O acesso é exterior contínuo: nenhum interior novo ou transferência de sala.

Contratos já verificados nesta revisão: 15 checks de circulação física real
(subida, descida, guarda-corpo e três varreduras de carro), 36 do binóculo,
9 de fontes do panorama e 264 amostras da água (257 na ponte, quatro além
das antigas bordas e três exclusões do deserto). O registro de execução
renderizada e comparação de desempenho desta revisão aparece ao final.

## Histórico da primeira implementação

Implementação de 07/10/2026. Conceito visual criado com image_gen integrado;
o [desenho](concepts/coastal-lookout/mirante-conceito.png) é referência artística,
não uma captura do jogo. [Prompt integral](concepts/coastal-lookout/prompt.txt).

Capturas reais anteriores ao farol: [mirante](concepts/coastal-lookout/mirante-no-jogo.png)
e [vista pelo binóculo](concepts/coastal-lookout/binoculo-no-jogo.png).
[Panorama final](concepts/coastal-lookout/mirante-panorama-final.png) após a
correção da malha do mar junto à ponte; render confirmado no diretório
`evidence/coastal-lookout-final-preview-107076-5835715/`.

## Acesso e controles preservados

Entrada pela calçada norte de Harbor, entre BridgeCourtWest e BridgeCourtEast,
em `(319.5, 0.055, -130.5)`, sob a linha elevada existente. Passeio sinuoso de
3,4 m com subida contínua até plataforma circular a 10,2 m, centrada em
`(303, 10.2, -198)`. A passagem elevada cruza sobre a contenção costeira;
não remove a barreira, não cria via para trânsito e não altera a ponte da campanha.

Há bancos, guarda-corpos físicos, piso de pedra clara, metais bronze,
rochas costeiras e espuma animada junto às pedras. Três balizadores barram
carros na entrada. A circulação não exige pular ou teletransportar.

O binóculo mira `(-180, 8, -900)`, no deserto real. Aproximar-se a pé no topo
oferece a interação normal; mouse/analógico/toque movem a vista, roda do mouse,
gatilhos ou botões de zoom aproximam, e interação/cancelar permitem sair.
A óptica tem céu e profundidade de neblina próprios, acompanhando horário e
clima, sem mudar a atmosfera global. Pausa, dano, morte e transições cancelam
a observação. Não se pode atacar, embarcar ou salvar durante a observação.
Ao sair, inventário, personagem, HUD e câmera normal permanecem disponíveis.

## Integração

- `world/places/coastal_lookout/CoastalLookout.gd`: geometria em lotes por material,
  colisão estática, rota autorada e modelo articulado do binóculo.
- `world/places/coastal_lookout/coastal_surf.gdshader`: espuma irregular local,
  deslocamento de impacto e dissipação; sem simulação de água por CPU.
- `world/places/coastal_lookout/LookoutDistantSea.gd`: continuidade visual do mar
  além dos chunks próximos, com fases do shader original e desnível da ponte.
- `runtime/coastal_lookout/CoastalLookoutRuntime.gd`: carrega a menos de 190 m
  da entrada e libera além de 260 m ou ao sair de Harbor/exterior. Consulta a
  residência a cada 0,5 s. O horizonte do deserto reutiliza a geometria autorada;
  o panorama auxiliar se oculta se a região do deserto já possui seu horizonte.
- `CoastalBinoculars.gd`, `BinocularOverlay.gd` e `binocular_mask.gdshader`:
  câmera óptica, posse temporária de input e controles funcionais.
- Integração aditiva em `FullSession.gd`; bloqueio de ataque pela posse da óptica
  em `Gameplay.attack_allowed()`. Sem conversão de sistemas C#/GDScript.

Nenhuma fita foi acrescentada nesta implementação; o local pode ser escolhido
posteriormente para a coleção do piloto. Nenhuma luz nova foi adicionada.

## Validação funcional e visual

Motor Godot 4.7.2 .NET, `Harbor.csproj` compilado sem erros nem avisos.
Render Mobile/Vulkan na RTX 4060 Laptop. Saves dos testes em diretórios
isolados dentro de `evidence/`, sem substituir slots pessoais.

- `tests/test_coastal_binoculars.gd`: 36 verificações aprovadas sobre admissão,
  câmera, zoom, limites, pausa, dano, morte, dono de input, toque e eco de teclas.
- `tests/test_coastal_lookout_physics.gd`: 15 verificações aprovadas; Actor real
  sobe e desce todas as curvas, alcança binóculo, para no guarda-corpo e volta.
  Varredura de casco de carro bloqueada nos três alinhamentos testados.
- Regressão `tests/test_garage_driver_restore.gd`: 34 verificações aprovadas,
  incluindo restauração do motorista, câmera e ataques bloqueados nas garagens.
  Log `evidence/coastal-lookout-garage-regression.log`; aviso de gravação de
  diálogo de guarda ausente, sem falha dos casos e sem relação com o mirante.
- `tests/test_coastal_lookout_sea.gd`: 257 consultas às malhas trianguladas reais
  confirmam que o mar distante permanece 12 cm abaixo do oceano na depressão
  da ponte (erro máximo 0,095 mm). A revisão encontrou interpolação de 16 m
  ultrapassando o mar original; o trecho passou a usar a mesma grade de 4 m e
  diagonal das faces originais, mantendo 16 m nas áreas planas.
- `tests/capture/capture_coastal_lookout.gd`: cena Main real, C# confirmado,
  subida/descida completas sem teleporte de percurso, interação e roda do
  mouse reais, câmera do deserto, bloqueio de combate, pausa e recuperação.
  Capturas em `evidence/coastal-lookout-capture-80316-5841698/`.
  Essa primeira execução registrou uma falha de fixture: a posição usada para
  testar descarregamento era a própria entrada. Os demais 33 checks passaram.
  A fixture foi corrigida; a verificação de ciclo de vida foi executada à parte.
- `--lifecycle-only`: 27 verificações aprovadas em
  `evidence/coastal-lookout-capture-18600-5993157/`. Restauração fria diretamente
  no topo sem teleporte de teste, apoio físico, save real isolado, entrada e saída
  repetidas, descarregamento e retorno. Campanha incompleta, ponte em obra e
  bloqueio de viagem ao deserto preservados. Um aviso de evento de joystick
  reutilizado na mesma frame foi corrigido na fixture após esta rodada.
- Sequência contínua diurna: 881 frames em 30 segundos, sem frames desenhados
  perdidos pela captura; 10 s parado, 10 s de deslocamento lento e 10 s de retorno.
  `surf-frames/`, timestamps no `report.json` e vídeo `ondas-30s.mp4` no diretório
  da captura. Leitura de pixels/JPEG e limite temporário de 30 FPS tornam essa
  gravação evidência visual, não benchmark. Inspeção de frames e diagnóstico
  sobre alvenaria estática não apontaram apagões; não certificam todo clima/noite.

O primeiro teste físico detectou um degrau de 26 cm no encontro da rampa com
o terraço. A correção estabeleceu patamar horizontal antes do círculo; a rodada
aprovada e a caminhada real subsequente verificaram o encontro corrigido.
O primeiro render também mostrou mar cortado pelo streaming e espuma em anéis;
ambos foram corrigidos antes da captura de 30 s.

## Performance e cobertura

Comparativo finito em `tests/measure/measure_coastal_lookout.gd`, cena Main
com população/trânsito reais, 5 s de aquecimento e 30 s por cenário estável
(entrada e enquadramento panorâmico). Alvo provisório: 60 FPS / 16,67 ms;
aumento de p95/p99 acima de 5% pede confirmação equivalente. Primeira
aproximação separada das amostras estáveis. **Comparativo final inconclusivo por
concorrência de processos renderizados de outra sessão.** Não há aprovação de
performance desta alteração.

A primeira fixture de benchmark foi descartada: a alteração de `aftermath`
invalidava o save e o jogador permanecia em Maciota. A fixture foi corrigida,
passou a exigir caminho de save válido e posição efetiva de medição.
As duas medições de baseline subsequentes chegaram a aproximadamente 144 FPS,
mas outra sessão abriu testes/capturas de esgoto durante ambas; não são uma
referência isolada confiável. O nome `baseline-isolated` registra a intenção
do runner, não comprova isolamento. Uma espera final limitada a 90 s não
encontrou janela livre, então a medição final não foi iniciada. Nenhum processo
de outra tarefa foi interrompido.

Evidências de tentativa: `evidence/coastal-lookout-baseline-valid.log` e
`evidence/coastal-lookout-baseline-isolated.log`, com relatórios/amostras em
`evidence/coastal-lookout-baseline-valid-36232-6058573/` e
`evidence/coastal-lookout-baseline-isolated-151764-5824202/`.
O runner final também mede 30 s da óptica na cena real. Para fechar a pendência,
executar baseline com `--lookout-baseline` e final sem essa flag em janela sem
outros jogos/testes/capturas, usando `--no-save --skip-arrival` e labels novos.
Não usar gravação de vídeo ou limite de FPS como prova de desempenho.

Cobertura visual atual: dia seco, câmeras de gameplay, panorâmica e binóculo.
Naquela primeira versão, noite, chuva/tempestade, colisão com NPC visitante e auditoria global do mapa
não foram exercitadas nesta tarefa. Não é aprovação geral da iluminação ou do jogo.

## Validação final da revisão para farol

Godot 4.7.2 .NET, C# compilado e caminho nativo confirmado no Main. Dados de
teste isolados; nenhum save do usuário alterado. Evidências funcionais:

- `evidence/coastal-lighthouse-physics-final.log`: 15 checks, nenhuma falha,
  após a correção das faces da cúpula e cornijas; toda subida/descida por física.
- `evidence/coastal-lighthouse-depth-127480-5695854/report.json`: 63 checks,
  nenhuma falha; rigs reais de jogador/NPC, controles positivos e corte visual.
- `evidence/coastal-lookout-capture-64692-6225742/report.json`: 38 checks,
  percurso integral no Main, pan nos dois limites, zoom, pausa e retorno.
  Esta captura revelou a cúpula sem faces e precede a correção visual.
- `evidence/coastal-lookout-capture-32208-5733504/report.json`: 34 checks,
  cúpula corrigida, dia/noite, save no topo, teclado/gamepad e gate da campanha.
- `evidence/coastal-lookout-capture-54888-5791978/report.json`: 30 checks
  após a preparação antecipada, sem duplicação de lanterna/binóculo e sem
  reconstrução geométrica na reentrada. Geração dos templates: uma vez.
- `evidence/coastal-lighthouse-optical-contract.log`: 36 checks;
  `coastal-lighthouse-sea.log`: 257 raios na ponte mais sete verificações de
  extensão/exclusão; `coastal-lighthouse-panorama.log`: nove contratos de
  fontes reais/água/proxies. Nenhuma falha nesses testes.

Foi corrigido um defeito da montagem dos lotes: `SurfaceTool.append_from`
introduzia índices só para primitivas, deixando faces manuais da cúpula e
cornijas sem referência. O lote agora é uniformemente não indexado. A nova
checagem confirma faces da cobertura e sua oclusão, separadamente da física.

### Desempenho medido

Mesma fixture/rota/configuração em Main, Mobile, RTX 4060 Laptop, 1920×1080,
VSync e limite144; cinco segundos de aquecimento e 30 s por janela estável.
População/trânsito permaneceram ativos (registro final: 40 pessoas/26 carros;
baseline: 36/25), portanto não se trata de cena congelada com carga idêntica
quadro a quadro. Nas verificações de processos não havia outro jogo renderizado.
Arquivos monitorados fora da feature coincidem com o baseline; cada execução
registrou fontes estáveis durante sua janela.

| Cena | FPS antes → final | p50 antes → final ms | p95 antes → final ms | p99 antes → final ms | Máximo final ms / >33,3 / >66,7 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Entrada | 143,88 → 143,97 | 6,961 → 6,961 | 10,639 → 10,516 | 12,958 → 12,674 | 22,994 / 0 / 0 |
| Panorama | 143,61 → 143,55 | 6,053 → 5,999 | 11,228 → 11,054 | 13,083 → 13,182 | 51,640 / 2 / 0 |
| Binóculo | 143,49 → 142,85 | 6,309 → 6,338 | 11,864 → 11,573 | 14,109 → 13,995 | 33,590 / 1 / 0 |

Baseline: `evidence/coastal-lookout-before-lighthouse-72420-6507806/report.json`.
Final: `evidence/coastal-lookout-after-lighthouse-cached-64768-5758937/report.json`.
Os p95/p99 finais não confirmam regressão acima do limiar definido de 5%;
todos ficam abaixo de 16,67 ms. Isso não significa ausência de travamentos:
os máximos e frames lentos estão explicitados acima.

A medição intermediária encontrou pico de **1.564,718 ms** na primeira
aproximação e p95/p99 ~9–10% maiores. A preparação das malhas foi movida para
o carregamento inicial, em `PackedScene` com recursos compartilhados. Ao sair,
nós ativos, física, luzes e binóculo são liberados; ficam apenas os templates.
A instalação final da primeira visita levou **21,32 ms**, a reentrada
funcional **1,619 ms**, e o máximo da janela inteira de aproximação caiu para
**96,439 ms** (baseline antigo: 468,758 ms). Ainda existe esse pico, acima do
alvo de um frame. A preparação registrada foi 6.731,906 ms sob carregamento;
não é custo zero nem prova de redução do tempo total para abrir o jogo.

### Cobertura temporal e limites

Na versão com cúpula corrigida foram gravadas duas sequências contínuas de
30 s, dia seco e noite seca, câmera parada/movimento/retorno, sem lacunas no
contador de frames. `temporal-screening.json` no diretório32208 registra
triagem da lente: maior variação entre frames estáticos de 1,381/255 de dia
e 0/255 à noite. Capturas estáticas e essa triagem não certificam ausência
de defeitos em todo frame de movimento. A inspeção integral em reprodução,
chuva/tempestade e benchmark noturno dedicado permanecem fora da aprovação.
O benchmark acima é diurno; não se afirma desempenho universal da iluminação.

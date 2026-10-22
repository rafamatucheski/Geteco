# Migração de interiores — checklist

## Maciota: circulação entre elevador e escritório — 22/10/2026

Escopo: **1 lugar físico existente / 1 interior existente alterado / 0 novos / 0 certificações integrais**; não somar novamente ao inventário. Vão do escritório ampliado de 1,40 para 2,20 m, avançando o batente frontal de Z 2,20 para 3,00. Malhas e colisões acompanham o mesmo recorte; pilar, paredes restantes, câmera e moradores preservados.

- [x] `tests/test_maciota_world.gd`: passou, incluindo travessia varrida nos dois sentidos por Z 2,50, paredes restantes e pilar bloqueando, spawns e interações livres.
- [x] Recompensas da garagem: `tests/test_garage_rewards.gd`, 47 verificações; eventos do guincho: `tests/test_tow_audio_events.gd`, 20 verificações. Esses testes não certificam circulação renderizada.
- [x] `tests/test_maciota_transition_safety.gd`: 39 verificações, zero falhas; entrada, restrições de armas, inventário, proteção de Maciota/mecânico, restauração isolada e saída. Adaptado ao corpo móvel do mecânico introduzido por outra sessão; exige forma física ativa e mantém as mesmas verificações de dano/proteção. [Resultado](../artifacts/car-maciota-20261022/maciota-transition-safety.json). A primeira tentativa procurava o antigo `ResidentBody` e falhou; preservada em `safety.log`. A colisão local passou novamente em `physics-final.log` após essa mudança concorrente.
- [x] Integração renderizada final: `tests/test_mission_objective_guidance.gd`, 15 verificações sem falhas. Objetivo persiste por 30 s, marcador muda entre guincho e carga, diário usa a mesma orientação, corpo real atravessa o vão nos dois sentidos e saída libera controle. [Log](../artifacts/car-maciota-20261022/final.log), [exterior/HUD](../artifacts/car-maciota-20261022/after-exterior-objective.png), [passagem 1](../artifacts/car-maciota-20261022/after-passage-11.png), [passagem 2](../artifacts/car-maciota-20261022/after-passage-12.png), [antes](../artifacts/car-maciota-20261022/before-garage.png). Tentativas anteriores preservadas: recursão de layout corrigida; rota antiga usava Z -130, mas a sala produtiva fica em Z -2000. A fixture usa agora o transform real e desabilita entrada externa de teclado. Essas falhas não são passagens de teste.
- [ ] Oclusão separada de Dante e NPC nos móveis: sem certificação completa nesta correção local.
- [ ] Performance: inconclusiva. A amostra inicial teve 56,26 FPS, p95 28,22 ms e p99 34,62 ms; rota/estado de interior e carga concorrente impedem usá-la como comparação válida. Outro processo iniciou `measure_interior_life.gd` durante a revisão. A execução funcional final registrou 60,00 FPS, p95 17,31 ms, p99 17,68 ms, máximo 30,97 ms em 30 s; isso não aprova regressão ou benchmark isolado. RTX 4060 Laptop, Godot 4.7.2 .NET, Forward+, 1280×720, VSync ativo, limite 60. O log também conserva erros preexistentes de prewarm de material e `mountain_zoo_walk`, além de aviso de objetos retidos ao encerrar a fixture.

HUD da missão: objetivo atual persistente junto ao minimapa; diário e marcador orientam a retirar o guincho do Neco antes de buscar a caminhonete quebrada. Não altera etapas, recompensas, saves ou o motor desativado do carro de missão.

## Garagem do Maciota: ampliação, câmera e escada da cobertura — 21/10/2026

Escopo: **1 lugar físico existente / 1 interior existente alterado / 0 novos / 0 certificações integrais**. Pedido de jogo em 3440x1440: escada "mal posicionada" e garagem pequena na tela. A oficina ganhou 4 m à esquerda (área de peças: estante, pilhas de pneus, motor no cavalete; carretel e pneu acompanharam a parede). Baia/origem, portão, escritório, spawn, saída, moradores e pontos de interação não mudaram. A câmera alinhada `(0,18,15)` agora mira o centro projetado da sala com size 10,2 (antes 13; mais largo em telas < 1,57). A escada da cobertura, que caía em pé no piso atravessando a divisória do escritório, é autorada na parede dos fundos (`WorkshopProps.roof_access_point`/rota).

- [x] Fotos reais na Main (fixture, `--no-save`), 16:9 e 21:9: [antes](../evidence/maciota-garagem-portamalas-20261021/antes-garagem-21x9.png), [depois](../evidence/maciota-garagem-portamalas-20261021/depois-garagem-21x9.png), [escada antes](../evidence/maciota-garagem-portamalas-20261021/antes-escada-16x9.png), [escada depois](../evidence/maciota-garagem-portamalas-20261021/depois-escada-16x9.png). Sala: ~49%→~84% da largura em 16:9, ~36%→~63% em 21:9.
- [x] Colisão dirigida: `tests/test_maciota_world.gd` (parede nova bloqueia, linha da parede antiga aberta, ponto/rota/caixa da escada livres, sala inteira no quadro em 4:3/16:9/21:9) e `test_harbor_service_roofs.gd -- --roof=maciota` na Main renderizada: 53 verificações, zero falhas (rota autorada andando, subida, telhado, save, restauração fria, descida, regras sem armas).
- [x] Garagem/transferências: `test_garage_vehicle_transfer` (11), `test_garage_driver_restore` (34), `test_maciota_transition_safety` (37), `test_maciota_exterior_access` passaram.
- [ ] Oclusão de Dante/NPC atrás dos móveis novos (estante, motor, pilhas de pneus) sem teste dedicado; só inspeção visual das fotos.
- [ ] Desempenho: ~50 malhas novas na sala, sem luz nova; sem comparativo em export release. Pendente.
- [ ] `test_v2_session.gd` não conclusivo: parou em "Integrated session becomes playable" (limite de 600 quadros de física para iniciar), antes de entrar na garagem.

## Ferramentas de interiores no editor — 21/10/2026

Escopo aditivo: **0 lugares físicos novos / 0 interiores novos / 0 migrações de ambiente / 0 certificações integrais**. Foram acrescentadas ferramentas para escolher salas/andares e editar seu conteúdo em um rascunho. O mundo oficial não foi reformado como demonstração; as contagens e pendências das revisões abaixo permanecem intactas.

- [x] Fluxo completo do editor renderizado: `tests/test_world_editor_interior_flow.gd` cobre criar, mover, redimensionar, copiar, excluir/desfazer, trocar sala/piso e salvar em arquivo isolado. [Execução registrada](../evidence/editor-workspace-20261021/final-test_world_editor_interior_flow.log): 31 verificações, zero falhas, `.err` vazio. Aprova esse fluxo dirigido, sem certificar reformas ou todos os ambientes.
- [ ] Comparação de fotos antes/depois de uma reforma autorada: nenhuma sala oficial foi reformada por esta ferramenta nesta etapa; não há nova aprovação visual de ambiente.
- [ ] Entrada/saída, spawn, circulação com Dante/NPC e recuperação da sessão para uma reforma: validar por sala efetivamente alterada. O gate de entrada/saída/morador/recompensa não substitui esse percurso.
- [ ] Colisão e oclusão de uma reforma em gameplay: os testes do adaptador são evidência dirigida, sem certificação automática de cada móvel ou de todos os interiores.
- [ ] Desempenho renderizado por ambiente: comparação integral pendente. A [prévia do banco, andar 0](../evidence/editor-workspace-20261021/interior-final-interior-harbor_bank-floor0.json) registrou 60,002 FPS estáveis (30 s, p95 16,705 ms, p99 16,729 ms, máximo 17,373 ms), mas carga de 12.080 ms e pico de 732 ms; o log do benchmark teve aviso de antialiasing corrigido depois. Os fluxos renderizados posteriores de interior (31 verificações) e prévia inválida (10) passaram com diagnóstico limpo; isso não substitui um comparativo de gameplay por ambiente. Essa amostra não certifica entrada, gameplay ou outros interiores. A vista global 2D de Harbor atingiu 60,002 FPS em 30 s/1.801 frames (p95 16,69 ms; p99 16,80 ms; máximo 17,18 ms; zero frames acima de 33,3/66,7 ms). Carga síncrona inicial de 1.592,89 ms e primeira reconstrução de 477,89 ms seguem pendentes. Essa [amostra do editor 2D](../evidence/editor-workspace-20261021/global2d-retained-harbor.json) não certifica FPS ou entrada dos interiores.
- [ ] Regras da garagem em uma reforma efetiva: manter invulnerabilidade dos moradores, área sem armas e inventário preservado; não confundir a prévia sem atores com teste dessas regras em gameplay.

A ferramenta mantém alterações por interior e andar, valida a posição protegida antes do salvamento e preserva o histórico/rascunho. Cada reforma posterior continua sujeita ao [padrão de interiores](interior-standard.md) e ao [contrato físico e de profundidade](interior-physics-and-depth.md).


## Casas de Santa Lua — 19/10/2026

Escopo: **4 lugares físicos / 4 interiores existentes / 0 novos / 0 aprovações integrais / 4 em andamento / 4 restantes para aprovação**. IDs `santa_lua_home_1` a `santa_lua_home_4`; não somar novamente ao inventário. Reforma localizada no gerador dessas casas: reboco, marcenaria, tecidos com bordas suaves, mesas ovais em Rosa/Lia, cortinas com dobras, quadros/cestaria, rodapés e recorte lateral da apresentação. Vigas centrais substituídas por verga traseira para deixar atores legíveis. Câmera, recompensas, posições de moradores e acessos mantidos.

- [x] Build `dotnet build Harbor.csproj --no-restore`: 0 erros/avisos. Godot 4.7.2 .NET, Vulkan Mobile, RTX 4060 Laptop.
- [x] Física: **384 verificações, zero falhas** em `tests/test_desert_village_homes.gd`. Dante/morador, cápsula, apoio, spawn/saída/recompensas, faces de sólidos, cama e desativação. Inclui raios a 1,8 m nas paredes laterais recortadas, cuja colisão permanece inteira. [Log](../evidence/desert-homes-physics-final-20261019.log).
- [x] Geometria estática, recursos arredondados e textura compartilhados em cache; juntas do piso agrupadas em um MultiMesh por sala, sem novos loops por frame ou fontes de luz.
- [x] Oclusão final: **224 verificações, zero falhas**, Dante e NPC antes/atrás/ao lado de mesas, cabeceiras e divisórias, com controles positivos. Baseline: 224 verificações aprovadas. Primeira versão oval revelou que as sondas traseiras das mesas ficavam perto da ponta, com visibilidade acima do critério; sondas movidas para perto da borda traseira, mantendo cápsula livre e os limiares originais. [Baseline](../evidence/desert-homes-depth-before-20261019.log), [primeira versão](../evidence/desert-homes-depth-after-20261019.log), [execução final](../evidence/desert-homes-depth-final-20261019.log). Cobertura dirigida; não certifica todo móvel em movimento integrado.
- [ ] Entrada/saída/reentrada e save na Main: inicialização parou antes de `ready_for_play` nas duas tentativas; segunda já usa fixture por empurrão (`tests/desert_home_finish_session.gd`) e `--ignore-error-breaks`. Interrompidas apenas as instâncias desta tarefa. [Baseline Main](../evidence/desert-homes-before-20261019.log), [Main final](../evidence/desert-homes-session-final-20261019.log). A existência dos quatro acessos no catálogo não comprova travessia jogando; a queixa de casas inacessíveis permanece sem confirmação/correção certificada.
- [ ] Performance: sem comparativo antes/depois; nenhuma aprovação. Alvo provisório 60 FPS/16,67 ms, p95/p99 >5% exige confirmação. Havia também outra sessão renderizada durante a tentativa final; processos alheios preservados. Capturas da fixture não são benchmark.
- [x] Fotos reais das quatro salas revisadas na câmera alinhada da fixture. Exemplo de Rosa: [antes](../evidence/desert-homes-finish-20261019/before/santa_lua_home_1-player-natural.png), [depois](../evidence/desert-homes-finish-20261019/final/santa_lua_home_1-player-natural.png). Demais fotos e máscaras em `evidence/desert-homes-finish-20261019/final/`. A fixture usa ambiente de teste, não certifica iluminação temporal da Main.
- [ ] Revisão de movimento integrado, retorno e certificação completa dos acessos: pendentes pelo bloqueio de inicialização acima.

## Lanternas pessoais nos boeiros — 17/10/2026

Escopo: **2 lugares / 2 interiores existentes examinados; 0 lugares novos e 0 migrações integrais concluídas**. Correção do equipamento compartilhado, sem mudar câmera, geometria, circulação ou spawn. Contagens globais de interiores certificados permanecem inalteradas.

- [x] Cinto: removida a sombra excessiva do próprio portador apenas nas lanternas pessoais; paredes, escadas, NPCs e sombras externas preservados. Feixe da arma ampliado e comando compartilhado corrigido.
- [x] Main/.NET renderizada: entrada/saída de `harbor_sewer` e `sewer_market`, restauração exterior, ambas as lanternas pelo comando de entrada, arma guardada e restrições da garagem.
- [x] Oclusão da luz por parede e iluminação radial; regressão de camadas/reflexos. Sem mudanças físicas; auditoria integral de colisão/mobiliário não realizada nesta tarefa.
- [x] Comparação renderizada de 30 s/local: cerca de 144 FPS, p95 final 9,112/9,642 ms, nenhum frame acima de 33,3 ms, sem regressão além da tolerância de 5%.
- [ ] Certificação temporal completa: sequências de 30 s/local analisadas, mas gravação com intervalos de até 110 ms limita defeitos de um frame; sem aprovação universal de flickering.
- [ ] Suíte geral de combate: fixture/expectativas divergentes, detalhadas no relatório; não aprovada nesta revisão.

[Resultado, fotos reais antes/depois, métricas e limitações](../artifacts/flashlight-fix-20261017/resultado.md). Não recertifica o interior inteiro nem outros mapas.

## Ferrovia costeira e acessos de Harbor — 15/10/2026

Escopo: **2 acessos de Harbor compactados / 1 vagão existente reformado / 0 lugares ou interiores novos**. O acabamento de corrimãos compartilhado alcança as quatro estações; a redução dos lances de 14 para 8 m fica restrita a Harbor. Inventário global e número de interiores certificados inalterados; nenhuma nova certificação integral.

- [x] Circuito Harbor Central → Northgate → Harbor Central fechado junto às margens; travessia norte na borda do terreno, fora dos quarteirões. Northgate deslocada 15 m ao norte para alinhar a chegada. Portão da campanha e ramais regionais preservados.
- [x] Rede: **112 verificações**; reservas locais: **20 verificações / 1.402 amostras**. Saves nas antigas escadas, passarelas e parte removida da plataforma retornam ao acesso apoiado; posições ainda apoiadas são preservadas.
- [x] Main renderizada/.NET: **740 consultas / zero interseções** da composição ao longo dos dois lados do circuito; **13 verificações**, incluindo subida e descida dos dois acessos com Actor real, sem teleporte durante a caminhada. [Log](../evidence/railway-coastal-20261015/clearance-final.log), [resultado e fotos de percurso](../evidence/railway-clearance-32468-8258777/clearance.json). Rodadas anteriores encontraram encosta, prédio salvo e contato na ponta da plataforma; foram corrigidos antes da rodada aprovada.
- [x] Trem: teto abaulado com colisão convexa correspondente, bogies, materiais separados e texturas locais, sem deslizamento no movimento. Modelo **10 checks**; câmera de embarque **6 checks**; UI **25 checks**. Externa única de tamanho ortográfico 36; seleção interna removida e snapshot de restauração preservado.
- [x] Viagem produtiva e recuperação: **162 verificações** na Main/.NET, incluindo volta pelo circuito, câmera e controles restaurados, pausa, cancelamento, plataforma ocupada, bloqueio do deserto antes da missão final, desbloqueio pelo evento de campanha e save/load real em arquivo isolado. [Log](../evidence/railway-coastal-20261015/runtime-final.log).
- [ ] Comparação de desempenho: duas tentativas posteriores interrompidas ao detectar jogos iniciados por sessões concorrentes; processos alheios preservados. Fotos físicas não são benchmark nem certificação temporal de iluminação; nenhuma luz foi acrescentada nesta reforma.

- [x] Pilares e streaming: **96 verificações**, iniciando por Harbor, montanha e deserto, sem falhas após disponibilização das regiões. [Log](../evidence/railway-coastal-20261015/pillars-final.log).
- [ ] Cenário de fundo: superfícies claras/com aparência ausente na borda da montanha e no convés de Santa Mare durante a volta. Causa ainda não isolada; arquivos de cenário com alterações concorrentes preservados. Não considerar aprovação visual integral.

Depois: [escadas](../evidence/railway-coastal-visual-20261015-harbor_central-50660-16119661/stairs-west.png), [trem junto à água](../evidence/railway-coastal-visual-20261015-harbor_central-50660-16119661/coast-harbor_north-035.png), [viagens e chegadas](../evidence/railway-coastal-visual-20261015-harbor_central-50660-16119661/metrics.json). As duas chegadas terminaram com apoio no piso, câmera restaurada e controles liberados.

Antes: [acesso na Main](../evidence/railway-coastal-before-20261015-harbor_central-20272-6625916/station.png). [Traçado derivado das rotas finais](../evidence/railway-coastal-20261015/circuit-final-map.png) é um diagrama, não uma captura de gameplay. Não recertifica escadas da montanha/deserto, iluminação global ou interiores fora deste escopo.

## Pisos dos acessos de Harbor — 13/10/2026

Escopo: **6 lugares físicos existentes / 0 interiores reformados / 0 lugares novos**:
Bay Medical, Westgate Garden, Quayside, Canal North, Ammu-Nation e casa do zelador. Inventário de interiores
inalterado. Retirado o acabamento urbano oculto sob fundações, soleiras e vagas
externas; cotas dos acessos preservadas. Os dois pavimentos do hospital foram
particionados e receberam apoio físico próprio, incluindo a subida de pedestres.

- [x] Reserva visual e apoio dos dez pontos de piso e travessia real dos dois
  níveis do hospital: 24 verificações aprovadas em `evidence/harbor-facade-ground-walk.log`.
- [x] Censo geométrico frontal sem redução da área coberta: comparação de
  `evidence/harbor-ground-layers/rebuild-upper-faces.json` com
  `evidence/harbor-ground-layers/rebuild-upper-reserved.json`.
- [x] Fotos atuais e sequência de movimento dos acessos do hospital e das três
  residências: `evidence/harbor-rebuild-20261013/access-final/` (dez quadros por
  local, posições e apoio físico em `frames.json`). Pisos contínuos e soleiras
  preservadas na revisão visual. Captura de PNG interrompe o frame e não mede FPS.
- [x] Medição integrada de Harbor: três cenas comparadas em 1280×720 e sete
  cenas atuais em 3440×1440, com 30 s estáveis por cena. Amostras, percentis,
  aquecimento e limites em `evidence/harbor-rebuild-20261013/validation.json`.
  Esta cobertura não equivale a benchmark individual dos seis interiores.
- [ ] Comparativo visual anterior dos seis acessos e recertificação completa
  de entrada/saída e oclusão dos interiores: não cobertos por este ajuste de
  pavimentação exterior; nenhuma nova certificação integral de interior.

## Retorno de Último Abrigo — APK 0.3.3 — 12/10/2026

Correção localizada em **1 acesso exterior existente**, sem novo lugar ou
interior. O retorno fica 1,5 m mais adiante no mesmo caminho, fora do aquecedor.
Entrada e saída físicas, controle, câmera, cápsula livre e ausência de loop
passaram no lote de 66 verificações de oito acessos representativos.
Registro: `docs/android-033-validation.md` e relatório da suíte iniciado em
UTC 16:55:11 em `evidence/test-suite/`. Não certifica novamente a decoração,
oclusão completa, iluminação ou performance; contagens de migração inalteradas.
Fotos comparativas específicas deste acesso permanecem pendentes.

## Lanterna nos esgotos — 12/10/2026

Escopo: **7 lugares físicos / 7 interiores existentes; 0 novos; 0 aprovações completas**. Iluminação compartilhada, sem migração de arquitetura, câmera ou acessos. Não somar novamente ao inventário. Detalhes em [lanterna-esgotos-20261012.md](reviews/lanterna-esgotos-20261012.md).

- [x] Ambiente escuro independente do sol; superfícies iluminadas preservadas pela camada de escuridão; sombras reais da lanterna e bloqueadores das paredes rebaixadas.
- [x] Contrato de ativação, saída e descarregamento: 12 verificações. Física de jogador/NPC, spawn, sólidos e coleta nos sete esgotos: 312 verificações.
- [x] Oclusão de jogador/NPC: 105 verificações aprovadas na fixture de profundidade corrigida pela sessão concorrente. Arma real, entrada/saída e iluminação restaurada no original e no Mercado; gravações de 30 s por lugar, com limites de cadência descritos no relatório.
- [x] Renderização de objetos expostos e bloqueados por parede em `harbor_sewer` e `sewer_market`: 6 verificações de pixels; ganho de iluminação atrás da parede igual a zero nos dois cenários.
- [ ] Aprovação global dos sete interiores: cobertura visual e temporal dos demais lugares, regressão de performance antes/depois e fotos anteriores à implementação pendentes.


## Galeria da Rodovia — acesso, câmera e contenção de granadas — 11/10/2026

Escopo deste lote: **1 lugar físico / 1 interior existente; 0 novos; 0 aprovações completas; 1 em andamento / 1 restante para aprovação**. Não somar novamente ao inventário histórico. Reforma restrita a `desert_under_culvert`; carregamento das definições no controlador compartilhado corrige a consulta de retorno dos quatro subterrâneos do deserto.

- [x] Câmera ortográfica de 32,8 para 13,5, acompanhando Dante horizontalmente com limites. Spawn central livre e saída oeste distinta do spawn permitem voltar imediatamente.
- [x] Grade física articulada abre ao caminhar contra a folha; estar parado não abre. Entrada, percurso, saída, reentrada e saída imediata pela Main renderizada/.NET passaram sem botão de interação e com controle restaurado. [Log](../output/culvert-access-validated.log). A apresentação de descida continua da porta já aberta, sem voltar à aproximação nem repetir a abertura.
- [x] Paredes físicas de 3,4 m e laje de teto a 3,2 m preservam a contenção mesmo onde a câmera recorta a malha. Cinco granadas produtivas arremessadas contra os quatro lados e teto permaneceram dentro e detonaram. Cápsula varrida, corredor, saída e posições autoradas das três recompensas aprovados. [Log](../output/culvert-enclosure-final.log).
- [x] Catálogo, moradores, recompensas e alcançabilidade dos quatro subterrâneos: **75 verificações, zero falhas**. [Log](../output/culvert-catalog-final.log).
- [x] Profundidade e colisão dirigidas de jogador/NPC na bancada: **16 verificações, zero falhas**, frente/atrás/lado com controle positivo de visibilidade. [Log](../output/culvert-depth-final.log), [máscaras](../output/culvert-review-20261011/depth/). Fixture de render separada; não certifica todos os móveis, combate ou cenários de recuperação.
- [x] Revisão visual: piso de concreto, areia baixa, detalhes do tapete, grade, carcaça, gaiolas e portal externo. Luz de entrada pelas grades estabilizada, preservando fogo intencional. [Antes, imagem enviada pelo usuário](../output/culvert-review-20261011/00-user-before.png), [interior depois](../output/culvert-review-20261011/03-interior-4.png), [acesso externo depois](../output/culvert-review-20261011/01-exterior.png), [retorno](../output/culvert-review-20261011/04-return.png). Não há baseline externo anterior à edição.
- [ ] Performance antes/depois e evidência temporal contínua de iluminação: **não aprovadas**. Sessão do usuário permaneceu aberta; nenhum benchmark concorrente foi usado. Contador de FPS nas fotos não substitui medição. Meta provisória 60 FPS/16,67 ms, comparação p95/p99 com investigação de variação acima de 5%, ainda pendente.
- [ ] Cobertura integral de móveis/oclusão, persistência, combate integrado com moradores, morte/resgate e restauração de save: não certificada neste lote. Build `Harbor.csproj` passou; validação realizada em Godot 4.7.2 .NET, Vulkan Mobile, RTX 4060 Laptop. Saves de teste isolados e `--no-save`.

## Salto, quedas e lojas protegidas — 10/10/2026

**0 lugares novos / 0 interiores novos / política em 26 lugares existentes e 31 pavimentos internos autorados / 0 concluídos integralmente neste lote.** Mantidas as contagens gerais; não somar novamente esses ambientes. A apresentação/arquitetura das lojas não foi reformada. [Implementação, fotos reais, cobertura e pendências](reviews/salto-quedas-e-lojas-20261010.md).

- [x] Lojas: bloqueio de armas, inventário preservado e admissão sem polícia verificados nos 26 IDs por contrato; NPCs usam proteção de dano comum e herdada da sala.
- [x] Curitiba Cellar na Main: Luísa/Nelson protegidos, entrada durante perseguição recusada, save isolado realmente gravado, restauração fria e saída — 15 checks. Fotos reais vinculadas no relatório; não houve foto anterior à implantação da política.
- [x] Salto: 23 checks físicos de cápsula, teto, mureta, mãos apoiadas, queda baixa, dano único/colete, recuperação, queda fatal e respawn; teclado real na Main — 8 checks.
- [x] Coberturas: ação de salto por E removida. Cobertura baixa — 13 checks; serviço Fuel — 48 checks na Main renderizada, incluindo circulação, câmera, persistência e queda até o piso real. Queda alta e pose de impacto verificadas com a falha histórica da fixture de teclado preservada e corrigida em rodada separada.
- [ ] Demais lugares/coberturas: circulação física, oclusão e apresentação temporal completas não certificadas por esta amostra. A cobertura lógica dos 26 IDs não aprova automaticamente seus interiores.
- [ ] Performance: comparação exclusiva e com carga equivalente pendente. Amostras renderizadas antes/depois de 30 s registradas, mas há sessões concorrentes e diferença de população/tráfego; não aprovar FPS por essas médias.
- [ ] Garagem: driver restore / vehicle transfer excederam o prazo de inicialização. Maciota e mecânico mantêm a proteção permanente; a seleção de recompensas passou, sem certificar as duas transições pendentes.

## Portas por empurrão e remoção do marcador — 10/10/2026

**0 lugares novos / 0 interiores novos.** Alteração do controlador compartilhado das entradas a pé e remoção global do desenho do retângulo laranja. Não altera a contagem de interiores nem certifica o inventário completo. A orientação de abrir por proximidade foi substituída pelo pedido do usuário: caminhar contra a porta bem de perto, com animação de empurrar, sem exigir E.

- [x] Compilação `Harbor.csproj` no ambiente Godot 4.7.2 .NET: sem erros ou avisos.
- [x] Fachadas de serviços: 32 verificações físicas aprovadas em `tests/test_service_facade_physics.gd`.
- [x] Porta física + Dante: 10/10 finais em `tests/test_door_push_physics.gd`; parada próxima/encostada, cápsula bloqueada, abertura animada, alcance da mão esquerda, passagem varrida, manutenção aberta com corpo no vão, fechamento ao afastar, bloqueio modal, altura e troca de fachada sem herdar abertura. Fixture dirigida, sem aprovação de FPS ou substituição da cena Main. [Log](../output/door-push-20261010/physics-final.log).
- [x] Fluxo dirigido na Main renderizada/.NET: **56/56**, loja de roupas, delegacia, supermercado e Ammu-Nation. Aproximação/parada não abrem; gesto e alcance da mão esquerda, porta animada, admissão, controle, saída e fechamento aprovados nesses quatro acessos. Ajustes: esperar a folha abrir antes da transição, usar intenção de movimento mesmo com velocidade removida pela colisão, alinhar o limite das lojas de armas ao plano físico da porta. [Log final](../output/door-push-20261010/validated-final.log). Execução com `--no-save --skip-arrival --no-prewarm --capture`; ainda registrou erro de compilação externo em `runtime/desert/drag_meet/TrackParticipantDamage.gd`, portanto não aprova inicialização integral ou sistemas do deserto. Tentativas anteriores tiveram erros concorrentes em CobraModel/ZooAnimal.
- [ ] Fotos de abordagem/empurrão capturadas e inspecionadas em `output/door-push-20261010/`; retângulo ausente e gesto presente. Sem baseline visual anterior à alteração; marquise da Ammu-Nation limita a leitura da porta na captura. Não contar como migração visual concluída nem prova de oclusão integral.
- [ ] Performance comparativa: não medida; outras sessões Godot renderizadas e testes concorrentes impedem baseline comparável. Nenhuma redução de qualidade, iluminação ou resolução.
- [ ] Cobertura de todas as entradas, casas bloqueadas, interiores, NPCs e oclusão: não auditada integralmente neste lote. Geometria e salas existentes preservadas; não estender a cobertura amostral ao jogo inteiro.

## Harbor — interferência entre fachada e interior preparado — 09/10/2026

**0 lugares novos / 0 interiores novos / correção no shell compartilhado dos prédios já inventariados; não somar novamente nem considerar o inventário inteiro certificado.** Recuo externo de 2 cm preservando faces internas, altura, abertura de porta e collider do piso. [Investigação e evidências](reviews/harbor-performance-20261009.md).

- [x] Reprodução do defeito no MarketHall com círculo transparente desligado: 340 frames contínuos / 30 s, parado e andando, alternância clara/escura nas faixas inferiores das fachadas.
- [x] Contrato geométrico: 92 verificações, quatro footprints/entradas/andares; baseline falhou na separação externa e versão corrigida passou, preservando planos internos e piso de colisão.
- [x] Comparação temporal final no MarketHall: 348 quadros / 30 s, sem lacunas, alternância clara/escura não reproduzida após correção. [Antes/depois](../evidence/harbor-regression-20261009/market-facade-flicker-before-after.png). Captura perturba a cadência e não certifica FPS.
- [x] Validação dirigida no MarketHall e Torque: 528 verificações renderizadas de física/profundidade (Dante e NPCs), mais 69 na cena Main de entrada, circulação, cobertura, save isolado, restauração e saída. Demais edifícios não exercitados nesta rodada.
- [ ] Performance estável: não aprovada. Gravações por frame não são benchmark; rodada limpa anterior ainda apresentou picos.

## Harbor — Umbra ampliada — 08/10/2026

**1 lugar existente / 1 interior distinto reformado / 0 interiores novos / 0 concluídos integralmente / 1 em validação / 0 restantes para implementar neste lote.** [Implementação, fotos e limites](reviews/umbra-expansion-20261008.md).

- [x] Planta 18 × 35 m, galeria superior, duas escadas físicas, banquete, cripta, biblioteca, berço, relógio e cinco novas estações de susto; fantasma antigo articulado. Primeira pessoa, ambiente bem escuro e lanterna acompanhando o olhar.
- [x] Física final **63/63**, jogador e NPC; Main/.NET **68/68**, percurso, alturas, pausa, saída/reentrada e oclusão separada com controles positivos. Fotos reais antes/depois vinculadas no relatório.
- [x] Entrada original, saída pelo indicador compacto, dois segredos e ausência de dano das atrações preservados. Sem passes de render por criatura.
- [x] Gravações: entrada com 625 frames; salão, galeria e cripta com **1.723 frames / 89,930 s**, sem lacunas. A tentativa extra passou após correção de parser alheio; fotos e pares dirigidos inspecionados.
- [ ] Desempenho isolado e estabilidade temporal integral: concorrência impediu baseline comparável e houve edições em fontes compartilhadas durante as capturas. Falta revisão integral das sequências, cobertura dedicada da aranha/guardião do relógio e escuta do áudio. Não contar como certificado nem usar FPS das fotos como benchmark.

## Harbor — Fagulha — 07/10/2026

Atualização de 12/10/2026: ajustadas a pose de acomodação no piso após sair, as mãos dos moradores e a jogabilidade de corrida, pinball e luta. Os quatro jogos receberam trilhas próprias e efeitos acionados pelas ações. Por pedido do usuário, esta atualização não executou testes nem capturas/benchmark; entrada/saída, poses, áudio, colisão/oclusão e desempenho da revisão permanecem pendentes de validação no jogo. Não altera as contagens de lugares nem certifica novamente os checks históricos abaixo.

**1 lugar físico novo / 1 interior distinto / 0 concluídos / 1 em validação / 0 restantes para implementar neste lote.** Loja entre Boa Praça e Ammu-Nation, sem substituir interiores existentes. [Implementação e evidências](reviews/fagulha-arcade-20261007.md).

- [x] Quatro fliperamas jogáveis e duas máquinas ocupadas por moradores humanos. Câmera ortográfica alinhada, sólidos completos, sala sem SubViewport, fachada somente com nome próprio e indicador compacto compartilhado.
- [x] Regras dos jogos **85/85**, incluindo lançamento natural do pinball; eventos reais de teclado/gamepad **32/32**; contratos físicos/de profundidade e ciclo das luminárias finais **261/261**. Limites dos parsers concorrentes registrados no relatório.
- [x] Main final **92/92**: entrada, partidas, saída/reentrada, recordes em arquivo, interrupções e retorno à mesma fachada. Carga fria e recompensa persistente sem duplicação **26/26**. Tentativas corrigidas e limites detalhados no relatório.
- [x] Fotos reais antes da ocupação da parcela e depois da loja, salão e quatro jogos, vinculadas no relatório.
- [x] Iluminação noturna final: **1.709 frames contínuos / 30,989 s**, parado e andando; zero candidatos a flicker nas seis regiões estáticas e sem piscadas/popping nos pares inspecionados. Evidências e limites no relatório.
- [ ] Comparação isolada de performance: diagnóstico final renderizado p95 rua **11,842 ms**, salão **10,900 ms**, corrida **10,461 ms**, mas houve outros processos Godot e alterações em arquivos compartilhados durante a execução. Não certifica ausência de regressão; não contar como concluído enquanto o comparativo obrigatório estiver pendente.

## Harbor — interações sociais dos moradores — 07/10/2026

**0 novos lugares / 0 novos interiores.** Componente aplicado aos moradores ativos dos prédios de exploração já inventariados abaixo (59 edifícios / 119 pavimentos internos). Não somar novamente esses lugares. **1 edifício / 4 pisos internos + cobertura exercitados nesta rodada; validação individual das interações nos demais prédios e performance comparativa permanecem pendentes.** [Escopo e evidências](building-social-interactions-20261007.md).

- [x] Reações e rotina: 40/40; felicidade, conversa, irritação, medo, acalmar, pausa e retorno ao trabalho. Mira exige arma, percepção e tempo; denúncia usa testemunho real e não duplica a mesma ameaça.
- [x] Interface e ciclo de vida: 37/37; prioridades, parede/andar, foco, controles remapeáveis, pausa, perigo externo, morte, troca de sala e descarregamento. Painel no lado oposto aos interlocutores.
- [x] Main/.NET: 33/33 no Customs, entrada/saída andando, aproximação contornando móveis, conversa pelos botões, denúncia com atraso, retorno ao posto e limpeza. [Conversa no jogo](../evidence/building-social-session-191684-7920731/02-joke-01.png). Nenhum save pessoal utilizado.
- [x] Colisão e oclusão verificadas separadamente: 581/581 nos cinco níveis do Customs, controles positivos de visibilidade e cápsulas apoiadas. Proteções da garagem preservadas: recompensas 47/47, restauração 34/34, transferência 11/11.
- [ ] Comparação de frame time: baseline inválida por dependências em edição concorrente e outras sessões Godot ativas. Capturas desta rodada não aprovam FPS. Não ampliar a cobertura amostral aos demais locais.

## Harbor — Curitiba Cellar — 07/10/2026

**1 novo lugar físico / 1 interior independente / 0 certificados integralmente / 1 em validação / 0 lugares restantes neste pedido.** Acréscimo de um estabelecimento às contagens históricas dos outros lotes, preservadas. Loja entre Union e Fuel, na Foundry Avenue, com Nelson no balcão e Luísa no financeiro. [Implementação e evidências](reviews/curitiba-cellar-20261007.md).

- [x] Visual autorado com referência ao catálogo oficial: oito rótulos de Grécia, Brasil, Portugal e Chile, adegas, balcão de degustação, escritório e materiais de madeira/pedra/latão. Fachada somente com o nome próprio. [Lote antes](../evidence/curitiba-cellar-before-exterior-156308-6042214/exterior.png), [fachada no jogo](../evidence/curitiba-cellar-session-119372-5797896/01-exterior.png), [interior no jogo](../evidence/curitiba-cellar-session-119372-5797896/02-interior.png), [compra](../evidence/curitiba-cellar-session-119372-5797896/03-shop.png). Não existia interior anterior neste lote.
- [x] Física e profundidade separadas: **150/150** verificações de sólidos, cápsulas, apoio, interações e varreduras de Dante/visitante; **26/26** de oclusão renderizada com controles positivos. Atores reais compartilham o espaço dos móveis. Logs e imagens no relatório.
- [x] Fluxo Main/.NET: **61/61**, com caminhada, entrada/saída pelo acesso real, controle, compra pela interface, conversas, presente único, quatro goles, cura, saída bêbado, save isolado em disco, recarga fria, reentrada, pausa e morte/resgate produtivos. Estoque preservado e embriaguez removida no resgate. O controlador compartilhado mudou em outra sessão durante esta captura; relatório diferencia fontes carregadas e fontes no disco, sem declarar estabilidade inexistente.
- [x] Estado e regressões: vinho/economia **71/71**, controles alcoólicos **13/13**, inventário **11/11**, garagem **47/47** e câmera aprovada. Nenhum save pessoal usado.
- [x] Iluminação temporal diurna do interior: **901 frames / 30,005 s**, sem lacunas no contador de frames, sem candidatos a flickering nas regiões estáticas analisadas e nos pares inspecionados. Duas fontes locais sem sombras; sem SubViewport por ator. Captura temporal não usada como benchmark, cobertura limitada à loja no horário/clima testados.
- [x] Luísa: **24/24** verificações dirigidas da pose e reação produtiva. Teclado ao alcance dos dedos; ela levanta sob ameaça, deixa a cadeira sólida no posto, volta e retoma a digitação. Visibilidade, morte e descarregamento verificados. [Contato real das mãos](../evidence/curitiba-cellar-luisa-155424-5399948/02-seated-hand-contact.png), [reação/colisão/retorno](../evidence/curitiba-cellar-luisa-51592-5602394/report.json).
- [x] Medições renderizadas: exterior antes/depois p95 **10,754 → 10,641 ms**, p99 **13,518 → 13,345 ms**, sem regressão observada nesse cenário. Interior com o ajuste final de Luísa: p95 **3,985 ms**, p99 **5,205 ms**. Configuração normal: 60 FPS/VSync, média **59,999 FPS**, p95 **19,567 ms**, p99 **20,840 ms**; essa média não certifica cada frame dentro de 16,67 ms. Janelas estáveis de 30 s, zero frames >33,3 ms nesses três cenários. [Confirmação e amostras brutas](../evidence/curitiba-cellar-after-confirm-153652-5791859/report.json), [foto final em Main](../evidence/curitiba-cellar-after-confirm-153652-5791859/confirm-interior.png).
- [ ] Certificação comparativa do custo da embriaguez: a confirmação iniciou isolada, mas outra conversa reiniciou testes de pesca durante as janelas bêbado/recuperado; população/tráfego também variaram. Fontes monitoradas permaneceram estáveis. [Auditoria de processos](../evidence/cellar-confirm-processes.jsonl). Não concluir regressão nem ausência de regressão causada pelo álcool. Picos de aquecimento de **86,484 ms** e **78,129 ms** separados do regime estável, sem atribuição causal. Implementação funcional concluída; certificação integral continua em validação por esta pendência, sem ampliar a conclusão a outros horários/climas/cidades.

## Montanha — avião dos Cobras — 07/10/2026

**Complemento do entorno:** lago, margens, acampamento e ilha integrados ao material efetivo de Mountain, com cargas, bote, bancos e pedras detalhados. Zero lugares/interiores novos; não somar novamente o avião. **38/38** no Main renderizado para apoio, caminhada, NPC e retorno de streaming; **80/80** de calor/fogueira. Sequência contínua de dia/noite e benchmark local registrados em [relatório do entorno](reviews/cargo-lake-20261007.md), com limites explícitos de inspeção e tráfego variável. [Foto geral final](../evidence/cargo-plane-lake-after-82424/airframe-closed.png).

**1 lugar físico existente / 1 compartimento acessível reformado / 0 lugares novos; 1 reforma concluída no escopo local / 0 em andamento / 0 restantes neste lote.** Preservar as contagens históricas de outros mapas. Não equivale a certificação global da montanha. [Relatório, limites e evidências](reviews/cargo-plane-20261007.md).

- [x] Fuselagem facetada, nariz, asas danificadas, motores/hélices, cauda T e identificação gráfica dos Cobras, sem textos decorativos nem novas luzes. Fotos reais [antes](../evidence/cargo-plane-before-153176/starboard.png), [exterior final](../evidence/cargo-plane-after-124360/airframe-closed.png) e [corredor final](../evidence/cargo-plane-after-124360/cargo-open.png).
- [x] Recorte do teto/lateral e câmera elevada localmente, com restauração na saída/reentrada e gates de alvo/câmera. **52/52** no Main .NET: caminhada rampa→carga→cockpit, jogador/NPC, sólidos identificados e controles positivos/negativos de oclusão em 14 vistas. [Resultados](../evidence/cargo-plane-final-97540/checks.json).
- [x] Som original de proximidade, sons reais de coleta, desaparecimento com liberação do sólido do baú, save e recibos sem duplicação: **30/30 integrados** e **20/20** de lifecycle de áudio. Regressões de câmera e recompensa PASS.
- [x] Carga fria após coleta, com Dante restaurado no antigo espaço do baú e apoiado no deck: [PASS](../evidence/cargo-plane-restore-107096/result.json). Disponibilidade aplicada antes da admissão; sem bloqueio, reaparecimento dos itens ou pagamento duplicado.
- [x] Comparativo renderizado de 30 s por versão, mesma rota/população/qualidade: p95 **10,791→10,450 ms**, p99 **13,684→13,374 ms**; sem regressão observada nesta amostra. Processos alheios na baseline e cobertura restrita registrados no relatório; não aprovar outros cenários por extensão.

Sem avaliação auditiva humana nem certificação do percurso completo cidade→lago, outras condições de clima/noite ou FPS global. Nenhuma alteração nas regras da campanha, ponte, garagem ou recompensas autoradas.

## Harbor — interiores contínuos e coberturas — 07/10/2026

**59 edifícios de exploração / 119 pavimentos internos / 59 coberturas, mais 24 coberturas em edifícios com interior existente.** Os 59 incluem os dois da leva anterior: 57 novos lugares de exploração e dois reformulados. Não somar pavimentos como novos lugares. O inventário deste lote reúne **83 edifícios**, sem alterar as contagens históricas de outros mapas. Implementação e correções funcionais/visuais concluídas no escopo validado abaixo; **certificação integral pendente da comparação isolada de performance**. [Inventário](harbor-interiores-por-levas.md) e [conteúdo](harbor-building-content-20261007.md).

- [x] Plantas físicas na parcela real, entrada caminhando sem marcador laranja, pavimentos com altura real e uma sala ativa. Serviços e gates existentes preservados; casa de Takeshi recebe porta física com o gate da missão.
- [x] Densidade proporcional à área: seis famílias, moradores, suprimentos, dinheiro e salas trancadas. A revisão das 237 fotos identificou sete compactos grandes pouco mobiliados; receberam zonas de uso em 13 pisos. [Contrato físico final, 1.598/1.598, oito prédios/25 níveis](../evidence/harbor-building-contract-33144-4284419/result.json), com o oitavo prédio como regressão, seguido da inspeção das 13 fotos Main finais. A passagem anterior com parser inválido foi descartada. Não declarar programas modulares como plantas exclusivas.
- [x] Revisão visual completa de Main: 59 exteriores + 119 pavimentos + 59 coberturas fotografados em `harbor-building-walkthrough-144964-5500560`. A rodada física renderizada teve 2.042 checks e duas falhas, ambas no cache da cobertura do editado `new_1790432139_406_2568146191`, obstruído por ventilação original. Também foram identificados recortes de fachada incompletos, viaduto/copa sobre áreas jogáveis e vila desativada dentro do Tonico. As correções foram verificadas nas rodadas dirigidas abaixo, incluindo posição acessível do cache, fachadas, câmeras, densidade, contexto urbano e trem em movimento. A rodada original é preservada como diagnóstico; a aprovação visual limita-se aos enquadramentos e sequências efetivamente inspecionados.
- [x] Dirigidos das correções: **811/811** em 21 prédios na [primeira rodada](../evidence/harbor-building-walkthrough-108380-5645232/result.json). A [rodada seguinte de 19 prédios/37 pisos internos](../evidence/harbor-building-walkthrough-19980-5577328/result.json) teve 761 checks e uma observação antecipada da atividade do porto, antes da próxima varredura de 0,25 s. O teste agora aguarda até 0,6 s por essa atualização, sem mudar a lógica de produto: [198/198 no dirigido de quatro prédios/20 níveis](../evidence/harbor-building-walkthrough-149476-5850955/result.json), incluindo o mesmo PortBuilding3. Esse dirigido também confirma o cache real do editado50, suas quatro fachadas internas e a coroa recuada do último andar do editado51. Entrada, piso, escadas, dinheiro, save, saída e restauração exterior passaram nesses casos.
- [x] Tonico: térreo, rooftop e carga fria mantêm vila visível, sólidos físicos ativos, frota estacionada e câmera correta. [Foto após carga fria](../evidence/harbor-building-walkthrough-19980-5577328/harbor_building_truckers_station_store-cold-roof.png). Porto: companhia, entorno e atividades próximas continuam ativos durante a exploração. Mantidos gates de visita e interação.
- [x] Contexto urbano: o índice usa a rotação real dos prédios editados, evitando lixo dentro da parcela; reservas de plataforma e rampas mantêm lixeiras/sacos fora do BRT. **756/756** contra as geometrias reais de prédio e estação, sem alterar vias ou colisores: [log](../evidence/building-context-transit-final-20261007.log). As fotos Main do editado48 e Torque confirmam portas legíveis com a órbita existente, BRT livre e pisos sem adereços intrusos. A primeira rodada de 83 checks foi invalidada por callbacks sobre nós liberados do novo tratamento do trem; depois da correção com referências fracas, a [repetição passou 83/83 sem erros](../evidence/harbor-building-walkthrough-60900-5413685/result.json).
- [x] Física das plantas: **11.773 checks / 59 edifícios / 178 níveis / zero falhas**, com jogador e NPC reais, apoio, corredores, móveis, patamares, recompensas e salas secretas. [Resultado](../evidence/harbor-building-contract-180184-4434147/result.json). Corrigida uma passagem indevida na junção de duas paredes por pilar físico, sem afrouxar a varredura.
- [x] Lockpick real **34/34**: consumo único, persistência, cancelamento, morte, retorno e desativação do CanvasLayer. [Log](../evidence/building-secrets-lifecycle-final-20261007.log).
- [x] Recuperação final **65/65**: morte antes/depois da troca de piso e durante preparação da entrada, resgate, câmera, controle, fachada, moradores, restauração do recorte ferroviário e nova visita. [Resultado](../evidence/harbor-building-recovery-3844-4363882/result.json). Substitui a passagem anterior de 62 checks com três verificações adicionais de limpeza da apresentação.
- [x] Oclusão renderizada por amostra, independente da colisão: **10 edifícios / 31 níveis**, abrangendo seis famílias, a menor e a maior parcela e a ala acessível do Foundry em L. Customs House, Union Apartments, Laundry, Cold Storage, Corner Diner, Aquarium, Maritime Museum, Foundry Lofts, PortBuilding4 e Market Hall. Jogador e NPC possuem controles positivos separados: frente/atrás de um sólido acessível nos pavimentos e visibilidade livre nas coberturas. Os controles ocultam somente a arquitetura, mantêm o ator e não alteram os limites de aceitação. [Amostra de oito edifícios](../evidence/harbor-building-contract-126988-5513881/result.json), [Laundry na rodada dirigida](../evidence/harbor-building-contract-54440-6719452/result.json). Na amostra, dois controles de Union 1 escolheram um sofá cujo assento baixo não cruzava os raios da câmera; foram substituídos por uma divisória acessível, sem mudança de produto ou tolerância. A [confirmação Union, 554/554](../evidence/harbor-building-contract-98320-6067575/result.json) substitui esses dois resultados. Isso não certifica todos os obstáculos nem a oclusão dos 59 edifícios.
- [x] Câmeras ajustadas de Customs, ColdStorage e Foundry East/West: **1.250/1.250** no [dirigido renderizado final de quatro prédios/13 níveis](../evidence/harbor-building-contract-42800-5410218/result.json), com controles separados de jogador/NPC e mobiliário presente. A tentativa anterior foi invalidada por erro de parser do Dressing, corrigido antes dessa passagem limpa. Main confirma a legibilidade de todos os pisos de Customs, ColdStorage e BridgeCourts em `harbor-building-walkthrough-108380-5645232`. O recorte ferroviário mantém a colisão e restaura a geometria no rooftop. O corte de copa de FoundryEast foi confirmado nas quatro fotos finais de `harbor-building-walkthrough-19980-5577328`, preservando tronco e árvore completa no exterior e cobertura. O helper de recorte/restauração passou **24/24** controles renderizados, incluindo streaming, cancelamento, destruição, tronco sólido e árvore distante intacta: [log](../evidence/building-sightline-foliage-final-20261007.log).
- [x] Fotografias naturais da amostra inspecionadas: [Cold Storage](../evidence/harbor-building-contract-126988-5513881/harbor_building_cold_storage-0-residents-active.png), [Foundry Lofts](../evidence/harbor-building-contract-126988-5513881/harbor_building_foundry_lofts-0-residents-active.png), [menor prédio portuário](../evidence/harbor-building-contract-126988-5513881/harbor_building_port_building_4-0-residents-active.png) e [Dante atrás da divisória Union](../evidence/harbor-building-contract-98320-6067575/harbor_union_apartments-1-Dante-behind.png). No Museu, o [zoom natural da visitante](../evidence/museum-resident-depth-48772-5363653/natural-close.png) e os [controles de máscara](../evidence/museum-resident-depth-48772-5363653/visitor-native-mask.png) confirmam mastros à frente das canelas e casco ocultando parte dos pés; corpo apoiado no piso e sem sobreposição. São capturas da geometria/atores reais em fixture renderizada, não prova da atmosfera noturna, do skyline ou de performance em Main.
- [x] Takeshi em Main renderizada: **32/32**, incluindo porta/varanda físicas, bloqueio antes da vitória, entrada caminhando na etapa 6, evento de missão, saída automática e revisita após conclusão. [Resultado final](../evidence/cobra-leader-walkup-156716-5641443/result.json), [limiar visível com recorte central da cobertura](../evidence/cobra-leader-walkup-156716-5641443/leader-open-threshold.png). Regressão da história **55/55**, incluindo lista, recompensa, save isolado, restauração e prêmio na garagem: [log](../evidence/building-leader-story-final-20261007.log). O teste passou a ler o texto realmente exibido no DialogueCard; duas gravações de voz ausentes continuam gerando avisos. A sala autorada de missão foi preservada; esses fluxos não certificam integralmente seus materiais, iluminação ou todos os móveis.
- [x] Queda física renderizada **13/13**, por caminhada através do vão, gravidade, dano ambiental, bloqueio de save no ar e limpeza. [Resultado](../evidence/harbor-rooftop-fall-81424-6157770/result.json).
- [x] Garagem: recompensas **47**, restauração de motorista **34**, transferência **11**, proteção de armas/personagens **37**, e SaveStore completo passaram. A gravação ausente de uma fala de guarda gera aviso no teste de motorista; não foi erro de física ou script.
- [x] Main dos **59 acessos / 119 pavimentos / 59 coberturas**, com entrada e saída caminhando, interação real da escada, percursos até dinheiro e portão do rooftop, save em arquivo próprio e retorno. [Matriz completa, 2.219 checks](../evidence/harbor-building-walkthrough-110908-4824484/result.json). A rodada registrou uma falha no waypoint artificial que exigia atravessar a chaminé de Foundry Terrace East em linha reta; o teste passou a encontrar um caminho com varreduras da cápsula real e caminhar por ele, mantendo a chaminé sólida. [Dirigido final, 39/39](../evidence/harbor-building-walkthrough-26548-4426758/result.json), incluindo save e carga fria, substitui aquele resultado. Não descartar a falha original nem alegar que os 2.219 passaram sem ressalva.
- [x] **24/24 coberturas complementares** percorridas em Main: admissão do proprietário, escada física acessível, altura/apoiamento, caminho até o portão, gravação efetiva, descida e retorno. São 667 assertions aprovadas nos trechos completos dos logs `service-roofs-core-recovery-20261007.log` (3 donos/84), `service-roofs-supported-fixed-20261007.log` (2/58), `service-roofs-fire-tail-20261007.log` (14/373), `service-roofs-vertice-northgate-20261007.log` (2/57) e `service-roofs-core-tail-recovery-20261007.log` (3/95). Os logs históricos retêm falhas dos casos seguintes; os dirigidos posteriores substituem somente esses casos. Corrigidos portão sobre sirene, volume físico indevido do batch Vértice e apoio da fixture na plataforma Union. A vila usa checkpoints independentes de paz/vida/colete entre casas; a porta continua provocando a reação armada normal. Autorização residencial/portuária e campanha concluída são condições da fixture, não atalhos de produto.
- [x] Coberturas de serviços: três mortes reais durante **subida, descida e salto**, com 21 assertions centrais de recuperação, além da preparação, no log `service-roofs-core-tail-recovery-20261007.log`. Tokens, controle humano, câmera, sala/flag e cápsula recuperados. O salto inicialmente podia devolver o controle ainda sobre a cornija; corrigida a duração do impulso físico até ultrapassar a borda com a cápsula inteira. [Dirigido final Clothing + Fire, 85/85](../evidence/service-roofs-cornice-jumps-final-20261007.log), com queda e dano reais, sem remover os sólidos originais. Saves/cargas frias usam arquivos próprios; execução com `--no-save` não vale como prova de gravação.
- [x] Amostra Main renderizada de **Union, Maciota, Fire e Vértice: 122/122**, com fotografias dos acessos e coberturas inspecionadas. [Resultado](../evidence/harbor-service-roofs-132324-5369700/result.json), [Maciota](../evidence/harbor-service-roofs-132324-5369700/maciota-roof.png), [Fire](../evidence/harbor-service-roofs-132324-5369700/harbor_fire_station-roof.png) e [Vértice](../evidence/harbor-service-roofs-132324-5369700/vertice_roof-roof.png). Atores apoiados, escadas legíveis, equipamentos preservados e cidade visível. O interior preexistente dos bombeiros permanece esparso; não foi reformulado por este acesso à cobertura. Aprovação restrita à composição diurna observada, sem extrapolar iluminação temporal/FPS para os serviços.
- [x] Revisão visual Main do Customs com cenário exterior completo: [térreo](../evidence/harbor-building-walkthrough-17432-5625112/harbor_customs_house-floor-0.png) e [rooftop](../evidence/harbor-building-walkthrough-17432-5625112/harbor_customs_house-floor-4.png). Viaduto preservado sem cobrir a sala, lixeira exterior íntegra, moradores e mobiliário legíveis. Equipamentos originais do telhado preservados, com passagem física até o dinheiro e o salto; **51/51** nessa sessão. Isso complementa a amostra nativa, sem certificar individualmente cada obstáculo/câmera dos outros edifícios.
- [x] Sequência noturna Main do Customs: **2.403 quadros nativos em 65,451 s**, incluindo entrada, 30 s internos, escadas e 30 s no rooftop, **11/11** verificações funcionais. [Vídeo](../evidence/harbor-building-temporal-143784-6383109/night-entry-interior-roof.mp4), [tempos/fases](../evidence/harbor-building-temporal-143784-6383109/phases.json) e [análise](../evidence/harbor-building-temporal-143784-6383109/temporal-inspection.json). Sem piscadas observadas nos trechos consecutivos inspecionados; quatro áreas estáticas analisadas em 1.137 quadros internos e 850 externos, variação média adjacente abaixo de 0,014 e 0,093 em escala 0–255. Cobertura limitada à noite limpa e câmeras estáveis desse edifício, não toda a iluminação/clima/cidade. Readback e gravação acrescentam custo: o vídeo não é benchmark.
- [x] Movimento diante do interior: a primeira sequência Bridge Court West de 2.067 quadros / 64,567 s revelou o trem encobrindo a sala; preservada como reprodução em `harbor-building-temporal-134416-5566264/frame-001108.jpg`. O tratamento local agora acompanha locomotiva, vagões, portas e rodas no shader, preservando os sólidos e materiais originais. **20/20** controles renderizados de movimento, equivalência de material fora do recorte, colisão, restauração e streaming: [log](../evidence/building-moving-sightline-first-20261007.log). Ferrovia/copas: **25/25**, incluindo descarregamento antes de callback: [log](../evidence/building-sightline-weak-streaming-final-20261007.log).
- [x] Repetição noturna Bridge Court West: **11/11**, **2.637 quadros nativos / 64,511 s**, com 30 s internos e 30 s na cobertura. [Vídeo](../evidence/harbor-building-temporal-102336-5608298/night-entry-interior-roof.mp4), [fases/posições do trem](../evidence/harbor-building-temporal-102336-5608298/phases.json) e [análise](../evidence/harbor-building-temporal-102336-5608298/temporal-inspection.json). Inspecionados contact sheet, dez quadros completos da passagem, incluindo 1249–1254 consecutivos, e os trechos 688–691/1947–1950. Dante, dois moradores, corredor e escada ficam legíveis durante a travessia; o trem permanece fora do recorte e restaura os materiais na cobertura. Quatro regiões estáticas em 1.152 quadros internos e 1.294 externos tiveram diferenças médias adjacentes inferiores a 0,014/0,076 na escala 0–255. Sem piscadas observadas nesses trechos; cobertura restrita a esse prédio/noite limpa e às câmeras capturadas, sem aprovação global nem uso do vídeo como benchmark.
- [ ] Aprovação de performance: os diagnósticos finais renderizados têm janelas de 30 segundos, C# ativo e fontes estáveis, mas o teste `test_armored_route_session.gd` de outra conversa reiniciou durante a tentativa isolada e permaneceu nas demais medições. **Não certificado** por interferência de carga concorrente. [Amostras, auditoria e comparação](../evidence/harbor-building-performance-final-20261007.json). Godot 4.7.2 .NET, Mobile, RTX 4060 Laptop, 1920×1080, VSync 1, limite 144 FPS e MSAA 2. O controle desativa a ativação dos interiores na cena atual; não representa checkout histórico anterior às mudanças. População e tráfego não foram congelados: 27/27 no controle e 30/29 no ativo.

| Diagnóstico anterior aos últimos recortes/contexto urbano, regime estável | FPS médio | p50 / p95 / p99 (ms) | Máximo (ms) | >33,3 / >66,7 ms |
| --- | ---: | --- | ---: | --- |
| Rua, ativação desligada | 143,49 | 5,721 / 11,605 / 12,758 | 22,944 | 0 / 0 |
| Rua, ativação ligada | 143,70 | 6,037 / 11,337 / 13,166 | 20,955 | 0 / 0 |
| Customs rooftop, noite | 144,02 | 6,966 / 10,374 / 12,026 | 13,686 | 0 / 0 |

O p95 da rua variou −2,31% e o p99 +3,20%; esses números contaminados não demonstram ausência de regressão. O limite de 144 FPS impede inferir folga de renderização. Primeira aproximação: máximo 45,257 ms no controle e 48,452 ms no ativo; entrada e subida dos quatro pisos na noite: máximo 29,184 ms, separadas do regime estável. Nenhum desses trechos teve frame acima de 66,7 ms. Essas amostras antecedem os últimos recortes de fachada/trem e reservas de contexto urbano. Faltam comparação isolada do código final e cobertura de desempenho das condições não medidas; capturas funcionais e fotos não substituem isso.

Após congelar os últimos ajustes, dois diagnósticos adicionais de 30 s verificaram os cenários afetados. Ambos usaram C# ativo, fontes estáveis e os mesmos parâmetros de renderização, porém a auditoria registrou testes de carro-forte de outra conversa durante as janelas. Uma nova tentativa de controle isolado foi recusada pelo runner antes de iniciar, pois outro motor já estava ativo. Mantida a pendência do comparativo; nenhum processo alheio foi interrompido.

| Código final, diagnóstico noturno | FPS médio | p50 / p95 / p99 (ms) | Máximo (ms) | >33,3 / >66,7 ms |
| --- | ---: | --- | ---: | --- |
| Bridge Court West, térreo e trem ativo | 144,00 | 6,980 / 10,169 / 11,770 | 13,881 | 0 / 0 |
| Torre editada51, cobertura após sete pisos | 143,90 | 6,372 / 11,449 / 12,768 | 17,974 | 0 / 0 |

Primeira aproximação: máximos de 49,488 e 48,639 ms. Entrada/subida da torre: 3,069 s, máximo de 52,703 ms, um frame acima de 33,3 ms e nenhum acima de 66,7 ms. Esses trechos ficam separados do regime estável. População/tráfego: 38/21 no térreo, 40/25 na torre. [Relatórios completos e auditorias](../evidence/harbor-building-performance-final-20261007.json); medições locais não equivalem a ausência de regressão ou aprovação global de FPS.


## Deserto — oficina aberta do encontro de arrancada — 06/10/2026

**1 novo pátio de oficina ao ar livre / 0 novas salas ou transições / 0 certificações integrais.** A oficina de Digo na cidade permanece; esta baia permite encontrá-lo trabalhando no encontro. Não altera as contagens de interiores fechados dos demais lotes.

- [x] Apresentação ampliada após revisão do usuário: pátio de 30 × 24 m, concreto texturizado com desgaste/óleo, Gol com capô aberto, segundo carro desmontado sobre cavaletes, macaco, bancadas com motores, racks de peças/rodas, carrinho, cabos e ferramentas. Parede traseira baixa e cobertura restrita ao armário mantêm a oficina aberta; somente o nome próprio Digo.
- [x] Roupa de oficina própria no deserto, com calça de trabalho, avental/cinto; rotina autorada entre carro e bancada, interrupção para conversar, retomada do trabalho, suspensão em modal e descarregamento por proximidade/região. Efeitos de ferramentas gravados acompanham as estações de trabalho e param ao conversar.
- [x] Física e rotina: `tests/test_desert_digo_routine.gd`, **42 verificações / zero falhas**, com cápsulas reais de jogador/NPC, varreduras dos móveis e segundo carro, corredores, percurso completo, conversa, áudio, pausa, retorno e descarregamento. [Log final](../evidence/drag-meet-final-20261006-2120/routine.stdout.log).
- [x] Profundidade separada: **120 verificações / zero falhas**, com frente/atrás/lado do carro e bancada, controles positivos do jogador e do rig real de Digo, câmera exterior e câmera diagonal do usuário. [Resultados e fotos](../evidence/desert-digo-depth-final-20261006-2120-fixed/results.json). A primeira passagem reproduziu ocultação total na bancada; foram corrigidas a parede/cobertura. A passagem seguinte identificou obstrução excessiva pelo capô na diagonal; abertura reduzida para 0,72 rad com haste física, sem relaxar os critérios.
- [x] Main real renderizada .NET: **43 verificações / zero falhas**, incluindo conversa, preparação do carro, rotina, população/áudio e saída/retorno sem duplicação. [Log](../evidence/drag-meet-final-20261006-2120/meet-fixed.stdout.log) e [foto final da oficina com Dante no corredor livre](../evidence/desert-meet-session-75740-5664048/digo-gameplay.png). A fixture fotográfica anterior foi corrigida por posicionar Dante dentro do capô; o posicionamento final verifica apoio e corpo fora dos sólidos.
- [ ] Comparativo de frame time renderizado. Usuário realizará a avaliação de performance; nenhum FPS aprovado por esta implementação.

## Harbor — primeira leva de prédios acessíveis — 06/10/2026

**2 lugares físicos / 2 interiores independentes / 8 pavimentos autorados; 0 certificados integralmente / 2 em validação.** Customs House (`NorthFrontage5`) e Union Lofts (`Apartments`), com térreo + três andares cada. Não confundir plantas por andar com novos prédios. O inventário efetivo de `harbor_buildings` tem 60 fachadas: 11 acessos anteriores, estes 2 novos e 47 ainda pendentes; construções de outras fábricas de cenário precisam de censo complementar. [Inventário e próximas levas](harbor-interiores-por-levas.md).

- [x] Oito plantas distintas: atendimento/arquivo, escritórios/reunião, contabilidade e copa/descanso no comercial; cozinha/jantar/sala, quartos/banheiro/estudo, estúdio e biblioteca/quarto de hóspedes no residencial.
- [x] Câmera alinhada, escala humana e marcador compartilhado de acesso/saída. Escada com interação funcional e troca coberta entre salas; não é circulação vertical contínua.
- [x] **715 checks físicos e de profundidade** nos oito pavimentos, com cápsulas reais de Dante/NPC, varredura contra móveis, corredores, patamares, controles positivos e oclusão separada: `evidence/harbor-building-contract-173028-4880618`. Revisão final da mesa do último pavimento: **96 checks**, `evidence/harbor-building-contract-92016-4797772`.
- [x] **46 checks no Main .NET renderizado** no primeiro par de pavimentos de cada prédio: caminhada à fachada, ação real de entrada, circulação até a escada, subida/descida, controle, save isolado, recarga fria no andar superior, saída e descarregamento: `evidence/harbor-building-session-86264-5246742`.
- [x] Versão com oito pavimentos: **58 checks no Main .NET**, incluindo botões reais de subir/descer nos andares intermediários, chegada ao terceiro andar, recarga fria no último patamar e retorno completo: `evidence/harbor-building-session-180248-4978171`.
- [x] Fotografias reais dos dois exteriores e oito pavimentos em `evidence/harbor-building-session-180248-4978171`. Antes: exterior do Customs House em `evidence/harbor-access-before-playable-139340-4912037/scene.png`; os interiores eram inexistentes. Não há fotografia anterior independente do residencial.
- [x] Regressão de persistência: `tests/test_full_save.gd`, **PASS**, sem falhas. Corrigida comparação numérica que rejeitava o andar após serialização JSON.
- [x] Comparação renderizada do exterior: p95 **7,277 → 7,377 ms (+1,37%)**, p99 **8,686 → 8,785 ms (+1,14%)**, dentro da tolerância de 5% nesse cenário. Oito pavimentos medidos por 30 s cada, p95 até **2,097 ms**, sem frames acima de 33,3 ms. Admissão bloqueada preserva sala e controle nos dois prédios. [Evidências e limites](reviews/harbor-building-batch1-20261006.md).
- [ ] Instrumentação separada dos picos de primeira visita/troca de andar; as janelas estáveis não os certificam.
- [ ] Cobertura temporal noturna e de iluminação, não certificada pelas fotografias diurnas.

Sem alterações nas regras da ponte, campanha, garagem, combate ou nos interiores dos demais mapas. Os NPCs das verificações são fixtures: esta leva ainda não acrescenta moradores ou funcionários permanentes.

## Deserto — quatro casas de Santa Lua — 06/10/2026

**4 lugares físicos / 4 interiores distintos novos; 0 certificados integralmente / 4 em validação / 0 não iniciados neste lote.** Cada fachada possui planta, acesso e retorno próprios. A loja e a torre da praça não entram nesta contagem. Não extrapolar as contagens históricas de outros lotes concorrentes.

- [x] Quatro fachadas diferentes, câmera alinhada, escala humana e entradas/saídas compactas compartilhadas.
- [x] Colisão e circulação: **82 checks exteriores / 376 interiores**, com jogador e NPC, apoio, sólidos e âncoras de entrada, loot e moradores.
- [x] Profundidade renderizada final: **224 checks interiores / 36 exteriores**, com controles positivos separados; telhados finais incluídos.
- [x] Rotina: vazias das 6h às 18h, moradores cozinhando/lendo/dormindo à noite; **106 checks** de ocupação, suporte, morte e limpeza.
- [x] Água e sanduíche consumíveis, dinheiro e recibos permanentes; **46 checks** de save após consumo/descarte e rejeição de recibos inconsistentes.
- [x] Main .NET: **127 checks** de entrada/saída/controle nas quatro casas, consumo, save e carga fria sem duplicação; fotos reais de dia/noite para cada sala.
- [x] Sequência da cozinha: **1.527 quadros / 29,949 s**, sem omissões. Nove quadros consecutivos em três janelas revistos, sem piscada observada nessas amostras; fotos finais das quatro salas revisadas.
- [ ] Cobertura temporal das outras três salas e condições adicionais de iluminação.
- [ ] Comparação controlada de frame time antes/depois. Concorrência e mudanças de fontes impedem usar as primeiras medições como baseline.

Evidências e limites em [Santa Lua](reviews/santa-lua-20261006.md). As fotografias anteriores registram a primeira revisão exterior; as quatro salas são novas. Não contar como certificadas enquanto houver checks obrigatórios pendentes.

## Serra Bruta — Galeria Santa Brasa — 06/10/2026

**1 lugar físico / 1 interior contínuo novo; 0 certificados integralmente / 1 em validação.** A galeria de carvão, o segredo e o ramal clandestino pertencem ao mesmo ambiente conectado. A mina acrescenta 1/1 à referência de 38/36; com as quatro moradias de Santa Lua integradas em paralelo, o catálogo registra **43 acessos / 41 interiores distintos**. A guarita é fechada e não conta como interior. As moradias pertencem a outro lote, sem certificação por estes testes.

- [x] Acesso exterior compacto no fundo da cava, entrada e retorno pelas transições nativas; câmera que enquadra os dois ramais.
- [x] Contrato físico: **65 verificações**, incluindo jogador/NPC, circulação, sólidos e área clandestina. A ponta legítima da parede é contornada pelo percurso.
- [x] Main: caminhada até a alavanca, revelação, recompensa única, save e reentrada; retorno a -28 m preserva vida e controle.
- [x] Quatro bandidos com combate real; dano recebido, morte/resgate, perda da bolsa e limpeza de guardas/corpos/itens conferidos. Fuga/pagamento/recarga final: **64/64**, com recibo exato e bônus de conquistas separados.
- [x] Profundidade renderizada final: **36/36**, jogador/NPC e controles positivos separados no vagão, coberturas e mesa do ramal clandestino (`evidence/mining-20261006/coal-depth`).
- [x] Sequências de 30 s: dia 889 quadros, noite final 898 e segredo final 900, sem quadros renderizados omitidos. Revisão amostral com trechos consecutivos; emenda de material e aparição antecipada do segredo corrigidas e revistas. Limites em `mina-serra-bruta.md`.
- [x] Areia exterior suspensa no interior e retomada no retorno, com emissão e simulação GPU paradas durante a visita.
- [ ] Ausência de regressão de frame time: comparação renderizada executada, com custo adicional confirmado frente ao local vazio. Meta absoluta de 60 FPS com folga no hardware medido; picos de preparação e limites documentados. Não marcar certificação integral por esse resultado.

Fotografias reais e limites da validação são registrados em [mina-serra-bruta.md](mina-serra-bruta.md). Manter **0 certificados** enquanto houver checks obrigatórios pendentes; este lote não certifica outros interiores.

Revisão de ambiente e percurso em 06/10/2026: **1 interior existente afetado, 0 novos interiores, 0 novas certificações**. A galeria recebe água posicional no dreno e estalos dos suportes, com duas vozes interrompidas ao desativar a sala. No exterior, o cascalho da espiral tem material próprio, balizadores bilaterais e bermas de rocha fora dos 14 m de circulação. Planta, sólidos, luzes e câmera da galeria permanecem os mesmos nesta alteração ambiental.

- [x] Ciclo de vida de áudio: **22/22** em `tests/test_mining_ambience.gd`, incluindo cue ativo ao suspender, visibilidade herdada, distância, retorno e liberação dos dois canais. Log: `D:/geteco/mining-ambience-fixed-20261006.log`. A primeira tentativa falhou na inferência de tipo de `weakref` da fixture, corrigida com `WeakRef` explícito; não foi falha do runtime.
- [x] Circulação com os novos balizadores/bermas: **15/15** em `tests/test_mining_access.gd`; quatro varreduras de **1.996 amostras** cada, carro comum e caminhão nos dois sentidos, sem contato ou falta de apoio. Log: `D:/geteco/mining-access-20261006.log`.
- [ ] Escuta do mix durante exploração e revisão visual da espiral completa/noite. Antes: `evidence/mining-measure-80048-5818417/mine-overview-diagnostic.png` e `coal-gallery.png`. Os contratos acima não comprovam qualidade sonora ou visual.
- [x] Revisão visual real do percurso: `evidence/mining-session-17468-5482116/mining_haul_truck-seated.png` e `evidence/mining-fall-review-170272-5309572/fall-00.png` revelaram cascalho excessivamente dourado/claro; cor corrigida para cinza/bege `77766f`, mantendo geometria e custo. `evidence/mining-fall-review-117488-5284252/fall-08.png` confirma o arco inferior diurno em tom neutro, balizadores legíveis e berma apoiada. A conclusão visual cobre esse arco, não a espiral completa ou a noite.
- [ ] Comparativo renderizado desta revisão: baseline coletado com interferência de outro teste no equipamento; não certifica ausência de regressão.

O mesmo lote revisa as cabines existentes dos **3 arquétipos industriais** (retroescavadeira, trator e caminhão): **0 novos lugares/interiores**. Carga e mecanismo hidráulico ficam fora do recorte de portas; vidro simples e acabamento fechado da cabine. O teste de acesso registrou **11/11**; a validação das portas encontrou espera cruzando a folha do caminhão, corrigida com limite longitudinal do ponto de espera. O reteste geométrico passou **348/348**, com afastamento mínimo da folha de 0,46 m no caminhão e 0,34 m no trator/retroescavadeira. Fotografias e integração final no Main permanecem pendentes; o contrato parcial não certifica as três cabines.

Ampliação de detalhe solicitada em 07/10/2026: bancadas da cava agora têm falhas angulares por setores, mantendo piso central e espiral autorada; o contorno norte foi recortado. Rochas/estratos/fragmentos usam bloco fraturado assimétrico, com 10 vértices dentro do envelope anterior e colisões exteriores derivadas da mesma malha. Britador, esteira e portal receberam nervuras, placas, ferragens, escada de manutenção, juntas, reparos e madeira rachada. Na galeria, detalhes estáticos agrupados em MultiMeshes acrescentam tábuas/ferragens das caixas, ancoragens dos trilhos, ferramentas e pacote em preparação, remendos do vagão e elétrica presa à parede. **0 lugares/interiores novos; 0 certificações adicionais.** Os sólidos da galeria foram preservados; o novo relevo e as rochas exteriores exigem nova validação física, visual e de performance, não coberta pelos checks anteriores.

A primeira revisão renderizada mostrou que somente ferragens pequenas não bastavam na câmera geral. A segunda passada acrescenta um material mineral compartilhado (piso/carvão/cascalho e estratos/manchas das rochas), diagonais largas de madeira nas paredes e objetos médios sobre mesas já reservadas: pacote em preparação, rádio e bandeja de munição. Não houve nova física, luz ou câmera nessa passada. A geometria angular passou **65/65 checks físicos**; o reteste final de oclusão passou **36/36**. Foto final revisada: `evidence/mining-20261006/coal-depth/player-natural.png`, com escoras, estratos, cascalho, cintas das caixas e bancada ocupada legíveis na câmera geral. Antes: `evidence/mining-measure-80048-5818417/coal-gallery.png`. A conclusão visual cobre essa vista, mantendo o estilo procedural; comparação de performance e cobertura temporal permanecem pendentes.

Fechamento local de 07/10: fotos reais da galeria, dia/noite exterior, panorama e três máquinas revisadas em `evidence/mining-measure-82232-5802516`. Relevo/rota final **15/15**, portas **347/347**, acesso a veículos **11/11**, cargas angulares **33/33**; fuga de Bison no Main **22/22**, incluindo direção, pagamento único e desembarque apoiado. Queda de 18 m manteve câmera sem inversões durante a queda e permitiu caminhada após aterrissar. Medição renderizada final: p95 **3,132 / 2,765 / 4,514 ms** em pátio/fundo/galeria, janelas de 30 s, sem frames acima de 33,3 ms; preparação teve picos até 173,697 ms. **Comparação de regressão continua pendente**, por concorrência externa e fontes compartilhadas alteradas entre versões; o aumento observado na galeria não foi isolado. Permanecem **zero novas certificações integrais**. [Evidências, escopo e limites](reviews/mining-experience-20261007.md).

## Cânion do deserto — casa abandonada e cabana — 06/10/2026

**2 lugares físicos / 2 ambientes contínuos novos; 0 certificados integralmente / 2 em validação.** São ruínas abertas no próprio exterior, sem portal, carregamento de sala ou câmera interior. O catálogo de transições continua com **38 acessos / 36 interiores distintos**; os dois lugares deste lote são contados separadamente e não fingem novos acessos de catálogo.

- [x] Casa de adobe parcialmente desabada e cabana de madeira, com mobiliário em escala humana, caminhos reservados e sólidos próprios.
- [x] Main .NET: jogador e NPC atravessam os acessos; mesa da casa e cama da cabana bloqueiam caminhada e varreduras, sem subir nos móveis.
- [x] Pista opcional dos Cobras/Vicente e dois esconderijos de R$ 5.000 com recibos separados; recarga fria preserva flags e recibos. Bônus existentes de conquistas são transações independentes.
- [x] **90/90 checks no Main .NET**: saldo, recibos, repetição, recarga fria, caminhada e oclusão de jogador/NPC nas duas ruínas. Saldo inclui conquistas de R$ 50/R$ 200; varanda e viga têm casos próprios além dos controles livres.
- [x] Revisão limitada das fotografias naturais e da sequência diurna: **591 quadros gravados em 19,8558 s**, nenhum quadro renderizado omitido; inspecionados os trechos `00028–00031` e `00538–00541`, além dos quadros `00120` e `00300`. Nos trechos consecutivos revistos, não houve desligamento/popping evidente de sombras ou sólidos durante a passagem pelas portas. Os 591 quadros não foram inspecionados individualmente.
- [ ] Iluminação noturna e cobertura temporal mais ampla. A revisão diurna amostral não certifica ausência global de flickering.
- [ ] Medição renderizada de frame time e comparação controlada. Capturas/máscaras de profundidade não são medições de FPS.

Evidência final de integração: `evidence/desert-secrets-session-107108-5011442`, com 90 checks, fotografias naturais, controles positivos de jogador/NPC, sequência diurna e saves isolados; stderr vazio. A primeira rodada (`evidence/desert-secrets-session-32576-5003184`) preserva as dez falhas de expectativa que revelaram os bônus de conquistas e os oclusores da varanda/viga. Nenhuma geometria foi removida para fazer o teste passar. Bandidos foram explicitamente pré-derrotados nessa fixture; o combate possui teste separado. A rodada não certifica iluminação noturna, combate, performance ou todos os interiores do jogo.

As portas mantiveram 91,7–93,7% de visibilidade do ator na casa e 96,5–98,7% na cabana nos controles diagnósticos. A varanda opaca pode ocultar completamente ambos os rigs na pose sob sua cobertura; a viga da cabana causa oclusão parcial. Os controles livres ao lado dos móveis mantiveram 99,9–100%. Isso prova casos de profundidade distintos, não visibilidade universal em qualquer posição. A sequência usa câmera normal do exterior; fotografias de profundidade usam enquadramento diagnóstico frontal. Houve um intervalo inicial de captura de 266,771 ms, associado à primeira escrita de imagem de 241,679 ms. O limite de 30 Hz, captura e varredura de pixels invalidam qualquer conclusão de FPS. **Mantidos 0 certificados / 2 em validação.** [Resultados, evidências e limites](deserto-fronteira-validacao-20261006.md).

## Mapa 2 — Cobre e Digo — 06/10/2026

**2 lugares físicos / 2 interiores novos integrados**, Cobre e oficina Digo, com modelos e plantas próprios em `world/desert`. O catálogo integrado registra **38 acessos / 36 interiores distintos**. Neste lote: **0 certificados integralmente / 2 em validação / 0 não iniciados**. Não somar o motel como interior: seu descanso é exterior. Estado detalhado em [mapa2-deserto.md](mapa2-deserto.md).

- [x] Modelos próprios de banco e oficina, entradas compactas e nomes próprios únicos nas fachadas.
- [x] Classificação dos sólidos, pontos de serviço e percursos preparados para o adaptador de interiores existente.
- [x] Ganchos centrais aplicados e parser Godot .NET executado; catálogo inclui os dois acessos.
- [x] Física e profundidade na fixture renderizada: **52 verificações aprovadas**, com Actor jogador/NPC reais, varredura contra balcão/mesa, cantos, deslocamento grande contra parede, corredor válido e residente atrás do móvel. Oclusão possui controles positivos separados; viga da oficina mantém seu caso próprio de profundidade.
- [x] Capturas reais dos dois interiores com câmera alinhada e materiais finais de reboco, pedra, concreto, madeira e tecido; volumes físicos preservados no acabamento dos assentos.
- [ ] Acessos exteriores e transições completos no Main, com inspeção de câmera e iluminação.
- [ ] Sequência temporal noturna e comparação renderizada de frame time.
- [x] Digo: 49 checks no Main; entrada/saída, botões reais, compra de peças e carro, carga fria do save e restauração de melhorias, pintura/dano e frota após streaming.
- [x] Cobre: caminhada física do asfalto pela rampa ao acesso original, entrada e saída no Main (`evidence/desert-curve-drive-54884-7050518`); revisão diurna exterior mostra nome e ligação ao passeio legíveis.
- [x] Cobre: retorno com carro estacionado bloqueando os cinco pontos centrais. Dois pontos laterais autorados, sujeitos à colisão e piso, permitem sair sem deslocar o veículo; reprodução antes/depois em `evidence/desert-bank-return-87180-6853752` e `evidence/desert-bank-return-69448-7341101`.

Evidências executadas em Godot **4.7.2 .NET**, renderer **Forward Mobile**, **NVIDIA GeForce RTX 4060 Laptop GPU**: [52 verificações e medições de visibilidade](/D:/geteco/artifacts/desert-20261006/depth/results.json), [log da segunda execução](/D:/geteco/artifacts/runtime-queue/desert-depth-2.stdout), [Cobre — captura real](/D:/geteco/artifacts/desert-20261006/depth/desert_bank-player-natural.png), [Digo — captura real](/D:/geteco/artifacts/desert-20261006/depth/desert_digo-player-natural.png). A primeira execução identificou oclusão legítima pela viga no ponto lateral da oficina; o caso foi separado da prova de visibilidade ao lado da mesa, sem afrouxar tolerâncias nem ocultar a viga.

**0 novos interiores certificados**. O resultado acima cobre a fixture nativa e seus casos físicos/visuais; não substitui benchmark comparativo no Main e evidência temporal dos interiores. Transições e compras/save de Digo passaram no fluxo real (`evidence/desert-workshop-session-54988-7507128`); caminhada e transições do Cobre também passaram no Main. Motor serializado pela fila compartilhada; uma medição posterior foi invalidada por dois headless de outro chat antes de ele aderir à fila. Nenhum processo alheio encerrado.

## História Harbor e oficina Maciota — 05/10/2026

**Oficina: 1 lugar / 1 interior existente reformado e relocalizado. Casa de Takeshi: 1 acesso / 1 interior novo.** O catálogo consultado registra **36 acessos / 34 interiores distintos**, incluindo os dois acessos compartilhados do Abrigo. Os 18 contêineres portuários são contados separadamente. Esses números não substituem o inventário histórico de salas e passagens especiais nem recertificam outros ambientes. Ambos em validação, 0 certificados integralmente neste lote.

- [x] Oficina afastada da delegacia, pátio próprio e circulação/baia preservados.
- [x] Câmera alinhada, escala humana e nome próprio único na fachada.
- [x] Garagem continua bloqueando armas e mantém Maciota/mecânico sem rotinas de dano.
- [x] Testes de recompensas, transferência e restauração de condutor passaram nas verificações centrais deste lote.
- [x] Apoio e passagem física terminal → rua → acesso da M8 conferidos pelo teste de percurso.
- [x] Passeio completo da M8 na rota direta, com desembarque livre e recuperação de impacto/cancelamento.
- [x] Jetta com M8 presente: desembarque sem deslocar o carro, 60 frames de estabilidade, caminhada até Jessica e conclusão/save no fluxo Main renderizado (65 verificações).
- [x] Casa: entrada, documentos, colisão e oclusão de jogador/NPC com controles positivos, recompensa única e save; 68 verificações renderizadas.
- [x] Fotos reais da oficina, acesso e sala de Takeshi.
- [x] Casa: orçamento atual renderizado de 30 s, câmera jogável, caminhada, lista e save/load isolado; p95 1,245 ms / p99 1,481 ms, população natural registrada.
- [ ] Comparação controlada da oficina: medições de 30 s concluídas, mas tempos maiores e quantidades diferentes de veículos impedem aprovação de regressão.
- [ ] Evidência temporal da apresentação e do acesso novos.

Progresso e limites em `docs/story-harbor-act1-20261005.md`; manter os itens pendentes até concluir as verificações.

## Carros do Digo — cabines existentes — 03/10/2026

**2 cabines de veículos existentes; nenhum edifício ou acesso acrescentado.** Contagens globais de estabelecimentos preservadas.

- [x] Dimensões internas ajustadas e teto/colunas preservados durante abertura das portas.
- [x] 30 verificações de geometria, portas dos dois lados e reentrada.
- [x] Entrada e saída públicas no mapa real, duas vezes por veículo; fotos antes/depois.
- [ ] Certificação ampla de física/oclusão e performance isolada não abrangida por esta correção local.

[Correção, evidências e limites](reviews/digo-cabins-20261003.md).

## Boa Praça — supermercado novo — 03/10/2026

**1 lugar físico / 1 interior distinto novo; 0 certificados integralmente / 1 em validação / 0 não iniciados neste lote.** Acrescenta 1 acesso/1 interior à referência registrada de 32/30: **33 acessos / 31 interiores**; não recertifica outros lugares.

- [x] Fachada própria, entrada/saída a pé, câmera alinhada, gôndolas, padaria, hortifruti, refrigeradores e dois caixas.
- [x] Dois funcionários e quatro clientes: escolhas, compras, caixa, saída/retorno e limpeza ao descarregar.
- [x] Comida útil no inventário, cura real, colete equipado, capacidade/dinheiro/recibos e save/load isolado.
- [x] 93 checks físicos/econômicos; 24 de profundidade com jogador/NPC e controles positivos; 20 de Main, incluindo controle e reentrada.
- [x] UI lateral revisada, feedback imediato, navegação por grade e painel/Voltar visíveis em três resoluções.
- [x] Fotos reais de interior, fachada e UI; sequência contínua de 30 segundos com clientes ativos.
- [ ] Baseline de performance e comparação controlada de frame time. Medições concorrentes e alterações compartilhadas impedem aprovação.
- [ ] Origem dos avisos de recursos no encerramento de Main ainda não isolada.
- [ ] Foto do exterior anterior e cobertura ampliada de combate/resgate/save durante conflito não disponíveis.

[Implementação, evidências e limites](reviews/supermarket-20261003.md).

Revisão localizada de 09/10/2026: cesta alinhada à frente dos clientes, mãos vinculadas às alças e alcance da prateleira no referencial da sala; referência do dono da cobertura corrigida para não usar `Node.owner`. Os 93 checks funcionais, o teste `test_supermarket_hand_targets.gd`, os 20 checks renderizados de Main e os 24 de oclusão com jogador/NPC passaram. A cobertura do supermercado passou 32 checks renderizados, incluindo subida, save temporário isolado, restauração a frio e descida (`evidence/harbor-service-roofs-34296-6702843/`); tentativa anterior com `--no-save` falhou na persistência por argumento inadequado e foi corrigida na invocação. Fotos atuais em `evidence/supermarket-20261002/arms-fix-20261009/` (comparação visual anterior: imagem fornecida no chat). Nenhum lugar ou interior adicionado; contagens e certificação integral permanecem iguais. Comparação de frame time antes/depois pendente por instâncias concorrentes do Godot; este ajuste não aprova performance.

## Banco North Pier: assalto, cofre e consequências — 02/10/2026

**1 lugar físico / 1 interior distinto**, existente; **0 certificados integralmente / 1 em validação / 0 não iniciados neste lote**. Nenhum lugar criado e contagens globais preservadas. Câmera e escala mantidas; circulação central, leitura do cofre e saída revisadas.

- [x] Guardas resistem ao primeiro tiro, entrada pacífica não inicia disparos e resposta armada tem antecipação.
- [x] Cartão e dinheiro giram/flutuam, coleta por aproximação e absorção; saque persistente visível de até R$ 15.000.
- [x] Saque é depositado ao sair vivo; morte perde o saque em mãos e até R$ 5.000 da carteira, sem cobrar duas vezes.
- [x] Porta do cofre mantém colisão na folha aberta; paredes ficam transparentes no Mobile, restauram opacidade e continuam sólidas.
- [x] Corpos de guardas/atendentes apoiados no piso durante/depois da queda e na restauração; sangue vinculado à sala.
- [x] Morte no assalto → 1 dia contínuo longe e fora da tela → 3 dias interditado; faixas externas, entrada bloqueada e nova equipe na reabertura.
- [x] 54 verificações Main de entrada a pé, roubo, saída, reentrada, morte/resgate e calendário; 42 físicas/de profundidade com jogador/NPC e controles positivos; 41 de corpos/sangue; 34 de ciclo e 20 de economia.
- [x] Fotos reais do gameplay, cofre, corpos, sangue, interdição e nova equipe. A comparação visual usa a primeira revisão desta tarefa, anterior à correção de transparência/corpos.
- [ ] Comparação de desempenho antes/depois: base isolada indisponível devido às outras sessões; medição atual registrada separadamente, sem aprovar regressão.
- [ ] Certificação ampliada de todos os móveis, combate prolongado com todas as armas e save/load completo em disco durante assalto não realizada.

[Evidências, resultados e limites](reviews/bank-gameplay-20261002.md).

## Prédios vizinhos das lojas da montanha — 02/10/2026

Complemento exterior em **3 famílias de fachada**: Summit, chalés e lojas. Modelos compartilhados atualizam instâncias existentes; nenhum lugar/interior criado. Contagens globais preservadas; zero novas certificações integrais.

- [x] Telhados acima das paredes, frontões triangulares e cumeeiras fechadas.
- [x] Janelas visíveis nas laterais e fundos; vidros antigos retirados de dentro das paredes.
- [x] Madeira/pedra texturizadas, molduras e peitoris; sem novas luzes dinâmicas.
- [x] 71 checks de geometria, vidro, portas e paredes aprovados; C# compilado.
- [x] Capturas reais antes/depois por quatro lados de três fachadas representativas.
- [ ] Performance isolada: outra sessão iniciou captura durante a base; comparação inconclusiva.
- [ ] Certificação ampliada de interiores, NPCs e estabilidade temporal não realizada neste complemento exterior.

[Causas, correções, imagens e limites](../evidence/mountain-neighbors-20261002/review.md).

## Lojas de roupas da montanha — 02/10/2026

Boutique Alpina, Casacos da Vila e Último Abrigo: **3 lugares físicos / 3 interiores distintos**, todos reformados; **0 certificados integralmente / 3 em validação / 0 não iniciados neste lote**. Nenhum lugar ou interior criado; inventário global preservado.

- [x] Fachadas com madeira/pedra texturizadas, paletas próprias e somente nome do estabelecimento.
- [x] Manequins modernos proporcionais com casacos, vendedores reais e atendimento junto ao caixa.
- [x] Circulação, spawn, jogador/NPC, sólidos e portas: 652 checks físicos aprovados.
- [x] Oclusão nos balcões com jogador e vendedor, frente/trás/lado e controles positivos: 36 checks renderizados aprovados.
- [x] Caminhada real até compra, menu, saída/limpeza e reentrada nas três lojas: 18 checks Main aprovados.
- [x] Fotos reais antes/depois das três fachadas/interiores; acabamento final inspecionado.
- [ ] Comparativo isolado de frame time: base contaminada por jogos iniciados por outras sessões; desempenho não aprovado.
- [ ] Certificação ampliada: travessia contínua de todos limiares, save/load, oclusão de cada móvel e cenários adicionais não cobertos.

[Revisão, fotos e limites das evidências](../evidence/mountain-shops-20261002/review.md).

## Saída secreta da montanha: isolamento e redução — 02/10/2026

Revisão do mesmo acesso exterior, sem novos lugares ou interiores e sem alterar as contagens de migração. Posição alterada de `(762, 0, -493)` para `(740, 0, -880)`: aproximadamente 399 m do resort. Formação 30% mais estreita, 20% menos profunda e 10% mais baixa; vão útil de aproximadamente 1,34 × 2,05 m. Malhas e colisões reduzidas juntas, com escala física unitária. Clareira local no terreno existente apoia o acesso e preserva a transição suave para a neve. Sem novos textos, luzes ou mudanças de câmera.

- [x] Godot 4.7.2 .NET, C# compilado sem erros ou avisos.
- [x] 48 verificações renderizadas do exterior: passagem aberta, bloqueio fechado, rochas, spawn, jogador/NPC e oclusão com controles positivos.
- [x] Contrato de terreno: 107 verificações sem falhas; apoio físico no novo ponto também conferido pelo teste do exterior.
- [x] Fotos comparáveis da estrutura: [antes](../evidence/secret-exit-20261002/before/actor0-front.png) e [depois](../evidence/secret-exit-20261002/after/actor0-front.png).
- [x] Fluxo integrado: 18 verificações aprovadas (subida, chegada no piso, abertura/fechamento, reentrada e retorno). [Foto no gameplay](../evidence/secret-exit-20261002/gameplay/02-laje-fechada.png). A primeira execução parou antes do gameplay porque o fixture aguardava apenas 420 ticks físicos, enquanto o pré-aquecimento levou 17,5 s. Espera corrigida para prontidão real com limite de 60 s, preservando as verificações funcionais.
- [ ] A execução integrada registrou erros de normalização de Basis em `BodyImpactPose3D.gd:40`, chamado por `CharacterFallPresentation3D.gd:123`, durante combate. Esses arquivos não foram alterados nesta revisão; as 18 verificações de acesso passaram, mas a execução não foi livre de erros.
- [ ] Desempenho antes/depois não medido: outras sessões de gameplay/medição em execução. Não atribuir FPS das capturas a esta revisão. Sem nova certificação integral ou temporal do terreno.

Evidências: `evidence/secret-exit-20261002/`.

## Montanha: acabamento visual a partir da imagem anotada — 02/10/2026

Removidos o pequeno piso de entrada acima da cabine e a mancha amarela da serraria. Terra dos caminhos e pátio dessaturada, com menor granulação/relevo e transições largas de transparência para o terreno/neve. Apoio original do pátio e dos caminhos preservado; piso curto removido intencionalmente. Sem novos lugares/interiores.

Conferência somente visual por captura do jogo, sem testes ou benchmarks novos, conforme pedido explícito do usuário. Os resultados da etapa abaixo são anteriores a este acabamento e não certificam esta versão.

[Captura final](../../artifacts/mountain-review-1001/visual-soft-final/sawmill.png).

## Montanha: saída secreta, heliponto e estações — 02/10/2026

Revisão localizada dos exteriores e acessos existentes; sem novos lugares/interiores ou certificação integral. Inventário preservado. Saída secreta menor e afastada, heliponto reposicionado, estações completas com rampas e suporte físico, piso duplicado da serraria removido.

- [x] Mapa editável real: 48 verificações físicas e de profundidade da saída/heliponto, incluindo jogador e NPC, controle visível e oclusão.
- [x] Estações: 50 verificações com jogador/NPC, colisão derivada das malhas e profundidade renderizada.
- [x] Entrada, combate, subida, abertura/fechamento e retorno da saída secreta no jogo real: 18 verificações.
- [x] Terreno, estradas, serraria, circulação física e descarregamento/retorno: 723 verificações; contrato adicional de malha, emendas e colisão: 107.
- [x] Aposentadoria de chunks: processamento desativado antes da desmontagem; regressão de animação e cache coberta por 7 verificações, orçamento e restauração por 18.
- [x] Inspeção renderizada em 14 pontos e sequência de 30 segundos, sem erros de script; 687 capturas, maior lacuna de 1,56 s, sem certificação temporal integral.
- [x] Serraria: removida duplicação e aplicado pré-passe de profundidade local, mantendo bordas suaves. Comparativo final controlado: p95 5,999 → 5,774 ms, média 323,9 → 362,2 FPS, zero quadros acima de 33 ms.
- [ ] Desempenho integral: p99 da serraria oscilou 7,121 → 9,516 ms no comparativo final; medições anteriores em movimento tiveram picos. Sem certificação de ausência de regressão de cauda, chuva/noite ou de todo o mapa.

[Fotos antes/depois e resultados](../../artifacts/mountain-review-1001/revisao-montanha.html).

## Túnel do canal: câmera traseira do carro e personagem — 01/10/2026

Ajuste local solicitado: perspectiva atrás do veículo ou personagem no túnel, acompanhando seu rumo e retornando à câmera de rua na saída. Nenhum lugar ou interior criado, nenhuma migração ou nova certificação integral; contagens do inventário preservadas.

- [x] Cena real renderizada: perspectiva nos dois sentidos, lente sob o teto, carro visível, teto/cidade sólidos no interior e restauração da projeção, inclinação e zoom de rua.
- [x] Glitches locais: afastamento entre concreto e azulejo, filtragem de juntas, fechamento/restauração da cobertura do cupê e água exterior ao vidro sul. Fotos e sequência de 30 s registradas.
- [x] Extensão a pé: desembarque real, giro parado nos dois sentidos, enquadramento atrás do personagem e restauração da câmera/materiais na saída. Carro estacionado permanece fechado na vista baixa.
- [x] Travessia física completa: carro desce, cruza e sai na ilha; zero contatos com paredes/teto, sem buracos no piso. Cais superior continua transitável.
- [ ] Comparativo isolado de frame time: pendente, outras instâncias Godot abertas. Capturas e contador de FPS não certificam desempenho.
- [ ] Cobertura adicional: chuva/noite, NPCs em oclusão, combate/mira e movimento prolongado a pé, entrada oeste em movimento. Sequência da saída leste tem lacunas de até 91 ms, sem certificação temporal integral.

[Fotos e escopo da validação](../evidence/tunnel-chase-20261001/report.md).

## Contêineres do porto: estabilidade exterior — 29/09/2026

Correção localizada nas nervuras dos tetos dos 18 contêineres acessíveis e no modelo superior. Sem criar lugares/interiores ou migrar ambientes: contagens anteriores preservadas, zero novas certificações integrais. Colisões, circulação, câmera interior, portas e recompensas mantidas.

- [x] Cache e física: 18 checks, incluindo parede/porta fechada e corredor aberto.
- [x] Oclusão renderizada de jogador/NPC e restauração dos tetos: 86 checks, zero falhas.
- [x] Evidências exteriores antes/depois e sequências temporais de 30 s de dia/noite.
- [x] Comparativo diurno isolado: 140,42 → 143,73 FPS; p95/p99 sem regressão.
- [ ] Estabilidade integral: pico isolado de 67 ms; captura com intervalos perdidos; chuva e comparativo de performance noturna não cobertos. Nenhuma aprovação global de interiores.

[Correções, vídeos, métricas e limites](../evidence/port-glitches-20260929/report.md).

## Casa 1 / porão / quartel subterrâneo — 28/09/2026

A Casa 1 da Vila conserva o acesso existente e ganha um volume subterrâneo
contínuo com porão, túnel e QG. O inventário passa a **58 lugares/acessos / 57
interiores distintos**. Neste escopo: **0 certificados integralmente, 1 em
validação, 0 não iniciados**. História e contrato técnico em
[secret-headquarters.md](secret-headquarters.md).

- [x] Parede traseira e chão recortados; caminhada física casa → anexo → porão.
- [x] Estante e parede do porão abertas; landing do túnel alinhado sem instância.
- [x] Sólidos marcados, móveis fora do corredor e guardas da Casa 1 autorizam
  Dante após a entrega da pasta.
- [x] Câmeras do porão e túnel usam camada subterrânea e excluem as coberturas.
- [x] Estado, snapshot, pasta, quatro pistas, keypad, energia e primeira rota.
- [x] Áudio de túnel, reverb temporário dos SFX, goteiras e três ratos suspensos.
- [x] Contratos isolados: progressão **68/68**, pasta **32/32** e túnel **61/61**.
- [x] Reforma 3D: alvenaria com juntas, arcos, poças irregulares, móveis
  modelados, gerador, cama de campanha, luminárias e setor lacrado visível.
- [x] Varredura física de jogador/NPC: **41/41**, incluindo estante/patamar, curvas, rampas,
  consoles, portão e móveis. Contorno/câmera de interior: **25/25**.
- [x] Fotos reais de casa, porão, túnel e QG; oclusão positiva/negativa de
  Dante/NPC junto à mesa do QG. Evidências em `secret-headquarters-v2/review/`.
- [ ] Retorno integrado completo após a correção final do pivô da estante.
  A ida ao QG e a subida de volta pelo túnel passaram antes desse ajuste.
- [ ] Travessia física integrada de jogador e NPC contra todos os novos sólidos.
- [ ] Frame time antes/depois na cena real; processos Godot concorrentes impedem
  comparação confiável nesta sessão.

## Perseguição policial em interiores — 28/09/2026

Visitantes policiais passam pela mesma fronteira de contexto usada pelo jogador,
após entrada observada ou denúncia interior. Nenhuma sala, câmera, luz ou mobília
foi criada ou reformada. Inventário global preservado em **58 lugares/acessos /
56 interiores**; **zero novas certificações integrais**. A garagem do Maciota
continua sem admissão policial e sem combate.

- [x] Implementação: equipe existente, chegada à porta exterior, transferência
  limitada a quatro visitantes, admissão por cápsula/piso livre e colisão nativa.
- [x] Rig original no mundo 3D da sala, sem viewport ou sprite duplicado; navegação
  usa os sólidos nativos e mantém máscara física; limpeza no descarregamento.
- [x] `tests/police_response/test_tactics.gd`: **28/28** verificações headless,
  incluindo LOS com controle positivo, movimento varrido, entrada obstruída,
  admissão, busca, saída e proteção do Maciota. Log em
  `evidence/police-response-20260928/tactics-headless.log`.
- [x] Pose dos cinco escalões: **101/101** contratos headless de mãos no cabo e
  guarda-mão, recarga, direção do cano, rapel/arnês e retorno à arma após aterrissar.
  Log `evidence/police-response-20260928/officer-poses-headless.log`; ainda não
  comprova qualidade visual, profundidade ou desempenho renderizado.
- [x] Integração Main e fotos reais no percurso da Ammu-Nation: entrada e saída
  pela FullSession, mesmo agente transferido, corpo fora dos sólidos e oclusão
  à frente/atrás do expositor, com jogador e residente no mesmo buffer 3D.
  Fotos novas após a correção da arma em `evidence/police-response-20260928/interior/`;
  log `interior-final-render.log`. Uma amostra não certifica todas as plantas.
- [ ] Fotos reais antes/depois e frame time comparável: baseline renderizado
  bloqueado por processos Godot concorrentes de outra sessão; não há aprovação
  de desempenho baseada apenas nos contratos headless ou nas fotos.

## Casas compráveis: uso doméstico e garagem — 28/09/2026

Westgate Garden, Quayside e Canal North: **3 lugares / 3 interiores existentes**,
sem nova sala ou novo acesso. As três garagens abertas pertencem aos terrenos.
Inventário global preservado em **58 lugares/acessos / 56 interiores**. Neste
escopo: **0 certificados integralmente, 3 em validação, 0 não iniciados**.
[Implementação, integração da mochila e evidências](residence-living.md).

- [x] Propriedade bloqueia tanto a porta física quanto a admissão antes da compra.
- [x] Guarda-roupa, geladeira, baú, cama, arsenal e save nos seus móveis; spawn e
  aproximações livres nas três plantas. Saves de teste não usam a partida real.
- [x] Colisão varrida de jogador/NPC contra os móveis, incluindo baú e mesa novos;
  fotos reais separadas de profundidade com dois atores na sala.
- [x] Carro e moto em slots separados: guardar após desembarque, retirar sem
  duplicação, save completo e reconstrução dos dois veículos nas três casas.
- [x] Baú bloqueado sem mochila; contrato de transferência e persistência validado
  com provedor controlado. Arquivos da mochila em desenvolvimento preservados.
- [ ] Integração com a mochila real: depende do provedor e da persistência dela.
- [ ] Comparação de frame time sem concorrência: amostras de 30 s nos seis
  cenários estão registradas, mas outras execuções Godot permaneceram abertas.
- [ ] Certificação integral do ambiente: evidência local não recertifica todos
  os obstáculos/ângulos nem substitui o gate de desempenho.

## Contêineres térreos do porto — 28/09/2026

18 lugares físicos / 18 volumes interiores distintos no próprio mapa, sem
novos acessos de transferência no PlaceCatalog. Somados ao inventário anterior
de 34 acessos / 32 interiores: **52 lugares/acessos e 50 interiores exploráveis**.
Neste escopo: **0 certificados integralmente, 18 em andamento, 0 não iniciados**;
os contêineres empilhados superiores continuam cenário. Não recertifica ambientes
anteriores. [Implementação, evidências e pendências](port-container-lockpick.md).

- [x] Lockpick na Ammu-Nation, quantidade persistente e minigame de ângulo/torque.
- [x] Portas físicas, entrada caminhando, coleta, saída e reconstrução por streaming.
- [x] Câmera superior com teto oculto; restauração de ângulo/zoom ao sair.
- [x] Colisão de jogador/NPC e oclusão renderizada com controles positivos.
- [x] Dinheiro, munição, armas, colete e vazios; recibos por carga sem duplicação.
- [x] Reposição em 20 minutos, três layouts com colisão/oclusão e bloqueio por ocupantes.
- [x] Ciclo e relógio salvos; testemunhas com linha de visão acionam viatura real.
- [ ] Comparação renderizada de frame time antes/depois sem processos concorrentes.
- [ ] Evidência visual anterior/final equivalente: fotos finais disponíveis;
  captura inicial interrompida por falha de gravação, baseline a reconstruir.

## Vila dos caminhoneiros / Posto do Tonico — 28/09/2026

Seis casas acessíveis no próprio mundo, com seis interiores distintos; o
balcão do posto é exterior. Somadas ao inventário de 52 lugares/acessos e
50 interiores incluindo os contêineres: **58 lugares/acessos e 56 interiores**.
Neste escopo: **0 certificados integralmente, 6 em andamento, 0 não iniciados**.
[Escopo e evidências](truckers-village.md).

- [x] Sólidos e aproximações: 328 verificações físicas; casas rotacionadas,
  quintais, bombas, bancos, vegetação e balcão. Acesso a pé livre e veículos
  bloqueados nos postes; tráfego termina no estacionamento externo.
- [x] Missão exclusiva e recompensa única com guardas de alcance/vida.
- [x] Fluxo integrado final de checkpoint e conserto do veículo; Main sem falhas,
  29 checks de lógica aprovados. Checkpoint real apenas na conclusão.
- [x] Fotos e oclusão renderizada separada para jogador/NPC; coberturas por
  presença, paleta corrigida e revisão da borracharia aberta.
- [x] Revisão country: três caminhantes mais Tonico, 47 checks de movimento
  e combate; compra/assalto, 26 checks e fluxo Main real com menu, economia,
  crime, persistência e dano. 18 árvores e capim/arbustos entre as casas.
- [x] Seis portas físicas automáticas, mobiliário sólido, câmera interna e
  restauração do exterior; 137 checks de interiores e passagem real em Main.
- [x] Dois moradores de doze por casa, chamado dos vizinhos e persistência;
  47 checks próprios, dano e alarme reais no Main.
- [x] Sete veículos utilizáveis, admissão física e restauração sem duplicação.
- [x] Dinheiro nas seis casas com recibos; 67 checks incluindo restauração,
  jogador morto, fora da casa, região incorreta e tentativa de duplicação.
- [x] Menu de balcão 350 × 210 validado após 45 frames, sem cortar botões.
- [x] Fotos finais dos seis interiores e 36 controles de jogador/NPC à frente,
  atrás e ao lado de móveis. Copas liberadas somente na câmera interna;
  sólidos, troncos e oclusão física preservados. Pasta `homes-final/`.
- [ ] Comparativo de performance aprovado; baseline renderizado disponível.

## Terminal público de Harbor — 28/09/2026

Um novo cais exterior com abrigo aberto e passarela, sem interior isolado novo:
inventário de interiores mantido em **34 acessos / 32 interiores**; zero novas
certificações integrais. [Escopo, fotos reais, testes e métricas](harbor-life-20260928.md).

- [x] Travessia física barco → cais → passarela → cidade; colisão de banco,
  barreiras e portão; posto dos pescadores apoiado e livre.
- [x] Oclusão inspecionada separadamente, com personagem à frente, atrás e ao
  lado do banco/abrigo. Capturas reais no registro.
- [x] Ciclos de viagem, população limitada, dano, atropelamento, morte e retorno;
  conservação de carga, save e regressões da abertura/garagem.
- [ ] Ausência de regressão de performance: comparação renderizada executada,
  com aumento de percentis e pico na chuva; aprovação pendente.

## Iluminação externa e mapa 2D — 28/09/2026

Sem novos lugares ou interiores: inventário mantido em 34 acessos / 32 interiores.
As novas fontes usam os postes, torres do porto e luminárias elevadas da Vértice;
nenhum acesso, móvel ou bloqueio de piso foi alterado. Interiores isolados não
recebem o preenchimento exterior e desativam o novo conjunto de luzes.

- Controlador: 26 checks aprovados de ciclo de vida/limites/transições;
  regressão de clima, sombras, dia/noite aprovada. As validações físicas anteriores
  permanecem aplicáveis à geometria de circulação, que não mudou.
- Fotos reais antes/depois e amostras de Main:
  `evidence/outdoor-lighting-20260928/{before,after,confirmation}/`.
- Editor 2D: 24 checks funcionais aprovados; performance com pendência de
  picos e limite preexistente, conforme `docs/world-editor.md`.
- Métricas, limites e estado de performance em `docs/outdoor-lighting-20260928.md`.
  Não se trata de nova certificação dos 32 interiores.

## Delegacia — fachada e calçada — 28/09/2026

Revisão de 1 acesso exterior existente: prédio de 18 × 10 m, ampliado para o
lado da praça; plataforma, mobiliário e rampa limitados à borda Z=130,5 da
Dock Street de 14 m. Sem novos lugares/salas: permanecem 34 acessos e 32
interiores. Neste escopo: 1 acesso validado, 0 em andamento, 0 restante.
O interior da delegacia conserva o acabamento e a câmera existentes.

- Fotos reais: `evidence/police-frontage-20260928/before/benchmark.png` e
  `after/benchmark.png`; entrada, interior e retorno em `access/`.
- `test_police_frontage.gd`: porta fechada/aberta, caminhada de entrada e saída,
  câmera/controle, spawn, policiais residentes, dimensões do editor, colisores
  rígidos e varredura de sólidos da faixa liberada aprovados em Main.
- `test_police_frontage_geometry.gd`: 22 checks aprovados, jogador e NPC sobem
  e descem a rampa e são bloqueados pelo banco. Profundidade verificada à parte
  com controles renderizados: ator visível à frente, parcialmente oculto atrás
  do banco e totalmente oculto pela parede. Evidências em `geometry/`.
- Performance: Main, RTX 4060 Laptop, Mobile, 1280×720, VSync desligado,
  limite normal 144, seed/câmera/horário fixos, 8 s aquecimento + 30 s medidos.
  Antes/depois: 110,52/131,52 FPS; p50 9,639/6,248 ms; p95 13,504/11,609 ms;
  p99 23,207/12,947 ms; máximo 72,199/23,234 ms; >33,3 ms 18/0;
  >66,7 ms 1/0. Sem regressão observada no cenário; resultado final abaixo
  de 16,67 ms em p95/p99. Primeiro aquecimento tem picos de 469,7/544,2 ms:
  não representa fluidez contínua desde o carregamento. Amostras em
  `before/performance.json` e `after/performance.json`. Repositório compartilhado
  recebeu trabalho concorrente durante a comparação; o ganho não é atribuído
  exclusivamente a esta reforma. Sem certificação de outros horários/cenários.
- Uma consulta inicial do teste precedia o registro físico do streaming;
  sincronizada por dois ticks, mantendo a exigência de bloqueio da porta.
  Avisos de Texture RID no encerramento também existem na medição anterior.

## Vértice — ocupação do terreno e esconderijo — 28/09/2026

A Vértice continua sendo **1 lugar físico**, agora com **2 interiores distintos**:
galpão/escritório contínuo e esconderijo subterrâneo. O alçapão adiciona um acesso;
o inventário passa de 33 acessos/31 interiores para **34 acessos / 32 interiores**.
Os demais lugares permanecem inalterados. No escopo desta revisão são **2 ambientes
validados / 0 em andamento / 0 restantes**, nos cenários e hardware registrados;
isso não recertifica os outros 30 interiores nem altera seus estados anteriores.

- Entrada e saída pelo fluxo existente de lugares, marcador compartilhado,
  câmera alinhada, M4A1 flutuante, segundo achado e persistência: 33 checks em Main
  aprovados em `test_vertice_hideout.gd`, incluindo nova sessão e reentrada.
- Pátio, copa e embalagem: 413 checks físicos gerais, 62 sólidos e passagem
  varrida de caminhões carregados pelas três docas. Oclusão geral: 51 checks.
  Estações de embalagem: mais 49 checks físicos e 27 de profundidade com controles.
- Subsolo: 114 checks de física/oclusão, com jogador e NPC, bancadas, armário,
  cantos, piso, corredores e posições livres de acesso e recompensas.
- Horários, portões, residentes e achados anteriores: regressão aprovada em
  `test_vertice_company.gd`.
- Comparação renderizada Main/RTX4060/Mobile/1280×720 aprovada para o orçamento
  de regime estável: p95 pátio 8,410→8,461 ms; galpão 8,540→8,635 ms; noite
  8,779→8,826 ms; copa com chuva 9,737→8,954 ms. Subsolo: p95 7,768 ms de dia e
  7,674 ms à noite. Fotos reais antes/depois e medições em [Vértice](vertice-logistics.md).
  Um pico isolado de 2,079 s na amostra intermediária não reapareceu na confirmação;
  aquecimento ainda chegou a 485 ms. Não se declara ausência de engasgos.
- Nenhuma alteração nas regras de Maciota.

## Vértice — transportadora rural — 28/09/2026

Registro histórico da primeira implantação; contagem e validação atuais na seção acima.

Novo lugar além do Neko: **1 lugar físico / 1 interior contínuo**, com galpão e escritório no mesmo ambiente. Somado ao inventário de 32 acessos/30 interiores, passa a **33 acessos / 31 interiores distintos**. Este acréscimo está **em andamento**, com **zero novas certificações integrais** até fechar a validação integrada e de desempenho; os estados dos 30 interiores anteriores permanecem inalterados.

- Física: 151 verificações aprovadas em `tests/test_port_depot.gd`, com jogador e NPC reais contra paredes, móveis, estantes e portas, além de corredores e pontos de recompensa.
- Entrada contínua, horário 8h–18h, saída após fechamento, câmera, guarda e dois recibos únicos: `tests/test_vertice_company.gd` aprovado em Main.
- Oclusão: `tests/test_vertice_depth.gd`, 51 verificações renderizadas aprovadas, com controles positivos; fotos reais e relatório em `evidence/port-logistics-20260928/depth/`.
- Fotos finais reais e métricas: [exterior](../evidence/port-logistics-20260928/after/vertice-overview.png), [interior](../evidence/port-logistics-20260928/after/interior.png), [noite](../evidence/port-logistics-20260928/after-weather-fixed/night.png). Main/RTX4060/Mobile/1280×720: pátio142,10FPS/p959,830ms; interior141,50FPS/p959,653ms; noite143,99FPS/p958,096ms após corrigir reconstrução contínua de chunks. Física e oclusão aprovadas. A baseline histórica sofreu concorrência de outras sessões e não isola a alteração; comparação rigorosa permanece inconclusiva, portanto não contar como certificação integral concluída. Histórico e amostras brutas em [Vértice](vertice-logistics.md).

## Saída dirigida do estacionamento do porto — 27/09/2026

Sem novos lugares ou interiores; contagens de migração inalteradas. `GarageRewards` detecta o carro avançando pela rampa e solicita a transferência existente antes de acabar o piso. Mantém admissão física do casco no exterior e persistência; nenhuma mudança em câmera, escala, materiais, iluminação ou mobiliário.

- Recompensas e regras existentes: `test_garage_rewards.gd`, 47 checks aprovados.
- Novo `test_port_garage_drive_exit.gd`: integração pendente. A execução foi bloqueada por erros concorrentes de compilação e arquivos ausentes em `activities/MountainProgression.gd`; tentativas anteriores pararam no embarque. O teste agora começa sentado para isolar a saída, mantendo física e transferência reais.
- Teste legado de transferência parou na criação do Ironback, antes do cenário afetado.
- Apoio após saída, colisão integrada, fotos antes/depois, oclusão e comparação renderizada de frame time permanecem pendentes. Outras instâncias Godot abertas; nenhum benchmark ou aprovação de FPS desta correção.

## Edição das fachadas de serviços — 26/09/2026

O editor passa a permitir transformação e cor de oito fachadas existentes: delegacia, hospital, bombeiros, banco, Ammu-Nation, Union, Fuel e Canal North. Nenhum lugar físico ou interior distinto foi acrescentado; contagens anteriores permanecem. As salas, câmeras internas, móveis e residentes não foram reformados. A alteração transforma fachadas, seus sólidos e acessos exteriores. Maciota e Northgate Auto não entram nesta integração; a tentativa de incluir Maciota foi bloqueada pela revisão automática.

- Controles, persistência em documento, entrada/retorno transformados e proteção de acessos vizinhos: `test_world_editor_service_controls.gd`, 46 checks (47 com prévia).
- Fachadas ampliadas/giradas: `test_service_facade_physics.gd`, 32 checks de geometria, cor, cápsula de ator livre na porta aberta e corpos físicos rígidos. As dobradiças conservam base rígida; a persiana dos bombeiros mantém sua forma animada após a ampliação.
- Delegacia em Main: `test_world_editor_service_buildings.gd` verifica porta fechada bloqueando, aberta liberando, caminhada para dentro, NPCs presentes, spawn, saída, retorno e controle. Capturas reais de exterior/interior/retorno em `evidence/service-editor-20260926/after/`; comparação exterior original em `before/benchmark.png`.
- A visibilidade normal em 3D foi conferida nas capturas. Não foi repetida a certificação completa de oclusão de todos os móveis/NPCs das oito salas; não se marca nova migração ou aprovação integral desses interiores.
- Performance exterior em Main: original/editada 143,82/143,94 FPS, p95 11,639/11,479 ms e p99 13,083/13,314 ms, sem frames estáveis acima de 33,3 ms, em amostras de 30 s após 8 s de aquecimento, Mobile/RTX 4060 Laptop/1280×720/limite 144. Comparativo dos cenários na implementação atual, não do código anterior; dados em `evidence/service-editor-20260926/{before,after}/performance.json`.

## Retomada pelo menu aéreo — 25/09/2026

Nenhum lugar ou interior novo; contagens e estados de migração permanecem inalterados. A câmera temporária do menu entrega a câmera interna já restaurada sob nuvens opacas, preservando enquadramento, alvo, posição e colisões. Save na garagem do Maciota conferido com bloqueio de armas e inventário preservado. Capturas e escopo de validação em [sky-menu-20260925.md](sky-menu-20260925.md); o comparativo isolado de performance permanece pendente. Isto não aprova novamente colisão/oclusão dos interiores existentes.

Na correção subsequente, a prévia aguarda também a restauração do motorista salvo na garagem antes da revelação. Suíte renderizada: 113 verificações aprovadas, incluindo câmera interna, arma guardada e inventário preservado; capturas em `evidence/sky-menu-fixes-20260925/functional/`. Sem alterações em salas, mobiliário, sólidos ou contagens. Abertura ainda com picos de frame time; nenhuma nova certificação de performance dos interiores.

## Isolamento da vegetação exterior — 25/09/2026

Correção compartilhada de `MountainGrass3D`: restringir à superfície física do terreno carregado, respeitar as reservas de acessos/interiores e suspender a geração em salas ocupadas. Nenhuma sala, câmera, móvel ou colisão interna foi reformada; contagens de lugares e interiores permanecem inalteradas. Testes ficaram com o usuário por instrução explícita. Fotos antes/depois, travessia nos dois sentidos, cidade/interiores e comparação de frame time desta correção estão **pendentes**, sem nova aprovação dos ambientes.

## Interiores físicos na campanha V1 — plano de 22/09/2026

[Inventário completo e ordem de execução](inline-interior-migration-plan.md): 29 interiores distintos acessíveis no porto e na serra. No início deste plano havia 2 Ammu-Nation contínuos e 27 salas isoladas. Em 22/09, os 29 estavam concluídos (15 na serra, 14 no porto); após a revisão da delegacia em 24/09, são **28 concluídos, 1 em validação (Harbor Patrol) e 0 ainda sem migração**. A contagem não inclui Northgate Auto, avião exterior nem necrotério sem acesso. A aprovação anterior cobria circulação, colisão, oclusão, reentrada/save, fotos e frame time renderizado nos cenários registrados; a nova câmera e porta da delegacia exigem validação atualizada.

### Andamento da migração integral em 22/09/2026

Os cinco testes legados da serra (`test_ski_lodge_cutaway.gd`, `test_mountain_bunker.gd`, `test_distinct_mountain_cabins.gd`, `test_mountain_cabin_scale.gd` e `test_mountain_refinement.gd`) passaram após atualizar expectativas de porta, escala e coleta automática. Quatro reloads da campanha também terminaram sem os erros anteriores de teardown durante a construção assíncrona das salas.

- **Serra, 13 interiores concluídos:** Último Abrigo, Casacos da Vila e sete chalés passaram **201/201 checks renderizados** de caminhada sem E/marcador, portas, teto, câmera, recompensas, compra, colisão e oclusão real de jogador/NPC; após estreitar a câmera das fachadas menores, passaram **165/165 checks headless**. Save/reload do Último Abrigo passou **7/7** com posição, câmera compacta, balcão e recuperação do antigo spawn fora do mapa; Casacos compartilha a mesma sala e passou o snapshot físico. O chalé Pinhais passou **7/7** no reload em disco com posição, abrigo da neve, câmera e saída, cobrindo o fluxo de save compartilhado pelos sete. Abrigo dos lenhadores (três instâncias físicas, recompensa única), Cume Branco (duas saídas), Estação Zero e Caverna da Queda passaram **150/150 checks renderizados**, incluindo sólidos, profundidade, missões, saves escritos em disco e recuperação de posições antigas. O RPG da caverna passou todos os checks do teste `test_mountain_cave_reward.gd` após limitar seu alcance inline. Fotos e JSONs reais: `%TEMP%/geteco-mountain-inline-0922/{before,after}-<id>-{exterior,interior}.{png,json}`; a foto exterior de Último Abrigo contém uma UI transitória `Game eng...`, sem relação com a fachada. RTX 4060 Laptop, Mobile, 1280×720, VSync, 30 s: p95 interno antes → depois, Último 16,912 → 16,981; Casacos 16,921 → 17,037; abrigo 16,904 → 17,019; lodge 16,902 → 16,912; bunker 16,929 → 17,052; caverna 16,897 → 16,882 ms, todos com 0 quadros >33,3 ms na amostra final. A primeira amostra serial da caverna (p95 19,209; 11 quadros >33,3) e a primeira após zoom de Último (p95 18,765; 5 quadros >33,3) ficaram preservadas como `*-interior-first.json`; repetições isoladas não confirmaram a cauda. Os sete chalés têm amostras atuais p95 16,931–17,011 ms, 0 quadros >33,3, comparadas às sete amostras históricas equivalentes por sala em `docs/measurements/interior-standard-0920/route-mountain_cabin*.json` (p95 16,912–17,036 ms; Godot 4.7.2, Mobile, RTX 4060, VSync e 30 s iguais; código de 20/09 anterior). Vila 02/03/04: 17,036 → 17,011; 16,912 → 16,983; 16,931 → 16,971 ms. A amostra histórica `cabins-expansion-before` usa outro cenário e não entrou na comparação.
- **Porto, residências e coveiro concluídos:** `test_inline_homes.gd` passou **61/61** após aguardar a preparação da fachada Canal; compra, entrada/saída caminhando sem E ou marcador, porta, teto, câmera, quatro estações e recompensas foram verificados nas quatro salas. Save/reload em disco passou **22/22** nas três residências (inclui coordenada antiga de Canal) e **6/6** no coveiro em execução isolada. `test_inline_homes_depth.gd` passou **24/24 renderizados**, com oclusão positiva/negativa de jogador/NPC e colisão do NPC com móveis em cada sala. Fotos reais limpas de exterior/interior: `%TEMP%/geteco-inline-homes-0922/retake-{exterior,interior}-{westgate_garden,quayside_house,canal_north,keeper}.png`; JSONs no mesmo diretório. Na RTX 4060 Laptop, Mobile, 1280×720, VSync e 30 s, p95 interno Westgate 17,608 → 17,790 ms e coveiro 18,849 → 17,620 ms, zero quadros >33,3 ms após. Baselines históricos de 20/09 nas mesmas condições para Quayside e Canal: p95/p99 18,174/19,091 (8 quadros >33,3) e 18,184/18,888 ms (1 quadro), respectivamente. Canal após migração: 17,987/18,321 ms e zero quadros >33,3. Quayside teve duas caudas iniciais de 23,690/43,781 ms (53 quadros >33,3) e 20,690/39,631 ms (42); dois controles posteriores com viewport normal ativo ficaram em 17,908/18,387 (0) e 18,281/18,908 ms (1). Logs `%TEMP%/inline-quayside-ablation-0923{,b}.log` comprovam `UPDATE_ALWAYS` nesses controles. Uma ablação 2×2 posterior deu 17,875/18,508 ms, mas o frame time já normalizara antes; não foi atribuído custo causal ao viewport nem reduzida sua resolução. A comparação histórica usa código anterior de 20/09 e a cauda intermitente fica registrada.
- **Porto, delegacia e clínica concluídos:** `test_inline_harbor_services.gd` passou **22/22**, save/reload **12/12** e `test_inline_harbor_services_depth.gd` **19/19 renderizados**. Passagem sem E/indicador, atendimento/cura, corredor, colisão/oclusão de jogador/NPC e restauração física foram confirmados; as formas 1–3 do prédio Bay Medical continuam protegendo as ambulâncias. Fotos/JSONs reais em `%TEMP%/geteco-inline-services-0922/`; retake limpo da clínica `retake-{exterior,interior}-clinic.png` remove o vazamento RGB e mostra a cruz de cura proporcional. Em 30 s, p95/p99 internos Harbor Patrol 17,753/18,562 → 17,464/17,895 ms (quadros >33,3: 1 → 0) e Bay Medical 17,596/18,048 → 17,769/18,236 ms (0 → 0). Exterior Patrol 17,583/19,894 → 17,684/19,560 ms (2 → 1); clínica 17,834/19,681 → 17,968/18,767 ms (1 → 0).
- **Harbor Patrol, revisão de 24/09 em validação:** enquadramento ortográfico reduzido de 19,25 para 16,0 m; sala aparente de cerca de 840×520 para 1008×626 px em 1280×720. O acesso exterior agora tem porta física que abre por proximidade, travessia a pé sem E e zoom de entrada/saída; retorno junto à mesma porta. `test_police_walkin.gd` passou headless e renderizado com porta fechada/aberta, corpo inteiro livre no vão, spawn, residentes, entrada, saída e zooms. `test_harbor_establishments.gd` passou 77/77 após aguardar o zoom; `test_camera_rig.gd` e `test_weapon_shop_walkin.gd` passaram, preservando as duas Ammu-Nation. Antes: imagem real enviada pelo usuário em `%TEMP%/codex-clipboard-214bcc01-6d9a-489e-8430-503713f136b9.png`; depois: `%TEMP%/geteco-police-walkin-0924/{exterior,interior,zoom-out,returned}.png`. Oclusão de jogador/NPC no novo enquadramento e comparativo de frame time renderizado de 30 s ainda pendentes; havia outra instância do Godot ativa durante o trabalho, portanto a medição atual não seria comparável à base anterior.
- **Porto, Maciota, Fire e Boss concluídos com caudas iniciais registradas:** `test_inline_harbor_complexes.gd` passou **39/39** nas três salas, save/reload a pé e em carro **25/25**, e `test_inline_harbor_complexes_depth.gd` **25/25 renderizados** para jogador/NPC. O gate obrigatório `test_garage_weapon_restrictions.gd` terminou sem falhas: Maciota e mecânico invulneráveis, arma guardada/bloqueada no interior, inventário e uso restaurados ao sair. Maciota p95/p99 interno 24,691/41,963 → 19,207/26,027 ms (quadros >33,3: 54 → 6) e exterior 23,420/41,876 → 18,379/23,878 ms (43 → 11). Em Northgate Fire, as três portas e os três caminhões permanecem físicos; `test_harbor_fire_station_trucks.gd` passou **23/23** ao dirigir cada veículo para fora e de volta sem duplicá-lo. A persiana se recolhe, os lintéis saem do recorte interno e o jogador fica visível; foto limpa `%TEMP%/geteco-inline-complexes-0922/retake-interior-fire.png`. Apesar de uma primeira amostra interna após migração em 17,969/18,325 ms (0 quadros >33,3) contra baseline 17,777/18,242, após o ajuste visual duas amostras deram p95/p99 18,406/27,746 (11 >33,3; 4 >66,7) e 18,681/27,685 ms (13 >33,3; 4 >66,7). Viewport reduzido só no harness a 2×2 continuou lento (18,731/29,108); ocultar visualmente NorthDistrict também (18,395/26,650). Controle pareado no mesmo boot: interior 19,656/34,941 ms, 22 quadros >33,3; ao sair, exterior 17,795/18,240 ms, zero. **Fire aprovado após aquecimento, com caudas iniciais registradas e causa não atribuída:** a amostra interna aquecida `%TEMP%/geteco-inline-complexes-0922/confirm-fire-interior.json` deu 60,063 FPS, p95/p99 17,722/18,120 ms e zero quadros >33,3, comparável ao baseline de 60,06 FPS e p95 17,777 ms. As ablações não localizaram o motivo dos picos transitórios. Garagem do chefe: `test_port_boss_garage.gd` passou **181/181** após isolar no fixture a sondagem de sólidos dos seawalls/portal do mundo; roubo, cinco carros, guardas, alarme/polícia, Neco R$50 mil e save preservados. Fotos limpas `%TEMP%/geteco-inline-complexes-0922/retake-{exterior,interior}-boss.png`. Baseline interno p95/p99 17,654/19,926 ms; duas amostras após foram 19,742/20,968 (0 >33,3) e 21,604/32,188 (16), mas a restauração do viewport normal no mesmo boot terminou em 17,663/18,160 (0), enquanto 2×2 ficou em 21,513/40,308 (34). **Performance Boss variável; não atribuir a cauda à resolução do showroom.** Fotos/JSONs gerais dos três complexos: `%TEMP%/geteco-inline-complexes-0922/`.

Atualização final de 23/09/2026 para os complexos do porto: a Monaliza estacionada usa o passe 3D da oficina quando ocupada; com o teto fechado, sprite e sombra 2D ficam ocultos sem alterar colisão, save ou embarque. Ao sair dirigindo, modelo, sprite e sombra retornam à rua. `test_inline_harbor_complexes.gd` passou **45/45**, incluindo esse ciclo, `test_inline_harbor_complexes_depth.gd` **25/25 renderizados**, `test_inline_fire_trucks.gd` **23/23** e `test_garage_weapon_restrictions.gd` **0 falhas**. Foto exterior final sem vazamento e foto interior com carro no elevador: `%TEMP%/geteco-inline-complexes-0922/retake-exterior-maciota.png` e `after-interior-maciota.png`. Fire e Boss tiveram caudas nas primeiras amostras, sem causa conclusiva; controles aquecidos no mesmo cenário renderizado deram Fire **60,063 FPS, p95/p99 17,722/18,120 ms, 0 quadros >33,3 ms** e Boss **60,061 FPS, p95/p99 17,674/17,961 ms, 0 quadros >33,3 ms**. A aprovação de desempenho se limita a essas janelas e ao hardware registrado. Na última janela Maciota de 30 s após ocultar também a sombra, RTX 4060 Laptop/Mobile/1280×720/VSync: exterior **59,712 FPS, p95/p99 18,593/23,216 ms, 5 quadros >33,3 ms** contra baseline **23,420/41,876 ms, 43 quadros**; interior **59,908 FPS, 18,727/22,297 ms, 4 quadros** contra **24,691/41,963 ms, 54 quadros**. O fixture de medição reportou dois erros de liberação tardia em `MedicalRescueWorkZone.gd:77` depois das amostras; não foram atribuídos à garagem.

- **Union, concluída:** passagem física, porta automática sem E/indicador, compra, recompensa única e retorno passaram no teste dirigido headless e renderizado. A execução renderizada também ocultou jogador e NPC atrás do anteparo, mostrou ambos em piso aberto e confirmou colisão de cada um com o balcão. Save dentro da loja passou 8/8. No mesmo cenário renderizado por 30 s, exterior p95/p99 antes → depois 24,643/45,680 → 17,867/22,700 ms, 2 quadros >33,3 ms após; interior 17,579/17,955 → 17,595/19,192 ms, 0 quadros >33,3 ms após. O retake após ajuste de ordem de desenho mostra o rack sem poste; a segunda amostra interna manteve 59,99 FPS e p95/p99 18,261/19,453 ms, sem quadro >33,3 ms. Houve amostras variáveis de 55–56 FPS em exterior/interior alternados nas duas reexecuções; a causa não foi atribuída à loja. Os JSONs no diretório são da última execução. Fotos e JSONs em `%TEMP%/geteco-union-inline-0922/`.
- **Banco de North Pier, concluído:** `test_bank_inline_migration.gd` passou 34/34 checks renderizados, incluindo circulação, roubo, recompensa única, colisão de balcão e profundidade de jogador/guarda; 30/30 na reexecução headless após compactar a textura. `test_bank_inline_save.gd` passou 8/8 em disco; save antigo fora do mapa é recuperado em piso físico seguro. Na cena real renderizada por 30 s, exterior p95/p99 17,668/19,008 → 17,870/20,467 ms, um quadro >33,3 ms em ambas; interior 17,710/18,123 → 18,048/18,389 ms e zero quadros >33,3 ms em ambas. A primeira textura interna mais pesada produziu 31 quadros >33,3 ms e foi reduzida antes da medição final. Fotos e JSONs em `%TEMP%/geteco-bank-inline-0922/`.
- **Esgoto, concluído:** entrada/saída automática e combate no mesmo XY, em camada física subterrânea, passaram no teste dirigido, assim como save seguro, cobertura animada e ausência dos indicadores E. A execução renderizada adicional confirmou oclusão de Dante e NPC atrás de parede opaca, visibilidade em piso aberto e colisão do NPC com a parede; terminou com zero falhas. Exterior renderizado antes → depois: p95/p99 19,167/25,777 → 17,601/21,150 ms; interior 16,847/17,037 → 16,953/17,346 ms, sem quadros >33,3 ms no interior. Fotos/JSONs em `%TEMP%/geteco-sewer-inline-0922/`.

- Fuel, baseline renderizado no porto, 1280×720 Mobile/RTX 4060 Laptop, 30 s: exterior 40,76 FPS, p95/p99 42,357/55,260 ms, 190 quadros >33,3 ms; interior ainda isolado 57,89 FPS, p95/p99 24,550/35,890 ms, 24 quadros >33,3 ms. Fotos e dados em `%TEMP%/geteco-fuel-cutaway-0922/before-{exterior,interior}.{png,json}`. O gargalo exterior precede esta migração; comparar o mesmo cenário após a mudança.
- Boutique Alpina, baseline renderizado na MountainPass real, mesmo renderer/GPU/resolução e 30 s por cenário: exterior 60,005 FPS, p95/p99 17,326/18,890 ms, 2 quadros >33,3 ms; interior ainda isolado 60,009 FPS, p95/p99 17,189/17,561 ms, 0 quadros >33,3 ms. Fotos e dados em `%TEMP%/geteco-boutique-inline-0922/before-{exterior,interior}.{png,json}`.
- Histórico de investigação: Boutique passou primeiro 19/19 checks funcionais; a verificação foi ampliada abaixo. Fuel passou inicialmente 32 checks e falhou dois por tempo insuficiente de caminhada no teste: 150 quadros cobriam 69 px dos cerca de 84 px exigidos. O limite foi corrigido após medir porta aberta, bloqueador desligado e ausência de colisão à frente; 38/38 checks físicos e funcionais passaram depois.
- Boutique, validação concluída: `test_boutique_inline.gd` passou **59/59 checks**, incluindo 176 aproximações de jogador/NPC contra 11 sólidos, corredor livre, compra, recompensa única de R$ 1.250, save em disco com coordenada física, migração de save antigo, teto/câmera e viewport desligado ao sair. O teste renderizado anterior passou 37/37, com parede frontal encobrindo por inteiro jogador e NPC (0 pixels visíveis) e controles positivos de 2.060 e 1.306 pixels. `test_standard_clothing_rooms.gd` passou nas outras duas lojas ainda isoladas. Fotos reais em `%TEMP%/geteco-boutique-inline-0922/{before-exterior,before-interior,after-exterior,after-interior}.png`. Exterior p95/p99 antes → depois: 17,326/18,890 → 17,356/18,286 ms, quadros >33,3 ms 2 → 1. Interior: a primeira amostra mostrou p99 19,183 ms, mas a confirmação equivalente de 30 s mostrou p95/p99 17,091/17,498 ms versus 17,189/17,561 ms antes, 60,009 FPS e zero quadros >33,3 ms. JSONs na mesma pasta.
- Fuel, validação concluída da migração: `test_fuel_inline.gd` passou 38/38 renderizado, teste de save isolado em disco 8/8 e oclusão renderizada jogador/NPC 4/4. `test_standard_bank_and_fuel.gd` passou, preservando o banco. Pisos e produtos repetidos foram agrupados em seis MultiMesh, sem alterar sólidos ou aparência na captura comparável. Duas amostras pós-ajuste de 30 s no interior: primeira 60,03 FPS, p95/p99 17,83/18,75 ms, zero quadros >33,3; confirmação 57,76 FPS, p95/p99 19,95/35,48 ms, 29 quadros >33,3. Baseline da sala isolada: 57,89 FPS, p95/p99 24,55/35,89 ms, 24 quadros >33,3. **Não houve regressão reproduzível em p95/p99; a meta provisória de 60 FPS constantes não foi demonstrada** no segundo ensaio e a cauda variou entre amostras. Fotos reais e JSONs em `%TEMP%/geteco-fuel-cutaway-0922/`; fotos de oclusão `test-player-depth.png` e `test-npc-depth.png`.

## Ammu-Nation no próprio prédio — 22/09/2026

As duas filiais agora ocupam os 8,4 × 4,4 m da própria fachada. A porta deslizante abre por proximidade; a entrada e a saída ocorrem caminhando, sem ação E nem teleporte. O teto some ao cruzar o limiar, a câmera aproxima e os expositores laterais deixam um corredor livre até o balcão. E continua apenas como ação funcional de compra junto ao vendedor. O marcador laranja e a mensagem flutuante de compra foram removidos das duas filiais a pedido do usuário.

- Porto: `test_ammunation_inline.gd` renderizado aprovou 42 checks nas duas filiais, incluindo ausência do marcador e da mensagem de compra, entrada sem E, circulação, suspensão do render vazio, colisão de jogador/NPC e oclusão com controle positivo (0 pixels ocultos / 1.719 visíveis). `test_ammunation_identity_navigation.gd` aprovou 38 checks de compras, cobrança única, circulação e retorno. `test_city_ammunation.gd` passou renderizado, com catálogo, compra, cobrança única e saída.
- Serra: `test_ammunation_mountain_world.gd` no mapa real aprovou 14 checks, incluindo compra, colisão do fogão, entrada/saída e restauração de save legado. O teste renderizado compartilhado aprovou porta, teto e catálogo também na filial da serra.
- Fotos reais antes/depois do porto e fotos atuais das duas filiais: `C:/Users/rafae/AppData/Local/Temp/geteco-ammunation-cutaway-0922/{before-exterior,before-interior,after-exterior,after-interior,mountain-exterior,mountain-interior}.png`. Os JSONs das medições estão na mesma pasta. A cópia dessas imagens para `docs/measurements` ficou pendente porque o sistema negou criação de diretório no workspace.
- Porto, Vulkan Mobile / RTX 4060 Laptop / 1280×720, janelas de 30 s: exterior antes 51,42 FPS, p95/p99 31,512/39,942 ms, 58 quadros >33,3 ms; segunda medição depois 59,32 FPS, p95/p99 18,768/28,692 ms, 9 quadros >33,3 ms. Interior antes 59,18 FPS, p95/p99 20,818/28,982 ms, 9 quadros >33,3 ms; segunda medição depois 60,03 FPS, p95/p99 17,944/18,384 ms, 0 quadros >33,3 ms. A primeira medição depois ficou mais lenta, mas a repetição não confirmou regressão; condições concorrentes podem explicar a variação.
- Serra, cena real renderizada na mesma GPU e resolução, 30 s por cenário: exterior 60,00 FPS, p95/p99 16,996/17,431 ms; interior 60,00 FPS, p95/p99 17,110/17,705 ms; nenhum quadro >33,3 ms. Repetição dirigida com seed, VSync e limite de FPS iguais ao [baseline anterior](measurements/interior-standard-0920/gunshop-before.log): interior 60,01 FPS; p95 17,008 → 16,902 ms; p99 17,403 → 17,157 ms; 0 quadros >33,3 ms em ambas as medições.
- A primeira tentativa de reexecução após a suspensão do SubViewport encontrou erros de parse transitórios em arquivos de pedestres alterados por outra sessão. Após a compilação voltar a funcionar, a reexecução renderizada passou 38/38 checks, incluindo a suspensão em ambas as filiais.

## Geteco V2 — escopo independente, 21/09/2026

**A validação ampla de `urban_detail` segue adiada.** A integração altera fachadas e aproximações dos acessos, e o despacho acrescenta veículos/equipes no exterior. Checks e capturas anteriores abaixo são históricos; não aprovam a nova montagem. O acesso do bueiro foi revalidado separadamente em 22/09, como registrado abaixo. Revalidar os demais acessos e o tráfego após concluir a implementação. A contagem permanece 31 acessos / 29 interiores, sem acrescentar salas por trocar fachadas.

Integração urbana de 21/09: Ammu-Nation externa foi reconciliada com `NorthFrontage2` em `(1550,140)` em catálogo, fachada, entrada e retorno; garagem do chefe do porto ganhou portal exterior nas dimensões V1, aproximação pelo oeste e retorno no `EXTERIOR` exato; esgoto ganhou bueiro transitável no ponto V1. Os contratos estruturais de Ammu (14 checks) e dos dois exteriores (10 checks, incluindo cápsula e paredes) passaram. As salas internas não mudaram e suas fotos históricas continuam válidas apenas para o interior; entrada real, retorno, save e oclusão exterior precisam de nova captura antes de concluir estes três acessos.

Revisão do bueiro no jogo 3D, 22/09: tampa fechada por padrão, abertura deslizante, descida com pose de escada e enquadramento temporário foram verificados na sessão real. O canteiro que ocupava o acesso e um balizador que cruzava a leitura da animação foram removidos; o piso visual e sua colisão têm um vão alinhado ao poço, com tampa sólida quando fechada e sem piso atravessando a descida quando aberta. `review_sewer_animation.gd` passou na execução renderizada limpa, incluindo a ação `E`, colisão, oclusão, entrada, saída e restauração da câmera; capturas em `geteco_v2/evidence/sewer-entry-0922/final3d-*.png`. Nova execução física confirmou que a cápsula cabe no poço e que os controles destravam no retorno. `test_harbor_access_exteriors.gd` passou 11 checks, `test_sewer_session.gd` passou 12 e `test_regions.gd` passou. Save e comparação de frame time antes/depois ainda pendentes, sem promover o acesso a concluído.

### Migração completa em andamento — atualização posterior ao primeiro trecho

**31 acessos físicos / 29 interiores distintos** no V2: garagem do Maciota e 28 definições adicionais. Os acessos compartilhados dos abrigos não multiplicam interiores. A evidência histórica do primeiro trecho abaixo permanece restrita àquele cenário.

- [x] Geometria e posições: testes dirigidos de regiões, cápsulas dos oito residentes originais e sete posições de veículos da garagem do chefe aprovados.
- [x] Apresentação e oclusão amostradas separadamente: 56 fotos de entrada/atrás de mobiliário, mais quatro salas povoadas; [relatório e fotos reais](../geteco_v2/docs/interior-visual-review.md). A aprovação é dos enquadramentos e pontos registrados.
- [x] Sessão integrada: tarefa do Maciota, transições, banco, câmera, restrição de armas, aproximação e diálogos dos oito residentes e coleta hospitalar aprovados em `test_full_session.gd`.
- [x] Maciota nativo atual: passagem do escritório e braços do elevador recolhidos com colisão; oclusão separada em [amostras reais](../geteco_v2/evidence/native-v2-depth.json), 85,23% da silhueta atrás da mesa. [Foto atual](../geteco_v2/evidence/full-native-interior-final-isolated-population24.png) e comparação de desempenho em [FULL_MIGRATION](../geteco_v2/docs/historico/FULL_MIGRATION.md).
- [x] Garagem do chefe: cinco carros e dois guardas com física dirigida e [foto renderizada](../geteco_v2/evidence/garage-guards-product.png). Comparação neutra 60 FPS, p95 17,460 → 17,615 ms, sem quadros >33,3 ms na janela estável. Pausas iniciais de aproximadamente 1,4 s e combate dos guardas permanecem fora desta aprovação.
- [x] Teste obrigatório V1: `full-v1-garage-test.log`, zero falhas; avisos de recursos retidos ao encerrar continuam registrados.
- [ ] Fluxos integrados de todos os ambientes, residentes, serviços, recompensas e restauração de saves.
- [ ] Entrada, saída e circulação completa dos veículos nas duas garagens; destino exterior com carro inteiro e apoio físico.
- Transferências dirigidas já aprovadas: 11 verificações nas duas garagens e 26 de restauração do motorista, incluindo casco completo, apoios, acesso físico à porta, câmera, inventário e ausência de duplicação. Não certificam todas as manobras de todos os 49 modelos.
- [ ] Desempenho comparável dos interiores adicionais com moradores e sistemas ativos. Medições do Maciota não aprovam as outras salas.

Migração integral **não concluída**. Estado geral em [FULL_MIGRATION](../geteco_v2/docs/historico/FULL_MIGRATION.md).

### Evidência histórica — primeiro trecho

**1 lugar físico / 1 interior distinto nesta etapa histórica:** garagem do Maciota no projeto separado `geteco_v2`. Não soma à contagem V1 abaixo nem implica migração da campanha completa. Primeiro trecho nativo 3D implementado e validado: entrada/saída, câmera fixa, conversa, peça, entrega e checkpoint próprio. Modelos originais preservados; residentes sem dano/morte. Naquela etapa o combate ainda não estava implementado; sua integração posterior preserva o bloqueio de armas.

- [x] Física: cápsulas e varreduras, moradores fora dos móveis, passagem do escritório e caminhada contínua pelos pontos da tarefa.
- [x] Função: ordem, repetição, coleta única, transições recusando destino ocupado e restauração física de save/câmera/etapa/restrição.
- [x] Visual: [fachada real](../geteco_v2/evidence/v2-exterior.png), [interior real](../geteco_v2/evidence/v2-interior-entry.png), [diálogo](../geteco_v2/evidence/v2-dialogue.png). Câmera alinhada, escala humana e marcador compacto.
- [x] Oclusão separada: [controle atrás da mesa](../geteco_v2/evidence/v2-depth-behind.png), [amostras](../geteco_v2/evidence/v2-depth.json), 84,8% da silhueta visível atrás contra 99,9% na frente.
- [x] Desempenho estável renderizado: mesma rota exterior antes/depois 60 FPS; interior 60 FPS durante 30 s, 52,50 m caminhados; condução com 96 pessoas também 60 FPS. Sem quadros >33,3 ms nas amostras estáveis. Aquecimento tem picos até74,296 ms; ausência de engasgos iniciais não certificada.
- [x] Teste obrigatório V1 de restrição de armas: 0 falhas; avisos de limpeza de recursos no encerramento registrados.

Detalhes, métricas e limites: [validação V2](historico/VALIDATION.md). A comparação exterior avalia o acréscimo desta integração; o novo interior fornece baseline própria, sem alegação de superioridade sobre a sala híbrida V1.

### Acesso às lojas de armas na V2 — 23/09/2026

**2 fachadas / 2 interiores distintos nesta revisão V2:** Ammu-Nation do porto (`harbor_ammunation`) e loja de armas da serra (`mountain_gunshop`). Não alteram a contagem da migração V1. Aproximação abre a porta, caminhar pelo centro da entrada inicia um zoom curto centralizado na fachada e carrega o interior já existente. A saída também é por caminhada; E permanece apenas para ações funcionais como atendimento no balcão. A passagem exterior–interior ainda usa a troca de cena da V2 após o zoom, portanto não é uma sala física contínua no mapa.

`geteco_v2/tests/test_weapon_shop_walkin.gd` passou nas duas filiais em execução headless e renderizada: ausência de E para entrar/sair, zoom observado, entrada, câmera interna, atendimento com E e saída. `geteco_v2/tests/test_harbor_establishments.gd` passou 77 verificações renderizadas; `geteco_v2/tests/test_regions.gd` aprovou os sólidos e spawns das duas lojas; `geteco_v2/tests/test_camera_rig.gd` passou sem falhas. Fotos reais exterior/zoom/interior das duas lojas: `C:/Users/rafae/.codex/visualizations/2026/09/23/01a0cf97-e522-7a51-912d-8349c2270087/v2-weapon-walkin/`.

**Aprovação integral pendente:** medir frame time renderizado antes/depois em sessão isolada, sem os processos Godot concorrentes observados nesta revisão; confirmar colisão por aproximações e oclusão de jogador/NPC especificamente nesta nova rota. Os testes funcionais e as capturas acima não substituem esses dois gates.

Atualização: 20/09/2026. Padrão: [Chalé + Maciota](interior-standard.md).

### Hospital, árvores e guindastes — revisão de acesso de 20/09/2026

Revisão em andamento no Bay Medical: a porta interna foi transferida para a face sul, coerente com a fachada pública. Câmera ortográfica alinhada, escala humana, móveis e luz clínica preservados; o spawn abre para o corredor central. Removido o vidro fixo que duplicava as folhas móveis da fachada. A revisão invalida a conclusão anterior deste hospital até fechar os checks atuais; inventário permanece 30 lugares no escopo e 29 interiores distintos.

Fotos reais anteriores em `measurements/hospital-cranes-0920/before-facade.png`, `before-interior.png`, `before-northstar-crane.png` e `before-tree-behind.png`. São fixtures renderizadas, não benchmark. `test_hospital_and_crane_access.gd` verifica orientação, ciclo das folhas, corpo inteiro no spawn/corredor e colisões dos pedestais; `test_tree_canopy_occlusion.gd` reproduziu três falhas lógicas e três visuais antes da correção do adaptador de cenários desenhados. `test_south_port.gd` passou após calibrar pedestal: 4.686 passos, 32 trabalhadores, três caminhões, carregamento e partida, zero falhas; recursos retidos ao encerrar fixture registrados como limitação.

Fotos posteriores no mesmo diretório: `after-interior.png`, `after-facade.png`, `after-facade-open.png`, `after-tree-behind.png`, `after-tree-front.png` e `after-crane-depth0.png` a `after-crane-depth2.png`. Inspeção confirma saída sul e copas/treliças sobre o ator atrás. `test_hospital_and_crane_access.gd`: 22 checks renderizados aprovados, incluindo 4 aproximações físicas do tronco, três pedestais e pixels dos três braços dos guindastes com controles positivos à frente. `test_tree_canopy_occlusion.gd`: 30 checks renderizados, zero falhas; árvore de rua reduziu pixels expostos do ator atrás de 14.080 para 7.109, preservando a frente. A gravação de uma foto coastal no diretório legado falhou por acesso, mas seu teste de pixels passou.

`test_standard_harbor_rooms.gd -- ClinicInterior` aprovado no HarborGame real: 512 aproximações varridas com jogador/NPC, entrada/saída, corredor/vida, posições autoradas dos funcionários, profundidade compartilhada e suspensão da sala vazia, zero falhas. Oclusão por pixels: ator encoberto 0 pixels alterados em ambos; controles visíveis 931 (jogador) e 1.041 (NPC). Foto integrada `measurements/interior-standard-0920/ClinicInterior-standard.png`. O fixture deixa recursos/RIDs retidos ao encerrar, registrado como limitação de teardown.

Inspeção dirigida após confirmação do local pelo usuário: os três guindastes ao lado do **Northstar**, em y=990/1460/1700. Bases inteiras no cais x=3140..3191; cinco superfícies de água/ripples em z=-1, casco/convés em z=0 e estruturas separadas em z=4. Comparação renderizada água ligada/oculta em 30 pontos (duas posições de pedestal e oito nas duas longarinas de cada guindaste) teve diferença RGB zero em todos, confirmando metal acima da água nesses pontos. Fotos integrais `after-northstar-full0.png`, `after-northstar-full1.png`, `after-northstar-full2.png`; log `northstar-water-layer.log`, todos em `measurements/hospital-cranes-0920/`. O teste dirigido ampliado passou 26 checks; não houve mudança adicional de runtime após esta inspeção. A captura anterior não demonstrou água cobrindo metal, portanto esta evidência certifica a ordenação atual observada, sem atribuir uma causa anterior não reproduzida.

Pendente nesta revisão: comparação de desempenho renderizado equivalente. Nenhum FPS aprovado por testes headless; meta provisória 60 FPS / 16,67 ms, investigar p95/p99 com regressão superior a 5% em amostras equivalentes. A primeira tentativa geral não teve foco de janela válido; uma amostra posterior isolada não substitui baseline comparável.

### Pedras da travessia junto ao avião e orientação automática — 20/09/2026

As três plataformas planas receberam laterais com volume, contorno chanfrado irregular, faces minerais, grãos, rachaduras e faixa úmida. Os anéis geométricos foram substituídos por reflexos discretos interrompidos. Desenho estático em CanvasItem, sem novos viewports, luzes ou loops por quadro. As posições e os polígonos transitáveis usados pelo sistema de água permanecem idênticos.

Removidas as mensagens automáticas que indicavam loja de roupa térmica e rota do chefe. O aviso de temperatura ficou apenas “FRIO INTENSO”; indicadores de condição, interações e objetivos funcionais permanecem. [Antes](measurements/interior-standard-0920/lake-rocks-before-plane.png) · [Depois](measurements/interior-standard-0920/lake-rocks-after-plane.png).

Validação integrada: três áreas secas originais, passos fora da água nas pedras, apresentação estática e ausência do aviso de rota aprovados. Mesmo MountainPass, câmera, seed, Mobile/RTX 4060 Laptop, 1280×720, VSync/limite 60 e janelas 5+5+30 s; monitor sem concorrência detectada. Antes → depois: **59,93 → 60,01 FPS**, p95 **17,113 → 16,951 ms**, p99 **18,890 → 17,163 ms**, máximos estáveis **28,795 → 17,882 ms**, zero quadros acima de 33,3 ms em ambos. Primeiro quadro global **1.639,118 → 1.695,157 ms**, separado da visita conforme diagnóstico anterior. Logs/JSONs `lake-rocks-before*` e `lake-rocks-after*`. Não acrescenta lugares nem altera a contagem de 28/30 aprovações.

### Fachada compacta do Maciota — 20/09/2026

Revisão exterior em andamento: largura 19,5 → 7,8 m e profundidade 15,625 → 6,25 m (redução de 60% em cada eixo); altura e vão de carros preservados. Prédio vizinho fechado, com janelas, cornijas, calha e chaminé, no mesmo viewport estático. Nenhum novo interior acessível; contagens de lugares acessíveis e interiores permanecem iguais. A certificação anterior do interior não certifica esta revisão exterior.

Capturas reais do motor em fixture de fachada: [antes](measurements/maciota-exterior-before.png), [depois](measurements/maciota-exterior-after.png). Não são capturas da cena integrada. `capture_maciota_compact_exterior.gd`: quatro movimentos varridos contra as fachadas bloqueados e passagem lateral livre. `test_garage_weapon_restrictions.gd`: zero falhas, incluindo entrada/saída, restauração, inventário e invulnerabilidade; avisos de recursos retidos ao encerrar o teste headless. Pendente: oclusão de jogador/NPC e aproximação física com carro no cenário integrado, fotos integradas e benchmark renderizado antes/depois. Outras instâncias Godot estavam abertas; nenhum resultado de FPS atribuído a esta alteração. Meta provisória 60 FPS / 16,67 ms, investigar regressão superior a 5% em p95/p99, em comparação equivalente na RTX 4060 Laptop. Não aprovar esta revisão exterior até concluir os checks pendentes.

### Identidade exterior do Maciota no V2 — 22/09/2026

Garagem existente, sem novo acesso ou interior: **31 acessos físicos / 29 interiores distintos** continuam. A fachada ganhou pórtico de metal e latão, nome próprio MACIOTA, cobertura e telhado de oficina, baia com elevador e carro visíveis em sombra, luminárias que acompanham a noite e marcas de uso no piso. Os quatro sólidos originais da fachada e o ponto de entrada não mudaram; os novos detalhes são visuais, sem `interior_solid_id` ou colisão.

- [x] Capturas reais isoladas com a mesma câmera: `C:/Users/rafae/.codex/visualizations/2026/09/22/01a0cb63-0146-7b31-ac11-ff2a15165ffd/maciota/isolated-before.png` e `isolated-after.png`. Fotos reais integradas em `city-before.png`, `city-after.png` e `city-night.png` na mesma pasta; estas têm tráfego e população variáveis e não são benchmark.
- [x] Geometria, acesso e colisão: `capture_maciota_exterior_life.gd` verificou os quatro sólidos originais; `test_maciota_exterior_access.gd` passou entrada/retorno livres e quatro varreduras contra parede/pilares; `test_maciota_world.gd` passou sem falhas. A cena `Main.tscn` carregou e foi fotografada de dia e à noite.
- [x] Entrada e saída integradas: `test_full_session.gd` passou pelas etapas da garagem, incluindo restrição de armas, snapshot em memória e retorno ao exterior; `test_maciota_exterior_access.gd` confirmou a cápsula livre nos pontos de entrada e retorno.
- [ ] Restauração integral de save: `test_full_session.gd` terminou com uma falha posterior em “Cancelled mission can be saved and restored”, após sair da garagem e visitar outros locais. A suíte completa não está aprovada nesta revisão.
- [ ] Oclusão de jogador e NPC na aproximação, circulação veicular completa e desempenho renderizado comparável. A primeira amostra A/B de 30 s foi invalidada por outras instâncias Godot concorrentes e por erro de escrita do relatório após as amostras. A segunda A/B/A renderizada em `Main.tscn` (Mobile, RTX 4060 Laptop, 3440×1440, 100 pessoas, 103 veículos, noite, limite 60, VSync desligado, foco 100%) registrou 48,16 → 20,56 → 11,02 FPS, com p95 34,56 → 140,76 → 183,07 ms. O controle final piorou mesmo com o acabamento novamente oculto; outras instâncias surgiram durante a medição. Dados brutos: `C:/Users/rafae/.codex/visualizations/2026/09/22/01a0cb63-0146-7b31-ac11-ff2a15165ffd/maciota/frame-times-contended.json`. **Comparação inválida para atribuir custo à fachada; desempenho não aprovado.** Repetir isolado na resolução normal 1280×720, com meta provisória 60 FPS / 16,67 ms e confirmação se p95/p99 crescerem mais de 5%.

**Revisão exterior ainda em andamento.** A evidência visual e física acima não conclui os checks pendentes.

### Histórico da revisão dos indicadores — 20/09/2026

Regra permanente do Maciota: `test_garage_weapon_restrictions.gd` aprovado, zero falhas (entrada, saída, restauração, bloqueio de armas e proteção dos dois personagens).

Pedido atual corrigido pelo usuário: retângulo laranja com cantos arredondados já implementado (26×14, raio 4), sem E ou símbolo de controle; não um quadrado. Corrigido o componente compartilhado `DoorAccessMarker`, usado pelo `BuildingEntrance` no porto e na montanha, incluindo casa do coveiro, lojas, cabanas, caverna, lodge, estação, delegacia, hospital, garagem e bombeiros. Fachadas sem interior conectado não anunciam acesso. Revisados separadamente os avisos das três residências, garagem do chefe e entrada/saída do esgoto; compra, horário fechado e interações com objetos mantêm seus textos funcionais. O retângulo usa desenho estático compartilhado, sem animação por frame.

Correção do formato conferida em captura renderizada: [retângulo arredondado na porta](measurements/interior-standard-0920/rounded-door-marker.png). Os 24 checks dirigidos passaram novamente após a correção; registro em `measurements/interior-standard-0920/rounded-door-marker-checks.log`. A skill e o padrão versionados também registram esse formato. Esta validação é do indicador e não conclui a reforma global dos interiores.

Referência anterior: imagem fornecida pelo usuário `C:/Users/rafae/AppData/Local/Temp/codex-clipboard-03ace57d-c7c8-4a9e-a871-301553d54f9f.png`. Captura renderizada posterior: `C:/Users/rafae/AppData/Local/Temp/geteco-door-marker-after.png`, reproduzível com `tests/capture_door_marker_review.gd`. Revisão visual integrada de todos os locais e comparação de frame time permanecem pendentes; uma sessão de jogo já estava aberta. Esta correção de indicadores não certifica colisão/oclusão nem altera a contagem de interiores aprovados abaixo.

Validação dirigida: `test_interaction_keycap.gd` passou 24 checks (marcador em aproximação, controle, bloqueio/transição e destino conectado; teclas de outras interações preservadas). `test_cemetery_keeper_home.gd` passou, incluindo entrada e retorno à porta; o relógio simulado recebeu o campo `is_dynamic_time` exigido pelo serviço médico. `test_port_boss_garage.gd`: 172 checks, duas falhas no prazo/chamada da polícia. `test_residence_prototype.gd`: entradas, saídas, circulação e restauração passaram; três falhas nas expectativas de preço/troca de imóvel. `test_manhole_sewer.gd`: entrada, saída, circulação, coleta e restauração passaram; cinco falhas de arma/projétil/granada no mundo físico isolado. Essas falhas não foram corrigidas nesta revisão visual, e os testes amplos não estão aprovados. O ambiente também reportou restrições na gravação de logs, leitura de certificados e recursos retidos ao encerrar.

## Escopo aprovado em 20/09/2026

O usuário aprovou o resultado visual do chalé alinhado e autorizou a migração global. Escopo reconciliado: **29 interiores + baia externa Northgate Auto + avião externo = 31 lugares**. As sete cabanas e três lojas de inverno agora têm plantas e recompensas independentes. O Chalé da Encosta oferece R$ 5.000. A antiga WorkshopInterior não tem porta conectada; o local acessível correspondente é a baia drive-in externa.

## Contagem atual

O inventário inicial incluía uma sala sem acesso e compartilhava sete cabanas e três lojas de inverno. Após conferir acessos e separar essas salas, são **29 interiores distintos acessíveis**. Salas criadas sob demanda contam como interiores distintos, mesmo quando não estão carregadas. Não é contagem de portas: bombeiros tem três portões, lodge tem duas saídas.

| Unidade | Total | Concluídos | Em andamento | Não iniciados | Restantes para aprovação |
|---|---:|---:|---:|---:|---:|
| Lugares no escopo atual, incluindo o avião externo | 30 | 27 | 3 | 0 | 3 |
| Interiores distintos acessíveis | 29 | 26 | 3 | 0 | 3 |

**Ajuste de escopo solicitado pelo usuário:** Northgate Auto foi retirado da reforma. A oficina de reparo preserva apenas o fluxo/animação do carro entrando e saindo e o reparo existente; sua reforma visual foi desfeita manualmente. O inventário continua tendo 31 lugares acessíveis, mas esta migração abrange 30. Não contar a oficina como interior reformado ou como pendência dos outros ambientes.

Continuação autorizada com dois agentes: montanha (seis lugares), locais especiais do porto (cinco após retirar Northgate Auto) e integração/porto (nove). As implementações estão aplicadas; a contagem de conclusão depende dos checks e das medições, não da distribuição do trabalho. As evidências atuais por local prevalecem sobre os registros históricos de tentativas abaixo.

Comparativos atuais de câmera, qualidade e desempenho: [nove interiores do porto](measurements/interior-standard-0920/harbor-performance-report.md), [casas, esgoto e garagem do chefe](measurements/interior-standard-0920/special-harbor-report.md) e [diagnóstico monitorado dos picos](measurements/interior-standard-0920/harbor-stall-trace-report.md). Os relatórios distinguem FPS medido, resolução interna, amostragem de bordas e frequência de atualização; o limite de 60 FPS não é uma medição.

“Em andamento” indica critérios ainda pendentes, mesmo quando a apresentação já foi aplicada. As referências também passam pelos mesmos critérios; não contam como concluídas apenas por escolha artística.

## Inventário

Em cada linha, conclusão exige: visual; entrada/saída e indicador; colisão/spawn/circulação; oclusão de jogador e NPC; FPS e suspensão da sala vazia. “Concluído” refere-se aos cenários e hardware medidos, não a certificação de todo o jogo.

| Interior / lugares físicos | Quantidade | Estado | Evidência / próxima pendência |
|---|---:|---|---|
| Porto — Garagem do Maciota / Westgate | 1 | Concluído | [Foto final](measurements/interior-standard-0920/harbor-final-GarageInterior.png); 1.008 aproximações, profundidade, retorno do ator e regras de armas aprovados; 59,98 FPS, p95 18,137 / p99 18,490 ms, sem regressão no comparativo |
| Porto — Harbor Patrol | 1 | Pendente de desempenho | [Foto final](measurements/interior-standard-0920/harbor-stall-trace-PoliceInterior.png); câmera, dinheiro, 2.384 aproximações e profundidade aprovados. Medição monitorada 52,52 FPS, p95 33,574 / p99 47,723 ms durante trabalho regional solicitado pelo ônibus; meta 60 não aprovada |
| Porto — Bay Medical | 1 | Pendente de desempenho após revisão de acesso | Porta interior sul; vidro fixo removido da abertura exterior. 512 aproximações jogador/NPC, entrada/saída/cura/profundidade/suspensão e 22 checks da fixture aprovados. Evidências atuais acima. Medição anterior de 60,02 FPS não certifica esta revisão. |
| Porto — Northgate Auto, baia de serviço externa | 1 | Fora da reforma a pedido | Reforma desfeita manualmente. `northgate-preserved-final.log`: 0 falhas, animação/porta, reparo, cobrança única de R$ 100 e controle aprovados. [Foto preservada](measurements/interior-standard-0920/northgate-preserved.png). Não entra nos 30 lugares deste escopo |
| Porto — Northgate Fire / 03 | 1 | Concluído no cenário isolado | [Foto final](measurements/interior-standard-0920/harbor-stall-trace-FireStationInterior.png); 240 aproximações, profundidade, ciclo dos três caminhões/portões e cura aprovados. Medição monitorada 60,01 FPS, p95 17,759 / p99 18,177 ms; picos da conferência anterior permanecem documentados |
| Porto — Ammu-Nation | 1 | Concluído na reforma em linha | Fotos e medições atuais na seção de 22/09; entrada/saída caminhando, teto, câmera, catálogo, colisão, oclusão e suspensão do render aprovados; segunda medição renderizada 60,03 FPS no interior, p95 17,944 / p99 18,384 ms, 0 quadros >33,3 ms |
| Porto — Union | 1 | Concluído | [Foto final](measurements/interior-standard-0920/harbor-final-ClothingRoom0.png); planta própria, dinheiro, compra, física, profundidade e suspensão aprovadas; 60,01 FPS, p95 17,693 / p99 18,071 ms, sem quadros estáveis acima de 33,3 ms |
| Porto — Banco North Pier | 1 | Concluído | [Foto final](measurements/interior-standard-0920/harbor-confirm-BankInterior.png); NPCs proporcionais, 400 aproximações, profundidade, guardas, cartão/gazua, cofre e R$ 10.000 sem duplicação aprovados. Confirmação 60,01 FPS, p95 17,959 / p99 18,899 ms, primeira visita 21,994 ms; pico anterior não se repetiu |
| Porto — Conveniência do posto | 1 | Concluído | [Foto final](measurements/interior-standard-0920/harbor-fuel-isolated-FuelInterior.png); atendente proporcional, planta própria, 192 aproximações, dinheiro, profundidade e caixa com cobrança única aprovados. Medição isolada monitorada: 59,98 FPS, p95 17,614 / p99 18,349 ms, primeira visita 33,269 ms; nenhuma captura concorrente detectada |
| Porto — Garagem do chefe | 1 | Concluído | [Foto](measurements/interior-standard-0920/port-boss-garagem.png); 174 checks de gameplay/física/profundidade e cinco de save/pausa do alarme aprovados; 60,01 FPS, p95 18,144 / p99 18,491 ms |
| Porto — Casa do zelador | 1 | Concluído | [Foto final](measurements/interior-standard-0920/harbor-final-CemeteryKeeperInterior.png); dinheiro, 192 aproximações, profundidade e suspensão aprovadas; 60,01 FPS, p95 18,084 / p99 18,382 ms, sem quadros estáveis acima de 33,3 ms |
| Porto — Casa Westgate Garden | 1 | Concluído | [Foto final](measurements/interior-standard-0920/special-harbor-after-westgate_garden.png); planta própria, R$ 300, marcador, física, profundidade, save e suspensão aprovados; 59,98 FPS, p95 17,839 / p99 18,283 ms |
| Porto — Casa Quayside | 1 | Pendente de desempenho | [Foto final](measurements/interior-standard-0920/special-harbor-after-quayside_house.png); planta própria, R$ 700, marcador, física, profundidade, save e suspensão aprovados. Confirmação 57,38 FPS, p95 17,675 / p99 18,263 ms, com picos regionais já presentes no baseline; meta 60 não aprovada |
| Porto — Casa Canal North | 1 | Concluído | [Foto final](measurements/interior-standard-0920/special-harbor-after-canal_north.png); planta própria, R$ 1.500, marcador, física, profundidade, save e suspensão aprovados; 60,01 FPS, p95 17,936 / p99 18,298 ms |
| Porto — Galeria subterrânea / esgoto | 1 | Concluído | [Foto final](measurements/interior-standard-0920/special-harbor-after-sewer.png); física, profundidade, escada, arma por contato, save e combate isolado aprovados; 60,00 FPS, p95 16,785 / p99 16,993 ms |
| Montanha — Ammu-Nation | 1 | Concluído na reforma em linha | Foto atual e medições na seção de 22/09; entrada/saída, teto, catálogo, colisão, save e suspensão do render aprovados. Comparativo equivalente: p95 17,008 → 16,902 ms, p99 17,403 → 17,157 ms, 0 quadros >33,3 ms |
| Montanha — Último Abrigo, Boutique Alpina, Casacos da Vila | 3 | Concluídos | Plantas separadas, compras, contato com dinheiro, jogador/NPC, colisão e oclusão aprovados; 59,97–60,01 FPS. Evidências na seção de lojas abaixo |
| Montanha — Chalé dos Pinhais, Chalé da Encosta, Posto Florestal, Chalés 01–04 da vila | 7 | Concluídos | Sete plantas, 1.776 aproximações físicas, oclusão, save em disco, recompensas, entrada/retorno, suspensão e desempenho validados. Indicador compartilhado: 24 checks |
| Montanha — Abrigo dos lenhadores | 1 | Concluído | [Foto](measurements/interior-standard-0920/lumberjack_shelter-standard-final.png); coleta do machado, acesso/retorno, suspensão, 224 aproximações e profundidade jogador/NPC aprovados. Benchmark vigente reutilizado: 60,01 FPS, p95 16,972 ms / p99 17,375 ms; sem alteração de runtime posterior |
| Montanha — Cume Branco / lodge | 1 | Concluído | [Foto final](measurements/interior-standard-0920/mountain-final-ski_lodge.png); R$ 900, 304 aproximações, profundidade, aluguel, ski, ambas as saídas, save e respawn aprovados; 60,01 FPS, p95 17,014 / p99 17,264 ms, sem quadros acima de 33,3 ms |
| Montanha — Bunker | 1 | Concluído | [Foto final](measurements/interior-standard-0920/mountain-final-mountain_bunker.png); entrada órfã corrigida, câmera alinhada, iluminação renovada e R$ 1.500; rádio, 432 aproximações, profundidade e retorno aprovados; 60,01 FPS, p95 16,997 / p99 17,266 ms |
| Montanha — Caverna da Queda | 1 | Concluído | [Foto final](measurements/interior-standard-0920/mountain-final-mountain_mystery_cave.png); planta irregular inteira, lanternas e sólidos; RPG, fluxo, 640 aproximações e profundidade aprovados; 60,01 FPS, p95 16,952 / p99 17,130 ms |
| Montanha — Avião cargueiro externo | 1 | Concluído no fluxo real | [Foto final](measurements/interior-standard-0920/mountain-final-plane-cargo.png); render 1440×1000, convés compartilhado, luzes, SMG por contato, baú, 176 aproximações e profundidade aprovados. Primeira entrada real: pico 17,123 ms, primeira aproximação 40,962 ms; regime 60,00 FPS, p95 16,986 / p99 17,269 ms. Startup global de 1,7 s também ocorre sem estar no avião e permanece registrado separadamente |

Fora do total: IML instanciado sem acesso exterior encontrado; clínica 2D legada usada como base do hospital; restaurantes com mesas externas sem salão interno conectado. Se um acesso jogável for confirmado, atualizar esta classificação.

## Lote inicial: documentação e textos

- [x] Skill criada e instalada em `C:/Users/rafae/.codex/skills/padrao-interiores/SKILL.md`.
- [x] Cópia versionada em `docs/skills/padrao-interiores/SKILL.md`; ambas passaram no validador oficial.
- [x] AGENTS.md exige carregar a skill em trabalhos de interiores e seus acessos.
- [x] Entrada/saída das casas e entrada aberta da garagem do chefe usam E. Teste compartilhado de keycap: 10 checks aprovados na etapa anterior; inclui controle, remapeamento, ocultação e restauração de estilo.
- [x] Letreiro da Union e variante de inverno sem categorias decorativas. Mudança apenas de texto.
- [x] Foto antes e depois da Union, mesma sala e enquadramento, render Vulkan Mobile / RTX 4060 Laptop / 1280×800.
- [x] Fotos atuais das duas referências escolhidas.
- [ ] Fotos no fluxo integrado, com jogador, e visitas a cada acesso físico.
- [ ] Validação física e de oclusão por ambiente.
- [ ] Benchmark comparável antes/depois para mudanças de runtime.

### Union — correção parcial

Antes: [union-before.png](measurements/interior-standard-0920/union-before.png).

Depois: [union-after.png](measurements/interior-standard-0920/union-after.png).

As fotos são de salas reais instanciadas isoladamente, sem jogador. Servem para revisar arte e letreiro, não para aprovar câmera de gameplay, colisão, profundidade ou FPS. A Union ainda mostra uma leitura excessivamente superior/plana nesta captura; investigar enquadramento e primeiro render antes de migrar câmera, pois caches e interpolação também podem alterar a vista.

### Pendência concreta de desempenho

Com autorização explícita do usuário, os oito processos antigos de testes (eventos de cemitério e inspeção de animação) foram encerrados após conferência dos comandos; o editor foi preservado. Baseline do chalé aprovado na cena MountainPass real, Vulkan Mobile / RTX 4060 Laptop / 1280×720, limite 60 FPS, VSync ligado, cinco segundos de aquecimento e amostra de 30 segundos: **30,06 FPS**, p50 **33,315 ms**, p95 **34,770 ms**, p99 **36,853 ms**, máximo **49,850 ms**, 458/902 quadros acima de 33,3 ms e nenhum acima de 66,7 ms. Desempenho ainda não aprovado: não atende à meta de 60 FPS. Evidências: [log](measurements/interior-standard-0920/cabin-baseline.log), [tempos brutos](measurements/interior-standard-0920/cabin-baseline.json), [foto](measurements/interior-standard-0920/cabin-baseline.png).

## Ordem inicial de trabalho

### Piloto solicitado: câmera do chalé

- Câmera ortográfica centralizada, sem giro lateral, mesma direção da garagem; tamanho 11,5 para enquadrar a planta do chalé. Materiais, luzes e geometria preservados.
- Timer da lareira não substitui mais render contínuo quando há atores no viewport compartilhado. Sala vazia continua suspensa.
- Contrato renderizado após correção: **0 falhas, 17 grupos sólidos, 136 aproximações varridas**; oclusão com jogador e NPC aprovada com controle positivo de visibilidade.
- Gameplay MountainPass: **0 falhas** em entrada, spawn, perímetro, circulação, coleta das três armas, saída, reentrada, respawn e restauração de save. A execução emitiu avisos de recursos ainda vivos no encerramento; isso não está aprovado como ausência de vazamentos do mundo completo.
- Fotos: [antes diagonal](measurements/interior-standard-0920/cabin-reference.png), [depois alinhado](measurements/interior-standard-0920/cabin-aligned.png), [com jogador no gameplay](measurements/interior-standard-0920/cabin-aligned-gameplay.png). A foto de gameplay foi feita após coleta, com avisos funcionais na tela; a vista geral é uma captura isolada do mesmo interior.
- Logs: [colisão e oclusão](measurements/interior-standard-0920/aligned-contract-after.log), [fluxos reais](measurements/interior-standard-0920/aligned-gameplay.log).
- Piloto visual aprovado pelo usuário; propagação autorizada. As sete fachadas ainda usam a mesma sala; separar sua identidade faz parte da migração.
- FPS continua não aprovado: baseline de 30,06 FPS registrado acima. Não confundir passagem dos testes físicos/visuais com desempenho aprovado.

### Primeiro ajuste da caverna — câmera e RPG

- [x] Câmera usa a direção alinhada do padrão, finalizada antes da projeção física.
- [x] RPG flutuante com oscilação vertical, rotação e círculo dourado legível. Modelo e área de contato sobre o mesmo piso livre, à frente do estojo.
- [x] Coleta ao caminhar, sem exigir E. Interação opcional usa indicador curto. Jogador morto ou em diálogo não recebe recompensa.
- [x] Fluxo real: 30 checks, zero falhas, incluindo exatamente quatro foguetes, controle após equipar, save, reconstrução sem duplicação e saída. [Log](measurements/interior-standard-0920/cave-contact-validation-fixed.log).
- [x] Oclusão do jogador e NPC explicitamente testada na caverna: zero pixels diferentes atrás do anteparo; controles visíveis de 1.725 e 1.034 pixels. Render ocupado contínuo; sala desativada suspensa. [Contrato renderizado](measurements/interior-standard-0920/cave-final-depth.log). As 136 aproximações reportadas pelo teste pertencem ao chalé; não são cobertura de todos os sólidos da caverna.
- [x] Regressão do coletável compartilhado no avião: zero falhas em flutuação, coleta, munição e persistência. Teste headless funcional, não benchmark. [Log](measurements/interior-standard-0920/shared-pickup-plane-regression.log).
- [x] Regressão renderizada no chalé após ajustar a flutuação compartilhada: 32 checks, zero falhas, incluindo coleta das três armas por contato, circulação, saída, suspensão vazia, reentrada e save. [Log](measurements/interior-standard-0920/cabin-pickup-regression.log). Novo comparativo de desempenho do chalé e do abrigo continua pendente.
- [x] Fotos reais no gameplay: [antes](measurements/interior-standard-0920/cave-baseline.png), [depois](measurements/interior-standard-0920/cave-final.png).
- [ ] Reforma artística completa e revisão de todos os sólidos do cenário. Não contar este ajuste como caverna concluída.
- [ ] Meta de 60 FPS. Comparativo abaixo permanece insuficiente para aprovação absoluta.

| Caverna / amostra de 30 s | FPS médio | p50 ms | p95 ms | p99 ms | Máximo ms | >33,3 ms | >66,7 ms |
|---|---:|---:|---:|---:|---:|---:|---:|
| Antes | 31,59 | 33,014 | 34,937 | 40,357 | 54,196 | 373/948 | 0 |
| Depois final | 30,09 | 33,281 | 35,441 | 37,385 | 49,844 | 441/903 | 0 |

Mesma máquina, renderer, cena real, resolução e harness do baseline do chalé. p95 aumentou 1,44%, p99 caiu 7,36%; média de FPS caiu 4,77%. Causa da limitação próxima de 30 FPS ainda não isolada. Não há aprovação de 60 FPS. [Log final](measurements/interior-standard-0920/cave-final.log), [amostras](measurements/interior-standard-0920/cave-final.json). Execuções do mundo completo ainda emitem avisos de recursos vivos no encerramento; ausência de vazamentos permanece não validada.

### Próximos lotes

1. Validar as referências no gameplay e resolver apresentação contínua sem perder desempenho.
2. Union e lojas de inverno: câmera, escala, manequins e profundidade; reaproveitar a base validada.
3. Northgate Auto e bombeiros: maiores diferenças de construção 2D/3D.
4. Hospital, delegacia, casas e zelador.
5. Banco, conveniência, lojas de armas, garagem do chefe e ambientes especiais de montanha/esgoto.

A cada lote atualizar fotos, checks e contadores; não confundir quantidade de portas, lugares físicos, scripts compartilhados e interiores aprovados.

## Sete cabanas distintas — implementação de 20/09

As seis cabanas adicionais são construídas na primeira entrada, com IDs estáveis por fachada. O chalé aprovado conserva o ID antigo e suas três armas, mantendo compatibilidade com saves anteriores. Salas vazias ficam sem processamento e render. O enquadramento agora mostra a sala inteira e a câmera não atravessa o vazio entre fachada e interior.

| Lugar | Identidade | Recompensa | Foto real |
|---|---|---|---|
| Chalé dos Pinhais | Refúgio dos caçadores aprovado | Rifle, machado e faca | [Foto](measurements/interior-standard-0920/mountain_cabin-unique.png) |
| Chalé da Encosta | Dormitório a leste e mesa de trabalho a oeste | $ 5.000 | [Foto](measurements/interior-standard-0920/mountain_cabin_encosta-unique.png) |
| Posto Florestal | Mesa de levantamento e arquivo de campo | $ 850 | [Foto](measurements/interior-standard-0920/mountain_cabin_forest-unique.png) |
| Chalé 01 | Bancada de pesca e caixas de equipamento | $ 450 | [Foto](measurements/interior-standard-0920/mountain_cabin_village_1-unique.png) |
| Chalé 02 | Máquina de costura e rolos de tecido | $ 1.200 | [Foto](measurements/interior-standard-0920/mountain_cabin_village_2-unique.png) |
| Chalé 03 | Piano vertical e espaço de ensaio | $ 650 | [Foto](measurements/interior-standard-0920/mountain_cabin_village_3-unique.png) |
| Chalé 04 | Mesa de revelação e câmera em tripé | $ 1.800 | [Foto](measurements/interior-standard-0920/mountain_cabin_village_4-unique.png) |

- `test_distinct_mountain_cabins.gd`: **0 falhas, 7 layouts diferentes e 1.776 aproximações físicas**, com jogador e NPC. Inclui acesso real, spawn, rota de recompensa, valores exatos, retorno à fachada correta, enquadramento integral e suspensão vazia. [Log](measurements/interior-standard-0920/distinct-cabins-final.log).
- Oclusão renderizada de jogador e NPC com controle positivo em cada cabana: aprovada. As fotos acima mostram o gameplay real.
- Baseline atualizado imediatamente antes da expansão: **60,01 FPS**, p95 **17,127 ms**, p99 **18,110 ms**, máximo **27,472 ms**. A queda para 30 FPS da rodada anterior não se repetiu; não atribuir sua causa a uma correção sem evidência. [Baseline](measurements/interior-standard-0920/cabins-expansion-before.log).
- Depois: todas as sete cabanas em **60,01–60,03 FPS**, p95 **16,912–17,036 ms**, p99 **17,102–17,396 ms**, sem quadros acima de 33,3 ms nas amostras estáveis de 30 segundos. Máximo na primeira visita: **24,564–50,867 ms**; há picos de entrada registrados, sem escondê-los no aquecimento. [Rota e métricas](measurements/interior-standard-0920/cabins-route.log).
- Save em disco e reconstrução das seis novas cabanas: **0 falhas**, R$ 9.950 preservados sem duplicação. [Log](measurements/interior-standard-0920/distinct-cabin-save.log). O chalé original passou novamente por seus 32 checks de gameplay, incluindo armas, circulação, save, respawn e retorno. [Log](measurements/interior-standard-0920/cabin-gameplay-final.log).
- Indicador efetivo de BuildingEntrance: a rodada anterior de 16 checks foi substituída pela correção solicitada pelo usuário — retângulo laranja arredondado sem letras. **24 checks passaram** no formato final. [Log vigente](measurements/interior-standard-0920/rounded-door-marker-checks.log).
- O baseline `harbor-before-WorkshopInterior` é **inválido e não deve ser utilizado**: a fachada MotorWorkshop não expõe a porta do interior legado. Northgate Auto permanece no inventário como baia externa acessível de serviço, não como aquela instância de sala.

## Verificações finais do porto — em andamento

- `harbor-directed-final.log`: **0 falhas / 1.120 aproximações**, cobrindo clínica (480), bombeiros (240) e banco (400), com oclusão renderizada e controles positivos para jogador e NPC. Banco com atendentes/guardas proporcionais e clínica sem o multiplicador antigo de 1,3 nos funcionários.
- `harbor-final-physical.log`: garagem (1.008), zelador (192), Ammu-Nation (160) e conveniência (192) passaram seus casos físicos e de profundidade. As duas falhas daquele lote eram na admissão dos bombeiros e foram corrigidas, com nova aprovação dirigida acima. Não tratar o log antigo inteiro como aprovado.
- `police-directed-physics.log`: **0 falhas / 2.384 aproximações** na delegacia.
- `fire-trucks-controls-final.log`: **0 falhas / três baias**. Entrada a pé, embarque, condução real pelo portão, retorno ao acesso correspondente sem duplicar caminhão, desembarque e cura. O teste antigo usava a ação obsoleta `ui_up`; passou a usar `move_up` e aguardar a animação nativa antes de acelerar.
- `garage-weapons-final.log`: **0 falhas**. Entrada guarda arma e apaga lanterna; saque, ataque, troca e recarga bloqueados; inventário preservado na saída; restauração/respawn e invulnerabilidade de Maciota/mecânico conferidos.
- `bank-fuel-payout-final.log`: **0 falhas**. Modelos proporcionais preservam mãos na arma e disparos reais; cartão, fechadura e caminhada até o cofre funcionam. As pilhas pagam R$ 10.000 uma única vez, com conquistas contabilizadas separadamente (R$ 100 e R$ 200 nesta partida). Caixa deslocado da conveniência paga R$ 180 sem duplicação. O atendente da conveniência também recebeu proporções ajustadas. Recompensas de chão atualizam diretamente o saldo do HUD, preservando seu comportamento de coleta.
- Primeira rodada final dos nove ambientes concluída: [comparativo, qualidade efetiva e pendências](measurements/interior-standard-0920/harbor-performance-report.md). Delegacia, clínica e Ammu-Nation exigem confirmação dos picos; banco exige conferir primeira visita e conveniência aguarda captura da correção de roupa. Os resultados aprovados já constam na contagem.

## Lojas de inverno — três ambientes independentes

| Lugar | Recompensa | Foto real |
|---|---:|---|
| Último Abrigo | $ 750 | [Foto](measurements/interior-standard-0920/mountain_outfitters-standard.png) |
| Boutique Alpina | $ 1.250 | [Foto](measurements/interior-standard-0920/mountain_boutique-standard.png) |
| Casacos da Vila | $ 450 | [Foto](measurements/interior-standard-0920/mountain_village_outfitters-standard.png) |

Plantas diferentes, manequins com proporção humana, câmera alinhada e caixa funcional. Teste integrado: **0 falhas / 3 layouts distintos**; compras, contato com dinheiro, colisão de jogador/NPC, oclusão com controle positivo, retorno à própria fachada e sala vazia suspensa. [Log final](measurements/interior-standard-0920/clothing-standard-verified.log). As execuções anteriores expuseram um erro real: o corpo da prévia de roupas era admitido como residente; corrigido no filtro de residentes da sala, sem desabilitar a prévia.

Medição real, Mobile / RTX 4060 Laptop / 1280×720 / VSync e limite 60: baseline compartilhado anterior **60,01 FPS**, p95 **16,964**, p99 **17,297 ms**. Depois: Último Abrigo **60,01 / 17,077 / 17,320**; Boutique **60,01 / 17,047 / 17,357**; Casacos **59,97 / 17,163 / 17,957** (FPS / p95 / p99 em ms). Nenhum quadro estável acima de 33,3 ms; máximos de primeira visita **29,054 / 30,299 / 27,152 ms**. [Log e identificação do hardware](measurements/interior-standard-0920/shops-lumberjack-after.log).

O mesmo log mede o abrigo dos lenhadores: antes **60,01 FPS**, p95 **16,983**, p99 **17,292 ms**; depois **60,01 FPS**, p95 **16,972**, p99 **17,375 ms**. A validação física e de profundidade foi concluída no lote de seis lugares abaixo; o comparativo final da integração permanece pendente.

## Lote final da montanha — seis lugares

Todos usam câmera ortográfica alinhada no eixo frontal, direção relativa `(0,18,15)`, e atores 3D compartilhando profundidade com o cenário. O tamanho ortográfico e a textura variam conforme a dimensão da planta, sem mudar o padrão visual. Renderização contínua enquanto ocupado; interiores vazios suspendem o viewport e o avião vazio conserva imagem estática. Esses modos não são uma medição de FPS nem da taxa física.

| Lugar | Textura 3D | Tamanho ortográfico | Identidade visual |
|---|---|---:|---|
| Abrigo dos lenhadores | 1080×750 | 11,5 m | Alojamento de madeira, beliches, fogão e ferramentas |
| Cume Branco | 1440×1000 | 14,2 m | Salão de ski, lareira, lustres e equipamentos |
| Estação Zero | 1280×960 | 17,5 m | Bunker militar, comando, rádio e dormitórios |
| Caverna da Queda | 1280×960 | 14,5 m | Contorno rochoso irregular, acampamento e lanternas |
| Ammu-Nation da serra | 1440×1000 | 16,4 m | Loja de armas em madeira, balcão, ilha e fogão |
| Avião cargueiro | 1440×1000 | 36 m | Fuselagem, convés elevado, duas fileiras de carga e luzes de emergência |

| Lugar | Coletável | Foto real | Estado da validação |
|---|---|---|---|
| Abrigo dos lenhadores | Machado flutuante | [Foto](measurements/interior-standard-0920/lumberjack_shelter-standard-final.png) | 224 aproximações jogador/NPC, controles de profundidade, rota da arma, entrada e saída aprovados |
| Cume Branco | R$ 900, além do equipamento de ski | [Foto](measurements/interior-standard-0920/ski_lodge-standard-final.png) | 304 aproximações, profundidade, recompensa, aluguel, equipamento, pistas, retorno e recuperação de save aprovados |
| Estação Zero | R$ 1.500 | [Foto](measurements/interior-standard-0920/mountain_bunker-standard-final.png) | 432 aproximações, profundidade, dinheiro, rádio e retorno aprovados |
| Caverna da Queda | RPG com quatro foguetes | [Foto](measurements/interior-standard-0920/mountain_mystery_cave-standard-final.png) | 640 aproximações, profundidade e rota real de coleta aprovados; contorno irregular, caixas, cama, rochas e estalagmites bloqueiam |
| Ammu-Nation da serra | Faca flutuante | [Vendedor e jogador](measurements/interior-standard-0920/ammunation-human-scale.png) | 176 aproximações, profundidade, contato, medidas do vendedor, compra e proteção contra cobrança repetida aprovados |
| Avião cargueiro | SMG e baú de R$ 1.800 | [Foto central](measurements/interior-standard-0920/mountain-final-plane-cargo.png) | 176 aproximações, profundidade jogador/NPC, rampa, SMG, baú e suspensão após saída do último NPC aprovados; regime estável e reentrada real aprovados, inicialização global com ressalva abaixo |

`test_remaining_mountain_standard.gd` aprovou as quatro primeiras salas, totalizando **1.152 aproximações** e oclusão com controle positivo para jogador e NPC. [Log](measurements/interior-standard-0920/mountain-standard-contract.log). A única falha da execução completa revelou a loja criada antes do jogador: a referência permanecia nula, impedindo integração do ator. Corrigido o reencontro do jogador no início do processamento da loja. Na execução dirigida seguinte, profundidade e 176 aproximações passaram; a compra resultou em saldo diferente do teste porque a conquista **BLINDADO** também paga R$ 50. A expectativa agora contabiliza recompensas do catálogo e verifica que uma segunda compra de colete cheio não cobra novamente. [Log da investigação](measurements/interior-standard-0920/ammunation-standard-contract.log).

O vendedor das duas Ammu-Nation mede **1,80 m de altura e 0,677 m de largura máxima**, em lugar do corpo excessivamente largo. A altura efetiva do modelo do jogador nesse adaptador é aproximadamente 1,73 m. O ajuste é de corpo/cabeça, sem mudar a escala global do jogador ou da loja.

A reexecução dirigida da Ammu-Nation e caverna terminou com **0 falhas / 816 aproximações**: inclui compra, proteção contra cobrança repetida e o novo contorno físico irregular da caverna. [Log final](measurements/interior-standard-0920/ammo-cave-final-contract.log). O conjunto final das cinco salas soma **1.776 aproximações físicas**, sem contar a versão antiga substituída da caverna. O fluxo específico do Cume Branco também terminou com **0 falhas**: aluguel, equipamento, pistas, retorno, oclusão real da lareira, recuperação de spawn inválido e restauração após respawn. [Log](measurements/interior-standard-0920/lodge-final-gameplay.log).

`test_plane_standard_gameplay.gd`: **0 falhas, 176 aproximações**, com NPC admitido automaticamente no mesmo viewport, pés no convés elevado, controle positivo de visibilidade, entrada/saída contínuas, ação remapeada do baú e coleta da SMG por contato. A rodada final inclui as luzes de emergência e confere que o NPC remanescente mantém o render ativo após a saída do jogador, e que a saída do último NPC restaura sua apresentação e suspende o render contínuo. [Log final](measurements/interior-standard-0920/plane-final-gameplay.log). Construção gradual preservada: **0 falhas**, 23 etapas em 12 quadros, máximo de duas etapas por quadro e pico de 4,823 ms; um quadro excedeu o orçamento interno de 2 ms, nenhum excedeu 16,667 ms. Esse teste headless verifica apenas a construção, não certifica FPS. [Log](measurements/interior-standard-0920/plane-final-staging.log).

Baselines em gameplay real, RTX 4060 Laptop / Vulkan Mobile / 1280×720 / limite 60 e VSync ligado, amostra estável de 30 segundos separada da primeira visita:

| Cenário | FPS | p95 / p99 (ms) | Máximo estável (ms) | >33,3 / >66,7 ms | Máximo primeira visita (ms) |
|---|---:|---:|---:|---:|---:|
| Estação Zero | 60,01 | 17,030 / 17,440 | 29,627 | 0 / 0 | 46,854 |
| Caverna | 59,92 | 17,004 / 17,959 | 70,255 | 2 / 1 | 50,825 |
| Ammu-Nation serra | 60,01 | 17,008 / 17,403 | 32,353 | 0 / 0 | 22,754 |
| Avião | 60,01 | 16,964 / 17,244 | 21,627 | 0 / 0 | 1.385,063 |

Dados brutos: `mountain-batch-before-*.json`, `gunshop-before-ammunation.json` e `mountain-before-plane.json`, na pasta de medições. Baseline do lodge preservado em `special-before-ski_lodge.json`.

### Desempenho final da montanha

Mesma RTX 4060 Laptop, Godot 4.7.2 Mobile, 1280×720, limite 60 e VSync ligado. Física confirmada em **60 Hz**. Cada amostra estável tem 30 segundos, além de cinco segundos de primeira visita e cinco de aquecimento. Render contínuo ocupado acompanha o jogo; não há limite artificial de 12/15/30 Hz nestes interiores.

| Lugar | FPS antes → depois | p95 antes → depois (ms) | p99 antes → depois (ms) | Máximo estável depois (ms) | Quadros >33,3 / >66,7 ms | Pico primeira visita depois (ms) |
|---|---:|---:|---:|---:|---:|---:|
| Abrigo dos lenhadores | 60,01 → 60,01 | 16,983 → 16,972 | 17,292 → 17,375 | 18,636 | 0 / 0 | 17,166 |
| Cume Branco | 60,01 → 60,01 | 17,015 → 17,014 | 17,378 → 17,264 | 17,679 | 0 / 0 | 21,819 |
| Estação Zero | 60,01 → 60,01 | 17,030 → 16,997 | 17,440 → 17,266 | 24,417 | 0 / 0 | 21,538 |
| Caverna | 59,92 → 60,01 | 17,004 → 16,952 | 17,959 → 17,130 | 17,775 | 0 / 0 | 33,512 |
| Ammu-Nation serra | 60,01 → 60,00 | 17,008 → 17,063 | 17,403 → 17,615 | 22,808 | 0 / 0 | 26,023 |
| Avião | 60,01 → 60,01 | 16,964 → 16,968 | 17,244 → 17,177 | 18,285 | 0 / 0 | 1.679,163 |

As cinco salas passaram os contratos funcionais, físicos, visuais e de desempenho. Logs finais: [quatro interiores](measurements/interior-standard-0920/mountain-final-performance.log), [abrigo com medição reutilizada](measurements/interior-standard-0920/shops-lumberjack-after.log). p50 final: Ammo **16,666**, lodge **16,671**, bunker **16,665**, caverna **16,667 ms**; amostras completas em `mountain-final-*.json`.

O avião passou o regime estável (p50 **16,669 ms**). O pico inicial aumentou de **1.385,063 para 1.679,163 ms** e a confirmação instrumentada registrou **1.701,384 ms**. Todos ocorrem no primeiro quadro da amostra, imediatamente após a construção da cena e antes da apresentação inicial; o harness mistura a inicialização do mundo com a primeira visão da aeronave. [Log principal](measurements/interior-standard-0920/plane-final-performance.log). [Foto central real com jogador, carga, luzes, SMG e baú](measurements/interior-standard-0920/mountain-final-plane-cargo.png).

A confirmação manteve a rota original e acrescentou saída e reentrada reais pela rampa depois de inicializar o mundo: **pico de entrada 17,391 ms**, seguido de **60,003 FPS / p50 16,669 / p95 16,979 / p99 17,232 / máximo 17,911 ms**, sem quadros acima de 33,3 ms nos 30 segundos estáveis. A construção CPU da vista custou **1,085 ms**; no primeiro quadro de 1,7 s, a fila de detalhes do avião ainda estava em **0/23 etapas**. A primeira etapa ocorreu depois e custou **10,335 ms**. O primeiro pico antecede métricas válidas de render; não permite atribuir sua causa a CPU, GPU ou shaders. Há uma limitação de inicialização global registrada, sem evidência de travamento local na entrada do avião. Não se alterou o carregador global para esconder esse custo.

Confirmação **sem processos de teste concorrentes**, verificada a cada dois segundos; o editor permaneceu aberto. [Log e reentrada](measurements/interior-standard-0920/plane-cold-confirm.log), [amostras instrumentadas](measurements/interior-standard-0920/plane-cold-confirm-plane-cold-trace.json), [monitor de processos](measurements/interior-standard-0920/plane-cold-confirm-processes.json). O harness carrega MountainPass diretamente e não chama `GameLoading.begin`; a ausência de tela de carregamento é inferida desse fluxo, não uma captura do primeiro quadro.

**Primeira visita normal, sem visita prévia ao avião:** carregamento mantido no spawn natural, com startup registrado separadamente; depois primeira aproximação exterior e entrada caminhando pela rampa. Pico de startup **1.700,189 ms** mesmo com jogador fora do avião; pico da primeira aproximação **40,962 ms**, pico da primeira entrada **17,123 ms**. Regime estável de 30 segundos: **60,002 FPS / p50 16,669 / p95 16,986 / p99 17,269 / máximo 17,948 ms**, zero quadros acima de 33,3/66,7 ms. Processo encerrado com código 0 e monitor sem sobreposição de outros testes. [Log](measurements/interior-standard-0920/plane-first-normal.log), [amostras completas](measurements/interior-standard-0920/plane-first-normal-plane-first-visit.json), [monitor](measurements/interior-standard-0920/plane-first-normal-processes.json).

O avião está aprovado nos fluxos reais, primeira visita e regime estável. O pico de 40,962 ms da primeira aproximação permanece registrado; a inicialização global de aproximadamente 1,7 s continua **não certificada**, sem causa interna isolada e sem alterações fora do escopo para escondê-la. A rodada original e todas as confirmações foram preservadas.

## Revisão do vídeo de 24/09/2026 — V2, primeiro lote

Escopo: **4 lugares / 4 interiores distintos existentes** — Ammu-Nation Harbor, Ammu-Nation da montanha, banco Harbor e Maciota. Nenhum interior novo, nenhuma migração contada novamente. As duas lojas receberam ajuste no ponto de atendimento; banco recebeu correção de mira dos guardas; transições compartilhadas receberam sincronização de câmera, clima e HUD. Piso, escala e mobília não foram reformados.

- [x] Apoio físico e pés do jogador nas duas lojas e no banco: testes isolados passaram. O deslocamento acumulado do corpo foi corrigido na apresentação de veículos, sem subir o piso.
- [x] Atendimento junto ao balcão nas duas variantes e mira/arma/mãos dos guardas: 39 verificações do lote de interiores passaram.
- [x] Integração da Main: 31 verificações passaram, incluindo arma guardada e HUD correto no primeiro quadro da garagem, chuva, entrada/saída, zoom, morte e resgate. Inventário preservado, saque da arma bloqueado na garagem. Não houve mudança nas rotinas de dano/morte dos residentes protegidos.
- [x] Capturas reais iniciais de três interiores: [banco](../evidence/video-review-20260924/bank-standing-armed-guards.png), [Ammu-Nation Harbor](../evidence/video-review-20260924/ammunation-counter-approach.png), [Maciota](../evidence/video-review-20260924/maciota-settled-rain-outside.png). A foto inicial da garagem revelou HUD atrasado e motivou correção posterior, registrada separadamente.
- [x] Confirmação específica de oclusão do banco: corpo visível [diante](../evidence/video-review-20260924/depth-fixed-bank-occlusion-front.png) e pernas ocultas [atrás do balcão](../evidence/video-review-20260924/depth-fixed-bank-occlusion-behind.png). Silhueta ausente desde a entrada; contorno exterior preservado. Moto sem mancha desde o [primeiro render após embarcar](../evidence/video-review-20260924/temporal-final-mounted-frame-000.png); 17 verificações de escopo/atualização passaram. [Relatório visual e controles](../evidence/video-review-20260924/visual-validation.md).
- [ ] Foto renderizada atual da variante da montanha e contrato completo de circulação/colisão com todos os sólidos; apoio físico isolado não equivale a esse contrato.
- [ ] Aprovação completa de oclusão, com controles positivos por obstáculo e por jogador/NPC. Imagens em espaço livre não bastam.
- [ ] Performance antes/depois comparável. Havia um jogo do usuário aberto; não houve benchmark isolado nem aprovação de FPS.
- [ ] Migração dos demais acessos para porta/proximidade/zoom. O lote atual cobre o fluxo já existente das lojas e preserva o da polícia; não declara banco/garagens migrados.

**Estado: lote parcialmente validado; aprovação global de interiores permanece pendente.** Resultados e limites em [relatório do primeiro lote](video-review-20260924-first-batch.md), [plano de ação](video-review-20260924-action-plan.md) e [protocolo de performance](../evidence/video-review-20260924/performance-status.md). As aprovações históricas acima pertencem aos seus cenários e versões; não substituem a validação deste código.

## Revisão do vídeo de 24/09/2026 — V2, segundo lote

Escopo de acessos: **3 lugares / 3 interiores distintos existentes** — banco Harbor, Maciota e Garagem do Chefe. Total do helper após este lote: **6 acessos automáticos / 6 interiores**. Inventário global: **32 acessos físicos / 30 interiores distintos** (29 do catálogo + Maciota; o abrigo compartilhado tem dois acessos extras). Restam **26 acessos / 24 interiores** fora desta migração. Nenhum interior novo e **zero novas certificações completas** neste lote, devido às pendências abaixo.

- [x] Porta física do banco fechada bloqueia e aberta permite caminhar; recesso central e batentes conferidos. [Porta fechada](../evidence/video-review-phase2-20260924/phase2-access-bank-door-closed.png), [entrada](../evidence/video-review-phase2-20260924/phase2-access-harbor_bank-entry-zoom.png).
- [x] Caminhada, zoom de entrada/saída, posição de retorno, reentrada sem oscilação e ausência de E de passagem nos três locais. Horário, investigação e cancelamento por modal/morte/prisão: **76 verificações funcionais + 16 imagens, 92/92**. [Log](../evidence/video-review-phase2-20260924/phase2-access-render-final.log).
- [x] Imagens reais dos três interiores e seus percursos inspecionadas: [banco](../evidence/video-review-phase2-20260924/phase2-access-harbor_bank-inside.png), [Maciota](../evidence/video-review-phase2-20260924/phase2-access-maciota-inside.png), [Chefe](../evidence/video-review-phase2-20260924/phase2-access-port_boss_garage-inside.png). Iluminação noturna escura do Chefe permanece; captura não implica aprovação artística completa.
- [x] Marcador funcional de Maciota, arma guardada/bloqueada, inventário e residentes protegidos preservados. Sessão: 31; motorista restaurado: 26; transferência de garagem: 11 verificações funcionais passaram. Não foram alteradas rotinas de dano/morte dos residentes. Avisos de retenção ao encerrar os testes de garagem estão registrados no relatório.
- [x] Integração dos estabelecimentos e catálogo/bancada inicial do Claude: 77 verificações; quatro imagens de interface inspecionadas. Ampliação posterior do Claude não recebe aprovação visual por essas imagens.
- [ ] Contrato integral de circulação/colisão de todos os móveis, sólidos e NPCs dos três ambientes. A travessia física da porta não substitui essa cobertura.
- [ ] Oclusão completa por obstáculo, com controles positivos para jogador e NPC. As verificações específicas do lote anterior permanecem evidência apenas daquele escopo.
- [ ] Comparação de frame time antes/depois na cena real. Jogo/editor do usuário preservados; não houve benchmark exclusivo.
- [ ] Demais 26 acessos/24 interiores, com tratamento próprio para navio, alçapão e caverna.

**Estado: acessos implementados e fluxos específicos validados; aprovação global continua pendente.** [Relatório do segundo lote](video-review-20260924-second-batch.md), com testes, imagens e limites; [plano atualizado](video-review-20260924-action-plan.md).

## Revisão do vídeo de 24/09/2026 — V2, terceiro lote

Escopo de acessos: **3 lugares / 3 interiores distintos existentes** — Union, conveniência Harbor e Bay Medical. Total atual: **9 acessos automáticos / 9 interiores**. Inventário global preservado: **32 acessos físicos / 30 interiores distintos**; restam **23 acessos / 21 interiores**. Nenhum interior novo e **zero novas certificações completas**, pois os itens obrigatórios abaixo permanecem pendentes. Reações de atores em salas já existentes não contam como novas migrações.

- [x] Portas fechadas bloqueiam o corpo inteiro; abertas permitem cápsula e movimento. Caminhada, zoom, retorno seguro, reentrada e interrupções nos três locais: **99 verificações funcionais + 18 PNGs, 117/117**. [Log](../evidence/video-review-phase3-20260924/phase3-access-after-render.log).
- [x] Fotos reais antes/depois inspecionadas. [Union](../evidence/video-review-phase3-20260924/phase3-access-after-harbor_clothing-inside.png), [conveniência](../evidence/video-review-phase3-20260924/phase3-access-after-harbor_fuel-inside.png), [Bay Medical](../evidence/video-review-phase3-20260924/phase3-access-after-harbor_hospital-inside.png). Captura limpa das três portas fechadas confirmada em execução dirigida, 17/17.
- [x] Reação local com colisão, retorno físico e espera diante de obstáculo, preservando atividade/carga. Main: 60 asserções; escopo de proteção: 5; confirmação final dirigida: 28, com sobreposição. Erro de foco observado no Main corrigido e ausente na confirmação. [Log final](../evidence/video-review-phase3-20260924/phase3-reactions-remaining-final.log).
- [x] Oclusão específica dos atendentes atrás do balcão durante o recuo e pose de proteção inspecionadas: [banco](../evidence/video-review-phase3-20260924/after-bank-clerks-shot.png), [Vance](../evidence/video-review-phase3-20260924/after-vance-shot.png). Isso não certifica todos os obstáculos das salas.
- [x] Atendimento interrompido sem executar conclusão/cobrança obsoleta; reentrada com uma conexão de ameaça; inventário independente preservado. Maciota e mecânico continuam excluídos da reação e sem API de dano/morte; arma guardada/bloqueada na garagem. Sessão 31, restauração de motorista 26 e transferência 11 passaram.
- [x] Union apresenta somente nome próprio; publicidade aleatória das duas fachadas alteradas foi removida. Nenhuma luz adicionada. Iluminação intensa preexistente do hospital permanece, sem aprovação artística integral.
- [ ] Contrato completo de circulação/colisão de todos os sólidos e móveis dos ambientes. Percursos de portas e recuos escolhidos não substituem essa cobertura.
- [ ] Oclusão completa por obstáculo, com controles positivos separados para jogador e NPCs.
- [ ] Frame time antes/depois comparável em cena real. Editor e jogo do usuário preservados; fotos e headless não aprovam FPS.
- [ ] Demais 23 acessos/21 interiores. Bombeiros requer revisão física da fachada; navio, alçapão e caverna exigem tratamento próprio.

**Estado: correções implementadas e fluxos específicos verificados; aprovação global permanece pendente.** [Relatório do terceiro lote](video-review-20260924-third-batch.md), [plano de ação](video-review-20260924-action-plan.md).

## Revisão do vídeo de 24/09/2026 — V2, quarto lote

Escopo interior: construção da arte compartilhada das **2 lojas de armas / 2 interiores existentes**, prévias e interface. Os acessos, dimensões e sólidos não foram migrados nesta fase. A contagem continua **9 acessos automáticos/9 interiores**, de **32 acessos físicos/30 interiores**; restam **23 acessos/21 interiores**. **Zero novas certificações completas.** Frete do porto e restauração do motorista usam áreas/veículos existentes e não acrescentam interiores.

- [x] Bancada em 1280×720 e 1920×1080: 59 verificações funcionais + 9 PNGs, sem falhas após corrigir scroll do foco do controle. Pistola sem guarda-mato duplicado e compensador da M4 conectado ao cano, com fotos reais antes/depois.
- [x] Boca/clarão/luz/tracejante e encaixe dos acessórios: 89 verificações funcionais em 18 casos. Nenhuma alteração de atributos de combate nessa integração.
- [x] Agrupamento das armas mantém triângulos, normais, materiais e partes móveis nas provas comparativas. Cache de recursos da sala tem verificação própria de geometria e isolamento entre instâncias; detalhes no relatório da fase.
- [x] Após corrigir a animação de restauração do motorista exterior, regressão das garagens: 26/26, mantendo arma guardada/bloqueada e os pontos de entrada dos carros. Não houve alteração das rotinas de dano/morte de Maciota ou mecânico.
- [ ] Aprovação de frame time: o diagnóstico renderizado ainda apresentou hitch de entrada e outra partida permaneceu aberta. Otimização de CPU não certifica o alvo de FPS nem encerra travamentos.
- [ ] Contrato completo de circulação/colisão e oclusão de todos os ambientes, com controles positivos de jogador/NPC. Evidências locais anteriores continuam limitadas aos seus percursos e obstáculos.
- [ ] Demais 23 acessos/21 interiores e revisão artística ampla de vazio, materiais, iluminação noturna e personagens.

[Relatório do quarto lote](video-review-20260924-fourth-batch.md) reúne alterações, imagens, resultados e limites. As otimizações da construção preservam a intenção visual; não conferem aprovação retroativa aos gates pendentes.

## Revisão de 25/09/2026 — V2, quinto lote

Por orientação do usuário, somente checagens essenciais; validação jogando fica com ele. Bombeiros acrescenta **1 acesso automático/1 interior existente**: total **10/10**, restam **22 acessos/20 interiores** de 32/30. **Zero novas certificações integrais.**

- [x] Bombeiros: passagem física, porta fechada/aberta, caminhada, zoom, saída e retorno; smoke 14/14.
- [x] Garagem do Chefe: três luminárias existentes redistribuídas; parse aprovado. Sem alteração de colisão ou regras de armas/personagens protegidos.
- [ ] Validação visual, oclusão e FPS pelo usuário; não executada nesta leva a pedido dele.

[Alterações e limites do quinto lote](video-review-20260925-fifth-batch.md).

## Revisão de 25/09/2026 — V2, sexto lote

Implementados os **22 acessos / 20 interiores restantes**: 19 acessos convencionais de seis famílias e três especiais (esgoto, navio, caverna). Total **32 acessos automáticos / 30 interiores distintos existentes**. **Zero novas certificações integrais.**

- [x] Porta física e caminhada por amostra de seis famílias, incluindo os dois acessos alternativos do abrigo; gate das casas e retorno por origem preservados. Smoke 65/66; única falha de fixture no retorno da loja corrigida e confirmada isoladamente, 10/10.
- [x] Esgoto, navio e caverna: proximidade, escotilhas, caminhada, spawn, saída, câmera/controle e retorno livre. Smoke conjunto, incluindo fogo e streaming: 20/20.
- [x] Fundo dos interiores isolados ajustado para cinza escuro; nenhuma luz ou geometria adicionada.
- [ ] Fotos e aprovação visual das novas fachadas, aberturas, câmera e fundo, pelo usuário.
- [ ] Circulação completa, colisão e oclusão de todos os ambientes e seus personagens. Amostras de percurso não certificam os interiores completos.
- [ ] Frame time renderizado e FPS. A redução de CPU das explosões não substitui essa validação.

As pendências numéricas de acessos registradas nos lotes anteriores são históricas; a implementação está completa, mas a validação integral permanece aberta. [Relatório do sexto lote](video-review-20260925-sixth-batch.md).

## Feedback jogando em 25/09 — indicador do Maciota

Sem nova migração: permanecem **32 acessos / 30 interiores distintos**. Indicador compartilhado passa a acompanhar a câmera todo quadro, em vez do intervalo de 0,1 s dos textos. Smoke Main headless **6/6**, incluindo arma bloqueada na garagem. Visual e FPS aguardam o usuário; nenhuma nova certificação integral. [Registro das correções](feedback-20260925-police-traffic.md).

## Organização espacial cidade–ponte–montanha — 25/09/2026

Alteração dos acessos exteriores, sem migrar interiores: permanecem **32 acessos / 30 interiores distintos**, **zero novas certificações integrais**. Ramais e acostamentos recortados nas junções, retorno no heliporto, conexão de volta da vila, caminhos para estabelecimentos/teleférico e aproximação lateral da caverna. Alterações concorrentes de ponte, material e cache do minimapa preservadas.

- [x] Implementação integrada; rotas de pedestres separadas do tráfego e incluídas na geometria do mapa.
- [ ] Percursos a pé/com veículos, entrada/retorno e interações: testes deixados com o usuário por instrução explícita.
- [ ] Colisão e oclusão, separadamente; continuidade visual do minimapa e capturas reais antes/depois.
- [ ] Performance renderizada e comparação de frame time. Nenhum benchmark executado, nenhuma aprovação de FPS.

[Escopo e pendências desta correção](route-spatial-20260925.md).

## Rodoviária: prévia e operação exterior — 26/09/2026

Sem interior novo: permanecem **32 acessos / 30 interiores distintos**, **zero novas certificações integrais**. Prédio restaurado na prévia 2D + 3D; quatro ônibus, dezesseis passageiros e duas cancelas integrados ao exterior. Ciclo físico e segundo embarque: 25 verificações aprovadas; cancelas: 10; suspensão e retorno: 5; prévia: 6. Chegada M00 preservada e testada. Capturas reais, escopo e métricas no [registro da rodoviária](terminal-restoration.md).

Performance renderizada medida, mas estabilidade **pendente**: uma amostra apresentou travadas que não se repetiram na confirmação. Nenhuma certificação de interiores ou de estabilidade de FPS foi acrescentada.

## Bueiro: entrada por interação — 27/09/2026

Sem migração: permanecem **32 acessos / 30 interiores distintos**, **zero novas certificações integrais**. Tampa fechada por proximidade, entrada pela ação de interação (E), sem hint e sem animação de escada/deslocamento do personagem. Saída existente preservada.

- [x] `tests/test_video_phase6_special.gd -- --no-save --skip-arrival`: 25 checks, zero falhas; inclui apoio sobre a tampa, proximidade sem entrada automática, interação silenciosa, spawn e retorno livres, controle liberado e regressão do porão/caverna.
- [ ] Execução sem erros de subsistemas: o teste acima completou, mas registrou erro de inferência de `impact` em `gameplay/urban_v1/UrbanRoutineActor.gd:151`, fora desta alteração.
- [ ] Capturas reais antes/depois e oclusão renderizada. Não verificadas nesta correção.
- [ ] Comparação de frame time antes/depois: não medida; outras instâncias Godot ativas. Nenhuma aprovação de FPS.

## Linha 510: seis plataformas exteriores — 28/09/2026

Seis tubos existentes reformados, sem interior novo: permanecem **32 acessos / 30 interiores distintos**, **zero novas certificações integrais**. Cada plataforma recebeu três portões operacionais e correção do piso e da colisão da rampa. [Implementação e evidências](biarticulated-transit.md).

- [x] Colisão: **60/60** verificações nas seis estações, incluindo piso superior, bancos, portões abertos/fechados, subida e descida pelas rampas.
- [x] Viagem e interação: embarque, atendimento às seis estações com população e tráfego normais (**5/5**), passageiros físicos e restauração do jogador após desembarque; suspensão e retorno por região (**6/6**).
- [x] Captura real de embarque, articulação em cruzamento noturno e inspeção individual de profundidade/oclusão nas seis plataformas. Fotos `station_0.png` a `station_5.png` no relatório; a estação Westgate foi recapturada após afastar a travessia.
- [ ] Estabilidade de frame time: comparação renderizada executada, mas com processos concorrentes e travadas; desempenho **não aprovado**. Ver métricas e limitação no relatório.

## Bancos, fogueiras e terreno — 02/10/2026

Revisão transversal dos objetos existentes, sem novo acesso/interior: permanecem **32 acessos / 30 interiores distintos**, **zero novas certificações integrais**. Bancos mantêm escala, orientação e função de cada ambiente; dez interiores usam a chama compartilhada das lareiras, preservando arquitetura e regras. [Escopo, inventário e evidências reais](../evidence/world-props-ground-20261002/review.md).

- [x] Padronização de treze famílias de bancos, com preservação dos estilos já acabados; sete fontes de calor exteriores com lenha, brasas e chama compartilhadas.
- [x] Terreno: união visual de trilhas/acostamentos no chão nativo; 552 verificações da mistura e 107 do contrato físico, sem falhas.
- [x] Bancos: dimensões e colisão avaliadas separadamente; revisão física em 24 bancos de famílias distintas. Fogo: integração, admissão e comportamento térmico verificados.
- [x] Evidência temporal real: resort dia/noite e lareira Summit, 30 s por cenário. Cobertura limitada a esses cenários; não certifica todas as lareiras.
- [ ] Certificação integral de colisão/oclusão de todos os interiores: esta revisão de objetos não equivale a uma migração completa de cada sala.
- [ ] Aprovação de performance: comparação antes/depois renderizada, com interferência de outras sessões registrada; resultado não isolado.

## Casas: interações presenciais — 02/10/2026

Revisão de **3 casas existentes / 3 interiores**, sem migração de acessos:
permanecem **32 acessos / 30 interiores distintos**, **zero novas certificações
integrais**. [Escopo e evidências](residence-living.md).

- [x] Guarda-roupa com personagem real/espelho, bancada com os modelos do arsenal e personalização persistente, descanso animado, geladeira articulada e mochila física integrada ao inventário.
- [x] Main renderizada .NET: **226 verificações, zero falhas**. Ações por E e clique, cancelamento, dano, restauração de controle/câmera/qualidade, foco, cobrança e save isolado verificados nas três casas.
- [x] Colisão avaliada separadamente: varreduras de jogador e NPC contra móveis a partir de posições livres, além do espaço corporal nos pontos de interação.
- [x] Fotos reais das cinco apresentações nas três casas; sequências de 30 s de troca de roupas e acabamentos em Westgate. Evidências em `evidence/residence-immersive/`; gravação limitada a 30 FPS não é benchmark.
- [ ] Certificação completa de percursos e oclusão jogador/NPC por todos os móveis. A fixture posiciona as aproximações; as capturas cobrem os enquadramentos de interação.
- [ ] Aprovação de frame time antes/depois. Baseline interrompido e sessões concorrentes; não há comparação equivalente. Espelho, luz local e MSAA precisam dessa medição para aprovação de performance.
- [x] Diagnóstico final renderizado de Westgate: 30 s por vista aquecida (geral, guarda-roupa, bancada), p95 de 1,924/3,407/1,228 ms e nenhum frame acima de 33,3 ms. Dados em `evidence/residence-immersive/profile.json`; isso não fecha a pendência comparativa acima.
- [x] Correção posterior das armas no painel: berços encaixados, folga traseira de 4 mm, painel livre das cortinas e luminária livre das armas. 60 verificações sem falha nas três casas, fotos `rack-after-*-normal/front/bench.png` e sequência real `rack.mp4`. Comparativo local de 30 s: p95 1,571 → 1,292 ms; sem regressão observada nesse ajuste. Não altera contagens nem certifica a reforma completa.

## Casas: circulação e compra — 09/10/2026

Correção de **3 casas existentes / 3 interiores**, sem novos lugares ou acessos.
Permanecem **32 acessos / 30 interiores distintos**, **zero novas certificações
integrais**. [Detalhes e evidências](residence-living.md).

- [x] Vão entre sofá e mesa ampliado de 60 cm para 1 m, com malha e colisão alinhadas; escada da cobertura ancorada em uma faixa livre junto à parede do fundo de cada planta.
- [x] Compra em cartão compacto, cancelamento, crédito da troca e som existente de conquista no sucesso; restauração do layout ao fechar ou substituir o menu.
- [x] Validação dirigida de compra, circulação jogador/NPC, escada e saída caminhando nas três casas: **114/114**, `tests/test_residence_circulation.gd`, log `evidence/residence-circulation-verified.log`. Ajuste final de âncoras de Westgate/Canal: **72/72**, log `evidence/residence-circulation-wall-access.log`.
- [x] Fotos reais finais e oclusão no corredor alterado: jogador/NPC atrás do sofá, no vão e à frente da mesa. Em `evidence/residence-circulation-20261009/`, usar `verified-purchase*.png`, `verified-quayside_house*.png` e `wall-access-*.png` para Westgate/Canal. Baseline `before-quayside_house.png`. Sem certificação de todos os móveis/ângulos.
- [ ] Certificação de desempenho antes/depois: baseline de 30 s teve outro benchmark Godot concorrente; p95 8,804 → 10,122 ms (+15%), p99 14,261 → 11,855 ms; comparação inconclusiva, sem aprovação de regressão. Dados brutos `before.json`/`after.json`.

## Porsche: acabamento da cabine — 04/10/2026

Ajuste local de **1 arquétipo de veículo existente**, sem novos lugares/acessos ou interiores de estabelecimentos. Permanecem **32 acessos / 30 interiores distintos**, **zero novas certificações integrais**. As duas barras do acabamento agora cabem sob o teto curvo, sem parecer um rack após o roubo. [Escopo, fotos reais e medições](reviews/coupe-roof-20261004.md).

- [x] Visual/profundidade: vistas de cima, laterais e câmera do jogo antes/depois; barras contidas sob a cobertura, motorista visível e sem geometria externa nova.
- [x] Física e pose no acesso: **130/130** verificações das portas do cupê, incluindo arco da folha, percurso pelo vão, contato e folga da cabeça.
- [x] Roubo, direção, saída e reentrada reais em Main: **17/17** verificações, controle restaurado e uma única cabine após reentrar.
- [x] Regressão geométrica: **10/10** verificações após o ajuste do painel; as três falhas das barras e o painel atravessando o para-brisa foram reproduzidos antes e corrigidos. Instrumentos preservados abaixo do plano do vidro. Cabines do Digo: **30/30**, preservando alterações de outra sessão.
- [x] Revisão adicional do painel: cobertura recuada, baixa e rasa; fotos reais dianteira/lateral/de cima. Portas na versão atual: **128 verificações, zero falhas**.
- [x] Fluxo renderizado após o ajuste do painel: **17 verificações, zero falhas**, incluindo movimento, saída e reentrada com o piloto visível.
- [ ] Performance isolada: duas janelas renderizadas de 30 s executadas, mas há processos e alterações concorrentes. p95/p99 observados: **25,495/36,350 → 17,197/26,529 ms**; não comprovam ganho atribuível ao ajuste nem estabilidade dentro de 16,67 ms.
- [ ] Performance isolada do painel: novas janelas de 30 s com p95/p99 **15,224/18,645 → 13,500/15,392 ms**. População/tráfego e sessões concorrentes variaram; não há aprovação de ganho ou ausência de regressão atribuível ao ajuste.

## Frente do Maciota e casa Quayside — 06/10/2026

Correção de **2 acessos exteriores existentes**, sem novos lugares ou reforma dos interiores. Permanecem **32 acessos / 30 interiores distintos**, **zero novas certificações integrais**. O depósito com outdoor de farmácia foi removido pelo overlay do mapa, junto de colisão e objetos do telhado. A casa Quayside e suas vagas passaram para o terreno liberado, ao sul, na posição (164,124); a oficina e o anexo mantêm sua posição. O catálogo visual do editor acompanha a casa.

- [x] Visual e profundidade exteriores: [antes](../evidence/maciota-frontage-20261006/before-diagonal.png) e [depois](../evidence/maciota-frontage-20261006/after-final-diagonal.png), em Main real, com chuva e câmera diagonal. Oficina e anexo separados da casa, personagem e entrada visíveis. [Novo acesso da casa](../evidence/maciota-frontage-20261006/after-final-quayside-exterior.png).
- [x] Geometria e física: `test_maciota_frontage_layout.gd`, **23 checks aprovados**: volumes reais sem interseção, depósito ausente, cápsula/apoio dos acessos, vagas e corredor para o casco completo. `test_maciota_world.gd` aprovado após estabilização das edições concorrentes de combate.
- [x] Fluxo renderizado: **20 checks aprovados**, cobrindo caminhada no espaço entre casa e oficina, entrada/saída/reentrada na garagem, restrição de armas, compra e entrada física na casa, spawn, vagas, serialização e retorno ao novo exterior. [Resultados](../evidence/maciota-frontage-20261006/access-final.json).
- [x] Segurança da garagem: `test_maciota_transition_safety.gd`, **37 checks aprovados**, incluindo bloqueio de armas/ataques, preservação do inventário e proteção de Maciota/mecânico contra dano direto e explosão externa. [Escopo e resultados](../evidence/maciota-frontage-20261006/maciota-transition-safety.json).
- [x] Comparação local de performance: Godot **4.7.2 .NET**, RTX 4060 Laptop, Mobile, 1280×720, MSAA 2×, noite/chuvoso, mesma câmera. Cada amostra: 5 s de aquecimento e 30 s sem limitador/VSync; depois fluxo funcional com 60 FPS/VSync. **Antes → final:** FPS 122,79 → 122,33; p50 7,043 → 7,013 ms; p95 **13,699 → 12,390 ms**; p99 **16,184 → 14,015 ms**; máximo 28,705 → 18,471 ms; zero frames acima de 33,3 ms em ambas as janelas estáveis. [Antes](../evidence/maciota-frontage-20261006/before.json) / [final](../evidence/maciota-frontage-20261006/after-final.json).
- Limites: população observada 23 em ambas; tráfego vivo 39 → 42 veículos. Sem outra partida, geração de voz ou benchmark concorrente nas janelas medidas; editor aberto. Resultado sem regressão observada nesse cenário, sem atribuir ganho causal ou certificar outras rotas. Aquecimento final teve um frame de **74,673 ms**, separado da janela estável. A posição inicial do primeiro teste de caminhada foi atualizada porque a casa passou a ocupar parte do antigo lote; a repetição final começa no corredor livre e passou.
- Dublagem: **40 tomadas** de Maciota/telefonema com um único locutor grave e volume consistente; teste do controlador real **169 checks**, abertura **24 checks**, auditoria de formato/clipping/transcrição **40/40 sem sinalizações**. Transcrição automática não certifica interpretação artística. [Amostra](../evidence/maciota-voice/maciota-preview.wav).

## Ferrovia — 07/10/2026

### Ônibus regional — lote de 07/10/2026

**2 pontos exteriores reaproveitados + 1 nova parada aberta em Cobre / 1 novo interior móvel compartilhado / 0 certificações integrais / 1 interior em validação.** Rodoviária de Harbor, Estação de Gelo e Cobre usam a mesma cabine; não são três salas novas. Trem e ônibus somam **2 interiores móveis distintos**, sem alterar as contagens anteriores de prédios acessíveis. Dante e seis passageiros ficam sentados; não há caminhada livre nem SubViewport adicional.

- [x] Conectado à sessão normal: escolha entre percurso rodoviário e viagem rápida, câmeras interna/externa, passageiros 3D, gate final do deserto, restauração de controles e save no desembarque.
- [x] Física separada da apresentação: apoio/cápsula nas três paradas e seis transferências rápidas; casco real contra parede e **3.270 amostras** nas seis rotas, sem obstáculos estáticos ou falta de apoio. [Resultado físico](../evidence/regional-coach-clearance-49216-4847846/clearance.json). Isso não certifica condução entre veículos em movimento.
- [x] Cabine/câmeras, oclusão dos atores sentados e recuperação: **79/79 em Main renderizado**, incluindo desembarque ocupado, pausa, cancelamento no fade e destruição/resgate. [Cabine noturna em movimento](../evidence/regional-session-166048-5932583/desert-harbor-interior-moving.png), [vista externa](../evidence/regional-session-166048-5932583/harbor-mountain-exterior.png), [log](../evidence/regional-night-short.log). Sem caminhada livre; casco e apoio foram avaliados separadamente das imagens.
- [x] Percurso completo Harbor → gelo após corrigir a curva da aproximação: **73/73**, com tráfego, pausa, chegada, save e recuperação. Deserto → Harbor também concluiu fisicamente; demais sentidos foram verificados por rede/varredura e viagem rápida. [Log do gelo](../evidence/regional-ice-final.log), [registro e limites](regional-coach.md).
- [x] Parada aberta de Cobre: **10/10**, caminhada, colisão do banco, apoio, embarque e retorno sem duplicação. [Foto real](../evidence/cobre-stop-final-169388-5943467/station.png). Comparativo local de 30 s: p95 **3,953 → 3,943 ms**, p99 **5,457 → 5,401 ms**, dois frames >33,3 ms em cada janela e nenhum >66,7 ms; não estende aprovação de performance à viagem. [Métricas e limites](regional-coach.md).
- [ ] Comparativo isolado de frame time e inspeção temporal: pendentes. Testes funcionais acelerados não são benchmark nem prova de ausência de flickering.

### Vagão e plataformas

**4 novos acessos exteriores / 1 interior móvel de passageiros / 0 certificações integrais / 1 interior em validação.** Harbor Central, Northgate, Pinhais e Cobre compartilham o mesmo vagão; plataformas abertas não são contadas como quatro salas. Este lote acrescenta o vagão ao inventário, preservando as contagens e pendências dos lotes anteriores.

- [x] Implementação: vias elevadas independentes do grafo viário, galerias cobertas, acessos físicos em três lances, plataformas, trem articulado, vista interna pelas janelas, vista externa, escolha de destino e viagem rápida. Deserto acompanha o gate final da cidade 1.
- [x] Contratos isolados: rede **101/101**, interface **26/26** e modelo físico **7/7** em Godot **4.7.2 .NET**. Cápsula, piso, assentos, corredor, folga da cabeça e janela conferidos separadamente da apresentação.
- [x] Caminhada física completa subindo e descendo os quatro acessos. [Central, Northgate e Cobre](../evidence/railway-clearance-4208-4595952/clearance.json); o acesso de Pinhais falhou inicialmente na cerca do zoológico, foi reposicionado e passou na [verificação dirigida final](../evidence/railway-clearance-82240-4504662/clearance.json).
- [x] Varredura final da composição: **3.648 consultas, zero interseções, oito sentidos**. Corrigidas as folgas das curvas, o prédio alto no viaduto urbano e a rocha do deserto. [Resultado final](../evidence/railway-clearance-112120-6196705/clearance.json). Pilares reservam ruas, caminhos, edifícios e zoológico; trilhos não criam conexões no grafo rodoviário.
- [x] Runtime real em Main: **162/162**, incluindo ida/volta, viagem rápida, gates da campanha, plataforma ocupada e nova tentativa, cancelamento, câmera, pausa, bloqueio de combate, restauração de abrigo/inventário e save/reload isolado. [Log final](../evidence/railway-runtime-final-validation.log), [save de teste](../evidence/railway-runtime-118716-5574429/railway-save.json). Regressões: mapa **248/248**, segurança Maciota **37/37**; os saves pessoais não foram utilizados.
- [x] Profundidade e iluminação temporal nas viagens completas renderizadas: Harbor Central → Pinhais à noite (**2.367 frames / 55,3 s**) e Cobre → Harbor Central de dia (**3.725 frames / 85,0 s**), com vista externa, janelas internas, túneis e chegada. [Sequência noturna](../evidence/railway-night-final-harbor_central-125204-5989463/railway-night.mp4), [contato noturno](../evidence/railway-night-final-harbor_central-125204-5989463/temporal-contact.jpg), [sequência do deserto](../evidence/railway-desert-final-desert_copper-104668-5679913/railway-desert.mp4), [contato do deserto](../evidence/railway-desert-final-desert_copper-104668-5679913/temporal-contact.jpg). O custo de capturar cada frame não é benchmark. Cobertura restrita a esses horários/percursos; não certifica todas as combinações de chuva e clima do jogo.
- [x] Embarque ao alternar a câmera durante o fade: corrigida a aplicação prematura da câmera, preservando a escolha até o trem ocupar a origem sob o véu opaco. Probe dirigido **5/5** e [sequência renderizada final de 165 frames](../evidence/railway-boarding-fixed-desert_copper-56244-5882035/boarding-contact.jpg) sem olhar para a posição remota do trem; viagem rápida e chegada após essa sequência também concluídas.
- [x] Oclusão final do passageiro: a revisão externa detectou a silhueta branca padrão de Dante sobre o teto. O embarque agora ativa o contrato existente `uses_interior_depth`, mantém o ator real e restaura exatamente o metadado/overlay anterior ao sair ou cancelar. **18/18** checks dirigidos, [vista externa final](../evidence/railway-perf-riding-desert_copper-63080-5623062/exterior.png), [janela interna final](../evidence/railway-perf-riding-desert_copper-63080-5623062/inside.png) e [chegada real após a correção](../evidence/railway-perf-riding-desert_copper-63080-5623062/arrival.png). As gravações anteriores conservam o contorno que motivou essa correção.
- [ ] Aprovação comparativa de desempenho: quatro pares renderizados de **30 s**, Godot **4.7.2 .NET**, RTX 4060 Laptop, Mobile, **1280×720**, VSync/limitador desligados apenas no diagnóstico, mesmo checkpoint/horário/câmera e hashes monitorados iguais. Baseline omite somente a nova ferrovia por `--railway-baseline`, sem reverter arquivos. [Métricas completas](../evidence/railway-performance-comparison.json). Outras sessões iniciaram testes durante **39/94** registros de monitoramento no baseline e **87/94** no resultado; população/tráfego vivos também variaram. Portanto **performance não certificada**: aumentos de p95/p99 em Northgate, Pinhais e Cobre exigem confirmação isolada, sem atribuir causalidade ao trem nem esconder as diferenças.

| Estação | FPS antes → com ferrovia | p95 antes → depois (ms) | p99 antes → depois (ms) | Máximo depois / frames >33,3 / >66,7 ms |
| --- | ---: | ---: | ---: | ---: |
| Harbor Central | 120,2 → 106,8 | 14,800 → 14,671 | 17,286 → 17,540 | 46,358 / 2 / 0 |
| Northgate | 265,2 → 214,8 | 7,732 → 9,171 | 9,516 → 10,832 | 21,016 / 0 / 0 |
| Pinhais | 145,0 → 121,5 | 11,562 → 13,069 | 12,734 → 14,530 | 33,634 / 1 / 0 |
| Cobre | 472,8 → 405,6 | 3,860 → 4,406 | 5,322 → 5,926 | 78,009 / 1 / 1 |

As capturas temporais usaram a configuração normal de 144 FPS/VSync. O alvo provisório do diagnóstico é **60 FPS / 16,67 ms**; médias altas não anulam o pico de 78 ms nem certificam todos os frames. Fontes reais da ferrovia nas amostras: uma luz por estação; Pinhais mantém também duas fontes do túnel próximo. Geometria por proximidade, MultiMeshes e ausência de SubViewport limitam custo sem remover vias, passageiros ou cenário.

Viagem final Cobre → Harbor Central, **30 s por câmera**, ambos os intervalos integralmente em movimento: vista interna **516,2 FPS, p95 3,636 ms, p99 5,390 ms, máximo 356,803 ms, 6 frames >33,3 ms / 4 >66,7 ms**; externa **354,6 FPS, p95 5,799 ms, p99 9,728 ms, máximo 67,730 ms, 3 / 1 frames acima dos limiares**. [Amostras brutas e estado da viagem](../evidence/railway-perf-riding-desert_copper-63080-5623062/metrics.json), [processos concorrentes](../evidence/railway-perf-riding.processes.json). Outros testes voltaram a iniciar após a janela livre inicial, atingindo **61/63** registros. O agrupamento de quatro frames de 281–357 ms coincidiu com inicialização de outra cena renderizada; isso é correlação, não diagnóstico causal. **A estabilidade temporal de frame time e a ausência de regressão continuam pendentes de repetição isolada**. Não há aprovação baseada nas médias altas, nem certificação da primeira visita a todas as áreas.

Durante a viagem Dante ocupa uma posição fixa no corredor do vagão; não há caminhada livre, NPC residente, sala remota nem SubViewport adicional. A recompensa funcional é o transporte entre estações, sem pickup monetário repetível.

### Telhados das estações — acabamento de 07/10/2026

Revisão das quatro coberturas existentes, **zero novos acessos/interiores e zero novas certificações integrais**. Chapas com emendas elevadas e fixadores, bordas dobradas, calhas abertas, vigas inferiores e mãos-francesas compartilham os MultiMeshes existentes; fixadores acrescentam um lote do material metálico já utilizado nos trilhos. Os elementos estruturais inferiores têm colisão; enfeites rasos superiores acompanham a cobertura sólida. Mantidos o vão central de visibilidade, a circulação, os trilhos e as luzes existentes.

- [x] Build Godot 4.7.2 .NET: zero erros. Caminhada real em Main pelos quatro acessos, subindo e descendo: **20/20**, [resultado físico](../evidence/railway-clearance-163884-6337959/clearance.json). Nenhuma migração ou alteração do vagão.
- [x] Fotos reais: [antes](../evidence/railway-roof-before-harbor_central-141664-6750367/station.png), [depois aproximado](../evidence/railway-roof-final-photos-harbor_central-126532-6124283/roof-detail.png), [Northgate](../evidence/railway-roof-final-photos-harbor_central-126532-6124283/harbor_north.png), [Pinhais](../evidence/railway-roof-final-photos-harbor_central-126532-6124283/mountain_pines.png), [Cobre](../evidence/railway-roof-final-photos-harbor_central-126532-6124283/desert_copper.png). Estrutura elevada e vão central conferidos na cena renderizada; câmera de revisão usada somente pelo harness.
- [x] Comparativo local de 30 s, mesma vista geral ortográfica de Harbor Central (tamanho 43), 1280×720, Mobile, RTX 4060 Laptop, dia, VSync/limite desligados apenas no benchmark. **Antes → final:** FPS 77,583 → 89,446; p50 **13,154 → 11,711 ms**; p95 **18,628 → 15,854 ms**; p99 **23,954 → 18,647 ms**; máximo **47,663 → 37,994 ms**; frames acima de 33,3 ms **4 → 3**, acima de 66,7 ms **0 → 0**. [Baseline bruto](../evidence/railway-roof-before-harbor_central-141664-6750367/metrics.json), [final bruto](../evidence/railway-roof-final-harbor_central-154248-5604899/metrics.json).
- Limites: população/tráfego **30/43 → 29/42**, outras sessões executando capturas durante parte do trabalho e alterações concorrentes no jogo. O resultado não demonstra ganho causal nem fecha a homologação isolada da ferrovia. A janela intermediária, anterior à inclusão das colisões das vigas, ficou em 76,253 FPS e p95 18,631 ms; não foi usada como versão final. Fotos das quatro estações também verificadas com configuração normal 144 FPS/VSync, sem usar esse limitador como prova de desempenho.

### Oficina de tunagem — apresentação e acabamentos, 07/10/2026

Uma tela compartilhada pelo mecânico do Maciota e pelo Digo foi revisada. **Zero novos acessos, zero interiores acessíveis novos e zero novas certificações integrais de salas**; permanecem as contagens anteriores do inventário. A baia é um cenário de apresentação no SubViewport já existente, sem jogador/NPC caminhável. Sua bancada e seus armários não foram colocados no interior físico da garagem. Colisão/spawn/oclusão de novos móveis acessíveis: não aplicável a essa vitrine; as transições produtivas da garagem foram exercitadas.

- [x] Visual: baia com concreto, bancada, armários, ferramentas e marcação no piso; carro maior, giro manual/automático, pausa, zoom e recentralização. Menu compacto, amostras de cor legíveis e indicadores comparativos preservados. [Antes em Main](../evidence/tuning-workshop-before-177020-6131045/mechanic.png), [depois em Main](../evidence/tuning-workshop-final-98580-5560358/custom-painted.png), [aros](../evidence/tuning-panel/6_coyote_aros.png). Bancos e apoios de cabeça bege do Porto Rosso foram identificados como mobiliário do carro, não ocupantes.
- [x] Compras e persistência: quatro pinturas, três acabamentos de carroceria e três cores de aro no catálogo existente. Prévia reversível, remoção devolve acabamento original, recibos por identidade do veículo e peças visuais não alteram desempenho mecânico. `test_maciota_workshop_session.gd` passou no Main renderizado com compra por input, carteira, aplicação real, cancelamento, save em disco isolado, recarga a frio e saída. [Checkpoint final da validação](../evidence/maciota-workshop-session-174908-5632038/checkpoint.json). O teste encontrou e levou à correção da integração entre acabamento comprado e base de desgaste na recarga. A saída de foco por teclado também restaura a prévia não comprada.
- [x] Materiais e recuperação: `test_tuning_appearance.gd`, **286 checks**, em oito modelos do deserto e três da frota base, sem alteração de material compartilhado, preservando dano e cor de origem. `test_tuning_showroom.gd`, `test_tuning_progression.gd` e `desert_cars_fleet.gd` passaram. `test_vehicle_damage_look.gd`: **170 checks**, incluindo desgaste, incêndio, carcaça e reparo. Ao fechar, o carro de prévia é liberado e o SubViewport deixa de renderizar; o pequeno cenário estático é reutilizado.
- [x] Regras da garagem: **37/37** em `test_maciota_transition_safety.gd`, headless/.NET, Main real e APPDATA isolado: bloqueio de armas e ataques, inventário preservado, proteção do Maciota/mecânico e retorno ao exterior. [Resultado e limites](../evidence/tuning-safety-2b9b3f1706394bdcaf5087c0dfe93298/maciota-transition-safety.json).
- [x] Geometria dos **8 carros do catálogo de tunagem/deserto**: aros vazados, raios unidos ao aro e ao cubo, talão ajustado para evitar folgas, cubos chanfrados e bocas de escape abertas. Substituídos **12 primitivos cilíndricos de roda por carro**, antes do batching; isso não é uma alegação de redução de draw calls. Materiais, pintura, pivôs e batching preservados. `test_desert_car_fit.gd`: **75 checks**; [capturas dos oito modelos](../evidence/desert-car-fit-68544-5534895). A frota exportada legada não recebeu essa reforma geométrica completa.
- [x] Comparativo local renderizado: Godot **4.7.2 .NET**, RTX 4060 Laptop, renderer Mobile, **1280×720**, Main/Maciota e caminho C# ativo. Cinco segundos de aquecimento e **30 segundos por janela**. Diagnóstico sem VSync/limite; funcionamento também medido com VSync/60 FPS. Nenhum outro jogo foi observado nas verificações de processos; o editor permaneceu aberto. [Métricas e amostras brutas finais](../evidence/tuning-workshop-final-98580-5560358/metrics.json), [comparação](../evidence/tuning-workshop-final-98580-5560358/review.json).

| Cena na oficina | FPS antes → final | p50 antes → final (ms) | p95 antes → final (ms) | p99 antes → final (ms) | Máximo final / frames >33,3 / >66,7 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Mecânico / Infernus | 418,77 → 445,86 | 2,215 → 2,097 | 3,426 → 3,013 | 4,990 → 4,049 | 22,327 / 0 / 0 |
| Coyote / neon | 450,26 → 459,45 | 2,108 → 2,035 | 2,958 → 2,913 | 3,721 → 3,855 | 7,090 / 0 / 0 |
| Painel fechado / limite 60 | 60,07 → 60,03 | 16,665 → 16,667 | 18,671 → 18,590 | 18,970 → 19,039 | 20,302 / 0 / 0 |

Sem regressão relevante observada nessas janelas: p99 do Coyote aumentou **3,6%**, abaixo do limiar pré-definido de investigação de 5%; a janela intermediária também não mostrou regressão. A média de FPS não certifica cada frame: houve máximo final de 22,327 ms no mecânico, acima do alvo provisório de 16,67 ms. O baseline teve invalidação do dispositivo de áudio e um pico de 111,223 ms; não se atribui redução desse pico às alterações. Painel aberto na configuração de 60 FPS: média **60,07**, p95 **18,599 ms**, p99 **18,878 ms**, sem frames acima de 33,3 ms. Não é benchmark da rua, de primeira visita a todas as áreas ou de corrida com sete carros.

- [x] Evidência temporal preservada: **1.498 frames / 29,998 s**, giro e zoom com neon ativo, **zero lacunas no contador de frames renderizados**. Intervalos de captura de 17–32 ms, média 20,039 ms; salvar imagens reduz a cadência e esse trecho não foi usado como benchmark. [Vídeo](../evidence/tuning-workshop-final-98580-5560358/workshop.mp4), [timestamps e contadores](../evidence/tuning-workshop-final-98580-5560358/metrics.json). Inspeção dos pares de maior variação (30–31, 964–965, 1216–1217) mostrou movimento coerente, sem apagão/popping observado. O vídeo usa cadência média; a sequência original retém os timestamps.
- [ ] Certificação temporal integral: não foi feita observação humana de todo o vídeo em reprodução contínua. Análise de diferenças e pares de frames não certificam ausência de flickering de um frame em todas as áreas/carros. A iluminação geral do jogo e a carga de corrida com vários carros permanecem fora desta validação.

## Farol costeiro — acesso exterior, 07/10/2026

Escopo: **1 espaço exterior acessível / 0 interiores novos**. O inventário de
interiores não muda. Passeio e escada externa contínuos levam ao binóculo na
galeria; não existe transferência para sala. [Implementação e evidências](mirante-costeiro-20261007.md).

- [x] Circulação: 15 verificações com Actor real, subida/descida completas,
  guarda-corpos e três varreduras de carro na entrada; sem saltos/teleporte.
  `evidence/coastal-lighthouse-physics-final.log`.
- [x] Profundidade: 63 verificações renderizadas, jogador e NPC nas duas
  voltas e na galeria, controle positivo sem arquitetura e corte localizado
  que preserva colisões/sombras. `evidence/coastal-lighthouse-depth-127480-5695854/`.
- [x] Main/C#: 38 verificações do percurso e binóculo; 34 do save no topo,
  controles e vistas dia/noite; após preparação antecipada, 30 verificações
  de restauração/reentrada confirmam uma lanterna, um binóculo e geometria
  gerada somente uma vez. Capturas `coastal-lookout-capture-64692-6225742`,
  `coastal-lookout-capture-32208-5733504` e `coastal-lookout-capture-54888-5791978`
  sob `evidence/`. A primeira captura precede a correção visual da cúpula;
  as duas seguintes mostram a malha final.
- [x] Antes/depois reais: mirante anterior em
  `evidence/coastal-lookout-before-lighthouse-72420-6507806/overview.png`;
  farol em `evidence/coastal-lookout-capture-32208-5733504/final-day.png`.
- [ ] Aprovação de desempenho e estabilidade temporal completa: consultar
  o relatório do farol. Sequências contínuas de 30 s por dia/noite, sem
  lacunas, e triagem de pixels não substituem inspeção de todos os frames
  nem certificam clima, cidades ou interiores fora deste escopo.

## Harbor — ilusão da Umbra por embriaguez extrema — 07/10/2026

**0 novos acessos permanentes / 0 locais adicionais no catálogo / 1 arena ilusória temporária acessível.** Umbra continua sendo um único interior cadastrado. A arena é um cenário distinto com céu aberto e duração limitada; não duplica a contagem da casa. **0 novas certificações integrais** enquanto a revisão temporal e o comparativo de performance estiverem pendentes. [Implementação e evidências](reviews/upside-world-20261007.md).

- [x] Quatro monstros, ruínas, fissuras, névoa roxa, meteoros, chuva e destroços; primeira pessoa com jogador físico. Entrada somente com embriaguez extrema, duração de 10–15 s, retorno sorteado em Harbor e sobriedade. Não há dano causado pelos monstros nem perda de estoque/progresso.
- [x] Física e profundidade separadas: **188 verificações** no fixture, com cápsulas reais, sólidos, apoio e oclusão com controles positivos. [Relatório](../evidence/upside-world-geometry-177504-5659916/report.json). Piso contínuo, sem aberturas cosméticas que provoquem queda.
- [x] Main/.NET: **71 verificações** do percurso normal e restauração fria; **67** de morte/resgate, prisão, load/menu e obstáculo que surge no destino durante a saída. Estado e interrupções dirigidas: **30 + 76**. [Cena final em Main](../evidence/upside-world-test-194140-6008731/cycle-0-upside.png), [retorno real](../evidence/upside-world-test-194140-6008731/cycle-0-return.png), [casa normal de referência](../evidence/upside-control-before-186156-5799435/house.png). A arena é nova; não há foto anterior dela.
- [x] Registro temporal: **1.117 frames / 37,35 s jogáveis**, com **33,90 s** em trechos contínuos depois dos controles iniciais, sem omissão de frames nesses trechos. Dia, noite e rotação; duas fontes locais. [Análise de regiões e eventos](../evidence/upside-world-capture-193084-5727916/pixel-temporal-analysis.json). As falhas de retorno encontradas nessa gravação foram corrigidas e reproduzidas com obstáculo físico no teste posterior de 67 verificações. A arte/iluminação permaneceu igual.
- [x] Quatro visitas finais consecutivas: **147 verificações**, três destinos distintos, retorno sóbrio e estoque preservado. Arena medida durante **39,126 s** de visitas aquecidas: p95 **3,471 ms**, p99 **5,259 ms**, sem frames >33,3 ms. [Resultados brutos](../evidence/upside-world-benchmark-194336-5972306/report.json); concorrência e alteração externa de `Gameplay.gd` impedem tratar essa janela como totalmente isolada.
- [ ] Homologação integral: confirmação antes/depois de **30 s por cenário** permaneceu afetada por outros motores e alterações concorrentes; p99 exterior **8,658 → 9,251 ms (+6,85%)**, acima da tolerância de investigação. [Comparação final](../evidence/upside-final-comparison.json). Também faltam reprodução temporal integral e medição da criação da arena sob o fade. Manter zero novas certificações integrais; não aprovar FPS por captura ou teste headless.

## Harbor — Parque Lume e Umbra — 07/10/2026

**1 novo parque exterior / 1 interior independente (Umbra) / 0 certificados integralmente.** Conteúdo opcional implementado; contagens históricas dos demais lotes preservadas. O interior usa primeira pessoa conforme o pedido. [Implementação, evidências e limites](reviews/amusement-park-20261007.md).

- [x] Montanha-russa percorrível, câmera em perspectiva, cancelamento, volta à estação e resgate; casa do terror com circuito fechado, fantasma mecânico inofensivo e saída pelo indicador compacto. Fachadas somente com nomes próprios.
- [x] Física: **440/440**, com apoio, cápsulas reais de jogador/NPC, cercas, mobiliário, degrau exclusivo da plataforma, porta e acesso aos seis segredos. **56/56** no Main renderizado, incluindo caminhada desde a rua, todo o percurso da casa, ida/volta, coleta, troca, morte/resgate e descarregamento. Não há NPC residente em Umbra; Dante fica oculto na câmera em primeira pessoa.
- [x] Profundidade separada: fantasma e segredo visíveis nos controles positivos (4.705 e 712 pixels), completamente ocultos pela divisória nos negativos (zero pixels). [Evidência renderizada](../evidence/amusement-park-temporal-181056-6007320/report.json). Colisão não foi usada como substituto de oclusão.
- [x] Segredos persistentes: duas roupas, dois óculos e duas máscaras; save antigo compatível e coleta sem duplicação. **43/43** verificações de estado, equipamento, combinações e save em disco isolado. **19/19** de teclado/controle/toque, incluindo botão de saída acionado por eventos reais.
- [x] Fotos reais: [lote anterior](../evidence/amusement-park-baseline-189940-6435239/overview.png), [parque](../evidence/amusement-park-final-187008-6177175/overview.png), [descida](../evidence/amusement-park-temporal-181056-6007320/coaster-descent.png), [interior](../evidence/amusement-park-final-187008-6177175/house.png), [porta/indicador](../evidence/amusement-park-temporal-181056-6007320/house-exit-door.png). Interior novo, sem foto anterior aplicável.
- [x] Desempenho medido na cena real/.NET: janelas de 30 s, 1920×1080/Mobile/RTX 4060 Laptop. Exterior antes/depois dia e noite, mais passeio e casa; p95 final 8,456–11,810 ms, p99 11,423–13,992 ms, zero frames >33,3 ms em regime estável. Limite normal de 144 FPS. Não houve aumento >5% nos percentis estáveis; população ambiente variou e a primeira visita conserva um pico de 160–171 ms já presente no baseline. Esses limites impedem alegar ausência de travamentos ou ganho causal.
- [x] Registro temporal noturno: **757 frames do parque + 786 da casa**, aproximadamente 30 s cada, sem lacunas de frames renderizados e sem falhas de gravação. Três fontes locais no exterior e três no interior, sem duplicação. Indicador em perspectiva e pausa real passaram; fonte permaneceu estável durante a captura. Captura a 1280×720, JPEG reduzido e limite temporário de 30 FPS; não é benchmark.
- [x] Encaixe final dos acessórios: 14 retratos com Dante/esqueleto reais, óculos e máscaras separados/combinados em frontal e três quartos; topo das máscaras abaixo dos olhos e armações próximas ao rosto. [Estrela + Raposa](../evidence/amusement-park-cosmetics-fit-190392/star-fox-three-quarter.png), [relatório e hashes](../evidence/amusement-park-cosmetics-fit-190392/report.json). Mesmo número de malhas; somente escala/posição alteradas.
- [ ] Certificação temporal integral: a revisão de regiões estáticas e pares de frames não equivale à inspeção humana integral em reprodução contínua. Cobertura não inclui chuva, todas as transições de horário nem dispositivo Android físico; não certificar iluminação ou performance de todo o jogo a partir deste lote. Acabamento final dos acessórios e achados da revisão estão no relatório vinculado.


## Gatos adotáveis nas residências — 07/10/2026

Escopo: **3 residências existentes / 3 interiores distintos alterados / 0 interiores novos**, além de 10 pontos exteriores de descoberta (um rooftop). O inventário global de lugares não muda. **0 novas certificações integrais; 3 ambientes em validação**, com desempenho comparável ainda pendente.

- [x] Dez pelagens e identidades fixas, liberadas após comprar casa; aproximação, E, som e contador `1/10 gatos adotados`; adoção única, coleção e acessórios acompanham a casa ativa. Caminhas e brinquedos ficam na escrivaninha, menu Casa. Sem novas luzes, SubViewports, rotinas de dano ou morte.
- [x] Integração dirigida no Main/.NET: **169 verificações aprovadas**, incluindo os dez locais, escada real do rooftop, adoção, troca entre Westgate/Quayside/Canal North, dez moradores no exterior/interior, conjunto máximo de 10 camas + 3 bolas + 2 arranhadores, formas físicas reais e save/load em arquivo isolado. [Log](../evidence/cats-session-verified.log). Deslocamento entre locais usa teleporte de fixture; não certifica caminhada de todas as rotas da cidade. A procura do porto foi exercitada; a gravação usa recuperação explícita para estado sem estrelas, sem afirmar cobertura de evasão policial.
- [x] Persistência e compras: **79 verificações** de casa, dinheiro, dez IDs, duplicação, mudança, JSON, migração antiga e rejeição atômica. Física separada: **22 verificações**, parede, corpo inteiro, caminha pela abertura, deitar/sair, bola/arranhador e suspensão; [log físico](../evidence/cats-physics.log). Reserva de circulação: **12 verificações**, incluindo corredor estreito entre amostras sem reduzir raio; [log](../evidence/cats-layout-final.log).
- [x] Profundidade nativa independente da colisão: gato sentado/andando diante, atrás e ao lado de armário, com controles positivos de 2.395–2.809 pixels; atrás, zero pixels. [Resultados e capturas](../evidence/cats-depth/results.json). Não equivale a filmar todos os móveis das três casas.
- [x] Fotos reais antes/depois: [Westgate antes](../evidence/cats-baseline-184548-6421738/westgate_garden.png), [Westgate com gatos e compras máximas](../evidence/cats-session-185132-8927987/westgate_garden.png), [Quayside](../evidence/cats-session-185132-8927987/quayside_house.png), [Canal North](../evidence/cats-session-185132-8927987/canal_north.png), [primeira adoção](../evidence/cats-session-185132-8927987/first-adoption.png).
- [ ] Desempenho comparável e revisão temporal integral: baseline inicial renderizado de 30 s por cenário preservado em `evidence/cats-baseline-184548-6421738/report.json`. Alterações concorrentes em outros sistemas exigem novo A/B no mesmo estado de código. `tests/measure/RunCats.ps1` aguarda janela sem outro Godot e interrompe apenas sua própria medição se surgir concorrência. A tentativa final terminou antes de iniciar com `CATS_MEASURE_BLOCKED concurrent session before launch` ([log](../evidence/cats-comparison-monitor.log)); não houve A/B final válido. Não aprovar FPS pelo HUD das capturas. Miaus são síntese local curta, sem loop; qualidade audível ainda sem escuta humana documentada.

## Parque Lume e Lago Sereno — ampliação exterior, 07/10/2026

Escopo: **2 exteriores alterados / 0 interiores novos ou reformados / 0 novas certificações integrais**. As contagens e pendências dos interiores anteriores permanecem registradas acima. [Implementação e evidências](reviews/park-countryside-20261007.md).

- [x] Parque preenchido com quatro barracas, cinco mesas/sombreiros, canteiros, carrinhos, balões e bandeirolas; quatro palhaços distintos andando com rig e colisão reais. Criação escalonada, ocultação/suspensão em interiores e liberação por distância.
- [x] Máquinas Aurora/Pingo: quatro consumíveis, preços do catálogo, débito/entrega/estoque por recibo persistente. **43/43** comércio, **428/428** física/circulação; compra pela interface real, checkpoint adiado por missão e restauração em disco **11/11**. [Resultado final](../evidence/amusement-park-life-session-195352-5993121/result.json).
- [x] Profundidade separada da física: barraca **32.329→0 pixels**, banda corporal coberta pela mesa **3.530→0** com tronco/cabeça acima visíveis; no bosque, Dante atrás de tronco **7.690→0** no ROI corporal. O contorno externo existente do CityLook foi preservado e não é confundido com a geometria do corpo.
- [x] Lago movido cerca de 326,6 m para oeste, estrada de terra de 6,5 m, estacionamento/retorno e **208 árvores novas**. Terreno nativo único, físico e carregado por área, sem pele coplanar; troncos sólidos fora da faixa rodável. **21/21** acesso/terreno, **71/71** geometria do lago e **58/58** Main: direção real, desembarque, caminhada, pesca, histórico, saves antigo/novo, mapa e retorno após descarregar.
- [x] Registro visual rural: **1.091 frames / 70,786 s**, zero lacunas, fontes estáveis. Amostras de todo trajeto e recortes consecutivos da emenda/bosque inspecionados sem buracos, mar pelo chão ou alternância de pisos nesses recortes. [Revisão e vídeo](../evidence/fishing-relocation-session-144656-7386378/visual-review.md). As capturas com readback/JPEG e limite de 30 FPS não medem desempenho normal.
- [x] Fotos reais finais: [parque ampliado](../evidence/park-countryside-after-188984-6034472/park_overview.png), [pesque-pague no bosque](../evidence/park-countryside-after-188984-6034472/fishing_overview.png), [palhaço](../evidence/amusement-park-life-session-193668-6786040/clown_1.png). Antes/depois com a mesma câmera relativa no relatório.
- [ ] Comparativo final isolado de desempenho: baseline de quatro janelas de 30 s preservado; outras sessões apareceram em **56/64 snapshots** da execução final. A reprise com proteção foi interrompida ao surgir outro Godot, encerrando somente a fixture própria. O A/B isolado e a investigação do pico de admissão de **197,828 ms** permanecem pendentes; nenhum FPS é aprovado por screenshots ou execução concorrente. [Registro final](../evidence/park-countryside-validation-summary.json).
- [ ] Revisão temporal integral: não houve reprodução humana de todos os frames. Não extrapolar os recortes inspecionados para todos os horários, chuva, dispositivos ou iluminação global.

## Parque Lume e Lago Sereno — integração dos terrenos, 08/10/2026

Escopo: **2 exteriores existentes / 0 interiores alterados / 0 novas certificações integrais**. Refinamento dos pisos da ampliação anterior, sem mudança de contagens de lugares. [Relatório desta etapa](reviews/recreation-ground-blend-20261008.md).

- [x] Gramado sob a montanha-russa e junto ao perímetro; pavimento e caminhos dividem o plano, com borda mineral e transição apoiada até a grama externa. A entrada conserva o encontro com a calçada. [Antes](../evidence/park-countryside-after-188984-6034472/park_overview.png), [depois](../evidence/amusement-park-ground-session-196080-6248021/park_overview.png), [quina da entrada](../evidence/amusement-park-ground-session-196080-6248021/entry_south_joint.png).
- [x] Lago com terra/cascalho misturados à grama no próprio chão nativo; pátio angular e três faixas visuais substituídos. Margem de pedra, água, plataformas, árvores, estrada, sólidos e IDs preservados. [Antes](../evidence/park-countryside-after-188984-6034472/fishing_overview.png), [depois](../evidence/fishing-ground-after-186436-6762190/fishing_overview.png), [entrada oblíqua](../evidence/fishing-ground-after-186436-6762190/apron-oblique.png).
- [x] Física dirigida: parque **16/16**, apoio dos **529 triângulos**, percursos de Dante/palhaço e reentrada; lago **21/21 + 71/71** e Main **76/76**, incluindo direção/estacionamento, volta a pé e descarregar/retornar. Percursos Main do parque apoiados e quatro palhaços residentes. O relatório bruto do parque preserva dois falsos negativos da quota de frames da fixture, diagnosticados separadamente; não são apresentados como uma execução totalmente verde.
- [x] Registro temporal do lago **1.439 frames / 78,4 s**, sem lacunas ou arquivos corrompidos, fontes estáveis; 80 amostras e 66 frames consecutivos das emendas inspecionados sem defeito observado nesses recortes. Parque: duas travessias registradas continuamente, 43 e 45 frames em aproximadamente 3 s cada. Capturas não medem FPS normal.
- [ ] Comparação isolada de desempenho: a tentativa A/B com acabamento anterior selecionado na construção foi interrompida ao surgir outro Godot antes da primeira janela estável. Somente nossa fixture foi encerrada. Sem par válido de 30 s, desempenho permanece pendente; runner e auditoria estão no relatório.
- [ ] Revisão temporal integral e condições adicionais: inspeção dirigida diurna/seca, sem reprodução humana integral de todo registro, chuva/noite ou Android. Não certifica iluminação, desempenho ou todos os terrenos do jogo.

## Parque Lume — montanha-russa, 08/10/2026

Escopo: **1 atração exterior existente / 0 interiores alterados / 0 lugares novos / 0 certificações integrais novas**. Implementação local concluída; certificação de desempenho permanece em andamento. Não alterar as contagens da Umbra, reformada por outra sessão.

- [x] Circuito simples de **129,72 m**, altura **0,38–16,31 m**, sem os retornos internos sobrepostos. A revisão auxiliar identificou cruzamento antigo com apenas **0,841 m** de separação vertical. Centro e ambos os trilhos, tangentes de fechamento, curvas e envelope dentro da cerca verificados em amostras de 25 cm. **10/10** no teste dedicado, incluindo cápsulas de Dante e NPC contra portinhola fechada, aberta e novamente fechada: [log](../evidence/coaster-track.log).
- [x] Entrada de **$5 por passeio**, recusa com saldo insuficiente, proteção contra interação duplicada e saldo preservado no snapshot. Dante aproxima-se, passa pela portinhola, entra e senta; porta e barra fecham antes da partida. Desembarque reverte a sequência na estação, com câmera própria e restituição de controles, visibilidade e colisões. Pedir saída durante a volta mantém o carro no trilho até a estação. Pausa e transições de recuperação preservam a liberação imediata preexistente.
- [x] Fotos reais: [trajeto anterior](../evidence/coaster-before-33120-6495977/station.png), [circuito novo](../evidence/coaster-after-36456-5735264/station.png), [entrada](../evidence/coaster-session-36788-7413130/entry-03.png), [saída](../evidence/coaster-session-36788-7413130/exit-02.png). Sequências de seis capturas por transição verificam aproximação, passagem e oclusão pelo carrinho; não constituem auditoria visual de todo o parque.
- [x] Controles desktop, gamepad e touch em fixture: **19/19**; [log](../evidence/coaster-input.log). Compilação `dotnet build Harbor.csproj --no-restore` sem erros/avisos, Godot **4.7.2 .NET**, Main com roteamento C# e save de fixture isolado. Os testes gerais antigos foram ajustados para o ingresso, a espera do desembarque e a malha atual de piso; não contar esses runners gerais como executados integralmente nesta revisão.
- [x] Sessão Main renderizada: **32/32**, incluindo embarque/desembarque real, bloqueio temporário da plataforma e retomada sem sobreposição, segunda cobrança, cancelamento durante aproximação, pausa, morte durante entrada e resgate. [Resultado](../evidence/coaster-session-36788-7413130/result.json), [log](../evidence/coaster-session-complete.log). Uma execução anterior foi interrompida por entrada de pausa externa; a fixture final bloqueia somente input de desktop não solicitado e invoca as ações do jogo explicitamente.
- [ ] Comparativo de desempenho isolado: duas janelas de **30 s** por versão, mesma câmera de estação, passeio real com repetições, Mobile/Vulkan, RTX 4060 Laptop, **1920×1080**, VSync ativo, limite **144 FPS**. Estação: p95 **9,101 → 10,699 ms**, p99 **12,532 → 14,868 ms**; passeio: média **123,46 → 134,41 FPS**, p95 **12,470 → 11,230 ms**, p99 **16,823 → 14,067 ms**, máximo **595,174 → 193,860 ms**. São dados diagnósticos: houve concorrência de processos, alteração de fontes durante a execução final (`source_stable=false`) e população distinta. Não atribuir melhora/regressão ao coaster nem aprovar FPS. [Antes](../evidence/coaster-before-33120-6495977/report.json), [depois](../evidence/coaster-after-36456-5735264/report.json), [processos concorrentes](../evidence/coaster-after-processes-during.json). Repetir A/B em janela isolada; amostras brutas, primeira visita e aquecimento estão separados nos relatórios.

## Casas compráveis — indicador e cobertura externa — 10/10/2026

Escopo: os três lugares existentes (`westgate_garden`, `quayside_house`, `canal_north`), com três interiores existentes, sem novos lugares ou reforma das salas. Esta revisão não altera a contagem global de interiores concluídos.

- [x] Cifrão verde pequeno em 3D, flutuante e giratório, junto ao acesso de compra; sem collider, fonte de luz ou SubViewport. Preserva a confirmação existente. Indicador oculto na propriedade ativa, inclusive após restauração, e reativado quando a casa volta à venda. O alias de fachada `CanalHomesWest` usa o mapeamento existente para `canal_north`.
- [x] Cobertura externa da garagem com nervuras metálicas e acabamento lateral/traseiro. Removida a ocultação provocada por pessoas/carros na área; preservadas posições dos postes, vagas e entradas. Fotos reais [antes](../output/residence-sale-20261010/before-quayside_house.png), [depois](../output/residence-sale-20261010/after-quayside_house.png), [garagem ocupada](../output/residence-sale-20261010/after-quayside_house-garage-occupied.png) e [terceira casa](../output/residence-sale-20261010/after-canal-fixed-canal_north.png).
- [x] Main renderizada com Godot 4.7.2 .NET, `Harbor.csproj` compilado sem avisos/erros, saves isolados: 27 checks pertinentes nas três casas. Giro, compra real no acesso, ocultação, retorno à venda, restauração e cobertura com Dante dentro. [Primeiras duas casas](../output/residence-sale-after.log), [terceira casa após corrigir alias](../output/residence-sale-canal-fixed.log). A primeira execução falhou ao localizar o indicador de `canal_north`; o teste dirigido seguinte aprovou essa casa.
- [x] Ciclo de vida: 13 checks, zero falhas; pré-carregamento que remove a fachada no mesmo frame, identidade das três propriedades, ausência de colisão no indicador e liberação no descarregamento. [Log](../output/residence-sale-lifecycle.log). A chamada adiada pertence à fachada para ser cancelada quando ela já foi removida; esse teste confirma a correção do erro visto no pré-carregamento da execução anterior.
- [ ] Performance aprovada: comparação diagnóstica com janelas renderizadas de 30 s, Main, Mobile/Vulkan, RTX 4060 Laptop, 1280×720, limite efetivo de 144 FPS. Westgate: média 104,78 → 55,29 FPS e p95 22,468 → 36,291 ms; Quayside: 28,70 → 24,33 FPS e p95 67,703 → 118,547 ms; Canal: 77,18 → 55,33 FPS e p95 32,155 → 58,390 ms. Houve vários processos simultâneos e mudanças concorrentes, além de erros preexistentes no sistema de skate. A piora observada não aprova performance nem permite atribuir a causa ao indicador/cobertura. Requer comparação isolada, sem encerrar sessões alheias. [Amostras anteriores](../output/residence-sale-20261010/before.json), [posteriores](../output/residence-sale-20261010/after.json), [Canal corrigida](../output/residence-sale-20261010/after-canal-fixed.json), [processos concorrentes](../output/residence-sale-20261010/concurrent-processes.json).
- [ ] Auditoria física e de profundidade completa dos interiores: fora do escopo desta alteração exterior; não reclassificar as salas como aprovadas nesta revisão. O indicador não participa de colisão e as novas partes da cobertura ficam acima da passagem, como conferido na construção/finalização da fachada.

## Boeiros de Harbor — reação coletiva ao combate, 10/10/2026

Escopo: **7 lugares existentes / 7 interiores com comportamento de moradores alterado / 0 lugares novos / 0 novas certificações integrais**. Geometria, câmera, iluminação e acessos mantêm sua configuração. O boeiro original recebeu três moradores; os seis demais mantêm sua população autorada. Não alterar as contagens de ambientes concluídos por esta implementação.

- [x] Primeiro golpe de punhos: dano e aviso funcional `PARE!`; segundo golpe: defesa, armas próprias e alerta entre aliados próximos. Ataque armado provoca defesa imediata. Equipamentos: punho, faca, garra improvisada, garrafa quebrada e pistola. Ataques têm preparação, alcance, cadência, teste de visibilidade e bloqueio por sólidos.
- [x] Física e comportamento das sete salas: **90/90** checks com corpos e salas reais, controlador reduzido somente para dano ao jogador; o alerta encadeado final no boeiro original acrescenta **18/18**. Inclui spawn, movimento varrido, ausência de penetração da cápsula real, dano inválido, aviso, retaliação, armas, bloqueio durante transição, paredes e morte. [Sete salas](../output/sewer-hostility-unit-approved.log), [alerta entre aliados](../output/sewer-hostility-relay-approved.log). Uma consulta retangular anterior produziu falso positivo no canto do barril do armazém; a verificação final consulta a cápsula física e exclui apenas o piso.
- [x] Sessão integrada inicial, headless: socos pela física do `Gameplay`, aviso, ajuda de aliada, dano real, diálogo bloqueado durante briga, saída/liberação dos três atores e reentrada sem estado residual. [Log](../output/sewer-hostility-integration.log). Esta primeira execução precede o refinamento do alerta até o morador armado; conferir a execução renderizada final abaixo para esse refinamento.
- [x] Regressão de acesso/conversa: seis tampas, descida, moradores, diálogos, saída, retorno à tampa e controles. O runner geral teve **123 PASS / 6 FAIL**: falharam coleta/posse de soqueira, machado e AK-47, pois acumula armas de todos os boeiros no inventário limitado. O mesmo resultado foi reproduzido sem mundo, NPC ou combate, usando `Economy.grant_world_reward`; as três recompensas passam individualmente em inventário novo. Não contar o runner geral inteiro como aprovado. [Sessão](../output/sewer-network-regression.log), [diagnóstico de capacidade](../output/sewer-reward-capacity-probe.log).
- [x] Conferência final renderizada do alerta completo e regressão de garagem: **24/24**, Godot 4.7.2 .NET, Main, Mobile/Vulkan, RTX 4060 Laptop. Socos reais provocam aviso e defesa dos três moradores, inclusive Beto com pistola; saída/reentrada limpa os atores. Garagem guarda arma, bloqueia saque e ataques, mantém Maciota/mecânico protegidos sem rotina de dano e libera a arma na saída. [Runner](../tests/test_sewer_hostility.gd), [log final](../output/sewer-hostility-gameplay-approved.log). A execução anterior revelou que a aliada corria antes de retransmitir o alerta; a propagação agora acontece antes da perseguição. [Tentativa anterior](../output/sewer-hostility-rendered-final.log).
- [x] Capturas reais do boeiro original: [moradores](../output/sewer-hostility/residents-idle.png), [aviso](../output/sewer-hostility/first-punch-warning.png), [briga](../output/sewer-hostility/fight-03.png). Conferidos escala humana, aviso legível e aproximação/golpes da aliada. São estados da implementação atual, não um comparativo visual com a versão antiga.
- [ ] Oclusão dirigida atrás/ao lado de todos os móveis e revisão visual das seis outras salas: não executadas. A física não certifica profundidade/renderização. Nenhuma reforma global de interiores foi realizada.
- [ ] Comparativo de frame time antes/depois: não medido. Havia outros testes e benchmarks Godot continuamente ativos durante a implementação; não executar benchmark simultâneo nem encerrar sessões alheias. Sem baseline comparável, não aprovar FPS nem atribuir regressão. [Processos durante a validação](../output/sewer-hostility-processes.json), [processos no encerramento](../output/sewer-hostility-final-processes.json), [medidor preparado](../tests/measure/measure_sewer_hostility.gd). A captura e o contador de FPS não substituem janelas isoladas de 30 s.


## Indicador de lockpick dos containers do porto — 10/10/2026

Ajuste restrito ao acesso dos 18 containers já arrombáveis; nenhum lugar ou interior novo, sem alteração de câmera, circulação, iluminação ou sólidos.

- [x] Bolinha laranja de 18 cm de diâmetro junto à fechadura, sem texto, luz, sombra, colisão ou atualização por frame. Só aparece com a porta trancada; restauração e reposição usam o estado existente.
- [x] Godot 4.7.2 .NET; build de Harbor.csproj sem avisos/erros. Teste existente de cache/colisão: 18 checks, zero falhas. Verificação dirigida: porta fechada/aberta, fade do teto, reposição e ausência de collider; aprovada. A primeira fixture chamou fade antes de liberar meshes descartados pelo otimizador; corrigida a espera da fixture, execução final sem erros.
- [ ] Visual na cena Main e performance comparativa: pendentes. Outros testes/benchmark simultâneos impediram medição isolada. Tentativa renderizada de Main bloqueada por erro de inferência em scripts/Driving.gd:132 (had_driver), modificado por outra sessão; arquivo preservado. Não certifica FPS, oclusão integral ou os interiores. Log: [after-render.log](../tmp/port-marker-20261010/after-render.log).
- [x] Modelo real renderizado em fixture isolada: bolinha pequena e visível junto à fechadura, com profundidade normal. [Antes](../tmp/port-marker-20261010/before-isolated.png), [depois](../tmp/port-marker-20261010/after-isolated.png). Esta captura não substitui Main nem benchmark.

## Boeiros de Harbor — escada, tampa e tecla F, 10/10/2026

Escopo: **7 acessos exteriores existentes / 0 lugares novos / 0 interiores reformados / 0 novas certificações integrais**. As contagens de interiores aprovados permanecem inalteradas.

- [x] Entrada chega ao ponto autorado da escada, faz a pega por 0,35 s sem baixar e só depois inicia a descida. Aproximação usa movimento varrido; uma barreira aborta a entrada. Escada na parede do poço, seção superior retrátil e mãos alinhadas aos trilhos nativos. O disco opaco que escondia os degraus na altura da rua foi removido; a escuridão permanece no fundo. Subida usa a mesma posição autorada e respeita giro do acesso.
- [x] Colisão da tampa fechada e paredes do poço termina no piso. A seção superior da escada fica invisível e sem colisão quando recolhida. **21/21**: veículo de produção cruza as sete tampas em ambos os sentidos, sem dano/queda, em fixture de física real com piso recortado. [Runner](../tests/test_manhole_closed_cover.gd), [log](../output/manhole-closed-cover.log).
- [x] Animação e contato: **17/17**, ator e escada reais, acesso sem giro e girado 90°, aproximação/pega antes de baixar, clipes de descida/subida, alinhamento, cancelamento e restituição da física. Distância máxima horizontal palma/trilho: aproximadamente **2,13 cm** no cenário medido. [Runner](../tests/test_manhole_ladder_access.gd), [log](../output/manhole-ladder-final.log). Capturas atuais: [tampa fechada](../output/manhole-access/closed.png), [pega](../output/manhole-access/grip.png), [descida](../output/manhole-access/descent.png). Não houve captura anterior à implementação com câmera equivalente.
- [x] Main renderizada: passagem local sobre tampas do boeiro original, cais e armazém, em ambos os sentidos, sem dano ou contato lateral; entrada com F, E sem efeito, indicador usando a ação remapeável de roubar veículo, descida, subida e liberação dos controles. [Log](../output/manhole-session-final.log), [indicador F](../output/manhole-session/F-prompt.png). O gamepad acompanha a ação de roubar; conversas e demais interações continuam na ação própria.
- [x] Input e restauração da localização subterrânea: **12/12** na execução renderizada final. Indicador apresenta **F Descer**, sem duplicar a tecla; a tampa permanece legível acima da textura da rua e seu suporte físico segue no piso. A admissão inicial do save pula a caminhada exterior; restaurar a partir das coordenadas internas não inicia uma travessia pela cidade. Física, controles e saída funcionam após `restore_location`. Isto valida a admissão, não um novo ciclo completo de gravação em disco. [Log final](../output/manhole-input-delivery.log), [admissão anterior](../output/manhole-input-restore.log).
- [ ] Circulação completa junto aos outros acessos: os runners amplos encontraram meio-fio/rampa, árvore e barreira costeira nas rotas; a cisterna apresentou perda de acesso/piso na sequência integrada, sem causa isolada. O runner antigo ainda colocou Dante na rota reversa do carro e continuou após colisões. Não contar esses percursos como aprovados nem remover seus obstáculos para aprovar a tampa. [Primeiro runner](../output/manhole-car-passage-final.log), [rotas locais amplas](../output/manhole-session-access-final.log). As três rotas Main escolhidas isolam o defeito da tampa; as outras quatro tampas têm cobertura física isolada.
- [ ] Comparativo de performance antes/depois: não medido, pois havia benchmarks e alterações concorrentes. Sem baseline isolado, não aprovar FPS. [Processos](../output/manhole-validation-processes.json), [benchmarks concorrentes](../output/manhole-performance-concurrent.json). Capturas e contador de FPS não substituem amostras equivalentes de 30 s.

Validação com Godot **4.7.2 .NET**, Main com serviço nativo C# (`route_jit_prewarm native=true`), Mobile/Vulkan e RTX 4060 Laptop. `dotnet build Harbor.csproj --no-restore -v quiet`: sem erros/avisos. Tentativas integradas encontraram erros transitórios em `Driving.gd` e `ProductionWorld.gd`, alterados por outras sessões; esses arquivos foram preservados e a execução avançou após suas correções.

## Biarticulado 510 — acesso ao volante — 10/10/2026

Nenhum estabelecimento ou sala de mapa acrescentado a este lote. Perfil de cabine dianteira do biarticulado: 1 tipo, 2 instâncias na linha; 1 instância exercitada em Main. O acesso é uma interação de veículo por F, com motorista sentado e câmera externa de direção, reutilizando VehicleInterior. Não contar como migração concluída de interiores.

- [x] Roubo/entrada, direção, saída, colisão restaurada e reentrada: 20/20 em Main renderizada; física articulada e snapshot temporário: 20/20; regressão do roubo compartilhado: 66/66. Fontes: tests/test_biarticulated_theft_session.gd, tests/test_biarticulated_theft.gd e tests/test_vehicle_carjacking.gd.
- [x] Desembarque de passageiros exige piso e cápsula livre; não materializa sobre terreno sem apoio. Portão permanece aberto durante a retirada. A posição roubada é admitida pelos três corpos ao reativar a cidade.
- [ ] Oclusão da cabine completa e validação temporal noturna: não certificadas. Fotos reais de antes, sentado, dirigido e saída em evidence/biarticulated/theft-20261010/; não substituem a inspeção de todos os ângulos.
- [ ] Performance comparativa: inconclusiva por jogos/benchmarks concorrentes e variação de frame time. Métricas e limites em docs/biarticulated-transit.md.
- [ ] Garagens, demais plataformas, outras regiões e save/load completo da campanha: fora da cobertura deste lote. O teste de FleetState grava/lê um JSON temporário separado dos saves pessoais.

## Cabines do lote de carros redesenhados — 11/10/2026

Escopo: correções em **2 perfis de cabine** (ambulância e conversível), sem novos
lugares ou salas e sem alterar os totais de interiores de mapa aprovados.
O diagnóstico percorreu 59 modelos; não é certificação visual de todas as cabines.

- [x] Identificadas inferências incorretas do banco por vidros agrupados da ambulância e acabamento refletivo do conversível. Evidência anterior e correção local ficam no [relatório da frota](reviews/fleet-redesign-validation-20261011.md).
- [x] Correção local por metadados de cabine: 80 verificações com Actor real nos dois modelos; contratos dos recursos atualizados e capturas `attempt-04` em Main. O destino do motorista voltou à cabine/intervalo da porta, sem deslocamento para o baú. [Evidências e limites](reviews/fleet-redesign-validation-20261011.md). O para-brisa encobre a pose sentada do conversível nesta câmera; isto não certifica todos os contatos visuais do cockpit.
- [ ] Oclusão por todos os ângulos, passageiros/NPCs e restauração de save de todos os perfis: fora da cobertura desta revisão. Não contar como migração integral concluída.

## Acessos das casas de Santa Lua — 11/10/2026

Escopo: 4 lugares físicos / 4 interiores existentes; nenhum interior novo. Correção funcional dos 4 acessos; não altera a contagem de migrações integralmente aprovadas.

- [x] Porta física animada pelo controlador compartilhado de empurrão; retirada da exigência de interação para entrada e saída dessas casas. Recesso da fachada acomoda a folha aberta.
- [x] Saída caminhando antes da borda do piso e retorno externo apoiado nas quatro casas: `tests/test_desert_home_walkup.gd`, 27 verificações aprovadas em Main renderizado, Godot 4.7.2 .NET com roteamento C# e save temporário isolado.
- [x] Contratos físicos existentes: `tests/test_desert_village_homes.gd`, 376 verificações aprovadas. Build de Harbor.csproj sem erros.
- [x] Capturas reais de porta fechada, interior e retorno: [evidências](../evidence/desert-home-walkup-23060-10455186/homes-report.json). Inspeção visual do interior e retorno da casa 1; capturas das demais disponíveis no mesmo diretório.
- [ ] Fotos anteriores à edição, sequência visual da animação, reentrada/save-load específico do novo acesso e oclusão em todos os ângulos não cobertos nesta correção.
- [ ] Performance antes/depois pendente: outras instâncias Godot estavam abertas; contador de FPS das capturas não constitui benchmark. Quatro interiores permanecem sem certificação integral deste checklist.

## Esgotos — volume, colisão e ambiência — 12/10/2026

Escopo: **7 lugares físicos / 7 interiores distintos existentes** (`harbor_sewer`, mercado, cais, armazém, cano, cisterna e porto). Nenhum interior novo; **0 novas certificações completas, 7 em andamento, 7 restantes para aprovação integral deste lote**. A contagem global de ambientes certificados permanece inalterada.

- [x] Canal das seis variantes: recorte real da laje e dos ladrilhos, fundo rebaixado e água animada visível, preservando passarelas e rotas. Alvenaria com relevo em MultiMesh; parede posterior do original com volume maior. Sem novas fontes de luz nesta reforma.
- [x] Colisões dos colchões, baús, caixotes girados, entulho, tubulações grossas baixas, corrimão do cais e passarela baixa do porto. As transformações finais das malhas alimentam os corpos do adaptador; removidos os bloqueios retangulares duplicados. Recompensas preservam seus IDs e valores, agora ao lado dos recipientes; morador do cano reposicionado fora do colchão.
- [x] Catálogo, spawns e caminhos até recompensas: **112/112**. [Log](../output/sewer-refresh-network-complete.log). Física com Dante e morador reais, movimentos varridos contra sólidos, cobertura das malhas classificadas e reativação do áudio: **338/338**. [Log](../output/sewer-refresh-physics-complete.log), [runner](../tests/test_sewer_refresh.gd).
- [x] Sessão Main renderizada: **90/90**, sete salas mais uma reentrada no armazém, descida/subida reais, NPCs, corpo inteiro nos pontos de coleta, retorno e controles. Som não toca durante a preparação na rua e para ao sair. [Log](../output/sewer-refresh-session-final.log), [runner](../tests/test_sewer_refresh_session.gd). A execução inicial encontrou coleta do Tonho encostada no colchão; corrigida. A aproximação inicial diagonal da fixture falhava no mercado/cano; a execução final parte do lado próprio da escada, sem contornar colisões do percurso.
- [x] Profundidade separada da física: **105/105**, Dante e morador na frente, atrás e ao lado de um móvel acessível por sala, com controles positivos. [Log](../output/sewer-refresh-depth-complete.log), [resultados](../output/sewer-refresh/depth/results.json). A máscara diagnóstica desativa somente a camada CanvasLayer de escuridão na fixture; não certifica iluminação. Corrigidos os problemas da fixture: animação entre capturas, seleção de paredes/posições externas e contraste da máscara com o overlay.
- [x] Fotos reais antes/depois das sete salas: `output/sewer-refresh/before-<id>.png`, `after-<id>.png`; câmera da sessão: `gameplay-<id>.png`. Exemplos: [armazém antes](../output/sewer-refresh/before-sewer_warehouse.png), [depois](../output/sewer-refresh/after-sewer_warehouse.png), [gameplay atual](../output/sewer-refresh/gameplay-sewer_warehouse.png), [original antes](../output/sewer-refresh/before-harbor_sewer.png), [original depois](../output/sewer-refresh/after-harbor_sewer.png). Os previews são instrumentos visuais, não benchmarks.
- [x] Ambiência própria nas sete salas: correnteza fechada, goteiras irregulares e reflexões, stream estéreo determinístico de 16 s, sem clipping, no bus Ambient. Um player por sala ativa, sem dependência de sons costeiros. [Fonte](../audio/sewers/SewerAmbience.gd), [gerador](../tools/audio/build_sewer_ambience.py).
- [x] `dotnet build Harbor.csproj --no-restore`: zero erros/avisos; Godot **4.7.2 .NET**, Mobile/Vulkan, RTX 4060 Laptop. Main registra caminho nativo C# ativo, sem aprovação silenciosa por fallback GDScript.
- [ ] Audição e aprovação subjetiva da mixagem, oclusão de todos os objetos, restauração de save e interrupções de morte/resgate não certificadas neste lote. As verificações de coletas testam espaço corporal; não reexecutam aquisição de todas as armas em inventário cheio.
- [ ] Performance comparável e estabilidade temporal da iluminação: pendentes. Baseline integrado do armazém: **30,008 s**, **110,57 FPS**, p50 **8,388 ms**, p95 **15,662 ms**, p99 **24,622 ms**, máximo **32,739 ms**, zero frames >33,3 ms. [Amostras](../output/sewer-refresh/before-warehouse.json). Outra sessão alterou `SewerDarkness.gd` e a iluminação do `SewerModel.gd` durante o lote; essas edições foram preservadas. Houve também benchmarks/testes concorrentes entre as validações. Não atribuir uma comparação ao custo isolado desta reforma nem aprovar FPS global.
- [x] Janela atual do armazém, após encerrar benchmarks concorrentes: **30,001 s / 4.320 frames**, **143,99 FPS**, p50 **6,957 ms**, p95 **8,716 ms**, p99 **9,018 ms**, máximo **21,681 ms**, zero frames >33,3 ms. [Amostras](../output/sewer-refresh/after-warehouse.json). Mesmos 1920×1080, Mobile/Vulkan, VSync 1 e limite 144 FPS; fontes monitoradas estáveis durante a medição, sem outro gameplay/benchmark no inventário inicial/final (editor e worker de preview headless presentes). A população externa mudou de 3 para 4, e a iluminação entre versões também mudou por outra sessão: o comparativo causal continua inconclusivo. Esta janela cumpre o alvo provisório de 60 FPS no armazém ocupado/parado; não certifica os outros seis esgotos, combate ou primeira visita.

### Cabines dos veículos — forro sobre o vidro traseiro (19/10/2026)

Correção local de geometria, sem acrescentar lugares físicos ou interiores distintos ao inventário. Três modelos cobertos pelo teste específico (Monaliza, Union Sedan e Metro Hatch), mais Sport Coupe como controle com limite autorado. Nenhuma cabine promovida a concluída por este lote.

- [x] Forro plano e acabamento traseiro terminam antes da borda superior do vidro traseiro; altura da cabine, câmera, assento, luzes, interações e colisões preservados.
- [x] Regressão demonstrada nos três modelos antes da correção; depois, 14 verificações aprovadas em `tests/test_vehicle_roof_liner.gd`. Log: `output/roof-liner-regression-after.log` (a execução registrou também erros transitórios de dependências em edição concorrente, fora desta correção).
- [x] Regressão de motorista sentado: 1.741 verificações, 47 veículos, zero falhas, Godot 4.7.2 .NET; `output/roof-liner-seated-driver.log`.
- [x] Fotos reais anteriores: `evidence/seated-driver/roof-baseline-monaliza_game.png`, `roof-baseline-union_sedan_game.png`, `roof-baseline-metro_hatch_game.png`.
- [ ] Revisão visual posterior, racha completo, entrada/saída em Main e comparação de frame time renderizado: pendentes. A tentativa integrada e a captura posterior pararam durante a inicialização; processos próprios encerrados, sem amostras de performance. Havia outras sessões renderizadas simultâneas; alterações concorrentes em DesertGroundCover apresentaram erros de compilação e foram preservadas. Capturas isoladas não certificam FPS nem o fluxo completo.

### Digo — tuning e acesso dirigido (19/10/2026)

Revisão de **1 lugar físico / 1 interior existente**, sem acrescentar lugares às contagens. Direção visual da opção 1 com a navegação hierárquica pedida depois pelo usuário: Visuais → Teto → opções → Voltar. Prévia no veículo real, comparação, aplicação conjunta e retorno ao volante. Nenhum ambiente adicional certificado por este lote.

- [x] Entrada dirigida em Main mantém carro, ocupante e identidade; desbloqueio do Digo e procura policial continuam bloqueando a admissão. Baia verificada com o volume inteiro do veículo e apoio físico. Save isolado aceita peças e recibos sob a identidade original; corrupção de identidade/ocupação/local é rejeitada.
- [x] Catálogo com aerofólios, seis cores adicionais, lanternas, modelos e tamanhos de aros; teto solar com recorte de malha/vidro em modelos compatíveis. Prévia não compra nem altera o conjunto mecânico. Compra conjunta validada antes de qualquer débito, com reversão integral se um recibo falhar.
- [x] Portão exterior real fechado impede acesso à casca vazia quando a admissão é recusada. Somente a transição autorizada sob token/input lock abre o portão. **38 verificações físicas aprovadas**: quatro cascos (Infernus, Monaliza, Faísca e Supra), fechado/velocidade alta, abertura autorizada, passagem livre, colunas como controles negativos, exclusão da batch estática e fechamento após uso. Log: `artifacts/tuning-design-20261019/exterior-gate-aperture.log`.
- [x] Serviço tem fechamento físico temporário no vão e restaura as paredes autoradas para a câmera baixa. **11 verificações** de admissão da baia/portão: desalinhamento e passagem ocupada recusados; collider, recorte, câmera e passagem restaurados ao fechar. Enquadramento verifica visibilidade física e projeção do volume em cinco ângulos. Capturas renderizadas: `qa-main-final/`, inclusive frontal e extremos da órbita; relatório visual em `design-qa.md`.
- [x] Catálogo final: **60 peças / 18 slots / 10 cores**, dois aerofólios, três lentes, três desenhos adicionais de roda e três proporções de aro. Teto solar com dois vidros em **13 modelos compatíveis**; Infernus, Monaliza e outros modelos com forro não recortado mantêm essa opção indisponível. **234 verificações** em `test_tuning_lens-preview.log`: teto real/recorte, entrar/sair/reentrar, amassados/reparo/remoção, isolamento entre instâncias e retorno do freio vermelho após inspeção da lente. Aparência: 364 verificações em `test_tuning_appearance-release-check.log`.
- [x] Novo menu e cancelamento, restauração de foco, aplicação recusada e containers órfãos: `hierarchy-focus-draft.log`, zero falhas/órfãos. Som autoritativo pago/grátis/recusado: dez verificações em `test_tuning_confirmation_audio.log`. Compra conjunta, recibos, rollback, reinstalação gratuita e compatibilidade no save: `loadout-final-validation.log`, zero falhas.
- [x] Regressões das garagens: recompensas **47 checks**, transferências **11**, restauração de motorista **34**, incluindo armas guardadas e ataque bloqueado no Maciota. Sessão real do Maciota também confirmou compra via GUI, save frio, peças e ausência de cobrança repetida (`maciota-ui.log`). Não houve alteração de dano/morte dos dois personagens protegidos.
- [x] Evidência temporal renderizada anterior ao último ajuste de enquadramento: **894 quadros / 30,023 s**, cada quadro apresentado capturado, limite temporário 30 FPS só nessa captura. Dez segundos frente fixa, dez traseira fixa e dez órbita. Após dois quadros de troca de câmera, os recortes da cena nas duas janelas fixas foram idênticos (297 e 295 quadros); não houve oscilação de lente/luz nessas janelas. A órbita revelou corte pelo rodapé, corrigido depois por fit de projeção e novas fotos dos extremos. Evidências: `camera-final-v3/results.json`, `temporal-analysis.json` e `temporal-contact-sheet.jpg`. Não certifica condução noturna/chuvosa, freio em movimento ou toda a iluminação do jogo.
- [ ] **Performance comparável isolada continua pendente.** A/B/A anterior usou UI/showroom preservados sobre o runtime/ativos atuais, não um build completo anterior. Em 1280×720, Mobile/Vulkan, RTX 4060 Laptop, VSync1/limite144, 30 s por caso: baseline p50/p95/p99 **6,945/8,090/8,291 ms**, live com peças **6,947/8,170/8,549 ms**. Janela posterior com câmera/portão de serviço: **4.319 quadros / 30,005 s / 143,94 FPS**, p50/p95/p99 **6,947/8,307/8,700 ms**, máximo **20,850 ms**, zero quadros >33,3/66,7 ms. Cumpre o alvo provisório de 60 FPS nessa janela parada, mas capturas renderizadas externas constam nos inventários de processos; a comparação causal e a versão final com menu hierárquico/portão exterior não estão certificadas. Não usar os screenshots ou headless como aprovação de FPS.
- [x] Integração final renderizada: **70 verificações / zero falhas**, Godot 4.7.2 .NET, C# nativo ativo, Vulkan Mobile, 1280×720. Entrada/saída por pedal, portão fechado nos bloqueios e após uso, Teto/Voltar via botão e `ui_accept` reais, foco devolvido a Teto, três níveis de ESC, draft/carteira preservados, compra Oceano pela UI com débito único de R$1.200, som SFX tocando com stream real, pose sentada na entrada/saída, cold restore sem duplicar/cobrar novamente e controles/câmera restaurados. Log: `artifacts/tuning-design-20261019/hierarchical-main-final.log`; fotos `hierarchical-main/{exterior-closed,menu-visuais,teto-opcoes,voltar-visuais,exterior-exit}.png`. A fixture usa armazenamento exclusivo; saves pessoais preservados. A tentativa anterior diagnosticou uma fixture Infernus tentando abrir Teto incompatível e perda real da pose em `Actor.teleport`; a fixture usa agora Coyote, e a transferência reassenta o motorista sem esconder o avatar.
- [x] Teardown renderizado final sem os erros de material nulo/`!is_inside_world` das rodadas diagnósticas. `SessionSystemProfile` preserva o último inventário de luzes no encerramento, evitando consultar luzes que já saíram de World3D. Permanece no cold boot o erro externo de edição `path/mountain_zoo_walk`; arquivo concorrente preservado. O flag `startup_streaming_settled=false` também foi registrado: fila residual continua ativa, sem tratá-la como vazia. Nenhum processo de teste deste lote ficou aberto.
- [ ] Fotos/globais de todos os móveis/NPCs e circulação pedestre completa não foram aprovadas por esta revisão veicular. Não promover o interior inteiro a certificado nem somar aprovações ao inventário geral.

### Ammu-Nation de Harbor e escadas dos rooftops — 19/10/2026

Escopo: **3 lugares físicos / 3 interiores existentes / 0 novos / 0 aprovações integrais / 3 em andamento / 3 restantes para certificação integral deste lote**. Reforma visual e NPC apenas na Ammu-Nation de Harbor; nas casas de Takeshi e do zelador, somente acesso ao rooftop. Não somar novamente ao inventário global. Trabalho distribuído entre três agentes, com integração e revisão na sessão principal.

- [x] Loja com materiais de madeira, reboco, metal e feltro, produtos em escala natural, circulação central livre e apenas o nome próprio no letreiro. Vance usa corpo humano importado e uniforme tático oliva; altura 1,760 m contra 1,751 m de Dante. A loja da montanha preserva a apresentação anterior.
- [x] Escadas autoradas junto à parede direita nos três locais, com orientação e percurso próprios. O acesso autorado bloqueado não é substituído por uma escada central. Removido bloqueio invisível atrás do balcão; armários reais e batentes conservam colisão.
- [x] Godot 4.7.2 .NET / Vulkan Mobile / RTX 4060 Laptop, Harbor.csproj compilado sem erros ou avisos. Física e oclusão separadas: **298 checks aprovados** com jogador/NPC, inventário de sólidos, movimento varrido, corredores, apoio e controles positivos de visibilidade. Vance: **17 checks aprovados**. Regressão das duas lojas de armas e banco: **39 checks aprovados**. Dono/cache/transform/rota da escada: **20 checks aprovados**.
- [x] Percurso normal na Main: **106 verificações sem falha** até fechar os três donos, incluindo caminhar até o atendimento, abrir/fechar catálogo, collider próprio da escada, subir/descer, retornar e restaurar save frio de rooftop. Saves pessoais preservados, armazenamento de fixture exclusivo. Não equivale à travessia de todas as portas por empurrão.
- [x] Fotos reais antes/depois dos três lugares inspecionadas nesta sessão. [Relatório, fotos e logs](../artifacts/ammunation-refresh-20261019/resultado.md).
- [x] Três interrupções letais na casa de Takeshi: subida, descida e queda interrompidas por dano real 100 → 0, resgate, limpeza da sala/flag, apoio e controles aprovados. Logs preservam também as expectativas incorretas das fixtures anteriores: morte na loja protegida e sobrevivência à queda de 10,866 m do rooftop alto. A seleção do runner distingue agora dono vulnerável e queda não letal, sem mudar dano ou asserts; fluxos comprovados separadamente, composição final sem nova execução integral. [Detalhes e limites](../artifacts/ammunation-refresh-20261019/resultado.md).
- [ ] Performance renderizada comparável: pendente, sem aprovação de FPS. A tentativa anterior parou no gate de população (14/40) antes da entrada na loja; havia execuções externas concorrentes. Capturas e headless não substituem benchmark. Nenhuma luz ou SubViewport por personagem foi acrescentado.
- [ ] Certificação integral, oclusão de todos os móveis/ângulos e todas as portas exteriores: fora da cobertura concluída deste lote. Não houve introdução de recompensa nova ou alteração da economia da loja.

### Digo — música e reforma de objetos 3D — 19/10/2026

Escopo adicional: **1 lugar físico / 1 interior existente / 0 novos / 0 certificações integrais adicionadas**. Não somar Digo novamente ao inventário global. [Relatório, fotos e limites](../artifacts/digo-workshop-refresh-20261019/resultado.md).

- [x] Móveis detalhados em 3D, materiais locais e duas luminárias existentes; doze volumes físicos mantidos, circulação central preservada. Música original instrumental no bus Music, fade e retomada do rádio sem perder estação/posição.
- [x] Física separada da oclusão: 47 checks móveis/portão e 169 checks renderizados de profundidade. Jogador/NPC, sweeps longos, apoio, frente/lado/atrás de bancada/mesa e frente/lado da estante. Fresta central atrás da estante é estreita demais para uma cápsula; não aprovada como rota.
- [x] Main .NET com save isolado: 85 checks funcionais, incluindo portão interior, entrada/saída dirigindo, pose sentada, compra/SFX, save frio e música. Execução headless prova lógica/física; capturas reais da Main estão no relatório.
- [x] Correção de enquadramento: 19 checks de câmera/serviço, 720 passos de giro contínuo, carro inteiro visível, arco frontal completo, reversão e rollback de candidatos inválidos.
- [ ] Comparação final isolada de performance: pendente. Outro benchmark GPU concorrente interrompeu a medição, e o renderer global mudou durante o trabalho. Não aprovar FPS com capturas ou testes headless. Os casos comuns/noturnos do baseline antigo são inválidos por queda/resgate e não contam.
- [ ] Certificação integral de todos os móveis, portas, trajetos e climas: não realizada. Música foi verificada tecnicamente; mixagem subjetiva não certificada por audição humana nesta execução.

- [x] Evidência temporal final da oficina, Main Forward+ em 1280×720: 1.799 frames completos, aproximadamente 30 s de dia e 30 s de noite, frente/traseira fixas e giro contínuo. Sem flicker/popping involuntário observado; órbita cruza o centro sem salto/congelamento. [Relatório final](../artifacts/digo-workshop-refresh-20261019/verified-main/temporal-light-review.json). Limite de captura e JPEG não contam como medição de FPS.

### Motel Oásis — posição da carta 08 — 21/10/2026

Escopo: **1 lugar físico / 1 interior existente / 0 novos / 0 certificações integrais adicionadas**. Apenas o ponto da carta saiu de dentro da cama para o piso livre ao pé dela; não contar o motel novamente no inventário. [Relatório e fotos antes/depois](cartas-vicente-posicionamento-20261021.md).

- [x] Geometria renderizada inspecionada e cápsula livre no destino e no trajeto local desde o vão da porta, usando os sólidos reais do ambiente.
- [ ] Caminhada, coleta, entrada/saída e corte de teto na sessão normal: usuário fará o teste.
- [ ] Oclusão com jogador/NPC e câmera final, certificação integral do interior e performance: não validadas nesta alteração de coordenadas. Nenhum móvel, luz, colisão ou processamento foi acrescentado.


### Deserto compacto — realocação de acessos — 21/10/2026

Escopo: realocação dos estabelecimentos existentes junto da redução do território. **0 lugares novos / 0 interiores novos / 0 certificações integrais adicionadas**; a contagem global de lugares físicos e interiores distintos permanece inalterada. Banco, Digo, Santa Lua, acessos subterrâneos, mineradora e cânion preservam dimensões, móveis, câmeras e identidades; as definições de acesso e retorno acompanham os novos exteriores.

- [x] Realocação rígida dos acessos, sem reduzir a escala humana ou os sólidos dos ambientes.
- [ ] Fotografias reais, entrada/saída na sessão, colisão de acesso/spawn, oclusão de jogador/NPC e comparação renderizada: acompanhar a evidência em `artifacts/desert-compact-20261021/`; nenhuma aprovação integral é inferida da redução do mapa.

## Oficina do Maciota e casas compráveis — detalhes de uso — 22/10/2026

Escopo: **4 lugares físicos / 4 interiores distintos existentes / 0 novos / 0 aprovações integrais / 4 em andamento / 4 restantes para aprovação**. Oficina (incluindo a sala do Maciota), Westgate Garden, Quayside e Canal North. Não somar novamente ao inventário global.

- [x] Oficina: óleo e marcas de pneus no piso, ferramentas/pano no carrinho e rádio na bancada. Sala: telefone, caderno, caneta, motivos no tapete, acabamento de madeira e poltronas. Bengala: haste laqueada, anéis dourados e ponteira. Sem novas fontes de luz.
- [x] Mecânico com corpo varrido, caminhada entre dois pontos livres e pausas com ferramenta/IK das mãos. Ponto de conversa acompanha o morador; processamento cessa com a sala inativa. Sem métodos de dano/morte, preservando Maciota e mecânico invulneráveis.
- [x] Casas: tecidos e bordas arredondadas, almofadas, acabamentos de madeira, utensílios, frutas, costuras e quadros sem texto. Detalhes ficam em móveis existentes ou na parede, preservando planta e áreas de aproximação.
- [x] Árvores de calçada nos lotes de renderização próximos às casas: malha compartilhada de tronco ramificado e copa irregular texturizada. Mantidos tipos/IDs das colocações, transformações editadas, sombras e colisão dos troncos. A escolha usa os três endereços autorados; não certifica outras espécies ou regiões. Lotes que contêm árvores a até 23 m dos endereços usam a malha nova; outras árvores do mesmo lote também a compartilham.
- [x] `dotnet build Harbor.csproj --no-restore`: 0 erros/avisos; Godot 4.7.2 .NET. Capturas: Forward+, RTX 4060 Laptop, 1600x1000.
- [x] Física da oficina: `test_maciota_world.gd`, zero falhas, incluindo corredores, escada e moradores. [Log final](../artifacts/interior-life-20261022/test_maciota_world-final.log).
- [x] Rotina do mecânico: 45 verificações aprovadas, ciclo de trabalho, chão livre, bloqueio por cápsula de jogador e suspensão na sala vazia. [Log](../artifacts/interior-life-20261022/mechanic.log).
- [x] Casas: 58 verificações aprovadas com Actor real nas aproximações, varreduras dos móveis principais e contratos de árvore. Cobertura dirigida, não inventário completo de todas as bordas. [Log final](../artifacts/interior-life-20261022/test_residential_finish-final.log).
- [x] Sessão real renderizada: 31 verificações aprovadas, incluindo entrada/saída da garagem, arma guardada, bloqueio de saque/ataque, inventário preservado e liberação ao sair. [Log](../artifacts/interior-life-20261022/session-rules.log). Houve diagnósticos de edição de mundo sem origem e 11 objetos retidos ao encerrar; não é certificação geral de estabilidade.
- [x] Recompensas: 47 verificações aprovadas. Transferência física de veículos: 11 verificações aprovadas, com erros de material do renderer dummy e aviso de 20 objetos retidos ao encerrar; resultado restrito aos asserts funcionais. [Recompensas](../artifacts/interior-life-20261022/garage-rewards.log), [transferências](../artifacts/interior-life-20261022/garage-transfer.log).
- [x] Fotografias reais comparáveis em fixture isolada: [oficina antes](../artifacts/interior-life-20261022/before-maciota.png), [oficina depois](../artifacts/interior-life-20261022/reviewed-maciota.png), [Westgate antes](../artifacts/interior-life-20261022/before-home0.png), [Westgate depois](../artifacts/interior-life-20261022/reviewed-home0.png). Outras duas casas: `before-home1/2.png` e `reviewed-home1/2.png` na mesma pasta. Árvores: `trees-final-tree-previous.png` e `trees-final-tree-new.png`, comparação de malhas produtivas na fixture, não fotografia do jardim integrado.
- [ ] Oclusão completa com Dante/NPC em movimento nas três casas, entrada/saída/reentrada por suas portas e save/load: pendentes. Fotos sem atores não aprovam esses critérios.
- [ ] Comparação de frame time antes/depois na Main e evidência temporal das sombras das árvores: pendentes. Baseline interrompido após erros repetidos do minimapa durante o carregamento; várias instâncias externas do Godot presentes e preservadas. Capturas isoladas não aprovam desempenho. Alvo provisório 60 FPS/16,67 ms; aumento acima de 5% em p95/p99 requer confirmação equivalente. Nenhuma aprovação de performance nesta entrega.

## Correções da garagem — 22/10/2026

Escopo: **1 lugar físico existente / 1 interior existente alterado / 0 novos / 0 certificações integrais**. Acesso com batentes e soleira contrastantes, rotina do mecânico até a bancada, ambiente local sem sons de oficina e saída com preparo/sincronização da colisão exterior antes de admitir Dante. Invulnerabilidade e restrições de armas preservadas.

- [x] Contrato dirigido headless `tests/test_mechanic_work_routine.gd`: quatro pontos visitados, 4,872 m percorridos, piso, bloqueio por corpo do jogador, interação e pausa da sala; zero falhas. Não certifica aparência.
- [ ] Visual, oclusão, circulação e entrada/saída jogando: validação reservada ao usuário, conforme pedido de alterar somente código.
- [ ] Performance renderizada antes/depois: não medida nesta revisão; sem aprovação de FPS.

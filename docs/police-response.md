# Resposta policial — 28/09/2026

> **21/10/2026 — perseguição de carro estilo GTA.** Rota aberta à frente do alvo, contato (PIT,
> flanco, interceptação), bloqueador de cruzamento, reciclagem da viatura deixada para trás,
> nascimento à frente, área de busca com cones de visão no minimapa, bloqueio com pregos a partir
> de 3 estrelas no caminho previsto, prisão dentro do carro parado com 1–2 estrelas e rádio da
> central no HUD. Regras e números em [gameplay/dispatch/README.md](../gameplay/dispatch/README.md),
> seção "Perseguição de carro estilo GTA". `GETECO_GTA_CHASE=0` desliga tudo isso.

## Balanceamento e fuga — 02/10/2026

Revisão solicitada para tornar a escalada gradual e a fuga legível. A implementação anterior descrita abaixo é histórica; estas regras substituem sua pontuação, fuga e chegada de especialistas.

- Os limiares 12/30/60/140/260/420 e o máximo de 600 pontos continuam compatíveis com saves. `PoliceEscalation.gd` limita a contribuição de cada categoria, sem reduzir uma procura já maior.
- Disparos identificados contam no máximo 4 pontos por episódio de 3 segundos (1 com supressor), inclusive denúncias de rajadas agrupadas. Sozinhos param em 59 pontos/duas estrelas. Continuar atirando mantém a ocorrência e a autorização de força, mesmo quando não acrescenta pontos.
- Alarmes e ocorrências genéricas param em 139 pontos/três estrelas; roubo de viatura do pátio para em duas. Agressões, atropelamentos não fatais e explosões sem morte podem chegar a quatro, nunca cinco/seis por repetição.
- Morte civil confirmada conta 30 pontos e é distinta de ferimento. Cadáver não gera nova morte ao receber dano. Autoria do jogador, testemunhas sobreviventes, visão e prazo de denúncia continuam obrigatórios. Mortes policiais conservam piso de três estrelas e registro único.
- Cinco estrelas exigem ao menos 180 pontos de consequências fatais (normalmente seis mortes), 60 segundos de ocorrência e pontuação total suficiente; seis exigem 360 (normalmente doze mortes), 120 segundos e 420 pontos totais. Essas condições são mínimas, não garantem promoção. Só novo crime fatal confirmado permite cruzar esses dois patamares: esperar, reencontrar o jogador ou atirar para o alto não promove. Pontos barrados não ficam aguardando liberação automática.
- A fuga completa encerra esse acúmulo de gravidade. Investigação local permanece por cinco minutos, sem identificação automática. Save/load preserva gravidade, tempo e intervalo dos disparos; saves antigos sem esses campos são aceitos.
- Primeira estrela cai após 18/23/28/33/38/45 segundos de busca em níveis 1–6; depois, oito segundos por estrela. Contato real reinicia a fuga. Novos crimes confirmados também interrompem seu progresso. Sem interrupções, seis estrelas levam aproximadamente 85 segundos para desaparecer, além do primeiro segundo de tolerância de contato.
- HUD mostra PERSEGUIÇÃO com estrelas estáveis, BUSCA com estrelas pulsando e barra de progresso para a próxima queda. Nos últimos 25%, a última estrela pulsa mais rápido. Ao escapar, comunica “Você despistou a polícia”; o estado residual diz INVESTIGAÇÃO LOCAL. Pausa não avança a animação.
- Helicóptero começa em três estrelas como reconhecimento, usa linha de visão física e última posição conhecida, não reserva agentes nem faz rapel. Especialistas, K9, bloqueios e rapel começam em quatro. No rebaixamento, equipes já na corda terminam sua descida com segurança e a aeronave parte. Cada incursão de reconhecimento é limitada; depois da saída, respeita o intervalo existente de retorno.
- Subida de nível preserva o tempo mínimo de despacho em vez de adiantar o reforço. Limites de entidades reduzidos pela revisão de 01/10 são preservados. Tanque continua no nível seis; novos veículos militares e expansão do Exército ficam para uma etapa futura.

Validação desta revisão e lacunas: `evidence/police-balance-20261002/`. Testes de resposta máxima usam estado explícito de fixture; `register_crime(420, ...)` genérico não é mais um atalho para seis estrelas. Teste funcional e captura dirigida não certificam performance nem perseguição completa jogada.

Resultados: escalada 30 verificações, casos/denúncias/persistência 50, resposta terrestre 35, aéreo/K9 40, HUD integrado 49, contrato de crimes policiais 10 e garagem 47+34+11 passaram. A captura temporal dirigida do HUD passou nas sete verificações. O teste amplo de despacho completou 7 grupos/60 verificações com uma falha de fixture (dano aplicado diretamente no ator, sem autoria/autorização do Gameplay); o grupo corrigido passou nas cinco verificações, com avisos de recursos no encerramento. O mesmo teste revelou interpolação inválida de personagens com escala não uniforme na queda: corrigida em `BodyImpactPose3D.gd` e validada em 61 amostras mais restauração. Não foi repetido o teste amplo inteiro após essas correções.

Pendências: `test_police_motor_pool.gd` falhou em posicionamento/interação antes de executar a nova pontuação e abortou ao acessar `alarm.visible`, agora um dicionário; a integração completa de lockpick do pátio não está aprovada. Comparativo de frame time não concluído: outras sessões iniciaram execuções durante as duas janelas tentadas; a primeira medição foi interrompida e a segunda não iniciada. Nenhum FPS foi aprovado. Há cópia isolada anterior em `D:/geteco/artifacts/police-balance-baseline-20261002`; seus recursos compartilhados exigem conferir estabilidade de fontes antes de retomar a comparação. O balanço ainda precisa de avaliação de sensação de jogo numa fuga completa, além das fixtures e da captura dirigida.

Reforma solicitada pelo usuário: helicóptero com quatro agentes em rapel e cordas móveis, motos policiais, K9, tanque, bloqueios/pregos, investigação após fuga, rendição nos níveis altos, perseguição em interiores e táticas por equipe. Reconhecimento de placa, roupa e rosto continua fora do escopo.

## Gravidade, informação e força

As seis faixas continuam em 12/30/60/140/260/420 pontos (máximo600). `PoliceCaseDirector` separa o delito, a testemunha que percebeu, a denúncia após2,5s, o contato e a investigação. Tiros/agressões/roubo de veículo comum passam pela percepção. Alarmes e sistemas de segurança que já confirmaram uma ocorrência continuam usando `register_crime`. Ferir/matar policial é evidência direta. Sons sem visão denunciam o local, sem identificar o jogador. Testemunha incapacitada não conclui a chamada; a posição denunciada é a observada, sem acompanhar magicamente o fugitivo. Uma denúncia anterior ainda vale se o jogador entrar na garagem. Viagem e save preservam chamadas em andamento, com contexto e tempo restante; no máximo24. O carro roubado é o objeto observado, sem bloquear a visão do próprio roubo.

Estrelas sozinhas não autorizam tiros. Violência confirmada mantém autorização de força por45s, renovada por novos eventos. Rendição suspende o ataque. `K`, remapeável em controles, inicia/cancela rendição: jogador vivo, a pé, imóvel e em local onde armas são permitidas. A arma é guardada e os agentes podem efetuar prisão em qualquer nível. Mover-se cancela a rendição. A prisão conserva o fluxo existente de custódia/respawn, sem confisco ou multa novos.

Depois do prazo original sem contato (23/28/33/38/43/120s), a procura perde uma estrela; as demais caem a cada8s sem contato. Um novo contato reinicia a busca. A fuga deixa uma investigação por300s, persistida no save, e até uma viatura investiga o local. Ouvir um crime sem identificar o suspeito também pode enviar essa viatura. Ela não volta a perseguir por mera proximidade do jogador. Limpeza explícita da procura, prisão e respawn encerram o caso.

## Unidades e limites

| Estrelas | Novos recursos |
|---|---|
|1|Patrulha comum; abordagem/prisão|
|2|Até uma moto com um policial, apoiando a primeira patrulha|
|3|Interceptores, moto, helicóptero com quatro agentes, um K9 e um bloqueio|
|4|SWAT; helicóptero, um K9 e um bloqueio|
|5|FBI/camburão; até dois K9 e dois bloqueios; reforços contínuos|
|6|Exército, até dois camburões táticos e um tanque; demais recursos mantidos|

Máximos terrestres preservados:2/3/4/5/6/8 viaturas e4/6/8/10/12/16 agentes. As quatro vagas do rapel são reservadas antes de embarcar e descontadas do orçamento a pé. Motos, tanque e equipes de viatura têm ocupantes finitos; transferência para interior ou roubo não repõe pessoas.

O helicóptero chega de fora da câmera, procura quatro colunas fisicamente livres até o chão, paira e baixa quatro agentes reais. Cordas acompanham a descida e se movem. O desembarque pausa/recolhe o agente se alguém ocupar a chegada. Após desembarcar, a aeronave sobe, faz uma curva e sai; `helicopter_cooldown_seconds=60.0` controla a próxima incursão, contada depois da partida e sujeita às quatro vagas disponíveis no orçamento do nível. A fuga cancela novos reforços, termina quem já estiver na corda e inicia a partida. Não admite rapel em telhados ou interiores. Há um helicóptero e um holofote noturno sem sombra adicional.

Fuselagem modelada por seções, cabine/portas móveis, trem tubular, turbinas, cauda, rotor principal de quatro pás e rotor de cauda articulados substituem o modelo inicial. Ambos os rotores giram durante o voo. A revisão por três ângulos corrigiu faces invertidas e a perda de triângulos não indexados ao agrupar a cauda com outras peças; evidência em `airframe/`. O rapel usa o corpo anatômico visível: mão superior na corda, mão inferior de frenagem e descensor no arnês; o cabo passa pelos contatos reais. Há fases de prender, descer com frenagem, amortecer a aterrissagem e soltar/retomar a arma. Colete, bolsos, luvas, joelheiras, capacete e tiras acompanham as articulações.

A arma dos cinco escalões agora usa o mesmo espaço do corpo visível. O rig antigo tinha orientação e comprimentos diferentes, causando fuzil atrás da cabeça e braços esticados sem contato. Repouso, mira e recarga mantêm uma única transformação da arma e os contatos das duas mãos. A recarga leva a mão de apoio ao cinto, carregador e mecanismo de rearme.

K9 tem policial responsável, corpo físico completo, navegação, visão e limites de distância. A contenção reduz temporariamente a mobilidade e não mata o jogador. Não ataca quem está rendido, dentro de veículo ou em área protegida; paredes bloqueiam mordidas. Ao perder o responsável, deixa de atacar.

Bloqueios surgem em ruas alcançáveis e fora da vista, com barreiras físicas e uma faixa transitável contendo pregos retráteis. A faixa considera o trajeto varrido das rodas, inclusive em alta velocidade. Só o carro perseguido sofre o efeito; rendição desarma os pregos. Pneus furados alteram direção/aderência/velocidade reais, ficam no save do veículo selecionado e são recuperados na reparação. Lagartas são imunes. O tanque policial mira e dispara contra o suspeito a pé ou no veículo, apenas com força autorizada e trajetória desobstruída. Jogador e IA compartilham o canhão descrito em [tanques e esmagamento](tank-control.md).

## Táticas e interiores

Comum aproxima; detetive flanqueia; SWAT alterna avanço/cobertura e procura abrigo para recarregar; FBI busca posições de cerco; Exército avança em etapas mais lentas. Todos conservam cápsula, navegação, munição e linha de visão reais.

A polícia só segue para uma sala quando observou a entrada ou recebeu denúncia daquela sala. Agentes existentes precisam chegar à porta exterior; até quatro são admitidos junto da porta interior após validar piso, cápsula e móveis. Jogador, residentes e policiais compartilham a profundidade3D nativa. Não há clonagem de equipe, visão entre espaços técnicos ou passagem por sólidos. A saída/descarregamento limpa visitantes.

A garagem do Maciota mantém proibição de armas, proteção do jogador naquele contexto e invulnerabilidade de Maciota/mecânico. Não houve migração de salas ou mudança de câmera/mobiliário neste escopo.

## Validação e evidências

Scripts dirigidos: `tests/police_response/test_cases.gd`, `test_ground_response.gd`, `test_air_k9.gd`, `test_tactics.gd`. Capturas reais: `capture_air_k9.gd`, `capture_ground_main.gd`, `capture_interior_pursuit.gd`. Todos os comandos de sessão exigem `--no-save`; capturas usam `--skip-arrival`. Resultados e imagens: `evidence/police-response-20260928/`.

Validação funcional atual: denúncias/persistência/rendição49 verificações; terrestre35; aéreo/K937; táticas28; poses101; balística107; equipamentos e recarga93; autoria de crimes10; garagem47+26+11. Logs específicos em `evidence/police-response-20260928/`. A revisão aérea final está registrada no log `test-air-k9-final.log`; a integração de limpeza na prisão/restore/viagem foi revalidada em `cases-lifecycle-final.log`. Os testes de autoria de crimes e recompensas da garagem ainda avisam sobre recursos remanescentes no encerramento da fixture; não foram contabilizados como logs inteiramente limpos.

Revisão visual nova: `officer-poses/geteco-officer-poses/` contém os cinco escalões e closes de mira, recarga e rapel; `interior/` contém entrada/saída real pela FullSession e policial à frente/atrás do expositor na Ammu-Nation, já com a arma corrigida. Foram conferidos separadamente colisão e oclusão nesse percurso; a amostra não certifica todas as plantas. `ground-main-vehicles.png` mostra moto, tanque e bloqueio no mapa. `air-k9-final/` registra os quatro agentes, contato das luvas/arnês, sequência do rotor e descida, aeronave e partida. As capturas renderizadas ainda apresentam aviso de textura/RID no encerramento, separado dos contratos funcionais.

Performance permanece pendente até comparação renderizada controlada. Outras sessões estavam executando testes do túnel/inventário na GPU e continuaram ativas na revisão final. Não foram encerradas. `measure_response.gd` usa Main,1280×720, semente fixa,8s de aquecimento e30s de amostras por cenário, com p50/p95/p99/máximo/FPS real/quadros acima33,3 e66,7ms. A cópia anterior dos scripts foi preservada para o comparativo. Critério provisório:60FPS/16,67ms nesta RTX4060Laptop; aumento maior que5% em p95/p99 exige confirmação equivalente antes de atribuir regressão. Captura bonita, testes headless e o contador de FPS de uma foto não certificam desempenho. O contador nas capturas curtas inclui carga inicial, troca de câmera/horário e gravação síncrona de PNG; não representa uma amostra estável.

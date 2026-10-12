# Direção do elenco — PT-BR / inglês

Inventário implementado em 12/10/2026: **565 combinações de locutor/texto, 90 labels e 95 identidades de casting**: 80 pessoas autoradas e 15 papéis procedurais por gênero/personalidade. Cada combinação tem PT-BR e inglês: **1.130 tomadas planejadas**. caller continua sendo Maciota ao telefone. Contagem de roteiro não certifica a geração ou aprovação artística de todos os arquivos.

O conjunto inclui 345 falas legadas, 159 combinações antes apenas em painel/balão/aviso agora vinculadas ao ator, 12 alternativas femininas para funcionários/guardas/policiais, seis frases de pânico ativadas e 43 reações curtas de dor. A seção final registra os patches e testes; o diagnóstico abaixo preserva os problemas encontrados antes da correção.

Fichas consumíveis: [voice-cast.json](../data/dialogue/voice-cast.json). Cada pessoa tem intenção, timbre, ritmo, vocabulário PT-BR/EN, exemplo bilingue, fontes e bloqueios. São direção de atuação, não certificação de áudio pronto. Nenhuma idade numérica nova virou cânone.

## Diagnóstico inicial, antes dos patches de 12/10

- O preenchimento PT usa praticamente duas vozes selecionadas por lista de nomes em tools/complete_portuguese_voices.py. Isso não distingue ofício, relação ou mudança emocional.
- O inventário une homônimos: Raul (esgoto, lenhador, piloto), Helena (banco, patrulha, esqui), Elias (cemitério, montanha), Luísa (vinhos, montanha). As fichas separam seus contextos.
- Dezoito labels da montanha repetem o mesmo par de falas no roteiro atual. A direção bilingue de linhas propõe individualização, ainda dependente de publicação.
- Nadir é masculino por DesertCharacter.LOOKS. Ferreira é masculino pelo catálogo de aparência/default do modelo de serviço. Nome isolado não decide casting.
- SewerHomelessModel herda CivilianModel, que monta wardrobe.female sem consumir is_female das definições. Os moradores precisam vínculo explícito entre pessoa e corpo; perfis carregam bloqueio de publicação.
- Ferrugem e Moradora são Actor.identity 7 e 3 sem gênero autoral explícito; o corpo procedural precisa conferência junto à voz antes de publicação.
- Guarda portuário e papéis genéricos não levam identidade do emissor ao áudio. DockWorkerModel não fixa gênero. Candidato masculino não pode ser publicado para corpo feminino.

## Atuação

Ofício, intimidade, risco e história definem a fala. Morador do esgoto não recebe voz bêbada, ignorante ou cômica por morar na rua. O apelido “O Maluco” não autoriza inventar diagnóstico ou imitar sofrimento mental. Takeshi não recebe sotaque japonês por nome; o inglês preserva pessoas brasileiras sem caricaturas raciais.

Dante economiza palavras porque procura respostas. Maciota conduz com calor e pausa. Jessica reage rápido e mantém controle na fuga. Vicente segura mágoa nas frases curtas. Polícia impõe autoridade por clareza; acolhimento não exige voz açucarada. A mesma pessoa muda de intenção sem trocar de ator.

## Elenco

| ID | Papel | Intenção | Timbre e ritmo |
|---|---|---|---|
| ana | Visitante da montanha. | Dividir descoberta útil sem fingir ser guia. | Light clear female middle voice, gentle lifted starts, friendly quick finish and natural curiosity. |
| anselmo | Zelador do cemitério; segredo da carta de Samuel. | Entregar pista sem ser ouvido. | Dry male low-mid voice, held breaths, clearly voiced whisper, hard stop on warning. Secrecy rather than supernatural dread. |
| bento | Lenhador da montanha. | Poupar visitante do frio. | Broad mellow male baritone, slow sturdy pulse, understated kindness and practical stress. |
| beto | Morador do esgoto; protege pessoas dos dois lados do canal. | Conhecer intenção do visitante e impor limites. | Compact male baritone, steady low volume, careful questions, hard final consonants. Protective belonging before territory. |
| beto_cascavel | Cria cascavéis na galeria do deserto e vende veneno. | Manter visitante atento e demonstrar ofício. | Husky male low-mid voice, deliberate quiet pace, spare breath and exact warnings. Calm expertise, no theatrical menace. |
| bia | Trabalha com Digo; negocia juntas e correias. | Resolver logística e ensinar sem subestimar cliente. | Resonant female mid-low voice, agile technical diction, brisk warmth, a brief earned smile after completed work. |
| bruno | Caminhoneiro da montanha. | Passar recado e voltar à rota. | Bright male middle voice, brisk clipped rhythm, good-humored impatience, strong location words. |
| caio | Patrulheiro da montanha. | Alertar sem alarmar e conferir entendimento. | Clean male high-mid voice, alert even pace, precise starts, small checking question lift. |
| capitao_rocha | Responsável pelo quartel 03 e saída das viaturas. | Abrir caminho para equipe e evitar acidente. | Open male resonant baritone, projected clarity, clean action beats, calm between emergencies. Authority helps the crew. |
| cecilia | Visitante da montanha. | Compartilhar abrigo como gentileza. | Rounded female middle voice, soft open onset, measured invitation, brighter ending. |
| cida | Moradora do esgoto, ligada a Raul e Beto. | Manter distância do estranho e defender cuidado mútuo. | Female low-mid voice, close dry tone, hesitant entry then firm affection. Wary and self-possessed, never helpless. |
| dante | Irmão de Vicente; procura seu rastro de Harbor ao deserto. | Conseguir resposta sem mostrar quanto ela importa. | Grounded mid-low male voice, compact phrases, attentive starts, restrained breath before personal admissions. Dry humor, delayed answers when vulnerable. |
| dente_de_ouro | Detento dos Cobras; provoca Dante sobre Vicente. | Recuperar poder pela conversa atrás das grades. | Male metallic higher baritone, quick sneer, teasing elongation, confidence briefly thinning. No villain laugh. |
| detetive_ribeiro | Investiga receptação dos Cobras no Píer Leste. | Ligar provas e testar o que Dante sabe. | Dry male middle voice, thoughtful starts, short evidence gaps, pointed questions. Lower volume than Morales, analytical focus. |
| digo | Piloto/mecânico; ensina motocross e libera preparação após correr. | Trazer Dante à prática e dividir entusiasmo por motores. | Bright male middle voice, smiling attack, quick pulses then clear technical beats. Mechanical passion rather than constant shouting. |
| dona_cida | Moradora aguardando queixa das corridas noturnas. | Ser ouvida e alertar jovem sobre porto. | Full female middle voice, precise irritated stress, patient pace fraying, then sincere softer warning. Politeness under strain. |
| dona_marlene | Moradora do Dreno do Cais; pesca junto à comporta. | Preservar silêncio e evitar queda na passarela. | Dry female alto, clearly voiced hush, watchful pauses, sharp practical warnings; knows tide and boards. |
| dona_nena | Moradora do Dreno do Porto; cozinha e riscos da carga. | Oferecer café e alertar como quem viu consequências. | Full low female voice, warm host rhythm, abrupt dry turn on danger. Experienced hospitality without grandmother caricature. |
| dona_zefa | Moradora da galeria do deserto; tapetes e Beto Cascavel. | Receber com ironia e informar sobre duna. | Textured female mid-low voice, lilting welcome, quick dry contradiction, comfortable breath. Vital hospitality, no frailty cliché. |
| dora | Visitante da montanha. | Quebrar gelo com hospitalidade. | Lower-middle female voice, dry amused edge, quick rhythm and decisive finish. |
| dr_miguel | Médico no hospital de Harbor. | Tranquilizar e encaminhar atendimento. | Smooth male middle voice, balanced pace, grounded reassurance, softened landing without patronizing. Attentive, not formulaic. |
| elias_cemetery | Contador de histórias do cemitério. | Mostrar pessoa por trás de cada nome. | Mellow male mid-low voice, soft grain, storytelling pauses, tenderness on remembered acts. Silence after loss, no ominous narration. |
| elias_mountain | Lenhador da montanha; observou comboio dos Lobos. | Informar caminho e valorizar lenha seca. | Male rough middle voice, short forward outdoor phrases, steady pace, concrete weather and work emphasis. |
| enfermeira_clara | Enfermeira no hospital de Harbor. | Acolher e orientar com eficiência. | Firm warm female middle voice, brisk pulse, practical reassuring emphasis. More active and rhythmic than Miguel. |
| ermitao_jaco | Morador do poço Santa Lua; velas e promessas. | Fazer respeitar silêncio e perceber sinais. | Soft low male voice, clearly voiced hush, measured spacing, weight on concrete symbols. Intimate reflection, no supernatural effect. |
| felipe | Caminhoneiro da montanha. | Dividir experiência sem alongar parada. | Low-middle male voice, rough consonants, relaxed forward rhythm, clear final directions. |
| ferrugem | Contato da oficina; conhece ordem de Vicente e encaminha a Neco e à corrida. | Medir competência antes de entregar confiança. | Dry grainy male tenor-baritone, brisk technical clauses, cautious pause before a name, reluctant warmth after completed work. |
| funcionario | Atendimento da Vértice; informa horário e circulação. | Tirar dúvida e voltar ao trabalho. | Male casting candidate, light middle voice, warm onset, efficient cadence. Friendly person with work to finish. |
| guarda | Controle de acesso no porto e Vértice; vários emissores. | Conferir autorização e manter fluxo de caminhões. | Male casting candidate, compact mid-low projection, alert pace, short firm instructions. Routine access control distinct from police. |
| helena_bank | Bancária do North Pier; ajudou nas contas da oficina. | Entregar comprovante e alertar sem expor clientes. | Composed female low-mid voice, precise consonants, quiet pace, short confidential volume drop. Discreet warmth. |
| helena_mountain | Patrulheira da montanha; distinta da bancária. | Levar Dante ao abrigo antes da nevasca. | Female firm middle voice, projected onset, clipped outdoor advice, attentive final pause. |
| helena_ski | Hóspede do chalé de esqui, distinta da patrulheira e bancária. | Dividir prazer da descida e descanso. | Female light warm higher-middle voice, relaxed smiling breath, flowing phrases, delighted rise on the view. |
| hospede_sete | Escondido no porão do motel há três semanas. | Evitar exposição e denúncia pelo cofre. | Narrow male middle voice, compressed low speech, uneven short breaths, clear urgent whisper. Fear held inward, no comic paranoia. |
| ines | Comerciante da montanha. | Receber Dante e observar movimento. | Full female middle voice, crisp warm starts, tiny expressive pauses, attentive questions. |
| irene | Confere manifesto e transferências no banco Cobre. | Encontrar alteração sem especular além da prova. | Low female register, fine dry texture, steady deliberate pace, tiny pause before discrepancy. Discreet and observant. |
| iris | Patrulheira/recepção exterior do Cume Branco. | Receber e orientar acesso e teleférico. | Clear ringing female middle voice, poised welcome, readable lists, naturally softer finish. |
| jessica | Pilota um Jetta, corre, propõe o assalto e dirige a fuga. | Testar Dante como parceiro e abrir espaço para afeto sem perder autonomia. | Clear female mid register with a dry edge, quick reactions, precise teasing pauses. Steady breath under pressure, warmth earned in private. |
| joana | Representante da cooperativa de Santa Lua pelo rádio. | Recuperar água dos canteiros e reconhecer serviço. | Clear female middle voice, focused radio diction, brisk task grouping, audible relief and genuine smile when pressure rises. |
| lia | Comerciante da montanha. | Orientar rápido acompanhando movimento. | Clear female upper-middle voice, lively pace, inviting rise then firm directions. |
| livia | Informa largadas e contatos no encontro do deserto. | Impor regras e colocar Dante no ritmo da pista. | Bright female middle voice, forward projection, fast clear lists, firm final beat; organizer addressing one person. |
| lucas | Hóspede do esqui; comemora Slalom do Pinhal. | Compartilhar empolgação e horário do teleférico. | Bright male high-middle voice, quick excited onset, satisfied breath, then careful practical detail. |
| luisa_mountain | Visitante da montanha, distinta da profissional dos vinhos. | Compartilhar abrigo e observações do trajeto. | Female airy middle voice, thoughtful start, gentle flow and clear concerned finish. |
| luisa_wine | Profissional do financeiro da loja de vinhos com Nelson. | Organizar compra e acolher com humor sobre Nelson. | Warm female low-mid voice, neat rhythmic phrasing, gentle amused rise then efficient clarity. Familiar affection without patronizing. |
| maciota | Dono da oficina e contato que liga para Dante; conhece Vicente. | Ajudar Dante sem facilitar escolhas nem revelar tudo. | Warm resonant male baritone, unhurried starts, firm consonants on instructions, a small private smile on trust. Grounded working-man assurance. |
| matias | Atendente do Cume Branco; aluguel e teleférico. | Preparar visitante para esquiar. | Warm male middle voice, grouped instructions, friendly greeting rise and precise hours. |
| mecanico | Trabalha com Maciota; entrega peça junto à bancada. | Orientar visitante sem largar trabalho. | Male middle voice, light nasal edge, short energetic phrases, friendly distracted focus; higher and quicker than Maciota. |
| mila | Visitante da montanha. | Compartilhar preocupação com mudança do tempo. | Light female middle voice with airy edges, hesitant start then clear certain warning. |
| moradora | Mãe ameaçada pela cobrança dos Cobras; indica registros após resgate. | Proteger filho e perceber que Dante ficou. | Female middle register, shallow urgent inhale, compressed requests, small release of breath after rescue. Intelligible fear and stunned relief. |
| nadir | Piloto rival de arrancada; exige trocas precisas. | Medir Dante pela troca e fechar conversa. | Clean male low tenor, taut rhythm, sharp consonants, decisive cutoff. Quiet precision, fewer words than rivals. |
| neco | Recebe veículo para reparo e conhece ordem 017. | Garantir que ninguém confunda conserto com sucata. | Weathered male baritone, firm forward projection, deliberate lists, softer final aside. Mild natural grain, practical focus. |
| nelson | Anfitrião da loja de vinhos, 60+; histórias da Grécia. | Transformar compra em conversa e despertar curiosidade. | Older warm male rounded baritone, unhurried storytelling, lively interest, a lift on fascinating detail. Invite a reply rather than lecture. |
| noe | Lenhador da montanha. | Avisar e voltar ao trabalho. | Soft grainy male middle voice, laconic phrases, slow final landing, gentle practical concern. |
| nora | Patrulheira que alerta sobre rastros na mata. | Impedir risco sem estimular curiosidade. | Low clear female voice, quiet firm starts, deliberate caution, almost no filler. |
| o_maluco | Morador identificado pelo apelido; fala dos sons do cano. | Fazer Dante escutar e indicar objetos concretos. | Soft thin male middle voice, listening gaps, sudden precise focus on noise, low clear warning. Pauses from listening, no comic mania. |
| operador | Operação da Vértice e acesso de caminhões. | Proteger circulação e terminar orientação. | Male casting candidate, resonant middle voice, deliberate consonants over imagined machinery, two clear beats per instruction. |
| operario | Contato do serviço de limpeza da cava Serra Bruta. | Ensinar entrega das pedras e combinar pagamento. | Male casting candidate, rough middle voice, measured hands-on instruction, separate stress on each completion condition. |
| otto | Lenhador da montanha. | Informar sem longa conversa. | Dry male bass-baritone, square steady beats, little melody, unexpectedly gentle ending. No inferred German accent. |
| padre_nicanor | Morador da Cisterna Velha; chama abrigo de paróquia. | Acolher e dividir receios sem perder fé. | Rounded male middle voice, gentle cadence, self-aware humor, softer endings on fear. Conversation rather than sermon. |
| passenger | Passageiro mais velho da balsa; conversa com Dante. | Oferecer companhia sem invadir história alheia. | Older male mellow mid-low voice, airy edges without frailty, patient questions, comfortable silences. Ease back when touching a wound. |
| pedro | Motorista de ônibus da montanha. | Orientar quem não conhece caminho. | Smooth male low-middle voice, patient reassurance, clear locations and times. |
| policia | Aviso de rendição em FullSession; emissor não identificado. | Parar ameaça e tornar rendição compreensível. | Male dispatch candidate, firm middle voice, urgent two-beat command, clear diction, controlled force, no pleasure in violence. |
| policial_ferreira | Vigia custódia temporária e Dente de Ouro. | Manter distância das grades e encerrar visita inútil. | Male mid-low voice, flat firm edge, clipped clauses, dry impatience held below anger. Watchful routine. |
| rauhz | Piloto de Focus MK1 2002; rival após Nadir. | Mostrar preparo e provocar resposta à altura. | Male middle voice with bright hard edges, forward lean, quick onset then measured technical finish. A short competitive grin. |
| raul_desert | Piloto do deserto; recebe peças e investiga carga da cooperativa. | Provar valor da experiência e acertar uma dívida. | Broad male low-mid chest voice, relaxed gravel, patient setup, wry landing. Understated pride in old machinery. |
| raul_mountain | Lenhador da montanha, distinto do piloto e morador do esgoto. | Orientar sobre frio e circulação do porto. | Male rounded higher baritone, easy pulse, practical outdoor projection, friendly plain finish. |
| raul_sewer | Morador do esgoto original; protege Cida. | Afastar ameaça do abrigo e preservar Cida. | Male dry middle voice, low volume, guarded starts and sharp firm endings. Personal protective alertness, unlike the relaxed desert racer. |
| rui | Lenhador da montanha. | Aconselhar sem inferiorizar visitante. | Nasal-textured male middle voice, loose easy timing, wry final lift, restrained camaraderie. |
| rute | Patrulheira da montanha. | Fazer Dante agir antes da nevasca. | Centered female middle voice, concise projection, quick instruction then calm pause. |
| sargento_morales | Balcão do 1º Distrito da Harbor Patrol. | Controlar balcão e recolher informação. | Grounded male chest voice, measured authority, crisp commands, lower intensity for local information. No constant barking. |
| sergio | Visitante admirando cordilheira e braseiro. | Compartilhar entusiasmo por detalhe percebido. | Bright male middle voice, spacious delighted phrases, small smile, relaxed finish. |
| seu_abel | Ex-trabalhador da oficina do cais; mora no Beco do Mercado. | Oferecer calor e proteger o pouco que restou. | Soft weathered male baritone, welcoming starts, pause before admitting loss. Fatigue without slurring, quiet dignity. |
| seu_tiao | Morador do porão do motel; cachaça de cacto e passagem secreta. | Acolher e afirmar domínio do porão com humor. | Rounded male middle voice, light gravel, relaxed timing, conspiratorial grin, clean sober articulation. |
| takeshi | Rival de arrancada e guardião dos registros; prêmio por honra. | Exigir precisão e reconhecer derrota com dignidade. | Centered male baritone, spare breath, even weighted clauses, decisive stops. Controlled heat; no Japanese accent inferred from name. |
| tita | Moradora da Cisterna Velha; fogueira e alertas sobre lago. | Oferecer abrigo e evitar que Dante se machuque. | Warm smoky female middle voice, steady short phrases, open invitation then crisp warning. No forced hoarseness. |
| tomas | Patrulheiro; rajadas e luzes além do bunker. | Fazer observar antes de seguir. | Quiet male lower-middle voice, deliberate observation, listening gap, firm final instruction. |
| tonho | Morador do Dreno do Porto; observa contrabando e evita polícia. | Ajudar sem parecer envolvido e continuar em paz. | Narrow male middle voice, quick low asides, tentative starts landing clearly, alert breath and a glance implied by pause. |
| tonico | Contato da vila dos caminhoneiros; restaura bomba de ar. | Montar peças com Dante em parceria. | Buoyant male middle voice, nasal warmth, quick calls then slower directions. A laugh held in the breath, practical delight. |
| velho_ozias | Mineiro idoso; trinta anos de galeria. | Contar experiência e indicar acesso que não consegue usar. | Older male deep grainy voice, slow setup, lively dry punchline, exact practical detail. Experience without frailty caricature. |
| vicente | Irmão de Dante; passou pela prisão e integra corridas do deserto. | Impedir que promessas apaguem oito anos de ausência. | Male low-mid voice, denser and rougher than Dante, level volume, delayed answers and hard endings. Hurt held back until the last word. |
| zeca | Trabalhou vinte anos nos galpões; dorme sob eles. | Transmitir saber preservando controle sobre história própria. | Grainy male mid-low voice, dry humor, measured pace, ironic release then guarded quiet. Dignity in work experience. |

## Homônimos e aliases

| Label | Identidades |
|---|---|
| Raul | raul_desert, raul_sewer, raul_mountain |
| Helena | helena_bank, helena_mountain, helena_ski |
| Elias | elias_cemetery, elias_mountain |
| Luísa | luisa_wine, luisa_mountain |
| caller / VOZ AO TELEFONE | maciota; mesma pessoa, filtro na mixagem |
| Cida / Dona Cida | Esgoto / cidadã na delegacia |
| Beto / Beto Cascavel | Harbor / galeria do deserto |
| Enfermeira Clara / Clara da boutique | Com fala / atendente sem fala no catálogo |

A resolução tenta line_keys, sections e default_character, nessa ordem. Empates/locutores desconhecidos falham; não há sorteio nem fallback masculino. Casting id não muda o hash legado.

## Evidência de gênero e idade

- DesertCharacter.gd tem female explícito de Vicente, Lívia, Raul, Nadir, Bia, Irene, Jessica e Rauhz.
- V1RoutineActor.gd:78 fixa appearance_female dos moradores/hóspedes da montanha.
- OriginalResidentData.json + ServiceResidentModel.gd determinam elenco de hospital, delegacia e bombeiros.
- NelsonModel.gd fixa masculino e 60+; LuisaModel.gd fixa feminino.
- FerryPassenger.gd explicita passageiro mais velho sem número. Velho Ozias é idoso pelo título autorado.
- Joana diz Obrigada; voz por rádio. Helena é a atendente índice 0 de Robberies, female=true; RobberyActor aplica appearance_female. Maciota também se refere a ela no feminino.
- Demais fichas distinguem casting proposto de prova de modelo. Gênero percebido da tomada precisa corresponder à pessoa e corpo.

## Figurantes, texto sem áudio e pessoas mencionadas

| Grupo | Evidência |
|---|---|
| Trabalhadores do porto e tripulação do cais | gameplay/routines_v1/RoutineCatalog.gd — ship_dock e south_port têm lines=[]; guarda interativo é papel separado. |
| Pranteadores Lúcia, Raul, Otávio, Marta, Vicente e agente funerário | gameplay/urban_v1/CemeteryOperations.gd — Única chamada say() atual é Elias, já coberto; homônimos não são protagonistas. |
| Nina e Clara das lojas da montanha; Bento atendente | world/places/OriginalResidents.gd — Modelo/dialogue_id presentes, sem entrada em ServiceDialogue.PEOPLE. |
| Lucas e Mara do porão Santa Mare | world/places/PlaceCatalog.gd — Modelo e nome, sem diálogo autorado no catálogo atual. |
| Ocupantes procedurais Lia, Rui, Helena, Caio, Marta, Joel, Nina, Pedro, Isa, André | world/places/harbor_buildings/HarborBuildingContent.gd — Diálogo textual social agora coberto por seis papéis de personalidade/gênero; ainda sem playback individual. Não herdam voz de homônimo de missão. |
| Pedestres, clientes locais do deserto e membros/convidados da arrancada | runtime/desert/DesertLocals.gd — Pedestres têm reações textuais e gritos, registrados no suplemento/inventário não verbal. Clientes e figurantes sem fala continuam separados. |
| Dona Alzira, Bento maquinista, Rosa e Samuel | gameplay/urban_v1/CemeteryOperations.gd:STORIES — Mencionados nas histórias de Elias; não falam. Bento não é lenhador. |

Manifesto, anotação, terminal, triagem e alarme textual são excluídos. Carta assinada por Vicente não vira fala dele automaticamente.

## Produção e aprovação

1. Resolver pessoa por locutor, chave e contexto; caller e Maciota mantêm identidade.
2. Combinar direction[idioma] com intenção específica da linha; timbre não sufoca emoção.
3. Audicionar PT-BR/EN: linha neutra, sob pressão e íntima quando o papel as possui; indivíduo reconhecível.
4. Escutar gênero percebido, compatibilidade com corpo, nomes, informação jogável e contraste entre colegas.
5. Ouvir no contexto de oficina, balcão, ameaça, abrigo, pista, telefone e rádio; acústica é mixagem.
6. Publicar só tomadas aprovadas. ASR, banco completo e ausência de silêncio não certificam interpretação ou química.

Pendências: escuta comparativa, bloqueios de aparência/emissor e verificação audiovisual no jogo. As fichas não dão essas validações por concluídas.

## Validação inicial dos 345 diálogos

Validação direta em Python com o inventário real e os resolvers do pipeline: 75/75 labels, 345/345 chaves, 80 identidades sem ambiguidade e 690 tomadas PT-BR/EN planejadas. Todos os caminhos de fonte existem; cast_id do catálogo de linhas coincide com a resolução contextual. caller e Maciota mantêm a mesma voice.identity. Gêneros de Nadir, Ferreira e Helena conferidos contra o código. Há 24 identidades com bloqueio de casting registrado, sem publicação automática.

Esta verificação cobre estrutura, cobertura, evidência e ligação entre catálogos. Não é benchmark, escuta artística ou execução renderizada do jogo.

## Auditoria ampliada de rotas

O agregador [directed_voice_inventory.py](../tools/directed_voice_inventory.py) preserva o inventário legado e acrescenta falas que não passam por show_dialogue. Ele verifica que cada texto suplementar existe na fonte antes de planejar áudio. Nenhum runtime foi alterado nessa coleta.

| Rota | Situação atual | Tratamento |
|---|---|---|
| CivilianSocialState / BuildingSocialPanel | Conversas, brincadeira, resposta a arma, susto e trabalho em painel | Seis perfis: friendly/reserved/nervous × masculino/feminino; respeitar condição de cada personalidade |
| HarborBuildingOccupants | Ameaça após mexer na porta, sem locutor no aviso | Mesma pessoa do prédio; exige id persistente e gênero real |
| CivilianReactionDirector | Quatro balões: larga a arma, para, polícia e sai daqui | Dois papéis de reação, separados por gênero; identidade do civil persistente |
| TruckersVillageHouseGuards | Aviso de invasão da casa sem áudio individual | Dois papéis por gênero; resident_variant==1 é feminino |
| Robberies, caixa do posto | Resistência, submissão e expulsão por texto | Caixa masculino pelo modelo atual; actor.female não é aplicado na ramificação fuel |
| WineRuntime presente | Uma fala adicional de Nelson em feedback | Preserva Nelson; nova linha precisa ligação de áudio/legenda |
| SewerResident | PARE! após primeiro golpe de punho | Uma combinação para cada um dos 17 moradores; Raul usa raul_sewer |

As 159 combinações não são 159 frases inéditas: o mesmo texto precisa de locução coerente quando emitido por papéis de personalidades/gêneros diferentes. Os emissores procedurais conservam o nome em cena, mas o nome não determina o sexo nem herda a voz de protagonista homônimo. A frase compartilhada Obrigado exige Obrigada na locução/legenda feminina.

## Papéis procedurais adicionais

| ID | Papel e intenção | Timbre e ritmo |
|---|---|---|
| civilian_friendly_female | Morador procedural receptivo dos prédios de Harbor. Acolher a conversa e voltar ao próprio trabalho; medo não apaga sociabilidade. | Warm female mid register. Open warm onset, easy connected phrases, audible smile at greeting, genuine small laugh after a joke. Firm boundaries under repeated interruption. |
| civilian_friendly_male | Morador procedural receptivo dos prédios de Harbor. Acolher a conversa e voltar ao próprio trabalho; medo não apaga sociabilidade. | Grounded male mid-low register. Open warm onset, easy connected phrases, audible smile at greeting, genuine small laugh after a joke. Firm boundaries under repeated interruption. |
| civilian_nervous_female | Morador procedural cauteloso dos prédios de Harbor. Manter segurança e controle da rotina; aceitar ajuda sem confiar de imediato. | Warm female mid register. Slightly airy onset, attentive brief pauses and a quicker reaction to threat. Breathing settles during reassurance. No permanent stutter or comic panic. |
| civilian_nervous_male | Morador procedural cauteloso dos prédios de Harbor. Manter segurança e controle da rotina; aceitar ajuda sem confiar de imediato. | Grounded male mid-low register. Slightly airy onset, attentive brief pauses and a quicker reaction to threat. Breathing settles during reassurance. No permanent stutter or comic panic. |
| civilian_reaction_female | Civil procedural reagindo a ameaça, agressão ou perseguição. Fazer a ameaça parar, buscar ajuda ou expulsar agressor. | Warm female mid register. Forward urgent projection, short distinct action beats, breath driven by immediate danger. Anger and fear differ by line; never a long indiscriminate scream. |
| civilian_reaction_male | Civil procedural reagindo a ameaça, agressão ou perseguição. Fazer a ameaça parar, buscar ajuda ou expulsar agressor. | Grounded male mid-low register. Forward urgent projection, short distinct action beats, breath driven by immediate danger. Anger and fear differ by line; never a long indiscriminate scream. |
| civilian_reserved_female | Morador procedural reservado dos prédios de Harbor. Preservar seu espaço e terminar o trabalho; confiança é conquistada. | Warm female mid register. Dry centered tone, compact answers, measured pauses before trust. A reluctant laugh is a small real release, never sarcasm on every line. |
| civilian_reserved_male | Morador procedural reservado dos prédios de Harbor. Preservar seu espaço e terminar o trabalho; confiança é conquistada. | Grounded male mid-low register. Dry centered tone, compact answers, measured pauses before trust. A reluctant laugh is a small real release, never sarcasm on every line. |
| fuel_cashier | Caixa do posto no assalto; corpo atual masculino. Sobreviver à ameaça; resistir ou ceder conforme estado real do assalto. | Grounded male mid-low register. Plain slightly nasal middle register, quick frightened intake, controlled but tightening speech. Resistance is defensive; surrender releases the breath without comic cowardice. |
| village_resident_female | Morador procedural de uma casa da vila dos caminhoneiros. Expulsar invasor e convocar vizinhos para proteger a casa. | Warm female mid register. Grounded forceful onset, personal anger in the first clause, decisive call for neighbors in the second. No cowboy caricature or invented regional accent. |
| village_resident_male | Morador procedural de uma casa da vila dos caminhoneiros. Expulsar invasor e convocar vizinhos para proteger a casa. | Grounded male mid-low register. Grounded forceful onset, personal anger in the first clause, decisive call for neighbors in the second. No cowboy caricature or invented regional accent. |

## Vocalizações: diagnóstico anterior ao vínculo implementado

- CivilianReactionPresenter escolhe panic_0..2 aleatoriamente, sem gênero do corpo; Gameplay._pain_voice usa hurt_0..2 para jogador/NPC e só muda pitch. Esses sons precisam escuta e vínculo com ator; não lhes foi inventada transcrição.
- MiningRaid toca panic_1.wav na posição SECRET_RETURN, sem emissor individual identificado.
- PHRASES_PANIC tem quatro textos, mas random_phrase() não tem chamador atual; o fluxo de pânico toca grito sem balão. Permanecem catalogados como autorados inativos, sem fingir fala jogável.
- POLICE/PHONE de ArrivalDialogue são dados legados de migração; chegada atual usa HOME_CALL/MEETING/TOUR. ATENDENTE/CONTATO não aumentam o elenco atual.
- Doze programas de rádio são arquivos de áudio. Não apareceu roteiro de locutor nas fontes atuais; ouvir/atribuir vozes presentes nesses programas continua pendente. A música Fronteira Country tem manifesto próprio.
- Stems voice_pt/voice_en de opening/v3 são legado; OpeningPresentation atual usa FerryFilm.

A releitura inicial de SewerResident, SewerResidentCombatModel e RoleBodyCatalog encontrou os bloqueios dos esgotos: o catálogo respeitava female quando fornecido, mas os moradores não vinculavam esse campo ao guarda-roupa. Naquele diagnóstico foram mantidos os 24 bloqueios autorados e acrescentados 11 bloqueios de ligação ao emissor/playback. A correção implementada e a remoção desses bloqueios estão registradas abaixo.

Validação da expansão intermediária: 504 chaves únicas e 86 labels resolviam 91 identidades sem ambiguidades. Os textos suplementares foram encontrados nas fontes reais. O conjunto final de 565 combinações inclui também as reações e alternativas femininas descritas na abertura deste documento; inventário não certifica geração ou atuação.


## Vínculo implementado em 12/10/2026

`audio/VoiceActorBinding.gd` é a autoridade do emissor. `resolve(actor, role, section)` devolve persona, character_id, actor_id, gender e section; `bind` associa pessoa autorada sem alterar sua aparência. O gênero vem do guarda-roupa final ou corpo real do modelo. Sem prova do corpo, o resultado é vazio; um nome feminino/masculino não basta. IDs persistentes ou identidade numérica do ator não são sorteados de novo a cada fala. `pain(actor)` preserva a voz já associada, incluindo Cida e Dante, e rejeita associação incompatível.

`audio/ActorDialogueVoice.gd`, implementado pelo agente de diálogos, cuida do áudio espacial, legendas e ciclo de vida. Os emissores usam essa API em eventos; não foi acrescentada busca global a cada frame. O helper limita a três tomadas ambientais simultâneas. Conversas fechadas, emissores removidos e personagens mortos devem interromper a tomada.

| Arquivos alterados nesta parte | Resultado |
|---|---|
| `SewerHomelessModel.gd`, `SewerNetwork.gd`, `CivilianModel.gd` | is_female chega ao guarda-roupa antes de escolher cabelo/barba. Cida é explicitamente feminina. Os 17 moradores de Harbor/deserto foram cruzados com as definições reais. |
| `CivilianBodyCatalog.gd`, `Actor.gd`, `MissionWorld.gd` | Ferrugem e Moradora recebem gênero autorado e identidade fixa. Sem GLB do gênero correto, o corpo procedural correspondente continua visível; não se escolhe o sexo oposto. |
| `SewerResident.gd`, `Services.gd` | PARE e diálogos do morador apontam para a mesma pessoa. Um corpo incompatível gera character_id de recusa explícita em vez de voz emprestada. |
| `BuildingSocialInteraction.gd`, `HarborBuildingOccupants.gd` | Respostas sociais, intimidação e aviso de invasão usam o residente real e sua personalidade. Atualizar o painel não repete o áudio. |
| `CivilianReactionPresenter.gd`, `Gameplay.gd` | Reações/pânico e Ai!/Ow! recebem gênero e identidade do ator. Pânico mantém cooldown de quatro segundos; dor mantém chance e cooldown de combate. O banco antigo só permanece no modo de comparação. |
| `HarborPortSecurity.gd`, `VerticeCompany.gd` | Cada guarda/funcionário/operador fala por seu próprio corpo. Novos perfis femininos preservam a população visual existente. |
| `PoliceAgent.gd`, `Gameplay.gd` | O aviso de rendição transporta WeakRef do policial real sem quebrar o sinal sem argumentos usado pelo cancelamento de conversas. FullSession consome esse vínculo no núcleo de áudio. |
| `MiningLife.gd`, `MiningYardJob.gd` | O serviço da cava fala pela estação sample_breaker viva. Contato morto ou descarregado não vira voz em coordenada vazia. |
| `TruckersVillageHouseGuards.gd`, `Robberies.gd`, `WineRuntime.gd`, `WinePanel.gd` | Invasão de casa, assalto ao caixa e presente de Nelson têm emissor, identidade, legenda e voz. |

Os 39 perfis com defeitos de implementação carregam `resolved_casting_issues` com evidência, e `casting_blockers` foi limpo após autorização para integrar. Isso não marca atuação ou render como aprovados. `allow_legacy_voice_fallback=false` impede reutilizar áudio antigo não verificado nos perfis corrigidos quando o banco dirigido está ativo.

O catálogo possui 95 referências vocais próprias em `voice.anchor_text_pt` e `voice.anchor_performance`, entre 80 e 150 caracteres por fala. Trinta referências foram adaptadas para audição; `anchor_text_kind=authored_voice_reference_only_not_gameplay_dialogue` deixa explícito que não acrescentam fatos ao cânone nem texto às missões. As outras usam falas já dirigidas. Há objetivo, interlocutor e inflexão em cada referência; a identidade não deve depender de uma leitura neutra. caller usa a mesma referência de Maciota. A referência urgente de Jessica já produzida pode ser reutilizada pelo pipeline.

### Evidência funcional desta parte

Godot **4.7.2 .NET**, após compilação C# feita pela sessão principal:

- `tests/test_voice_actor_binding.gd`: PASS. Corpo real, gênero explícito, três personalidades, guarda/polícia femininas, identidade persistente, recusa de incompatibilidade, 17 moradores, fallback procedural visível, dor de Cida/Dante.
- `tests/test_building_social_interaction.gd`: **37/37 PASS**. Aproximação física, parede, piso, controle, fechamento, ameaça síncrona, pausa, morte e descarregamento.
- `tests/test_arrival_port_security.gd`: **18/18 PASS**. Preserva acesso público e restrição do porto enquanto altera a apresentação vocal.

Logs: `tmp/voice-actor-binding.log`, `tmp/voice-social-interaction.log`, `tmp/voice-port-security.log`. Fixtures de sessão receberam somente o método show_speech necessário ao contrato atual. Esses testes não certificam FPS, oclusão ou interpretação. Comparação renderizada e escuta pertencem à validação integrada conduzida pela sessão principal.

Os avisos globais mantêm a frase canônica, persona, identidade e seção mesmo com `play_voice=false`, permitindo trocar legendas/voz durante a fala sem duplicar o áudio 3D. Balões de reação, PARE dos esgotos e a legenda de dor consultam apenas a superfície que ainda possui a tomada ativa antes de expirar; o timer de dor usa referência fraca e geração para não apagar uma fala posterior. Após esses ajustes, social **37/37** e porto **18/18** passaram novamente (`tmp/voice-social-interaction-locale.log`, `tmp/voice-port-security-locale.log`). A sessão do núcleo também validou o Main real com **41/41** checks; essa evidência continua funcional, sem substituir benchmark renderizado.

### Limites explícitos

O pânico da emboscada da mina continua um SFX espacial anônimo em SECRET_RETURN: não foi atribuída uma pessoa ou gênero sem evidência. Os bancos não verbais antigos de dor/pânico permanecem disponíveis somente para comparação com GETECO_DIRECTED_VOICES=0; o modo dirigido usa as novas reações autoradas. Os doze programas de rádio seguem como conteúdo gravado sem roteiro de locutor encontrado nas fontes. Nenhuma transcrição foi inventada para esses arquivos. O inventário verbal e os patches não afirmam ter auditado todas as vozes contidas nos programas de rádio.

### Triagem acústica das referências sintéticas

`tools/audit_voice_cast_audio.py` compara os WAVs de `anchors.json` com o casting autoral por SHA256, sem editar áudio ou manifesto. Usa somente CPU, uma thread, com o [modelo ECAPA-TDNN original](https://huggingface.co/JaesungHuh/voice-gender-classifier) e a [exportação ONNX MIT](https://huggingface.co/Alice-Sabrina-Ivy/voice-gender-classifier-onnx-q8/tree/5debf995242f9851881d4e4848fe6eed2bb5ade7). O SHA256 dos 15.779.619 bytes do modelo é `33a7f84f17d5ceee61aae8b23488e06fc1e3295a44eaf7eb5744f3e01e380784`, conferido com o objeto LFS publicado. Nenhum código remoto foi executado.

A política foi fixada antes de examinar as previsões: três janelas distribuídas de dois segundos; mediana do softmax; limiar 0,8; revisão também quando uma janela confiante diverge do casting. O áudio é convertido para mono float32 a 16 kHz sem normalização externa de amplitude, conforme o [pré-processamento do exportador](https://huggingface.co/Alice-Sabrina-Ivy/voice-gender-classifier-onnx-q8/blob/5debf995242f9851881d4e4848fe6eed2bb5ade7/preprocessor_config.json). Cinco testes cobrem os limites da política, a ordem das classes, divergência entre janelas e a impossibilidade de converter suporte automático em aprovação humana.

Os resultados em `evidence/voice-direction-20261012/cast-acoustic-audit.json` registram cobertura real, scores, janelas, SHA do cast, do áudio, do modelo e do manifesto. Snapshots preservam evidência antes de retakes. São alertas sobre a adequação de vozes ficcionais ao casting, sem inferir identidade de pessoas reais, saúde, idade ou qualidade da atuação. O classificador treinado em VoxCeleb2 não estabelece sua precisão nestas vozes sintéticas em PT-BR; os scores não são probabilidades calibradas de verdade.

`anchor-flags-review.json` cruza os mesmos SHAs com o ASR conduzido pela sessão principal e distingue formatação de números/contrações de possíveis desvios de conteúdo. Também registra comandos, nomes e verbos suspeitos quando a similaridade global é alta. As notas manuais iniciais ficam vinculadas ao SHA original, sem migrar a crítica automaticamente para um retake. Após os 95 originais, oito referências receberam uma alternativa delimitada: Digo, Helena do banco e Passenger por alerta acústico acima do limiar fixo; Funcionária e Elias da montanha por dúvida de conteúdo para ICL; Bruno, Dona Marlene e Moradora após duas leituras ASR focalizadas. Os pedidos estão em `digo-anchor-retake.json`, `passenger-anchor-retake.json` e `content-anchor-retakes.json`. Texto e personalidade permaneceram iguais, arquivos antigos ficaram preservados e o cast congelado não mudou.

As 95 referências selecionadas, após esses oito retakes, não apresentaram mediana de classe oposta acima de 0,8. O relatório ainda conserva oito ambiguidades e dois desacordos entre janelas (Cida/Digo). Isso não é certificação artística. A referência de Bruno continua lexicalmente duvidosa; suas tomadas finais em PT-BR exigem segunda leitura, e uma eventual correção pontual pode usar `speaker_embedding` para não alinhar texto contra uma referência incerta. A revisão das referências foi encerrada para iniciar o banco, sem ciclo indefinido de novos seeds.

### Segunda leitura lexical focalizada

`tools/audit_directed_content_secondary.py` usa [faster-whisper/CTranslate2](https://github.com/SYSTRAN/faster-whisper/tree/v1.2.1) com os [pesos turbo fixados](https://huggingface.co/dropbox-dash/faster-whisper-large-v3-turbo/tree/0a363e9161cbc7ed1431c9597a8ceaf0c4f78fcf). O [modelo original](https://huggingface.co/openai/whisper-large-v3-turbo) tem quatro camadas de decodificação. O download de dados foi limitado a 1,8 GB/600 s e verificado pelo SHA LFS; nenhum código remoto foi executado e Torch não foi alterado. O runner opera com CPU/int8, uma ou duas threads, um worker, limite de memória e prazo. Não recebe o texto esperado no prompt e não altera gravações ou publica decisões.

O primeiro lote de quatro referências contestadas levou 157,172 s em CPU1, incluindo 5,625 s para carregar o modelo; pico de working set 1.877,9 MiB e de commit 3.831,1 MiB, durante geração TTS concorrente. Não foi uma segunda transcrição de todo o elenco. A leitura turbo recuperou `no Digo`, `imóvel/Devagar` e `baixa essa mão`, evitando retakes por falhas do reconhecimento inicial. Concordância dos dois modelos em outras dúvidas motivou as três alternativas finais; ambos pertencem à família Whisper e continuam sujeitos a erros comuns.

Na produção, `production-content-decisions.json` admite somente decisões textuais sobre a tupla exata SHA do áudio + idioma + texto esperado. Homófonos e grafias equivalentes podem resolver um falso alerta; omissões, nomes, comandos, números e substituições não são aprovados pelo score global. `human_listening=false` e atuação pendente permanecem explícitos.

Também são examinadas diferenças com score acima de 0,85: uma frase longa pode ocultar um comando ou uma negação alterados. A segunda leitura fica limitada aos trechos contestados, preservando cache por SHA e snapshots em `secondary-asr-snapshots`; o relatório mantém os lotes anteriores em `archived_takes`. Os quatro testes de seleção/cache passaram. O nome estrangeiro escrito de outra forma pelo ASR não exige pronúncia uniforme entre personagens.

As reações `combat_pain` pedem um único impulso de aproximadamente meio segundo. Após aparecerem gravações de 13–14 segundos, foi autorizada a rejeição das tomadas acima de **2 segundos**, independentemente de similaridade ASR. O campo `active_seconds` do auditor mede a extensão entre a primeira e a última amostra acima do limiar, não atividade contínua. `production-pain-repair-requests.json` registra somente os SHAs afetados e uma alternativa focal de Dante/Ow ambíguo, com a mesma identidade, orçamento curto, término natural e máximo de dois segundos; não autoriza truncar áudio ou regenerar toda a família. Interjeições curtas que o reconhecedor transcreve como outra palavra permanecem uma limitação específica da análise automática.

O classificador acústico também aceita `cloned-production.json` e prioriza tomadas de pelo menos dois segundos, com CPU1 e prazo finito. Reações menores, incluindo Ai/Ow, recebem `insufficient_duration_for_casting`, sem probabilidade ou aprovação inventada. `complete_current_manifest` significa somente cobertura do snapshot que já foi gravado, não que todas as 1.130 tomadas planejadas existem. Os hashes distintos comprovam arquivos diferentes, não vozes perceptualmente distintas.

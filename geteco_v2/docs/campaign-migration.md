# Campanha, economia e persistência V2

Este documento distingue dados preservados, lógica funcional isolada e integração no mundo. **Ter um catálogo ou ledger não torna a cena original jogável.** A pequena tarefa `harbor_arrival_v2` continua sendo adaptação de validação e não substitui a chegada original, Primeiro Giro, guincho ou campanha Cobras.

## Inventário e estado deste lote

| Conteúdo original | Fonte | Estado entregue neste lote | Dependência no mundo nativo |
| --- | --- | --- | --- |
| 9 beats: prologue_call, bus_terminal_arrival, port_vehicle_job, trap_and_arrest, ankle_monitor_release, garage_and_contracts, contracts_arc, final_race, district_one_aftermath | data/campaign/campaign_v1.json | JSON integral + CanonicalCampaign com ordem, flags, desbloqueios e restauração validados | Cinemáticas, roubo, bloqueio remoto, prisão, tornozeleira e corrida final devem produzir eventos reais; não instanciados pelo ledger |
| 4 contratos: lista_quente, duas_chaves, patio_17, isca_para_o_rei | Mesmo JSON | IDs, objetivos, recompensas e barreira do arco preservados | Condições de integridade, prazo, dois veículos, apreensão e interceptação exigem adaptadores físicos |
| Primeiro Giro | HarborFirstFavors / HarborArrivalMission | Máquina de estados comprovante → peça no porto → Maciota; recompensa original 150 | Helena/North Pier, peça no navio e conversa na garagem; root conecta alvos e UI |
| Dentro do território | HarborStoryTow / CobraCampaignState | Sequência Ferrugem → carregar → descarregar → Neco → Ferrugem, recompensa 120 | Guincho real, carro da cliente e baia; conversar não substitui transportar |
| Prova de rua | CobraCampaignController | Quatro portões em ordem, carro obrigatório, limite 100 s, recompensa 200 | Largada 21h, rota física e relógio de prova |
| A conta chega / Cortar o abastecimento / A última cobrança | CobraCampaignController | Ordem, encontros requeridos, provas e recompensas 250/350/600 | NPCs, encontros de combate, proteção da moradora e documentos |
| 16 armas | guns/WeaponCatalog → gameplay/WeaponCatalog | IDs, preços, descobertas, posse, munição, compra e recarga no Economy | Combate e apresentação pertencem ao agente gameplay/root |
| 11 roupas | characters/OutfitCatalog | Constantes originais, preços, posse e equipar | Aplicação visual da roupa e controle de estoque/localização por loja |
| 49 veículos incluindo 3 motos | VehicleCatalog / MotorcycleCatalog | Constantes originais, famílias e IDs | Modelos exportados/runtime de veículos tratados pelo root; **não existem preços de venda no catálogo original** |
| 5 corridas e 3 zonas de drift | RaceCatalog / DriftZoneCatalog | Dados integrais, recompensas e coordenadas originais preservados | Rotas/gates/zonas físicos em metros e resultados medidos |
| 10 colecionáveis | CollectibleCatalog | IDs, coleta única, 50 por descoberta e bônus originais em 3/5/10 | Posicionamento dos pickups e recompensa visual/áudio |
| 19 conquistas | AchievementCatalog | Critérios originais, recompensas únicas e snapshot | Contadores reais de direção, combate, neve, exploração e guincho |
| 3 residências | ResidenceManager / ResidenceRules | PROPERTIES e regras puras originais: uma residência ativa, troca a 70%, veículo armazenado | Casas, compra/troca, vaga, armazenamento e respawn; dados/regras ainda sem integração neste lote |
| 5 serviços sequenciais de guincho | cars/salvage/TowJobs | Catálogo original e next_job preservados | Guincho, prensa, limites diários, contrato e veículo real; não confundido com missão narrativa |
| Serviços de oficina, colete, munição | HarborAutoService / GarageMenu / HarborAmmunationInterior | Preços fonte + débito idempotente; compra de munição atômica | Efeito físico do reparo/colete depende do consumidor |
| Saves V1 | SaveManager / CampaignState / Player | Inventariados; nenhum save original aberto/escrito | Conversão V1→V2 não implementada; root agrega snapshots V2 e migra somente save do protótipo V2 |

Contagens verificadas pelo motor: 16 armas, 11 roupas, 49 veículos, 5 corridas, 3 drift, 10 colecionáveis, 19 conquistas. `source-manifest.json` registra arquivos e SHA256 de origem dos primeiros sete catálogos. As coordenadas `Vector2` e caminhos `model_class` dentro dos catálogos são **metadados de origem**, não referências prontas para instanciar no novo mundo. Não carregar modelos V1 por esses caminhos a partir do V2; usar o catálogo de frota exportado pelo root.

## Campanhas são distintas

O JSON canônico e o arco de Harbor coexistem no V1. O primeiro tem estrutura de nove beats e quatro contratos; o segundo implementa a chegada, Primeiro Giro e cinco missões Cobras com descoberta gradual sobre Vicente. Não unificamos artificialmente seus IDs nem marcamos um arco como concluído ao terminar o outro.

`CanonicalCampaign` fornece `current_beat`, `objective`, `complete_beat("<id>_completed")`, `complete_contract(id,economy)`, `snapshot`, `validate_snapshot` e `restore_snapshot`. Concluir `contracts_arc` exige os quatro contratos obrigatórios. O caller deve emitir conclusão apenas depois de validar o objetivo real; esse ledger não comprova roubo ou prisão por si só.

`CampaignRuntime` fornece `available_missions`, `begin(id)`, `current_step`, `target_id`, `objective`, `apply_event(event_id,payload)`, `cancel`, `claim_reward(economy,id)`, `snapshot`, `validate_snapshot` e `restore_snapshot`. `current_step` inclui evento, ID estável do alvo e requisitos. Eventos fora de ordem/alvo incorreto não alteram a sessão. Os requisitos incluem estar a pé, arma guardada, veículo correto vivo, encontro concluído e portão/tempo de corrida. O caller deve obter esses valores do mundo, não de um botão de conclusão.

`legacy_flags()` projeta os IDs originais `harbor_delivery_started`, `harbor_first_favors_v3`, `harbor_delivery_receipt`, `harbor_delivery_picked_up`, `harbor_delivery_complete` a partir do checkpoint. `cobra_status()` preserva as regras de acesso/reputação/derrota de CobraCampaignState. `flags` interno também contém marcadores locais V2 de conclusão; não substituem automaticamente todo o estado V1. `source-flags.json` registra callsites de flags originais para os próximos adaptadores.

Recompensas de Harbor são reservadas no estado da campanha e pagas usando recibo `campaign:<id>` no Economy. Campanha e carteira devem ser persistidas juntas. Repetir pagamento não duplica dinheiro. Cancelar não cobra taxa.

## Diálogos e mapa

`OriginalDialogue.lines(section,language)` devolve `speaker`, `message`, `source`, `line`. Seções: `primeiro_giro_begin`, `bank_receipt`, `bank_unavailable`, `primeiro_giro_finish`. As 13 falas PT/EN de HarborFirstFavors foram extraídas sem reescrita; a branch de banco indisponível fica separada da conversa de Helena. `narrative-source.json` preserva outras 132 linhas-fonte para migração dirigida; esse arquivo de rastreabilidade não é uma cinemática executável.

O objetivo original da peça fica em `Waterfront/ShipWaypoints/CargoInspection`, definido por HarborWaterfront como `Vector2(3515,1450)` no espaço local do waterfront. Aplicar transform do pai antes da escala nativa; não substituir por uma peça aleatória perto da garagem. O contato Helena fica no Banco North Pier. As três ações de Primeiro Giro não cobram compra nem exigem roubo.

## Economia e integração

`Economy` é RefCounted, sem nó de cena nem loop por frame. Começa com dinheiro zero e punhos; root decide política explícita de transição dos dados antigos. Propriedades: `balance`, `equipped_weapon`, `outfit`, `inventory` (cópia). Métodos principais:

- `storefront("weapon"|"outfit")`: linhas com ID, preço original, owned e unlocked. Lojas físicas filtram estoque e não devem exibir descrições decorativas dos catálogos.
- `purchase(category,id,transaction_id)`: `{ok,reason}`. Compra repetida com o mesmo recibo e produto não cobra novamente; reutilizar recibo para outro produto é rejeitado.
- `grant_reward(receipt_id,amount)` e `spend(amount,receipt_id)`: carteira limitada, sem valores negativos, recibos persistidos.
- `grant_weapon`, `owns_weapon`, `equip_weapon`, `get_ammo`, `consume_ammo`, `add_ammo`, `reload_weapon`: posse e munição persistidas. Pickup duplicado não cria arma/munição adicional.
- `reload_weapon(id,capacity=-1)` aceita capacidade efetiva original dos mods; o caller calcula via WeaponCustomization. Teto exato: shotgun +2, hunting_rifle +3, pistol/smg/ak47/m4a1 +50%. Cartuchos já carregados são preservados quando remover o mod.
- `buy_ammo(id,rounds,transaction_id)` paga e adiciona munição na mesma operação. Fórmula original: mínimo 40, 2 por cartucho ou 60 por explosivo.
- `discover`, `collect`, `evaluate_achievements`: IDs originais, desbloqueios e pagamentos únicos.
- `grant_item`, `consume_item`, `owns_outfit`, `equip_outfit`: itens e roupas sem acoplamento à apresentação.

Economy não conhece localização. **GameState deve bloquear equipar/atacar/recarregar conforme contrato da garagem**, guardar automaticamente a arma e liberar uso ao sair. Os NPCs protegidos não recebem saúde/dano. Isso não pode depender de a loja estar fechada.

## Persistência e lacunas rastreadas

Cada módulo valida seu snapshot antes de substituir estado e normaliza números JSON. Integração usa GameState root para commit conjunto, backup e namespace isolado; `Progression.gd` do primeiro trecho permanece intacto. Formato V1 tem campanha, player, world e wanted, incluindo coordenadas/veículos e estado adicional que não podem ser convertidos silenciosamente.

Ainda precisam de migração física/estado específico além dos catálogos: intro/telefone/passeio de Maciota; cinemáticas canônicas; contratos de veículos; guincho/prensa; residência/garagem particular; corridas livres/drift; clima e frio; esqui/elevador; expedição e mistério da montanha; banco/alarme/fechamento; assistência médica e corpos; viagens regionais/ônibus; customização visual; interface completa de saves/opções. Alguns estão sendo implementados por outras frentes — atualizar status pela evidência integrada do root, não por esta lista isolada.

## Validação deste módulo

Correção anterior de relógio da prova Cobra: CampaignRuntime acumula delta ativo entre portões em race_elapsed; race_outside preserva quatro segundos fora da pista. O lote anterior teve Campaign/Economy158 e Activities65 checks aprovados. Esses resultados antecedem a implementação angular abaixo e não validam o código novo.

### Corrida Cobra: implementação angular ainda não validada

Por orientação explícita do usuário, este lote foi implementado sem executar Godot, testes ou benchmark. Arquivos: systems/campaign/CobraRaceProgress.gd, systems/campaign/CampaignRuntime.gd, runtime/MissionWorld.gd e objetivo inicial em data/campaign/HarborMissions.gd.

Fonte: world/harbor/campaign/CobraCampaignController.gd, preparação e atualização da corrida. Para largar, o veículo deve estar íntegro, perto da marca (85px), parado até20px/s e apontado para norte (produto escalar>=.65). A interação nativa E substitui a tecla R específica de V1. Contagem de3s sem cobrar o tempo da prova; deslocar mais de18px antes de JÁ causa falsa largada. O HUD existente consome campaign.objective(), exibindo contagem, portão e tempo; não exige painel novo.

O helper acompanha o mesmo ID de veículo, posição anterior, ângulo anterior, progresso angular assinado, posição de largada, ângulo de saída, estado na pista e índice0..4 dos portões. Detecta salto maior que max(80px,delta*900px), saída/troca/quebra do carro, limite100s, abandono4s, corte dentro de150px e retorno fora de±.3rad do ponto de saída. O anel é300±60px; faixa321px; tudo convertido a1/16 em XZ. Os quatro portões exigem progresso acumulado dePI/2, PI,3PI/2 e2PI, mais distância<85px. A chegada é o quarto portão após a volta inteira; aproximar-se parado ou em sentido inverso não completa a prova. A conclusão preserva evento/recompensa idempotente existente e fala original de Ferrugem.

Persistência: race_run é campo opcional do snapshot de campanha, sem quebrar leitura dos saves V2 anteriores. Novos saves preservam contagem, trajetória, carro e os dois cronômetros. Saves antigos com corrida parcialmente avançada mas sem trajetória retornam à largada da mesma missão; não se inventa uma volta comprovada. Outras missões, dinheiro, inventário, desbloqueios e recompensas continuam intactos. Campo failure recebe race_restart_required nessa migração e é limpo na nova largada. Ao cancelar ou concluir, race_run é removido (dicionário vazio), sem sobrepor objetivos posteriores.

MissionWorld ignora o relógio enquanto ready_for_play é falso, sessão pausada/modal ou vehicle_transition_busy; este último cobre o embarque assíncrono ao restaurar hóspedes da garagem. Root é responsável por preservar vehicle_id/was_driven na frota e restaurar o condutor antes de liberar o relógio. Se a admissão física falhar e o jogador permanecer a pé, a corrida é cancelada de forma controlada e salva como race_vehicle_left. A restauração não remove obstáculos nem força travessia.

Pendências deste lote: parser e execução reais, adaptação dos testes antigos de eventos para fornecer posição/ID e percurso real, save/reload durante contagem e retorno à pista, última linha de chegada e medição renderizada. O controle de tráfego da praça, áudio dos sinais e apresentação de setas da corrida original não foram ampliados neste lote. Nenhuma aprovação de performance ou paridade completa é inferida da implementação.

### Atividades e recuperação do guincho

`activities/Activities.gd` integra dois drifts reais Harbor, dez colecionáveis de produção e três residências com preços/regras originais. Cinco corridas e três drifts CityDemo continuam como dados e runtime para região legada; não foram espalhados em coordenadas falsas de Harbor. Motores de prova exigem deslocamento físico, carro e tempo; pontuação de drift usa deslocamento observado. Validação física/renderizada de todas as rotas e vagas continua dependente da integração.

MissionWorld expõe `snapshot()`, `restore_snapshot(Dictionary)->bool`, `validate_snapshot(Dictionary)->bool` e `validate_ownership(snapshot, active_mission, activity_contract)->bool`. Snapshot versão1 contém job, loaded, unloaded_at_bay, truck/cargo; cada veículo contém archetype, position[3], yaw, health e paint. Transformação e saúde são finitas, modelo precisa existir, prêmio/duração/tipo devem corresponder ao catálogo; carga pertence a apenas um contrato ou à missão cobra_contact. A restauração deve acontecer antes de Activities.configure ou begin_tow_job. Falha de spawn mantém o save intacto e deve impedir autosave até recuperação; não iniciar um contrato substituto. FullSession salva em world_state.mission_world e deve salvar também após carregar/descarregar fisicamente o guincho. Saves V2 anteriores sem esse campo usam recuperação antiga explicitamente, sem inferir transporte já concluído.

Os cinco serviços preservam ordem, tipos, pagamentos e prazos. As vagas de fallback vêm de HarborSouthPort (3480,4160) e CobraNeighborhood (8340,1750), escala1/16; modelos especiais são sport_coupe, cobra_v8 e police_cruiser. Limitação atual: a seleção dinâmica original por distância entre todos os carros estacionados não está integralmente reproduzida. Entrega na baia ainda adapta a conclusão original na prensa; não equivale à prensa funcional. Último trabalho não exige noite na fonte original; horário só afeta reação policial. Cancelar aguarda saída do jogador/descarga livre e não apaga o carro ocupado. Reação policial específica, prensa e comparação renderizada de performance continuam pendentes.

`tests/test_campaign_economy.gd` roda headless, sem alterar saves do jogador. Primeiro lote: 119 checks aprovados. **Execução final em 21/09/2026: 150 checks aprovados em Godot 4.7.2, exit 0.** Abrange transações, idempotência, pré-requisitos, portões, tempo, recompensas, corrupção de snapshot, ordem canônica, contratos, desbloqueios, serviços, diálogos, coleta, munição personalizada e contagens dos catálogos. A execução final também imprimiu dois erros de recurso da fonte `assets/Barlow.ttf`, ainda aguardando importação da integração pelo root; nenhum erro de script nesta suíte. Teste puro não certifica colisão, proximidade real, combate, visual ou performance da cena integrada.

# Água e frio: auditoria de migração

Auditoria estática em 21/09/2026. Escopo: fontes V1 e conexões V2. Nenhuma alteração de runtime, região, física ou asset; nenhum processo Godot executado. “Ativo” abaixo significa conectado no código de produção, não comportamento reexecutado nesta auditoria.

## Resultado

O original possui travessia a pé sobre os lagos com apresentação aquática, não um sistema de natação. Não foram encontrados estados de nadar, fôlego, afogamento, profundidade funcional, flutuação ou penalidade térmica por roupa molhada nas buscas em characters/world/systems. Não se deve chamar a implementação desses sistemas de mera migração: seriam regras novas que exigem definição própria. O frio original, ao contrário, está ligado à produção e ainda não está migrado ao V2.

## Comportamento e fontes V1

| Área | Fonte e conexão efetiva | Regra observada |
|---|---|---|
| Água dos lagos | `world/mountain_pass/MountainLakeWater.gd`, chamado por `characters/Player.gd::_play_footstep` | Testa polígono local; exclui interiores, atores invisíveis, ilhas secas e avião. Não muda velocidade, gravidade ou dano. |
| Pegadas/ondas | `MountainLakeWater.actor_step` | Até48 marcas; água dura0,85s, marca molhada4,5s, seis passos molhados após sair. Entrada no deck/interior elimina marcas molhadas. Ondas recortadas ao polígono. |
| Som dos passos | `audio/footsteps/FootstepSurfaceResolver.gd::resolve`, Player | Água retorna water, deck do avião retorna metal. Player usa ProceduralAudio e aumenta volume aquático5dB. Deck/passarela do navio também são metal. |
| Aparência aquática | `geodata/nature/WaterPresentation.gd`, `WaterSurface.gdshader` | Shader canvas compartilhado; lake usa flow(2.5,.8), strength.65. Não é shader espacial reutilizável diretamente. |
| Frio | `ColdSurvivalController.gd`, instanciado por `MountainPass._setup_weather_and_cold` | `force_cold_active=true`: toda região selecionada é fria, não apenas acima do limiar y=-1500. `ContinuousWorld` habilita controlador somente na região selecionada. |
| Abrigo | `MountainPass._process` | Interior mountain/harbor, túnel ou metadata mountain_shelter tornam sheltered=true. Abrigo desativa zona fria e recupera temperatura. |
| Roupa | `MountainExpedition._process`, `characters/OutfitCatalog.gd::cold_protection` | Atualiza proteção pelo traje equipado, além do booleano thermal_coat. |
| Clima de montanha | `IceStormManager.advance_weather` | Ciclo240s, frente suave e rajadas; estado clear/light snow/blizzard/hail. Intensidade chega ao controlador térmico limitada0..1. |
| Save | `systems/RegionTravel.gd` + `MountainPass.restore_region_interior` | Salva/restaura temperature e weather_clock da montanha. Não salva exposure_seconds nem acumulador fracionário de dano. |

### Regras térmicas exatas

Temperatura0..100. Exposição só acumula ao ar livre sem veículo nem calor; quando protegido, exposição recua2 segundos por segundo até0. Há15s de carência e15s de rampa integrada, independente do tamanho do frame. A integral é t²/(2r) para t<r e t-r/2 depois, com t=max(0,exposição-15), r=15.

Perda base3,5/s +2/s×intensidade da tempestade, multiplicada por1-proteção e pelo intervalo integrado de exposição. Roupas: ski.9, arctic.8, trench.6, lumberjack.35, classic.15, suit/cowboy/madmax.1, ghillie.25, demais0. Booleano térmico garante pelo menos.8, não imunidade.

Na zona fria, fogo recupera35/s e tem precedência; veículo recupera20/s. Fora da zona fria ou abrigado, recuperação15/s. A0, dano5/s acumulado em inteiros; acima0 limpa acumulador e encerra hipotermia. API original prefere `take_environment_damage`, evitando agressor/crime, e só depois usa fallback health.

A detecção original de veículo aceita is_driving/current_vehicle/is_inside_vehicle e até invisibilidade. Essa última convenção não deve ser transportada ao 3D: o adaptador deve consultar o estado real de direção. Fontes de calor são Node2D no grupo heat_source a distância **<220px**, equivalente13,75m na escalaV2. Raios desenhados em Area2D (por exemplo180px no acampamento e550px na lareira) não são consultados pelo controlador: copiar esses raios mudaria o comportamento. Interiores já aquecem15/s por sheltered, independentemente da lareira.

### Fontes térmicas e assets reutilizáveis

Inventário de criadores: MountainPass (madeireira e cume), MountainSceneryBuilder (acampamento do lago secreto), MountainExpedition (aquecedor), MountainSettlement, ResortPromenadeProp, MountainTransitVillage/ MountainTransitVillageLayout, MountainCabinInterior, LumberjackShelterInterior e SummitSkiLodgeInterior. Extrair transforms globais dos criadores antes de reduzir a lista; não substituir todos por um único fogo. A madeireira usa pai(6350,560)+filho(90,20). Vila de trânsito usa HEAT_SOURCE(7650,-1553).

Reaproveitar geometria nativa já copiada de lareiras/interiores/avião, dados de polígonos `OriginalLakeData.json`, e desenho original de fogo `MountainCampfire.gd` como referência explícita de reconstrução2D. `IceStormManager` usa partículas2D e `audio/regional/SnowWindAudio.gd`: parâmetros/áudio podem ser adaptados, partículas precisam implementação3D. Não há rig/animação original de natação identificado. `ColdStatusHUD` oferece sinais/estados/textos funcionais, mas sua montagem e busca global pelo controlador precisam integrar a HUDV2.

## Estado V2 verificado

`NativeLake.gd` reconstrói polígonos originais, ilhas, gelo, camp e avião; `contains_water(Vector3)` usa XZ local e exclusões secas. Há grupos native_water_surface e native_heat_source. O marcador do acampamento tem radius=180/16, que é metadata visual/fonte, **não** equivalência do raio efetivamente usado no frioV1. Não há consumidor térmico desses grupos encontrado. Região mantém chão atravessável sob o lago; “DeepColor” é cor de superfície, não profundidade.

Exclusão do avião em contains_water é um retângulo aproximado (|x|<1.7, -13.6<z<9.7), diferente de consultar suporte físico real do deck/rampa. Corrigir essa classificação será parte da paridade de passos; não retirar chão como consequência incidental.

`Actor.gd` usa gravidade20 e CharacterBody3D; não possui modo aquático. `runtime/Weather.gd`, ligado por ProductionWorld, altera luz/chuva/neve visual. Usa clima aleatório120..240s e não o ciclo térmico original240s. Snow visual não significa sobrevivência ao frio. `GameState.world_state`/SaveStore já guardam estado extensível e roupa via economia, mas não há temperatura/exposição integrada. O catálogo V2 de roupas mantém aparência/IDs; a função cold_protection original não foi portada ali. `Actor.take_damage` integra ferimento/morte/emergência, mas é preciso adapter de dano ambiental sem registrar crime e respeitando recuperação/save; nunca escrever somente health para contornar esse fluxo.

## Plano de implementação em lotes

1. **Paridade térmica determinística:** extrair cálculo puro com mesmos valores/integral/sinais. Adaptador nativo recebe região ativa, abrigo, direção real, intensidade original, roupa e fontes próximas. Converter distâncias por16; offset montanha(4300,-4960) antes de XY→XZ. Não confundir Y2D norte com altitudeY3D. Coordenar ownership runtime com root; regiões/fachadas externas não precisam mudar.
2. **Persistência e integração:** adicionar estado térmico versionado ao GameState, com defaults100/0/0 quando ausente; salvar temperatura, exposição, dano fracionário e relógio climático. Os três últimos ampliam continuidade em relação ao saveV1 e devem ser registrados como correção deliberada, não falsa paridade. ImportaçãoV1 usa apenas temperature/weather_clock disponíveis. Restaurar depois de instanciar controlador (o _ready original reseta100), antes de primeiro tick. Roupa vem de economy.outfit; abrigo/direção/hipotermia derivam do mundo, não booleanos antigos.
3. **Travessia aquática existente:** preservar chão caminhável; resolver superfície real incluindo altura de suporte de deck/rampa, ilha, gelo e interiores. Restaurar passos aquáticos, seis passos molhados, ondas limitadas48 e vidas originais, usando apresentação3D. Não adicionar afogamento, lentidão, dano molhado, barco dirigível ou quebra de gelo sem regra autorizada.
4. **Apresentação/clima original:** adaptar ciclo de frente240s ao Weather existente e portar vento/partículas com orçamento local ao jogador; manter clima ambiente exterior separado de abrigo. Capturar frio ao ar livre, veículo, interior e acampamento. Só depois avaliar uma proposta separada de natação profunda: requer profundidades autorais, entradas/saídas, rig, veículos, respawn e salvamento definidos antes do código.

## Critérios de aceitação física, saves e desempenho

- Lógica térmica: comparar60/30/10ticks por segundo nos limites15s/30s, roupa0/.15/.8/.9, fogo/veículo/abrigo, intensidade0/1; dano somente ao atingir0 e sem crime. Confirmar fogo precede veículo e abrigo recupera15/s.
- Física real: caminhada margem→água→ilha→rampa→deck→margem, cápsula e altura de apoio corretas, sem teleporte através de sólidos. Classificação aquática não invade deck, interior ou seca. Streaming de chunk não perde chão sob jogador/veículo. Este lote não autoriza remover solo sob lago.
- Saves: roundtrip frio, aquecido, dirigindo, interior remoto, lago, avião e troca de região; arquivo antigo sem campos; valores inválidos/NaN/infinito; clima/exposição contínuos sem reset explorável ou dano duplicado ao carregar. Posição carregada precisa suporte físico e ausência de sobreposição. Preservar backup/validação existentes em SaveStore.
- Garagem: entrada e restore continuam sem armas; Maciota/mecânico nunca recebem dano térmico ou de qualquer tipo. Controlador acompanha apenas jogador.
- Visual: evidência renderizada de pés, ondas, pegadas, oclusão no deck/ilha e estados funcionais da HUD. Não inferir aprovação visual de um teste de polígono.
- Performance: medir frame time antes/depois na mesma rota/câmera/população com tempestade, água e streaming; limitar atualização espacial às fontes/chunks próximos e efeitos ao orçamento48. Teste headless não aprovaFPS.

Nenhum desses checks foi executado nesta auditoria. A documentação distingue constatação estática, proposta e critérios futuros; não declara água/frio migrados.


## Lote térmico implementado (integração root separada)

Ownership implementado: `runtime/ColdSurvival.gd`, `runtime/cold/*`, `tests/cold/*`. O cálculo `ThermalState` mantém valores e integralV1, gera dano inteiro e expõe snapshot versão1. Adapter consulta região ativa, place_id, carro ocupado real, roupa equipada, sete fontes originais, túnel e avião. Fora da montanha pausa relógio/temperatura conforme ContinuousWorldV1; morto não recebe novos ticks. Nenhuma regra aquática adicionada.

Contrato root: `configure(session)`, `snapshot()`, `restore(Dictionary)->bool`, `validate_snapshot(Dictionary)->bool`, `status()->{visible,key,text,temperature,maximum,exposure,heat_id}`. Salvar sob world.cold; ausência aceita defaults100/0. Campos: version1, temperature0..100, exposure>=0, damage_fraction[0,1), weather_clock[0,240). Rejeita NaN/infinito/tipos inválidos antes de alterar estado. Sinais temperature_changed/hypothermia_started/hypothermia_ended; API de dano `Gameplay.damage_environment`, sem colete/crime. Não há escrita direta em health.

`recover_after_rescue()` recupera100 e zera exposição/fração, preservando relógio. Melhoria solicitada para impedir ciclo de morte após resgateV2; não é alegação de regra original. A roupaV1 já calculava mountain_thermal_coat=(proteção>=.8); EconomyV2 não possui esse item. Adapter usa roupa equipada e não inventa compra/consumível térmico.

Fontes externasV1: sete coordenadas em `OriginalHeatSources`. Representações em `HeatPresentation`: braziers originais Transit/Resort, efeitos originais Hearth sem OmniLight, fogo2D MountainCampfire reconstruído como lenha3D e chamas. MarcadoresV1 de calor sem modelo próprio (outfitters/patrulha) materializados com brazier original Transit: adaptação explícita de apresentação, não cópia de um aquecedor que não existia. Marcador nativo do lago reutiliza anel/piso existentes, adiciona somente chama. Nenhuma Light3D/SubViewport nova. Consulta/apresentação a cada.25s; modelos só a80m, descarregados fora de alcance/interior/região; efeitos dos modelos ativos mantêm animação original. Sólidos físicos dos recipientes/bancos preservam circulação, sem converter raio térmico em barreira.

Validação inicial:121 checks de cálculo/save e14 de adapter passaram. Primeira baseline foi reclassificada como diagnóstico estático porque cabana bloqueou caminhada em7,56m; não serve como aprovação da rota. A fixture corrigida exige reta livre por25consultas físicas e>=40m de percurso, e compara Main+24habitantes+neve+1280x720 com warmup5s e amostra30s. Meta60FPS/16,67ms, variação>5% no p95/p99 exige confirmação. Resultados finais abaixo após medição. Sem alteração em Weather/FullSession/GameState/NativeRegion por este agente.


### Conflitos de cenário identificados na revisão das sete fontes

A primeira revisão visual reprovou três contextos, apesar dos sete pontos de aproximação livres. Fotos anteriores preservadas como `tests/cold/evidence/before-heat-{logging_camp,summit_camp,smuggler_camp}.png`.

1. Acampamento: polígono seco original tinha z-index2 acima do lago z-index-3; V2 o colocava em y.008 sob água.015/.018. Apenas o piso seco foi elevado a.028, sem mudar contorno, nível físico do chão ou regra aquática.
2. Heliponto: a floresta nativa omitira `_is_helipad_reserved` da fonte MountainSceneryBuilder. Portada exatamente a exclusão de125px em(6335,-2795) e corredor com65px de afastamento. Não desloca a base, fogo ou heliponto.
3. Madeireira: não era erro da posição do fogo. East Vale foi convertido equivocadamente em asfalto marcado, enquanto a fonte `_init_dirt_roads`/`build_backcountry_dirt_roads` define terra60px sem faixa/calçada. O pátio original `build_detailed_sawmill` sobrepõe a via (z1 sobre z0) e foi omitido no V2. Restaurados superfície/largura do ramal EastVale e dois polígonos exatos do pátio/acesso, mantendo curvas e fogo(6440,580). Isso não significa que toda madeireira/veículo/mobiliário foi migrada.

Mudanças restritas a NativeLake/NativeRegion autorizadas pelo root; nenhum NativePine ou urban_detail alterado. Recapturas finais inspecionadas: piso seco não é mais coberto pela água, pátio não tem faixa/calçada e heliponto está sem árvores. Execução física final685checks PASS, incluindo preservação do afastamentoEastVale. Exclusão de árvores aplicada após geração determinística, sem reposição, e corredor EastVale preserva afastamento anterior5,625m para não redistribuir a floresta ao corrigir largura da estrada. Fotos after: `heat-logging_camp.png`, `heat-summit_camp.png`, `heat-smuggler_camp.png` na mesma pasta. Medição final concluída conforme tabela abaixo.


### Medição térmica renderizada (antes das três correções de cenário)

Main real, RTX4060Laptop, Godot4.7.2 Mobile,1280×720,24habitantes, neve fixa/mesma rota/horário, limite60FPS;5s aquecimento+30s amostrados. Saves desativados. Fonte visível/hud/cálculo explicitamente configurados só no after.

| Variante | FPS | p95ms | p99ms | Máximo | >33,3ms | Caminhada |
|---|---:|---:|---:|---:|---:|---:|
| Baseline |60,0028|17,564|18,599|20,686|0|52,54m|
| Frio+fonte+HUD |60,0043|17,673|18,416|21,307|0|52,56m|

p95+0,62%, p99-0,98%. Sem regressão de frame time no cenário medido; isso não é garantia universal nem certifica cidade inteira. Tempos de processoCPU p95 subiram6,873→7,416ms; frame intervals permaneceram no orçamento observado. GPU específica não instrumentada. Arquivos completos: [baseline](D:/geteco/game/geteco_v2/tests/cold/evidence/mountain-baseline.json), [after antes do terreno](D:/geteco/game/geteco_v2/tests/cold/evidence/mountain-cold-before-terrain.json); [foto antes do terreno](D:/geteco/game/geteco_v2/tests/cold/evidence/mountain-cold-before-terrain.png) inspecionada. O primeiro trajeto bloqueado está preservado em mountain-static-diagnostic e excluído da aprovação.

Testes finais pré-correção: Thermal121checks e adapter17checks PASS, este último sem avisos após fixture aguardar Weather/áudio montar antes de encerrar. O aviso anterior era street_0.ogg devido ao encerramento durante montagem assíncrona, não recurso térmico. Fotos das sete fontes foram inspecionadas; quatro contextos claros e três conflitos acima em correção. Nenhuma aprovação visual ampla foi inferida dos testes físicos.


### Resultado final do lote e admissão física

Após as correções do terreno e preservação das demais árvores: **60,00296FPS**, p50 16,676ms, p95 17,516ms, p99 18,091ms, máximo20,460ms, zero quadros>33,3/66,7ms,1801frames em30,015187s. Mesma rota e24habitantes da baseline; p95-0,27%, p99-2,73%. [Medição final](D:/geteco/game/geteco_v2/tests/cold/evidence/mountain-cold.json) e [foto final inspecionada](D:/geteco/game/geteco_v2/tests/cold/evidence/mountain-cold.png). Percurso final: 52.56m. Uma tentativa intermediária foi interrompida para ceder janela de GPU e não foi usada como evidência; rodada completa final exit0 sem avisos.

Fotos dos três conflitos foram inspecionadas e os problemas específicos corrigidos. Isso não aprova a madeireira inteira (galpão, pilhas, detalhes e caminhão continuam fora deste lote), nem toda a montanha. Estado de lógica/adapter:121+17checks PASS; terreno685checks PASS. Scripts de integração root foram mantidos fora deste ownership.

Admissão de saves: `prepare_collision_at(point)->bool` instala sólidos térmicos próximos até8m antes de aceitar pose de jogador/veículo. Retornafalse na criação e até passar umphysics_frame, preservando outras fontes; chamador aguarda física e repete sua consulta completa de casco/cápsula. `HeatPresentation.update_sources` ganhou retain_existing=false/radius80 opcionais, usados como true/8 nessa admissão. Isso previne aceitar carro de save antigo dentro de braseiro que antes só seria criado no primeiro tick. Geometria/animação permanecem iguais às medidas; apenas ordem de instalação mudou. Teste dedicado `tests/cold/test_admission.gd`: 11 checks PASS, exit 0; não exige novo benchmark de regime estável.

Limite de admissão: raio de 8 m cobre o maior casco do catálogo atual (ônibus route_city, 2,536 × 9,78 m; meia diagonal horizontal 5,052 m) mais o ponto mais distante dos bancos do braseiro (2,554 m), total conservador 7,606 m. Esta garantia precisa ser revista se forem adicionados veículos maiores. Integração real do hook em Main é verificada por `tests/cold/test_admission_integration.gd`.

Integração de admissão concluída: `test_admission_integration.gd` com Main e Cold padrão passou 7 checks (exit 0, sem erros). A ordem final consulta os quatro apoios do veículo antes de materializar fontes. Fonte removida foi recriada pelo hook e recusada no mesmo frame; após três frames, o casco sobre o braseiro continuou recusado, e a pose livre com suporte `(642.5, 0.04, -259.3125)` foi admitida. O teste isolado de admissão passou 11 checks. Nenhuma nova geometria ou loop por frame foi adicionado nesta proteção de carregamento; permanecem válidas as medições renderizadas anteriores.


## Passos aquáticos — implementado, NÃO VALIDADO

Por solicitação explícita do usuário, este lote foi escrito sem executar Godot, testes, capturas ou benchmark. As medições térmicas anteriores não aprovam este novo efeito.

`audio/WorldAudio.gd` consulta `runtime/world/WaterSteps.gd` no passo existente do jogador. O helper usa os lagos carregados do grupo `native_water_surface`, seus polígonos, pedras/ilhas/acampamento secos e exclusão do avião; interiores, teleporte e entrada em veículo limpam o rastro. Som aquático é a síntese determinística original de `audio/footsteps/FootstepAudioBank.gd::_water_step`, isolada em `OriginalWaterStep.gd` e cacheada em quatro variantes. Não foram inventados sons ou regras de natação/afogamento.

Ondulações adaptam `MountainLakeWater.gd` para geometria XZ: até 48 marcas, 24 segmentos, duração 0,85 s, quatro gotas e seis pegadas úmidas de 4,5 s ao sair. Escala 1/16, paleta e crescimento originais; segmentos são cortados pelo classificador nativo da água, incluindo áreas secas. Um mesh sem sombras e sem luz é atualizado somente enquanto existem marcas. Sem novos corpos físicos, alterações de velocidade, dano ou campos de save; efeitos transitórios não persistem. Escopo: jogador; passos de NPCs permanecem para integração posterior.

Validação pendente: parser/import, som em ambos os lagos, bordas/pedras/ilhota/deck secos, seis marcas após saída, limpeza ao entrar em ambiente/veículo/teleportar, captura da orientação/altura real dos efeitos e comparação renderizada antes/depois no lago. O custo do primeiro som sintetizado e da atualização limitada do mesh ainda não foi medido.

## Clima sincronizado — implementado, NÃO VALIDADO

`Weather.gd` agora lê `ColdSurvival.weather_sample()`, derivado do relógio térmico persistido. `ThermalState` compartilha a frente de 240 segundos e os limiares de `IceStormManager.advance_weather`: neve leve acima de 0,08; nevasca acima de 0,65; granizo acima de 0,92 antes da fase 0,60. A perda de calor mantém a fórmula original, sem segundo relógio independente para a tempestade visual.

O emissor existente representa neve e um emissor separado mantém granizo simultâneo. Densidade, direção, velocidade e intensidade acompanham o estado; Harbor recupera as características anteriores de chuva. Áudio de vento regional acompanha a intensidade e fica abafado nos abrigos; a chuva de Harbor não toca na montanha. As fontes de abrigo do cálculo térmico também interrompem precipitação local. Não foram acrescentadas luzes, SubViewports ou regras de dano do granizo. Neblina e estilhaços no chão continuam pendentes.

Nenhuma execução realizada neste lote, por solicitação do usuário. As medições anteriores não aprovam o novo emissor ou a apresentação sincronizada. Ficam para depois: compilação, ciclo completo, save/restauração da fase, alternância de regiões, abrigos, áudio e apresentação renderizada.

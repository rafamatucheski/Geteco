# Relatórios recebidos para consolidação

Registro de recebimento, não auditoria independente. A pedido do usuário, o panorama global fica para depois da chegada dos demais relatórios. Prioridades abaixo foram atribuídas pelos autores e precisam de triagem conjunta. Linhas podem mudar com edições concorrentes.

## Atividades, serviços e persistência

Fonte: anexo `C:/Users/rafae/.codex/attachments/de926ba7-10a5-4a85-acd4-c43c8425e05f/Texto colado.txt`, lido integralmente.

- Autor relata duas corridas Harbor, duas zonas de drift, três provas de ski, dez colecionáveis e serviços conectados por código. CityDemo e suas cinco corridas são identificadas como legado desconectado, não obrigações produtivas.
- Entregas relatadas: `activities/V1OptionalRewardPolicy.gd` novo; alterações em `runtime/Services.gd` e `data/catalogs/ServiceCatalog.gd`; documentos `OPTIONAL_ACTIVITIES_HANDOFF_2026-09-21.md`, `SERVICES_FLOW_HANDOFF_2026-09-21.md` e `SAVE_PROGRESSION_CONTRACT_REVIEW_2026-09-21.md`.
- Integrações pendentes: helper de pagamento repetível do ski em MountainProgression; remoção do ramo genérico de garagem e guarda contra compra de colete cheio em FullSession; importador V1; persistência de CanonicalCampaign; consistência entre recompensas e economia; alias dos IDs do RPG da caverna.
- Drift possui adaptação angular/anti-wall-grind diferente do V1. Não registrar aceitação do usuário sem decisão explícita.
- Autor informa ausência de Godot, testes, benchmarks, build e commits. Mudanças e conexões ainda não foram conferidas independentemente neste recebimento.

## Controles, câmera e interface

Fonte: texto integral fornecido pelo usuário na mesma mensagem.

- Nenhuma edição relatada. Workspace concorrente; Gameplay mudou durante a auditoria.
- Prioridades relatadas: conflito interact/reload no X; trunk/unarmed no D-pad; ausência de foco e cancelamento B nos modais, acesso ao inventário no controle.
- Demais achados: restauração de zoom/heading no resgate; exceção incorreta no remapeamento; Actor ignora GameInput.sprinting; radio_previous sem consumidor; instruções com teclas fixas; cancelamento de configurações incompleto; mensagens de erro invisíveis na pausa; instrução incorreta quando slots não têm opção habilitada.
- Destinos: FullSession e ProductionWorld (integrador); GameInput, SettingsMenu e MainMenu (controles/interface); Actor (coordenar com Claude); WorldAudio (equipe de áudio); Driving (coordenar com responsável por condução).
- Autor relata verificação isolada de CameraRig e tentativa integrada bloqueada por tipagem em Gameplay, linha 451 na ocasião. Isso não comprova funcionamento da sessão atual nem erro ainda presente após novas edições.
- A execução relatada diverge da restrição de não executar estabelecida para aquela rodada. Registrar a divergência, sem tratar como autorização para novas execuções.
- validate_controls depende de árvore antiga segundo o autor. Sem benchmark renderizado; oclusão e performance não certificadas.

## Próxima consolidação

## Som, rotinas e modelos ambientais — segundo recebimento

Fonte: relatório colado pelo usuário; não reconferido no código neste recebimento.

- Áudio: autor relata WorldAudio conectado via Main → World → ProductionWorld._audio, ambiência contextual, passos por superfície/clima, detalhes espaciais e efeitos de atividades. Módulos em audio/v1_ambience; documentação AUDIO_AMBIENCE_MIGRATION.md. Quatro WAVs com hashes V1 iguais segundo o autor. Carga e guincho ainda precisam publicar eventos inequívocos. Rádio/motor preservados, mas isso não comprova correção de radio_previous apontada na outra revisão.
- Rotinas: catálogo de três rotas do cargueiro, 32 postos/rotas do Porto Sul, 23 moradores da serra e três residentes do lodge; diretor limitado a 12 atores externos com histerese 48/62m. Código em gameplay/routines_v1 e NPC_ROUTINES_MIGRATION.md. NÃO integrado: instanciar RoutineDirector após session em ProductionWorld e conectar nearest_action/v1_routine em FullSession. Maciota/mecânico excluídos.
- Modelos: picape estática da serraria relatada como conectada via MountainDetailFactory → EnvironmentalParityFactory. Teleférico implementado com duas torres/estações e cinco cadeiras, mas registro/montagem em NativeRegion e horário 08h–18h ainda pendentes. Documentação SCENARIO_MODELS_MIGRATION.md.
- Sem execução de Godot, testes, benchmarks ou commits segundo o relatório. Audibilidade, rotas, colisão, oclusão e performance não validadas.

## Continuidade Harbor–serra — segundo recebimento

Fonte: relatório colado pelo usuário; não reconferido no código neste recebimento.

- Autor relata implementação sem troca de cena/teleporte: rodovia norte, aproximação elevada, cabeceira (456.25m,-285m), ponte, encosta, túnel e estrada da serra. WorldConnection3D.gd monta estrutura nas coordenadas originais.
- ProductionWorld mantém regiões residentes na faixa 240–320m da emenda, separando região física/lógica. NativeRegion limita secundária a 3×3 chunks e remove terreno nos vãos. Grafo de tráfego conecta pistas sem recriação dos veículos na emenda.
- Contratos preservados segundo leitura do autor: jogador/carro e anexos; transporte de passageiros; população/tráfego; despacho; snapshots de missões/atividades; clima/frio; coordenadas globais no schema atual; viagem rápida/restauração.
- Fonte documental: MAP_MIGRATION_COVERAGE.md atualizado pela equipe. Convergência V1 (7300,-4560), túnel termina a 175m da emenda segundo auditoria do autor.
- Sem execução; travessia física, tráfego, passageiros, túnel e custo da sobreposição continuam pendentes. Não repetir continuidade como funcionalidade ausente sem conferir esta entrega; também não marcá-la validada.
- Divergência a reconciliar: relatório da ligação ainda cita ambiência-base da serra incompleta; equipe de áudio relata ambiência contextual implementada. Conferir integração atual antes de consolidar ausência ou conclusão.

## Aguardando último relatório

Após receber os demais relatórios: reler código atual, eliminar achados já corrigidos e duplicados, separar implementação de conexão e execução, identificar responsáveis e ordenar bloqueios de inicialização/controle, perda de progresso, acesso físico e paridade. Nenhuma correção foi aplicada a partir destes relatórios neste recebimento.

# Interações com moradores dos prédios — 07/10/2026

Os moradores dos prédios de exploração do Harbor aceitam conversa pela ação **Interagir**, remapeável (E por padrão), quando Dante está próximo, no mesmo andar e com passagem visual livre. O painel permite cumprimentar, conversar, brincar, acalmar e intimidar; aparece no lado oposto aos personagens.

Personalidades sociável, reservada e nervosa modificam as respostas. Cumprimentos e brincadeiras podem gerar alegria; insistência provoca irritação. Os moradores alternam sua atividade com pequenas pausas, voltam a atenção para Dante e retomam o trabalho após a conversa. Humor e confiança são memória da instância ativa, sem nova persistência de relacionamento no save.

Arma à vista gera medo. Mira armada mantida por 1,5 segundo e intimidação explícita podem iniciar uma denúncia de 12 pontos; portar arma sozinho não gera crime. O sistema existente de polícia mantém os 2,5 segundos do telefonema, a evidência observada e o cancelamento quando a testemunha morre. Moradores que percebem a mesma mira compartilham o relato. Tiros reutilizam o crime produzido pelo combate. Acalmar reduz medo residual, sem apagar denúncias. Depósitos ilícitos não acrescentam denúncia social à polícia.

O recuo e o retorno continuam sob `WorkplaceThreatReaction`: cápsula real, varredura contra sólidos e apoio no piso. Sem caminho livre, o morador se protege no posto. O medo residual pode continuar por alguns segundos depois da volta; o objeto de trabalho reaparece ao terminar a recuperação ou a pausa autorada. Telefone e gestos usam o rig nativo.

Conversa não pausa o mundo. Ferimento, tiro próximo, explosão, ameaça ao interlocutor, procura policial, morte, pausa, troca de andar/sala e perda de alcance encerram o painel. Serviços, missões, portas e escadas conservam prioridade. O clique que encerra o painel não vira um disparo. Maciota e o mecânico ficam fora da inscrição social; suas regras de invulnerabilidade e garagem sem armas permanecem.

## Escopo e validação

Nenhum novo lugar ou interior. A integração usa os moradores ativos do catálogo de exploração, registrado no checklist como 59 edifícios / 119 pavimentos internos. Não inclui todos os pedestres de rua nem substitui personagens de missão ou vendedores. A validação renderizada desta rodada cobre **Customs: um edifício, quatro pisos internos e cobertura**. Outros prédios usam o mesmo componente, mas não foram revisitados individualmente nesta rodada.

- Compilação `dotnet build Harbor.csproj --no-restore`: zero erros/avisos; Godot **4.7.2 .NET**, caminho C# comprovado na sessão Main.
- Interface: [37 verificações aprovadas](../evidence/building-social-20261007/test_building_social_interaction-final.log), incluindo bloqueio por parede/andar, dono do input, pausa, perigo externo, foco, clique mantido e descarregamento.
- Reações: [40/40](../evidence/building-social-20261007/reactions-recovery-contract.log), incluindo humor, pausa, acalmar, mira breve/sustentada, parede, andar diferente, dois depoentes sem crime duplicado, móveis impedindo fuga, telefonema e morte interrompendo a denúncia. Retorno físico e medo residual têm prazos distintos; a verificação final aguarda uma única janela calculada pelo estado observado. Logs das tentativas preservados.
- Main: [sessão final, 33/33](../evidence/building-social-20261007/session-final.log), com caminhada real, botões, telefonema, retorno ao posto, saída e limpeza. [Painel corrigido](../evidence/building-social-session-191684-7920731/02-joke-01.png), [ameaça e telefone](../evidence/building-social-session-191684-7920731/03-threat-02.png), [recuperação](../evidence/building-social-session-191684-7920731/05-recovery-02.png). A [primeira sessão](../evidence/building-social-20261007/session-first.log) também passou 33/33 antes do reposicionamento do painel.
- Colisão e oclusão separadas: [581/581](../evidence/harbor-building-contract-184308-7321083/result.json), cinco níveis do Customs, móveis, suporte, varreduras, jogador/NPC à frente/atrás/ao lado e controles positivos de visibilidade. [Log](../evidence/building-social-20261007/depth-customs.log).
- Garagem: [recompensas 47/47](../evidence/building-social-20261007/test_garage_rewards.log), [restauração 34/34](../evidence/building-social-20261007/test_garage_driver_restore.log), [transferência 11/11](../evidence/building-social-20261007/test_garage_vehicle_transfer-final.log). A restauração emite aviso de gravação de voz ausente do guarda do porto, separado das assertions aprovadas.

As capturas reais mostram conversa, medo/telefonema e recuperação; screenshots e a sequência curta não certificam performance. A primeira captura revelou painel cobrindo os personagens, corrigido pelo posicionamento lateral. O teste de interface inicial usava uma fixture sem callback de física; passou após passar a observar ticks reais. O teste de recuperação distinguiu retorno físico, medo residual e pausa, em vez de presumir que voltam no mesmo instante.

**Performance comparativa pendente.** A janela inicial tinha outras sessões Godot/benchmark ativas. A tentativa posterior [de baseline](../evidence/building-social-20261007/baseline.log) falhou no carregamento de dependências do arcade em edição concorrente, e outras sessões voltaram a iniciar. Nenhum processo alheio foi encerrado. Houve também interrupção da primeira regressão de transferência da garagem por erro de tipo temporário no arcade; a repetição ocorreu após a fonte ter sido corrigida pela outra sessão. Não há baseline válida nem conclusão de regressão/FPS. Próximo passo: comparação isolada na Main, mesma configuração/carga, ao menos 30 segundos por cenário normal/ameaça/recuperação; alvo provisório 60 FPS e confirmação finita se p95/p99 subir mais de 5%.

## Arquivos

- `gameplay/civilian_social/CivilianSocialState.gd`: emoções, personalidade, falas e pausas.
- `gameplay/civilian_social/BuildingSocialRoutine.gd`: percepção, testemunhas e ponte com a reação física existente.
- `world/places/harbor_buildings/HarborBuildingResident.gd` e `HarborBuildingOccupants.gd`: rig, objetos, admissão e intrusão percebida.
- `runtime/BuildingSocialInteraction.gd`, `ui/BuildingSocialPanel.gd` e hooks em `FullSession.gd`: interação, interface e ciclo de vida.

# Plano de melhoria do combate corpo a corpo

Data: 30/10/2026. Escopo: taco, faca, katana e machado. Análise estática com dois agentes, sem executar Godot, testes ou benchmark. Nenhuma mudança de gameplay aplicada. Qualidade audível e sensação dos controles ainda dependem da avaliação do usuário.

> Atualização após autorização de implementação: as alterações abaixo foram aplicadas em 30/10/2026 com dois agentes. O diagnóstico e o plano originais ficam preservados neste documento. Não foi aberto Godot, executado teste do motor nem medido FPS.

## Implementação para avaliação jogando

- Mira melee própria, com cursor, indicação de alcance, alvo alcançável e obstrução. O seletor compartilhado pelo feedback e dano prioriza alinhamento; mantém verificação de sólidos, altura e distância. Inimigos vivos têm prioridade sobre cadáveres.
- Orientação melee separada da caminhada limitada das armas de fogo; redução curta durante contato, por arma, com mobilidade recuperada depois. Animação de corrida frontal acompanha a mudança.
- Correção de direção na preparação, seguida de direção fixada durante a janela ativa; consulta limitada à janela com um único acerto por golpe. Geometria usa arco/largura por arma, não colisão exata por triângulos da lâmina.
- Buffer de um único próximo ataque nos últimos 160 ms da recuperação; limpo em pausa, restrições, troca e transição. Normalização de punhos sem arma e remoção de estado pesado herdado de outra arma.
- Ritmo inicial: faca 1,20×, taco 1,25×, machado 1,12× e katana 1,40×. Forja acelera relógio do golpe e contato; blends de locomoção e pausa de impacto preservam tempo real. Danos e alcances do catálogo foram mantidos nesta primeira calibração; alcance visual e equilíbrio de dano por segundo exigem avaliação jogando.
- 60 WAV de Foley preparados offline, quatro tomadas por evento sem repetição imediata, com sons distintos por arma, separação confirmada e queda. Materiais usam o banco existente. Sabre mantém seu estilo. Sem geradores de ruído/osciladores novos no ataque. Fontes/licenças em `audio/melee_foley/CREDITS.md`.
- Até cinco regiões diferentes por cadáver, sem repetir membro, dano, morte, recompensa ou denúncia de morte. A decisão atual não acrescenta crime específico por corte pós-morte. Corpos disponíveis por até 30 segundos reais, registro limitado a 24 referências fracas; pool continua com seis peças e prioriza reciclar fora da tela.
- Cortes letais usam a projeção do golpe no corpo; cortes adicionais usam a junta real selecionada. Desmembramento não letal e ataques contra múltiplas vítimas não foram adicionados.

Validação feita sem motor: leitura/revisão cruzada dos fluxos; análise sintática com `gdparse`; sintaxe Python do gerador; conferência técnica dos 60 WAV (mono 44,1 kHz, arquivos distintos, 0,16–0,46 s, pelo menos 5 dB de headroom). Isso não equivale à compilação GDScript pelo Godot nem à aprovação funcional/auditiva.

Testes de regressão foram escritos/atualizados para execução futura: estado pesado/relógio de ataque, mira/contato/buffer e múltiplos membros/proteção. Nenhum foi executado no motor. Permanecem pendentes: importação efetiva dos novos áudios, sensação de mira/movimento, sincronismo, clipping no mix completo, colisão/oclusão das peças e comparação de performance. O usuário fará a avaliação jogando.

## Diagnóstico confirmado no código

- **Direção existe, mas fica invisível.** `gameplay/Gameplay.gd:106,936,1383` usa direção de mouse/analógico e exclui melee da retícula. `ui/AimReticle.gd` depende desse filtro.
- **Atacar reduz a mobilidade.** `scripts/Actor.gd:369-375` limita movimento com `combat_facing` a 2,3–3,2 m/s; corrida normal é 6,5 m/s. A katana mantém `_aim_hold = 0.8` em `Gameplay.gd:1181`. Orientação do corpo e penalidade de movimento estão acopladas.
- **O clique guarda um ponto antigo.** `Gameplay.gd:1515,1609-1614` grava o destino ao iniciar e calcula o contato mais tarde usando esse destino. Enquanto isso, a orientação visual pode acompanhar a mira atual. Há risco de discrepância ao virar durante o golpe.
- **Cliques podem ser perdidos.** `runtime/FullSession.gd:2239` exige novo aperto para armas não automáticas; `Gameplay.gd:1421` rejeita ataques durante cooldown/contato pendente. Não há fila curta de próximo golpe nesse caminho.
- **Contato genérico.** `Gameplay.gd:1676-1708` consulta uma caixa de largura 1,3 m, ordena alvos pela proximidade, verifica obstrução e acerta apenas o primeiro elegível. A escolha não prioriza o alvo apontado; o volume não acompanha o arco específico da arma.
- **Identidade desigual.** `WeaponCatalog.gd` configura faca em 0,44 s, taco 0,65 s, katana 0,78 s e machado 0,85 s por ataque. A katana tem alcance lógico de 3 m, abaixo do taco (3,875 m) e machado (4,125 m). Esses valores não comprovam correspondência com as malhas.
- **Desmembramento restrito por regras, não por sorte.** Só katana/machado em corte forte, somente no golpe letal; mortos são ignorados. `KatanaWounds.gd` bloqueia segundo corte no corpo, mantém seis peças por dez segundos e escolhe a região por perfil do combo. Dano cheio de katana (45) e machado (52) já supera o limiar 40.
- **Áudio sem evento específico de separação.** `Gameplay.gd:1704` ignora o resultado de `try_sever`; o som é escolhido como impacto comum. `CombatAudio.gd` inclui síntese para melee, enquanto a katana tem três variações preparadas de Foley. A procedência não prova qualidade: não houve audição nesta análise.

## Ordem de implementação proposta

### 1. Mira visível, seleção previsível e mobilidade

Criar feedback próprio para melee: pequeno cursor direcional e indicador discreto do alcance efetivo enquanto se prepara/realiza o golpe. Distinguir alvo alcançável, fora de alcance e bloqueado sem textos decorativos. O feedback deve consultar as mesmas regras do dano; não basta liberar a retícula de tiros, que usa trajetória de arma de fogo.

Mouse escolhe a direção livremente; analógico direito orienta e mantém a última direção válida ao voltar ao centro. Dentro do volume real do golpe, priorizar alinhamento com a mira e usar distância como desempate. Não puxar o cursor nem trocar de alvo automaticamente fora da intenção do jogador.

Separar orientação de combate da velocidade: postura de guarda não deve manter Dante lento depois de atacar. Aplicar redução curta por fase e por arma, restaurando movimento no começo da recuperação. Machado preserva compromisso maior; katana deve permitir reposicionamento rápido. Não acelerar globalmente o personagem nem remover colisão para aproximar alvos.

**Aceite pelo usuário:** apontar para um entre dois NPCs deve tornar previsível quem recebe o golpe; aproximar, atacar e sair não deve produzir arrasto prolongado; inimigos atrás de obstáculos não podem receber dano.

### 2. Resposta, contato e identidade de cada arma

Unificar o estado do golpe: preparação, janela ativa, recuperação e próximo ataque. Permitir correção angular durante preparação, fixando a direção no início da janela ativa. Pose, volume, áudio e efeito usam esse mesmo estado.

Adicionar buffer de um único próximo clique, inicialmente 120–180 ms antes de liberar o próximo ataque. Valores são proposta de ajuste, não números validados. Limpar buffer ao trocar arma, morrer, entrar em veículo/garagem ou mudar de área; não reproduzir golpes atrasados ao retornar de menus.

Usar contatos com varredura limitada na janela ativa, sem depender de um único instante e sem exigir colisão exata de cada polígono da lâmina. Registrar alvos já atingidos por golpe para não aplicar dano repetido. Preservar checagem de sólidos e altura.

| Arma | Papel pretendido | Ajuste principal |
|---|---|---|
| Faca | Curta, rápida e precisa | Preparação curta, recuperação ágil e golpe dirigido a um alvo |
| Taco | Alcance e controle | Arco legível, impacto contundente e reação/empurrão coerente |
| Katana | Cortes rápidos e reposicionamento | Menos retenção de movimento, combo fluido e alcance coerente com a lâmina |
| Machado | Compromisso e impacto pesado | Preparação mais pesada, contato forte e recuperação explícita, sem lentidão residual |

Começar mantendo danos; ajustar tempos e alcance visual antes de rebalancear dano por segundo. Se houver varredura contra múltiplos inimigos, adicioná-la depois como característica de golpes específicos, com limite e dano secundário próprios, não removendo indiscriminadamente o `break` atual.

Integrar melhorias da forja ao mesmo perfil temporal: `gameplay/forge/BladeForge.gd:99-101` altera intervalo, dano e alcance, enquanto o contato continua definido em outros caminhos. Uma melhoria de velocidade deve manter animação, contato e recuperação coerentes, sem apenas reduzir cooldown.

Revisar também o estado de golpe pesado: `WeaponRigPose.attack()` não limpa `_move` quando a arma não tem moveset genérico; katana/faca usam outros caminhos. Impedir herança de propriedades da arma anterior. Isso não impede atualmente o corte letal da katana por dano cheio, mas pode afetar áudio e hit-stop.

### 3. Sons e sensação de contato

Preparar e comparar Foley por evento: deslocamento no ar, impacto contundente, corte comum, separação confirmada e queda da peça. Taco deve ter baque seco; faca, contato curto; katana, corte rápido; machado, impacto mais pesado. Sons de metal, madeira e concreto precisam responder ao material atingido.

Usar amostras próprias ou licenciadas, com variações reais e prevenção de repetição imediata; pitch sozinho não resolve repetição. Aproveitar sons existentes que passarem na audição. Sincronizar transiente com contato, não com clique. Tocar camada de separação apenas quando `try_sever` confirmar sucesso e evitar empilhar impactos completos no mesmo evento.

Ajustar volume relativo em contexto de rua, com passos, NPCs e tráfego. Hit-stop e câmera devem ser breves e específicos por arma, sem congelar o mundo ou prejudicar a mira. Guardar estética sonora do sabre como exceção deliberada à katana convencional.

**Aceite pelo usuário:** distinguir erro, acerto e separação pelo som; reconhecer as quatro armas sem olhar; ouvir uma sequência sem repetição óbvia ou estalos/clipping.

### 4. Mais desmembramento com consistência

Primeiro tornar os cortes atuais claros e relacionados ao golpe que realmente aconteceu. Usar região do contato/arco para selecionar cabeça, braço ou perna, em vez de depender apenas do índice do combo.

Depois permitir cortes adicionais em corpos: substituir a trava única por estado de membros já removidos, com limite anatômico por corpo e sem duplicar uma cadeia removida. Criar caminho de contato pós-morte separado, sem repetir dano vivo, recompensa, morte, voz de dor ou eventos de missão. Auditar separadamente a regra de crime aplicável.

Manter taco contundente e faca como lâmina curta; aumentar variedade com katana e machado, sem transformar qualquer toque em separação. Desmembramento não letal fica fora desta primeira proposta: exigiria comportamento, animação, locomoção e colisão de NPC ferido.

Preservar pool e reutilização. O teto atual de seis peças deve ser ajustado apenas após comparação de custo feita pelo usuário; mais oportunidades de corte e melhor apresentação vêm antes de multiplicar entidades. Queda, repouso, oclusão e limpeza devem funcionar sem peças atravessando o chão, reaparecendo no corpo ou desaparecendo abruptamente em primeiro plano.

## Validação prevista para uma futura implementação

Não executada nesta análise. Reutilizar seletivamente `tests/test_melee_moveset.gd`, `tests/test_melee_dismember.gd`, `tests/test_weapon_locomotion.gd` e testes de contato. Atualizar expectativas deliberadamente substituídas (como proibir segundo corte) e incluir katana onde hoje não consta na matriz de locomoção.

Cobrir contratos importantes: mira e dano concordam, buffer não duplica ataque, um dano por alvo por golpe, sólidos bloqueiam, trocar/cancelar limpa estados, partes não se duplicam, cleanup funciona. Preservar imortalidade de Maciota/mecânico e proibição completa de armas na garagem, inclusive save/load. Mudanças futuras devem manter Godot 4.7.2 .NET e compilar Harbor.csproj antes de executar os testes pertinentes.

Roteiro para avaliação do usuário: cada arma parada e em movimento; alvo próximo/limite/afastando; dois alvos lado a lado; parede/porta entre jogador e alvo; virar durante preparação; clicar pouco antes de recuperar; errar e acertar; alternar armas após golpe pesado; cortar e sair/voltar da área. Avaliar áudio com fones e mix normal.

FPS, frame time e apresentação temporal ficam pendentes de medição pelo usuário na cena real, antes/depois comparáveis, incluindo sequência de combate e recuperação após corpos/peças. Não há aprovação de performance neste documento.

## Recorte recomendado para a primeira entrega

Implementar fases 1 e 2 primeiro, acompanhadas de correção do evento de som de separação. Avaliar o controle com o usuário. Em seguida finalizar Foley e ampliar cortes por corpo. Essa sequência permite identificar melhora de jogabilidade antes de aumentar efeitos e carga física.

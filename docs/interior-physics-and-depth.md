# Contrato obrigatório de interiores acessíveis

Este contrato vale para novos ambientes, prédios, veículos acessíveis, móveis e interações de entrada, e para os ambientes alterados. Chalé e garagem do Maciota são referências de apresentação; a implementação atual é a V2, com cenário, atores e física 3D nativos. Um ambiente não está aprovado apenas porque existe no projeto.

## Comportamento obrigatório

- Jogador e NPCs caminham no piso livre. Mesas, camas, sofás, balcões, caixas, banquetas, portas fechadas e suportes ocupam espaço físico.
- Pernas finas de um móvel não autorizam atravessar seu tampo. Reserve a área do objeto inteiro. Divida móveis em L em partes para preservar os corredores livres.
- Piso e tapete raso são transitáveis. Vigas, lustres e superfícies elevadas encobrem atores pela profundidade, sem criar paredes invisíveis no chão.
- Não altere ordem de desenho, transparência ou posição visual do ator para fingir uma colisão. Não eleve o ator até o tampo nem o teletransporte por obstáculos para resolver um caminho.
- Sentar, deitar ou subir só é permitido em uma interação explicitamente implementada, com acesso livre, pose, apoio e saída validados. O movimento comum continua bloqueado.
- Spawn, retorno, restauração de save, NPC residente, pickup e aproximação de interação devem ficar em espaço livre, considerando a dimensão real do ator. Navegação e deslocamento usam as mesmas colisões; NPC não recebe permissão especial para atravessar cenário.

## Implementação de referência na V2

1. O catálogo [PlaceCatalog.gd](../world/places/PlaceCatalog.gd) define modelos, coordenadas em metros, acessos, spawns e interações. [NativePlace.gd](../world/places/NativePlace.gd) instancia as salas comuns; [MaciotaPlace.gd](../world/maciota/MaciotaPlace.gd) e os lugares especiais possuem integração própria. Preserve a identidade do acesso usado para o retorno.
2. Classifique cada objeto sólido por `interior_solid_id` nas malhas ou pelos volumes autorados consumidos pelo adaptador. `NativePlace` transforma os limites para o espaço local da sala e cria `StaticBody3D`/`CollisionShape3D` na camada do cenário. Não agrupe toda a sala em um sólido; divida volumes em L para conservar corredores. Um objeto sem classificação não ganha bloqueio automaticamente. Verifique volume físico e malha visível separadamente: recortes de paredes para a câmera não removem sua colisão.
3. Jogador, NPCs e mobiliário compartilham o mundo 3D e o desenho da cena. Preserve os rigs e os corpos reais de [Actor.gd](../scripts/Actor.gd) e dos NPCs envolvidos. Não reintroduza projeção para física 2D, sprite por personagem ou SubViewport por ator. A câmera ortográfica determina o enquadramento; não determina a posição física dos sólidos.
4. Entrada, saída, restauração, resgate e transferência de veículo passam pelos fluxos de [FullSession.gd](../runtime/FullSession.gd) e seus controladores de acesso. Preserve os tokens de transição, bloqueio temporário de comandos, origem, máscara de colisão e restauração de câmera/ambiente. A admissão deve verificar o corpo inteiro e o apoio no piso; `FullSession.position_clear` combina cápsula e raio de suporte. `NativePlace.is_floor_clear` é uma consulta auxiliar em XZ, não prova isolada de suporte, altura livre ou passagem varrida.
5. Construa os bloqueios antes de admitir atores e valide sua disponibilidade no servidor de física. Reentrada e descarregamento devem desativar ou liberar sala, NPCs, efeitos e reservas pertencentes àquele fluxo. Um fallback de spawn não dispensa provar que posições autoradas de moradores, recompensas e interações estão livres.
6. Disparos, efeitos e mãos usam os transforms reais dos rigs/armas em 3D. Preserve animação, escala, colisão e ciclo de vida ao integrar outro NPC. Valide oclusão pela câmera final e pelo renderer configurado, incluindo controles em que o ator precisa permanecer visível.

Os antigos `InteriorSolidProjection`, `InteriorActorPresentation` e adaptadores de sprite pertencem à arquitetura projetada da V1. Não são dependências a recriar na V2. Os requisitos visuais e físicos deste contrato permanecem obrigatórios.

## Gate de entrega

Para cada ambiente novo ou alterado, acrescente casos verificáveis ao teste correspondente. Não marque um ambiente como aprovado por ele apenas usar a classe compartilhada.

- Inventário completo de móveis: verificar que cada objeto sólido visível tem cobertura física, incluindo props pequenos e partes adicionadas depois.
- Movimento varrido com o jogador e com NPC real contra as bordas e cantos, inclusive deslocamento grande que poderia atravessar uma parede. Verificar também caminhos válidos: os bloqueios não podem fechar corredores.
- Testar entrada, spawn, pickups, interação, saída, reentrada e recuperação/respawn usando os fluxos reais. Query de ponto isolada não prova que o corpo cabe.
- Renderizar ator antes, atrás e ao lado de móveis, portas, vigas e paredes. Teste de oclusão deve ter controle positivo: esconder o ator sempre não passa. Verificar movimento e origem de armas/efeitos, não só uma pose parada.
- Verificar NPC residente e visitante, duas pessoas na mesma sala, remoção do ator e descarregamento. Sala inativa não deve conservar efeitos, processamento ou renderização desnecessários; não adicionar passes individuais de atores.
- Comparar performance na cena real, seguindo `performance-do-jogo`, e registrar lacunas. Headless não comprova profundidade nem FPS.

Referências de validação existentes na V2, para selecionar conforme a mudança:

- [test_video_interior.gd](../tests/test_video_interior.gd): apoio físico e aproximação dos balcões nas duas lojas de armas e no banco; contém também casos dirigidos dos guardas, sem certificar o fluxo completo da sessão.
- [test_bank_depth.gd](../tests/test_bank_depth.gd): colisão varrida e oclusão renderizada de jogador/NPC no banco, com controles positivos de visibilidade. O viewport da fixture é um instrumento de teste, não a arquitetura produtiva.
- [test_video_session_transitions.gd](../tests/test_video_session_transitions.gd): transições de garagem, loja e banco, chuva, restrição de armas e resgate. Avalie a barreira de carregamento e o escopo da fixture antes de usá-la como evidência atual.
- [test_garage_rewards.gd](../tests/test_garage_rewards.gd), [test_garage_driver_restore.gd](../tests/test_garage_driver_restore.gd) e [test_garage_vehicle_transfer.gd](../tests/test_garage_vehicle_transfer.gd): contratos de recompensa e transferência/restauração da garagem.

Compile `Harbor.csproj` e use o Godot 4.7.2 .NET indicado em `AGENTS.md`, com dados isolados e `--no-save` quando aplicável. Os testes de profundidade exigem renderização; headless serve somente às propriedades físicas/lógicas que a fixture realmente verifica. As referências acima não significam execução ou aprovação nesta revisão documental. Novos ambientes precisam de casos próprios; aprovação de um caso não substitui a cobertura de outro.

Se qualquer caso de colisão, profundidade, spawn ou circulação falhar, corrija a causa antes da entrega. Não ignore assertions, não aumente tolerâncias para aprovar clipping e não declare garantia universal de ausência de bugs.

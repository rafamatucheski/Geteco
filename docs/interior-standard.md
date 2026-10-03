# Padrão de interiores — Chalé + Maciota

Aplica-se a interiores acessíveis novos e reformados em todos os mapas, incluindo seus acessos exteriores. A skill `padrao-interiores` deve ser carregada nessas tarefas. O usuário escolheu o chalé das três armas e a garagem do Maciota como referências. Os parâmetros recomendados são pontos de partida ajustáveis, não uma aprovação dos ambientes atuais.

## Direção visual

Do chalé: volume, materiais com identidade, proporções naturais, iluminação motivada por fontes reais e detalhes que mostram uso. Da garagem: composição organizada, circulação livre, objetos funcionais reconhecíveis e acabamento. Hospital não precisa da luz âmbar de chalé: cada estabelecimento conserva sua identidade.

Na V2, construir sala, atores e colisões em 3D nativo, com câmera ortográfica e profundidade real. Atores e móveis compartilham o mesmo mundo 3D. A direção visual do chalé e da garagem permanece; os adaptadores de sprites e física 2D da V1 são referências históricas, não o padrão de implementação atual.

## Câmera e escala

- Piloto aprovado pelo usuário em 20/09/2026: câmera alinhada da garagem do Maciota, ortográfica, centralizada e sem giro lateral, com materiais e iluminação do chalé. Aplicação autorizada a todos os interiores, caverna e avião externo.
- Salas compactas: enquadramento estável. Salas grandes: acompanhamento suave limitado à área útil. Sem mostrar vazio exterior, zoom por velocidade ou mudanças de projeção durante a caminhada.
- Usar a inclinação da garagem (`Vector3(0,18,15)` em relação ao alvo) como referência. Ajustar tamanho ortográfico e enquadramento à planta sem deformar móveis. Perspectiva diagonal deixa de ser o default; novas exceções precisam respeitar a direção visual solicitada.
- Calibrar atores pela projeção do piso, com referência humana próxima de 1,8 m, respeitando estaturas autoradas. Não aumentar personagem para compensar câmera distante nem encolher móveis para abrir passagem.
- Conferir NPCs ao lado de Dante no gameplay: altura, largura dos ombros, cabeça, mãos e pés devem ter proporção humana compatível. Não conservar multiplicadores antigos de sprite/rig que os tornem gigantes; evitar troncos cilíndricos e membros esféricos volumosos como acabamento padrão. A conferência inclui vendedores, funcionários e seguranças, não só o jogador.
- Finalizar transforms de sólidos, spawn e interações no espaço 3D antes de admitir atores. Validar o enquadramento com a câmera final. Entrada, saída e save não podem deixar câmera, zoom ou escala do ambiente anterior.

## Materiais, iluminação e efeitos

- Distinguir madeira, metal, tecido, vidro e alvenaria por geometria, cor e rugosidade. Detalhar zonas funcionais sem obstruir corredores.
- Luz ambiente moderada, principal com sombras legíveis e luzes locais motivadas pelo cenário. Medir alcance e sobreposição; não impor quantidade universal.
- Fogo, vapor e partículas só onde houver fonte. Não encobrir acessos, pickups ou jogador. Não depender de recursos incompatíveis com o renderer configurado.
- Fachada somente com nome próprio. Sem slogans, categorias ou legendas decorativas. Preservar diálogos, objetivos, preços e estados funcionais. Roupas expostas em manequins vestidos proporcionais.

## Identidade e recompensas

- Cada lugar físico deve ter planta e composição próprias. Trocar somente a cor ou a fachada de uma sala repetida não satisfaz o padrão. Compartilhar componentes e materiais é permitido.
- Todo interior deve oferecer uma recompensa acessível: dinheiro, arma ou item útil. Incluir uma cabana com R$ 5.000. Respeitar as restrições específicas da garagem do Maciota.
- Armas coletáveis flutuam, oscilam verticalmente e possuem um círculo visível no piso. Recolher ao caminhar sobre a área; não exigir interação adicional. Aplicar também à caverna e ao avião.
- Manter o objeto sobre piso acessível, alinhado à área de coleta e fora dos sólidos. A recompensa tem identificador persistente por lugar, não pode duplicar na reentrada ou restauração de save e não deve ser concedida a jogador morto.
- Atualizar efeitos somente enquanto o ambiente estiver ativo, preservando animação dos atores na cena compartilhada.

## Entrada e saída

- Para interiores migrados para dentro da própria fachada, seguir o fluxo contínuo aprovado na Ammu-Nation: abrir a porta por proximidade, atravessar caminhando, ocultar o teto e ajustar a câmera ao cruzar o limiar. Nesses acessos, não mostrar o retângulo laranja nem pedir E para entrar ou sair. Manter a ação de interação somente nos objetos e personagens que a usam.
- Para acessos que ainda transferem para outra sala, usar o retângulo laranja compacto com cantos arredondados junto à porta utilizável, mantendo o formato já implementado (26×14, raio 4), sem letra E ou símbolo de controle. Usar `ui/DoorAccessMarker.gd`; aproximar-se não troca o marcador por uma tecla. A ação de interação e seu remapeamento permanecem funcionais.
- Não concatenar “APERTE E PARA ENTRAR”, nome do prédio ou descrição da saída. Evitar prompts duplicados. Objetivos e diálogos não são prompts de porta.
- Acessos a pé que ainda transferem para outra sala usam a ação de interação. Abrir a porta por proximidade não transfere o jogador por si só nesses acessos. Passagens automáticas ou dirigidas existentes são exceções funcionais; não mudar silenciosamente em ajuste apenas visual.
- Fechado, preço e requisito podem ter texto funcional curto. Não indicar ação disponível quando bloqueada. Compra permanece distinta da entrada.
- Reutilizar fluxo de transição, cooldown, origem e save. Retornar ao acesso usado, inclusive quando várias fachadas compartilham a sala.

## Profundidade e física

Seguir [o contrato de colisão e profundidade](interior-physics-and-depth.md). Na V2, consultar [NativePlace.gd](../world/places/NativePlace.gd), [PlaceCatalog.gd](../world/places/PlaceCatalog.gd), [MaciotaPlace.gd](../world/maciota/MaciotaPlace.gd) e os fluxos de [FullSession.gd](../runtime/FullSession.gd). `InteriorSolidProjection` e `InteriorActorPresentation` pertencem à V1 projetada e não devem ser recriados como requisito da V2.

O adaptador antigo que só amplia sprite não satisfaz profundidade. Volume completo de móveis e portas fechadas bloqueia; piso e tapete raso não. Validar corpo inteiro, cantos, spawn, pickups, circulação e oclusão separadamente.

Invulnerabilidade e ausência de armas da garagem do Maciota continuam específicas e obrigatórias. Não estender ao chalé ou lojas de armas por compartilharem o padrão visual.

## Qualidade e fluidez

- A sala nativa usa a resolução, escala de render e antialiasing do viewport principal. As antigas dimensões de SubViewport por sala (1440×1000 ou 2048×1024) não são requisitos da V2.
- Comparar nitidez e tamanho aparente na mesma resolução de saída, sem esticar a imagem nem reduzir a qualidade para ocultar custo.
- Meta provisória: 60 FPS / 16,67 ms em gameplay real, conforme skill de performance e hardware medido. Distinguir física, limite global, frequência da sala e FPS efetivo.
- Personagens integrados e câmera têm apresentação contínua enquanto ocupados. Não copiar timer de 30 Hz do chalé ou de 20 Hz dos lenhadores como standard.
- Cadência menor da lógica de efeitos não pode reduzir apresentação dos atores. Se um recurso específico precisar de SubViewport, defina um único responsável por sua atualização e meça seu custo; não adicione um passe por personagem ou por sala nativa sem necessidade demonstrada.
- Suspender render e atividade desnecessária em sala vazia. Validar primeira visita e reativação. Não duplicar rigs ou manter passe individual por personagem integrado.

## Referências e entrega

- Chalé: [modelo original](../assets/regions/source/world/mountain_pass/MountainCabin3D.gd), integrado pelo catálogo e por `NativePlace`.
- Maciota: [MaciotaPlace.gd](../world/maciota/MaciotaPlace.gd) e [WorkshopProps.gd](../assets/maciota/WorkshopProps.gd). Os gerenciadores e viewports da V1 são históricos. Não confundir a garagem do Maciota com o serviço Northgate Auto.
- Northgate Auto (oficina de reparo): excluída desta reforma por pedido explícito do usuário em 20/09/2026. Preservar o serviço e a animação do carro entrando e saindo; não acrescentar interior explorável, decoração, pickups ou apresentação compartilhada nessa baia.
- Indicadores e comandos: [DoorAccessMarker.gd](../ui/DoorAccessMarker.gd), [InteractionPrompt.gd](../ui/hud/InteractionPrompt.gd) e [GameInput.gd](../runtime/GameInput.gd). Os controladores de acesso mantêm a distinção entre passagem contínua e transferência por interação.

Manter [checklist e evidências](interior-standard-checklist.md). Fotografar antes/depois reais. Conferir entrada, interação, saída/reentrada, controle/remapeamento, jogador e NPC na frente/atrás/ao lado de móveis, primeira visita e sala vazia. Executar casos físicos aplicáveis e benchmark da skill de performance sem concorrer com outras instâncias de gameplay. Não encerrar sessões alheias.

Falha de colisão ou profundidade bloqueia aprovação. Sem medição, desempenho fica pendente. Criar documentos não altera nem aprova interiores legados.

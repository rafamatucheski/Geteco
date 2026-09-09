# Harbor e Mountain Pass — revisão de 08/09/2026

## Entrega

Revisão baseada nas 15 imagens e na gravação de 5,35 segundos enviadas pelo jogador. As atribuições foram divididas entre três agentes internos (veículos/câmera, polícia/navegação, personagens/armas/ursos), com integração do mundo e validação pela Astra. Os prompts para Antigravity e Claude estão em `PROMPT_ANTIGRAVITY_2026-09-08.md` e `PROMPT_CLAUDE_2026-09-08.md`; os modelos e áudios entregues foram integrados.

- Harbor e montanha compartilham a mesma cena, jogador e coordenadas. A ponte não troca de cena nem teletransporta o carro. Tráfego ambiente e viaturas atravessam nos dois sentidos mantendo suas instâncias.
- Curva de saída encurtada, junção corrigida, continuação norte reservada e limites físicos mantidos. O desafio de derrapagem saiu da praça inicial e foi para a curva da ponte. Corrigido o ajuste automático que unia as duas pistas e induzia retornos indevidos.
- Curvas da serra suavizadas, colisões dos guardrails alinhadas ao desenho e retorno do topo ampliado. Carro especial e árvores afastados da área de manobra.
- Danos substituídos por deformações limitadas e marcas pequenas; reparo restaura a geometria. Portas usam o modelo 3D. A transferência da câmera preserva o enquadramento ao entrar e sair.
- Polícia nasce em pista válida e livre, respeita rotas e mantém o ponto externo de busca quando o jogador entra numa casa. Sirene responde ao estado da ocorrência. Segurar a tecla de sirene não alterna seu estado a cada frame.
- Cabeça acompanha o tronco durante a corrida; armas têm encaixe e modelos compartilhados com os drops. Rifle e faca do chalé ficam próximos ao piso, giram, são coletados por proximidade e persistem no save. NPC removido do chalé.
- Avião cargueiro 3D no lago: rampa, corredor, colisões, teto que abre a visão e abrigo do clima. Tesouro de $1.800 concedido uma única vez e registrado no save.
- Ammu-Nation da montanha com fachada e interior 3D, vendedor e compra funcional. Abrigo dos lenhadores próprio, com beliches, ferramentas, mesa comunitária e fogão, diferente do chalé.
- Pinheiros com galhos assimétricos e neve mais discreta. Família de ursos com mãe e dois filhotes, outro adulto territorial, investida anunciada, mordida com intervalo, sangue e sons posicionais.
- Áudios de sirene, alarme e conclusão revisados e mantidos em cache. Teste de PCM, amplitude, loops e envelopes passou; a avaliação subjetiva de mixagem ainda deve ser feita jogando.

## Validação executada

Godot 4.7.2, Windows, Vulkan/Forward+, RTX 4060 Laptop. Testes reais, sem usar reprodução gráfica como evidência do jogo.

- `test_continuous_world.gd`: mesma cena/jogador/carro na ida e volta, saúde preservada, deslocamento por frame limitado, um único sistema de efeitos.
- `test_continuous_ambient_traffic.gd`: mesmo carro e seguidor nas duas direções; suspensão dos dois ciclos de simulação a distância e reativação ao se aproximar.
- `test_continuous_police_pursuit.gd`: mesma viatura cruza e retorna; maior deslocamento observado de 4,60 px por frame.
- `test_continuous_save.gd`: dinheiro, roupa, itens, carro e pintura; conversão única de coordenadas antigas; retorno correto de interior. `test_region_travel.gd` passa a usar esse contrato contínuo.
- Testes de danos/câmera, portas nativas, segurança policial, rotas, armas/poses, avião/loja, lenhadores e família de ursos passaram. Detalhes nos relatórios específicos abaixo.
- `test_mountain_life.gd`: clima, abrigo, residentes, quatro ursos, ataque, coleta e persistência passaram. O encerramento ainda reporta seis instâncias ObjectDB não liberadas; a origem permanece pendente.
- `git diff --check`: sem erros de whitespace nas alterações rastreadas.

## Desempenho e limites

Perfil curto em 1280 × 720, sem VSync, com uma janela de teste externa já encerrada para evitar disputa de GPU. Depois da preparação: média de **15,73 ms por frame (~63,6 FPS)**, percentil 95 de 33,88 ms e maior frame de 78,34 ms, em 100 frames. Isso não é garantia de 60 FPS sustentados em todo o mapa.

A preparação antecipada levou **7,35 segundos**, distribuída em 279 frames; maior frame de **158,02 ms**, média de 26,20 ms. Ainda existem engasgos durante essa preparação. Recursos são solicitados antes da ponte; árvores, interiores e habitantes são construídos em etapas.

As duas regiões permanecem residentes para preservar estado. A região distante deixa de renderizar/processar e o tráfego distante para, mas isso **não descarrega integralmente as regiões da RAM**. Memória estática medida pelo Godot: 351 → 611 MiB; memória de vídeo: 495 → 672 MiB; working set do processo aproximadamente 1,29 GiB. Mais cidades exigirão descarregamento por setores e persistência de entidades além desta base de duas regiões.

## Evidências e referências

- Log de desempenho: `D:/geteco/continuous-stream-isolated.log`.
- Captura real da ponte: `D:/geteco/continuous-bridge-review.png`.
- Avião: `D:/geteco/mountain-plane-cutaway-review.png`.
- Loja: `D:/geteco/mountain-gunshop-interior-review.png`.
- Lenhadores: `D:/geteco/lumberjack-shelter-interior-review.png`.
- Relatórios: `VEHICLE_DAMAGE_CAMERA_2026-09-08.md`, `POLICE_PURSUIT_FIXES_2026-09-08.md`, `MOUNTAIN_PLANE_SHOP_2026-09-08.md`.

A campanha do boss 2 e a expansão para deserto/cidade seguinte continuam como trabalho futuro. A junção visual da ponte ainda comporta polimento adicional das calçadas e sinalização; a continuidade física e o tráfego foram validados.

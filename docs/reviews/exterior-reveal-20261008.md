# Visibilidade exterior de Dante — 2026-10-08

A câmera abre uma janela suave nos objetos que ficam entre ela e Dante. O raio chega a 4 m a pé e 7 m no carro, com antecipação na direção do movimento. O centro fica totalmente transparente para mostrar o personagem e o veículo reais. Colisões permanecem ativas. A janela é restaurada ao sair do caminho, trocar de câmera, bloquear a câmera ou descarregar a geometria.

O controlador `scripts/camera/ExteriorReveal.gd` seleciona geometria próxima por consultas físicas espaçadas, preserva materiais compartilhados e suporta materiais padrão com projeção triplanar e shaders espaciais compatíveis. Materiais com passes adicionais ou billboards permanecem com seus responsáveis. Não representa certificação de todos os objetos do mapa.

Na entrada do carro, os materiais originais são restaurados antes de preparar portas e interior. Na preparação dos edifícios de Harbor, cópias das peças do telhado recebem o material original, não a variante temporária da câmera. Uma cópia temporária herdada também pode ser recuperada pelo controlador. Essa correção elimina a camada opaca que ainda escondia Dante na imagem enviada pelo usuário. Nenhuma mudança de acesso, layout, colisão ou contagem de interiores foi feita.

## Validação

- Godot 4.7.2 .NET, Vulkan Mobile, RTX 4060 Laptop, cena Main real em 1280 × 720. `Harbor.csproj` compilado; inicialização confirma caminho nativo. Sessões isoladas com `--no-save`.
- `tests/test_exterior_reveal.gd`: 23 verificações, zero falhas. Inclui restauração, streaming, colisão preservada, materiais compartilhados, parâmetros animados e telhado derivado. Log: `evidence/exterior-reveal-derived-roof.log`.
- `tests/test_camera_rig.gd`: aprovado. Log: `evidence/exterior-reveal-camera-contract.log`.
- `tests/test_harbor_building_access.gd`: 755 verificações, zero falhas, catálogo de 59 lugares. Log: `evidence/exterior-reveal-access-validation.log`. Isso verifica o contrato físico/lógico; não aprova visualmente todos os interiores.
- Ponto exato do telhado MarketHall, Dante em `(109.375, -0.009167, 32.8875)`: capturas antes/depois em `evidence/railway-exterior-reveal-roof-fixed-harbor_north-57260-6756614/`. Inspeção visual confirma o corpo inteiro visível. A peça `ParcelDetail0` agora participa da abertura.
- Dante a pé e entrada real no carro sob o viaduto: seis capturas em `evidence/railway-exterior-reveal-body-visible-harbor_north-41792-7320530/`. Personagem e carro visíveis. Esse ensaio precede a correção final da cópia do telhado; a captura de prédio desse diretório ainda mostra o defeito e foi substituída pelo ensaio MarketHall acima.
- Sequência de 30 segundos com movimento, giro de câmera e transição para noite: 424 quadros no diretório `temporal` do ensaio do viaduto. Amostra visual de 12 quadros em `evidence/exterior-reveal-temporal-contact.jpg` mostra abertura e restauração durante giro. Amostragem não certifica ausência de flickering em todos os quadros ou iluminação de todo o mapa.
- `world/editing/world_edits.json` preservado: SHA256 `0A8B6AB760A486CB6CDE88256A1A8F489054E0508D7C7075D5E94699B55CB9B2`.

## Pendência

Performance não aprovada: falta comparação controlada de frame time antes/depois, sem outra sessão renderizada em paralelo. Havia preview do usuário ativo; ele não foi encerrado. FPS mostrado em captura e sequência com gravação de imagens não substituem esse benchmark. O runner permite `--reveal-benchmark` para uma execução posterior isolada. A cobertura visual atual é MarketHall e viaduto de Harbor; outros cenários não foram certificados.

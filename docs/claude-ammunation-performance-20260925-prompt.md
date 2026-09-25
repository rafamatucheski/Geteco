# Prompt para o Claude — próxima frente

Trabalhe no Geteco V2 em D:/geteco/game. Implemente uma correção para os travamentos de entrada e reentrada da Ammu-Nation. Trabalhe em paralelo com o Codex, respeitando a divisão abaixo. Não se limite a entregar uma análise.

Leia primeiro:
- D:/geteco/game/AGENTS.md
- D:/geteco/game/docs/video-review-20260924-fourth-batch.md
- D:/geteco/game/evidence/video-review-phase4-20260924/ammunation/phase4-ammo-handoff.md
- C:/Users/rafae/.agents/skills/testes-com-criterio/SKILL.md
- C:/Users/rafae/.codex/skills/performance-do-jogo/SKILL.md
- D:/geteco/game/docs/skills/padrao-interiores/SKILL.md e os contratos de interiores referenciados.

Estado conhecido: sua entrega anterior de catálogo/bancada já foi integrada. O Codex corrigiu scroll do foco, guarda-mato duplicado, encaixe da M4 e um detalhe flutuante da SMG; preservou as regras de compra. Também já existem caches limitados de malhas/materiais e agrupamento otimizado das armas. Preserve essas correções.

O diagnóstico renderizado mais recente registrou picos de 151,35 ms na primeira entrada e 114,78 ms na reentrada; a construção da arte consumiu 77,55/68,61 ms. São números diagnósticos, com outra partida aberta e população diferente entre coletas: não constituem benchmark isolado nem aprovação de FPS. Confirme o código atual antes de assumir a causa restante.

Sua frente reservada:
- D:/geteco/game/assets/regions/source/guns/ammunation/AmmunationArt.gd
- D:/geteco/game/assets/regions/source/scripts/player/ArsenalWeapon3D.gd
- D:/geteco/game/assets/regions/source/scripts/player/WeaponFinish3D.gd
- Novos helpers/recursos exclusivos da montagem da Ammu-Nation, testes com prefixo test_claude_ammo_perf_ e evidências em D:/geteco/game/evidence/claude-ammo-performance-20260925/.

Identifique o custo restante antes de otimizar. Instrumente construção, instanciação, inclusão na árvore e primeira utilização dos recursos conforme necessário. Avalie reutilização ou pré-compilação de recursos imutáveis, cache com ciclo de vida limitado e redução de trabalho síncrono repetido. Escolha pela evidência; não aplique todas as técnicas indiscriminadamente. Se transferir custo para o carregamento, meça e informe também essa etapa e o uso de memória.

Preserve geometria, materiais, vidro, peças móveis, customização independente, iluminação, NPCs, inventário e qualidade visual. Não esconda a travada aumentando fades, diminuindo resolução/população, removendo objetos ou alterando o limite de FPS.

Arquivos compartilhados ficam com o Codex: D:/geteco/game/runtime/FullSession.gd, D:/geteco/game/runtime/ProductionWorld.gd, D:/geteco/game/runtime/WeaponShopEntrance.gd, D:/geteco/game/world/places/NativePlace.gd, scripts de direção/veículos/câmera, física, tráfego, combate e acessos. A cópia D:/geteco/game/gameplay/WeaponFinish3D.gd também fica com o Codex. Não edite catálogo/bancada novamente neste lote. Se precisar de integração nesses arquivos, entregue o patch proposto no relatório, indicando ponto de chamada e contrato, enquanto completa o trabalho independente nos seus arquivos.

Use os testes existentes proporcionais à mudança: D:/geteco/game/tests/test_video_phase4_weapon_batch.gd, D:/geteco/game/tests/test_video_phase4_art_cache.gd e, se afetar a prévia, D:/geteco/game/tests/test_video_phase4_workbench.gd. Reutilize a instrumentação de D:/geteco/game/tests/measure/video_phase4_ammunation.gd. Não repita toda a suíte sem uma mudança ou hipótese que justifique.

Compare primeira entrada e reentrada na Main real, com mesmo save de teste, população, renderer, resolução, câmera e clima, mais uma janela estável de pelo menos 30 segundos. Registre p50/p95/p99, máximo, quantidade de quadros acima de 33,3/66,7 ms, ambiente e fotos reais antes/depois. Headless valida comportamento, não FPS. A meta provisória é 60 FPS/16,67 ms; melhoria parcial não equivale a aprovação.

Antes de medir GPU, confira processos e combine uma janela exclusiva com o Codex. Não execute benchmarks ou capturas simultâneos aos dele. Não encerre editor/jogo do usuário nem escreva no save pessoal. A autorização anterior para fechar a partida ainda não foi concedida; PIDs históricos não são autorização nem identidade atual de processo. Sem janela exclusiva, avance na análise e correção de CPU, mas deixe a aprovação de desempenho explicitamente pendente.

Execute git status antes de operações Git. Preserve todo trabalho local; não use checkout, restore, reset --hard, clean, descarte de stash ou sobrescrita integral para limpar alterações. Não faça commit. Releia os trechos antes de editar e sinalize mudanças concorrentes inesperadas.

Entregue código implementado, arquivos alterados, causa demonstrada, comparação antes/depois, testes com seus resultados reais, imagens, limitações e qualquer integração necessária em D:/geteco/game/docs/claude-ammo-performance-20260925.md. Não marque resolvido o que não foi comprovado.

O Codex cuidará da queda original do carro/streaming, dos próximos acessos e da validação de colisão/oclusão; essas frentes ficam fora da sua edição.

# Personalização de armas — lanterna

O sistema foi ampliado para a oficina de acessórios e acabamentos; consulte [arsenal-customization.md](arsenal-customization.md). As medições abaixo são da primeira etapa de lanterna e não certificam o conjunto novo. A compatibilidade atual inclui também Magnum, escopeta curta e lança-chamas.

No catálogo da Ammu-Nation, selecionar uma arma própria compatível e usar **Instalar lanterna • $350**. O kit pertence à arma: remover e reinstalar não cobra novamente. O botão **Facho** alterna entre concentrado (mais alcance) e aberto (mais largura). A peça aparece na arma e na prévia do catálogo, nas filiais do porto e da montanha.

Compatíveis: pistola, SMG, escopeta, AK-47, M4A1 e rifle de caça. G liga/desliga; o comando pode ser remapeado nos controles. A lanterna acompanha a orientação da arma, levanta a postura de mira e funciona sem munição. Trocar/guardar a arma, ocultar o jogador, entrar em diálogo, morrer e entrar na garagem apagam a luz. O save guarda compra, instalação e facho por arma; carregar começa com a luz apagada. Saves antigos continuam aceitos.

`WeaponCustomization.gd` concentra compatibilidade, normalização e peça 3D. `WeaponFlashlight.gd` mantém uma única luz 2D e uma textura compartilhada; não processa física enquanto apagada. Não adiciona geometria ou colisões aos interiores. Esta versão ilumina o canvas; não implementa sombras físicas novas para paredes, árvores ou interiores 3D.

## Validação

- `test_weapon_customization.gd`: catálogo real, compra, saldo insuficiente, compatibilidade, reinstalação grátis, modelos, eventos reais de G, repetição de tecla, remapeamento, morte, diálogo, troca, ocultação e save legado/atual/inválido. 24 verificações aprovadas; execução também renderizada e prévia inspecionada.
- `test_garage_weapon_restrictions.gd`: 30 verificações aprovadas, incluindo instalação, apagamento imediato, bloqueio de ativação e preservação do kit na saída, além da proteção de Maciota e do mecânico. Uma execução encerrou com código 1 antes de emitir casos; a execução seguinte, sem outro teste desta tarefa em paralelo e com log próprio, passou. Causa da interrupção não determinada; log final em `garage-final.log` na pasta de evidências.
- `test_ammunation_walkthrough.gd -- functional`: 27 verificações aprovadas de percurso das lojas e interação com o vendedor, incluindo três entradas/saídas no porto e a filial da montanha.

## Medições de 19/09/2026

Godot 4.7.2, Mobile/Vulkan, NVIDIA RTX 4060 Laptop, 1280×720, VSync e limitador desativados apenas nos processos de medição. Meta provisória: 60 FPS / 16,67 ms; aumentos acima de 5% em p95/p99 exigem confirmação. Saves dos diagnósticos isolados.

`measure_forest_flashlight.gd` usa MountainPass real, noite, clima sem tempestade, jogador em (5850, 540), tráfego e moradores ativos. Aquecimento de oito segundos; 30 segundos por estado, com três segundos de acomodação após cada troca. Não é uma rota contínua nem um teste de primeira ativação com cache de shaders vazio.

| Estado | Frames | FPS médio | p50 ms | p95 ms | p99 ms | Máximo ms | >33,3 / >66,7 ms |
|---|---:|---:|---:|---:|---:|---:|---:|
| Apagada | 4870 | 162,31 | 6,090 | 7,615 | 8,268 | 14,380 | 0 / 0 |
| Concentrado | 4639 | 154,62 | 6,394 | 7,679 | 8,188 | 11,033 | 0 / 0 |
| Aberto | 4662 | 155,40 | 6,349 | 7,616 | 8,173 | 11,577 | 0 / 0 |

No checkpoint noturno de HarborGame, o baseline anterior registrou 76,05 FPS, p95 18,557 ms e p99 41,478 ms. A primeira versão com lanterna registrou 84,91 FPS, p95 15,511 ms e p99 17,859 ms; houve um pico de 1483 ms durante o aquecimento. Causa não isolada. Esse comparativo precede o ajuste final da postura de mira e não comprova ganho de desempenho.

**Estado de performance:** amostras estáveis da floresta dentro da meta, sem regressão >5% nos percentis; certificação geral pendente. Havia outras sessões Godot no ambiente, sem controle de exclusividade, e falta medir primeira ativação a frio e repetir com configurações normais. Não atribuir variações globais de FPS exclusivamente à lanterna.

Evidências locais (JSON, CSV e capturas): `C:/Users/rafae/.codex/visualizations/2026/09/19/01a0bb59-dcd2-7151-9835-df98e996d9c4/`, subpastas `weapon-before`, `weapon-on` e `forest-flashlight`. Captura do catálogo: `%TEMP%/weapon-customization-catalog.png`.

O ambiente restrito emitiu avisos de acesso ao log e ao diretório padrão de saves antes de os testes redirecionarem seus saves. As cenas completas também emitiram avisos de recursos ainda vivos ao encerrar; esses avisos não equivalem a validação de descarregamento sem vazamentos.

# Geteco — base 3D independente

Projeto Godot separado para começar a construir e avaliar o Geteco em um mundo 3D compartilhado, visto de cima. Esta primeira versão é um trecho urbano jogável; não é uma migração do jogo completo nem prova de ganho sobre HarborGame.

## Abrir

- Dois cliques em **Jogar.cmd** para jogar.
- **Editar.cmd** abre este projeto no editor Godot.
- Também é possível importar o **project.godot desta pasta** no gerenciador do Godot e pressionar F5.
- Em outra instalação, use `Open.ps1 -GodotPath 'caminho/do/Godot.exe'` ou configure `GODOT_EXE`.

## Controles

| Ação | Controle |
|---|---|
| Caminhar | WASD ou setas, em relação à câmera |
| Correr | Shift |
| Aproximar / afastar | Roda do mouse |
| Girar a câmera | Q / E |
| Pausa, voltar ao início e sair | Esc |
| Entrar / sair do carro dourado | F, próximo da porta / com o carro parado |
| Acelerar / frear até engatar ré | W / S, dirigindo |
| Virar o volante | A / D, dirigindo |
| Frear | Espaço |
| Repetir o percurso concluído | R |
| Mostrar desempenho e população | F3 |
| Diminuir / aumentar população | [ / ], com o painel F3 aberto |

## Conteúdo

- Mundo 3D com uma câmera ortográfica principal, luz solar e sombras compartilhadas.
- Dante original, com malha e animações importadas, controlado por CharacterBody3D.
- Quatro quarteirões, cruzamento, ruas, calçadas, fachadas, árvores, bancos e postes.
- Oito carros estacionados com a geometria preparada original do cupê e seus materiais.
- Um cupê dourado dirigível, com aceleração, ré, freio, rodas animadas, luzes de freio e câmera antecipando o movimento.
- Entrada pela proximidade da porta e saída com verificação do corpo inteiro. Se um lado estiver bloqueado, tenta o outro; se ambos estiverem bloqueados, permanece no carro.
- Seis carros em duas rotas contínuas, freando diante de veículos, pedestres e sólidos.
- Um percurso de quatro paradas, com marca no chão e seta para o próximo ponto. Cada parada exige o carro ocupado, quase imóvel, durante um segundo.
- 24 moradores por padrão, com apresentação original do CivilianDriverModel e percursos físicos em volta dos quarteirões.
- Colisões nos edifícios, bases, bancos, vasos, postes, carros, caixa e limites do mapa.
- População ajustável até 96 para experimentação; não é promessa de desempenho universal.

As fachadas são volumes de estudo e não dão acesso a interiores. Apenas o carro dourado é dirigível. A condução usa física arcade, sem suspensão, dano ou áudio de motor. O tráfego usa rotas autoradas, ainda sem semáforos, trocas de faixa ou planejamento dinâmico. Missões e saves do jogo atual, combate, inventário, clima e carregamento de regiões não foram integrados. O percurso é uma atividade local deste protótipo. Os NPCs não executam a IA completa do jogo antigo.

## Isolamento

O arquivo `.gdignore` impede que o projeto pai importe esta pasta como parte do jogo atual. Este projeto tem seu próprio `project.godot`, cache `.godot`, cena principal e diretório de dados `GetecoWorld3D`. Não usa autoloads nem saves do Geteco atual. Não há referências `res://` para fora desta pasta, links simbólicos ou importações compartilhadas.

Os modelos foram copiados como uma fotografia do estado existente em 21/09/2026. Alterar o original não altera automaticamente esta base, e vice-versa. O personagem e o cupê conservam os arquivos binários originais. O adaptador dos moradores conserva sua construção visual, compartilhando recursos geométricos e materiais.

## Organização

| Arquivo | Responsabilidade |
|---|---|
| Main.tscn / scripts/World.gd | Cena, população, luz e interface |
| scripts/Street.gd | Geometria urbana estática agrupada e sólidos físicos |
| scripts/Actor.gd | Movimento 3D, colisões e animação |
| scripts/CameraRig.gd | Câmera ortográfica, seguimento interpolado, giro e zoom |
| scripts/Vehicle.gd / VehicleVisual.gd | Corpo 3D do veículo, condução, sensores, rodas e modelo compartilhado |
| scripts/Driving.gd | Entrada, saída, troca de controles, câmera e interface |
| scripts/Traffic.gd | Rotas e criação dos seis veículos de tráfego |
| scripts/RouteActivity.gd | Percurso de paradas, marcador e indicação do destino |
| assets/ | Cópias independentes dos modelos e adaptador visual |
| tests/ | Validação funcional, profundidade e medição |
| evidence/ | Capturas e resultados |

Não há SubViewport por pessoa ou carro, Sprite2D para apresentar modelos, ou física 2D. A geometria estática de mesma forma/material usa MultiMesh nesta pequena cena. Em uma cidade maior, o agrupamento deverá ser dividido por região para preservar o descarte fora da câmera.

## Validação

Na pasta deste projeto, usando o executável Godot 4.7.2:

```powershell
godot --headless --editor --import --quit
godot --headless --fixed-fps 60 --script res://tests/validate.gd
godot --headless --fixed-fps 60 --script res://tests/validate_driving.gd
godot --headless --fixed-fps 60 --script res://tests/validate_controls.gd
godot --script res://tests/visual_depth.gd
godot --script res://tests/capture_driving.gd
./tests/Measure.ps1
./tests/Measure.ps1 -Counts 96 -Prefix 'driving-' -Driving
```

`--fixed-fps` acelera apenas o roteiro funcional; seus números não medem desempenho. O teste renderizado fotografa o jogador na frente, atrás e ao lado da caixa, usando a imagem sem o ator e sem a caixa como controles.

A medição abre a cena real deste protótipo, move Dante por uma rota com colisões e mantém os pedestres ativos. Cada população (0, 24, 96) recebe cinco segundos de aquecimento e pelo menos trinta segundos de amostra. Registra intervalos reais entre frames, p50/p95/p99, máximo, quadros lentos e processos externos. Por padrão, recusa outra execução do jogo. `-AllowConcurrent` permite apenas uma leitura preliminar identificada como concorrente.

O objetivo inicial é 60 FPS na RTX 4060 Laptop, Mobile, 1280×720, MSAA 2×, VSync ligado. A matriz 0/24/96 avalia o acréscimo de população nesta cena, não a diferença entre motores ou entre o protótipo e o jogo completo. Consulte **SYSTEMS.md** para o comparativo antes/depois dos sistemas e **VALIDATION.md** para o registro histórico da primeira base.

## Próxima etapa

Experimentar a entrada e saída do carro, a direção no trânsito e as quatro paradas. Ajustar a sensação da condução a partir desse uso antes de ampliar sistemas. Comparar com o híbrido somente quando os trechos tiverem modelos, densidade, luz, resolução e comportamentos equivalentes.

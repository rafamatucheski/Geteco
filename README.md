# Geteco V2

Migração estruturada para um mundo 3D nativo no Godot. Projeto independente, com o jogo anterior e o protótipo preservados. Primeiro trecho: bairro, carro, tráfego, garagem original do Maciota, conversas, tarefa curta e salvamento próprio. Plano e limites: [MIGRATION.md](docs/MIGRATION.md).

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
| Trocar arma (a pé) / sintonizar rádio (dirigindo) | Roda do mouse |
| Girar a câmera exterior | Z / C |
| Entrar, sair, conversar, coletar e avançar diálogo | E |
| Salvar / carregar checkpoint | F5 / F9, fora do carro e diálogos |
| Pausa, voltar ao início e sair | Esc |
| Entrar / sair do carro dourado | F, próximo da porta / com o carro parado |
| Acelerar / frear até engatar ré | W / S, dirigindo |
| Virar o volante | A / D, dirigindo |
| Frear | Espaço |
| Repetir percurso experimental | R, somente iniciado com --sandbox |
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
- Garagem acessível ao noroeste, com oficina e escritório originais, Maciota e mecânico protegidos, câmera fixa e sólidos nativos.
- Tarefa inicial adaptada: falar com Maciota, conversar com o mecânico, pegar a peça ao lado da bancada e entregar. Autosave por etapa e transição.
- Percurso de quatro paradas preservado no modo experimental `--sandbox`.
- 24 moradores por padrão, com apresentação original do CivilianDriverModel e percursos físicos em volta dos quarteirões.
- Colisões nos edifícios, bases, bancos, vasos, postes, carros, caixa e limites do mapa.
- População ajustável até 96 para experimentação; não é promessa de desempenho universal.

Somente a garagem é acessível; os outros edifícios são volumes de estudo. Apenas o carro dourado é dirigível. Condução arcade, sem suspensão, dano ou áudio de motor. Tráfego em rotas autoradas, ainda sem semáforos ou planejamento dinâmico. Campanha completa, combate, interface de inventário, clima e carregamento de regiões continuam no plano de migração. A tarefa curta não substitui a missão de chegada original. O bloqueio de armas é um contrato testado para os futuros sistemas de combate, ainda inexistentes nesta V2.

## Isolamento

O arquivo `.gdignore` impede que o projeto pai importe esta pasta como parte do jogo atual. Projeto, cache e diretório de dados `GetecoV2` são próprios. O save mantém missão/inventário/localização por checkpoint, não posição exata nem estado do trânsito. Save inválido sem backup é preservado e bloqueia sobrescrita nessa sessão. Não usa autoloads nem saves V1. Não há referências de recursos para fora desta pasta.

Os modelos foram copiados como uma fotografia do estado existente em 21/09/2026. Alterar o original não altera automaticamente esta base, e vice-versa. O personagem e o cupê conservam os arquivos binários originais. O adaptador dos moradores conserva sua construção visual, compartilhando recursos geométricos e materiais.

## Organização

| Arquivo | Responsabilidade |
|---|---|
| Main.tscn / scripts/World.gd | Cena, população, luz e interface |
| scripts/Street.gd | Geometria urbana estática agrupada e sólidos físicos |
| scripts/Actor.gd | Movimento 3D, colisões e animação |
| scripts/CameraRig.gd | Câmera ortográfica, seguimento interpolado, giro e enquadramento automático da V1 (sem zoom manual) |
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
godot --headless --script res://tests/test_progression.gd
godot --headless --script res://tests/test_maciota_world.gd
godot --headless --script res://tests/test_v2_session.gd -- --no-save
godot --headless --fixed-fps 60 --script res://tests/validate_driving.gd -- --sandbox --no-save
godot --script res://tests/capture_v2.gd -- --no-save
./tests/Measure.ps1
./tests/Measure.ps1 -Counts 96 -Prefix 'driving-' -Driving
```

`--fixed-fps` acelera apenas o roteiro funcional; seus números não medem desempenho. O teste renderizado fotografa o jogador na frente, atrás e ao lado da caixa, usando a imagem sem o ator e sem a caixa como controles.

A medição abre a cena real deste protótipo, move Dante por uma rota com colisões e mantém os pedestres ativos. Cada população (0, 24, 96) recebe cinco segundos de aquecimento e pelo menos trinta segundos de amostra. Registra intervalos reais entre frames, p50/p95/p99, máximo, quadros lentos e processos externos. Por padrão, recusa outra execução do jogo. `-AllowConcurrent` permite apenas uma leitura preliminar identificada como concorrente.

O objetivo inicial é 60 FPS na RTX 4060 Laptop, Mobile, 1280×720, MSAA 2×, VSync ligado. A matriz 0/24/96 avalia o acréscimo de população nesta cena, não a diferença entre motores ou entre o protótipo e o jogo completo. Consulte **SYSTEMS.md** para o comparativo antes/depois dos sistemas e **VALIDATION.md** para o registro histórico da primeira base.

## Próxima etapa

Validar a sensação do trecho Maciota com o usuário e avançar para o bairro de referência conforme `docs/MIGRATION.md`. Documentos SYSTEMS.md e VALIDATION.md são históricos herdados do protótipo; resultados específicos desta V2 ficam em `docs/VALIDATION.md`.

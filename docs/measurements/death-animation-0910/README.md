# Animação de queda e sombra — 10/09/2026

Os personagens agora perdem o equilíbrio, articulam braços e pernas, caem e assentam no chão. Atropelamentos preservam o deslocamento físico, com uma pequena trajetória vertical visual e sem giro contínuo. A sombra fica fora do rig, horizontal no chão, e se alonga durante a queda. A câmera interna acompanha o corpo para não cortar cabeça ou mãos. A alta hospitalar restaura postura, sombra e câmera.

Implementação procedural compartilhada em `CharacterFallPresentation.gd`, aplicada a civis, policiais, paramédicos, bombeiros, funcionários do IML, moradores da montanha e motoristas retirados dos carros.

## Evidência visual

Capturas com renderização Vulkan, em uma cena de comparação ampliada:

- [Em pé](01_em_pe.png)
- [Perda de equilíbrio](02_perda_equilibrio.png)
- [Durante a queda](03_queda.png)
- [No chão](04_no_chao.png)

## Verificação

- `tests/test_character_fall_animation.gd`: 46 verificações aprovadas, em headless e com renderização real. Exercita sete tipos de personagem, pose intermediária, orientação da sombra, repouso, atropelamento leve e apresentação adiada.
- `tests/test_ambulance_hospital_routine.gd`: atendimento real, transporte, alta e restauração visual aprovados.
- `tests/test_police_fair_arrest.gd`: aprovado.
- `tests/test_pedestrian_render_lod.gd`: zero falhas; 120 solicitações próximas e 30 reduzidas.
- `tools/check_references.py`: nenhuma referência quebrada.

Os logs anexos registram avisos de objetos remanescentes no encerramento das cenas de teste. As capturas verificam os casos dessa cena; não substituem uma partida completa em todos os mapas. A queda é animada proceduralmente, sem simulação de ragdoll; não foram feitas medições de desempenho.

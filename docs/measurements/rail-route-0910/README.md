# Ligação ferroviária Porto–Serra

Circuito implementado em 10/09/2026, com a mesma locomotiva e os mesmos seis
vagões entre o porto e a região da montanha.

## Percurso

1. Viaduto existente do porto e sua descida sul.
2. Túnel de ligação até a entrada oeste da ponte ferroviária.
3. Ponte ferroviária paralela à ponte rodoviária, 360 unidades ao norte dela.
4. Túnel da encosta e saída no vale, ao sul da serraria.
5. Contorno sul da vila e leste da floresta, distante das casas e das estradas.
6. Subida pela encosta nevada até o túnel norte.
7. Retorno subterrâneo ao portal oeste do porto, fechando o circuito.

São os dois mapas existentes; o túnel norte fecha o retorno, sem simular a
existência de um terceiro mapa. O trem continua ambiental, sem embarque.

O circuito tem 49.766,6 unidades de mundo. A volta simulada levou 286,9 s
(aproximadamente 4min47s), usando o controlador normal: 105 unidades/s no
porto, 118 na serra e até 280 nos túneis longos. A aceleração subterrânea só
começa depois da entrada da cauda; a frenagem antecede a saída do túnel.

## Integração

- Uma curva canônica, um progresso e uma composição. O trem continua rodando
  durante o carregamento e enquanto a região distante está adormecida.
- Trilhos e símbolo do trem no minimapa, sem inserir a ferrovia no GPS de carros.
- Trechos elevados mantêm passagem por baixo, transparência localizada e som
  da primeira etapa. Cada vagão é ocultado individualmente nos portais.
- Pilares de apoio separados das estradas; reserva de 100 unidades para impedir
  que a geração de pinheiros ocupe o corredor ferroviário.
- Tabuleiros de até 640 unidades permitem descarte visual por trecho.
- MountainPass avulsa usa o mesmo circuito com o deslocamento de coordenadas
  adequado. A região carregada por ContinuousWorld reutiliza o trem do porto.

## Verificação

Godot 4.7.2. Capturas com Vulkan/Forward+ e RTX 4060.

| Verificação | Resultado |
|---|---|
| `test_harbor_train_3d.gd` | 0 falhas |
| `test_harbor_mountain_rail.gd` | 37 verificações, 0 falhas; volta inteira e identidade dos vagões |
| `capture_harbor_mountain_rail.gd` | 0 falhas; cena real, streaming, minimapa e 480 pinheiros fora da faixa |
| `test_harbor_safety.gd` | 0 falhas; ruas e descida continuam livres |
| `test_harbor_mountain_drive.gd` | Ida e volta físicas de carro: nenhuma falha |
| `test_opening_cutscene_runtime.gd` | 0 falhas |
| `test_pedestrian_life_routines.gd` | Aprovado |
| `test_pedestrian_render_lod.gd` | 0 falhas |
| Importação do editor | Concluída, sem erros de parse |
| `check_references.py` | Nenhuma referência quebrada nova |

O teste de segurança agora verifica a separação vertical correta para os dois
casos: viaduto acima da rua ou túnel abaixo dela. Continua rejeitando passagem
de nível e verificando fisicamente que a rua não foi bloqueada.

O perfil de carga real registrou `errors=0` no RoadSafety e `issues=0` no
BreakwaterAudit. Tempo total observado: 15.649 ms; 13.175 nós no mundo e zero
órfãos durante a medição. Não foi feita uma comparação controlada de desempenho
antes/depois; esses números não são uma promessa de FPS.

Pendências encontradas na suíte geral, fora dos testes específicos da ligação:

- `test_menu_flow_integration.gd`: uma falha na posição após carregar o save
  (1611,073; 900,073 contra 1600; 900, com tolerância de 10). Dinheiro, vida,
  armadura, troca de cena e os demais passos passaram. Não foi alterado o save.
- `test_mountain_pass_integration.gd`: quatro falhas nas expectativas de frio,
  aquecimento no veículo, traje térmico e elementos secretos do lago. Os
  setpieces, interiores, ponte e túnel rodoviário foram encontrados.
- Persistem mensagens de InputMap na inicialização de testes e avisos pontuais
  no encerramento. Não se afirma que toda a suíte do projeto esteja verde.

## Arquivos de revisão

- [Mapa do circuito](rota-porto-serra.png), extraído de [route.json](route.json).
- [Ponte ferroviária junto à rodoviária](01-ponte-ferroviaria.png).
- [Passagem pela serraria](02-serraria.png).
- [Curva no contorno da floresta](03-curva-da-floresta.png).
- [Encosta nevada](04-encosta-nevada.png).
- [Entrada no túnel norte](05-tunel-norte.png).

As capturas usam posições controladas para revisão visual. A volta completa
foi testada separadamente pelo controlador do trem, sem teletransportes;
o maior deslocamento entre passos simulados de 50 ms foi 14,441 unidades.

Para regenerar o mapa: executar `tests/test_harbor_mountain_rail.gd` e depois
`python tools/render_rail_route_map.py` (Pillow).

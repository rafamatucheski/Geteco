# Rodoviária Harbor — 10/09/2026

A cena de produção `world/harbor/HarborGame.tscn` monta o terminal em `ArrivalStop`, na posição (1700, 1060). O antigo abrigo foi substituído por uma construção nativa em 3D, projetada sobre o plano físico do jogo.

- Quatro plataformas cobertas e numeradas, com quatro ônibus rodoviários estacionados e colisões correspondentes.
- Bilheteria, lanchonete, letreiro, bancos, bagagens, faixa de pedestres e calçada.
- Plataforma 05 para o ônibus que circula pelo pátio. Percurso contínuo, pausa de sete segundos, portas e rodas animadas.
- Guarita com entrada e saída separadas. As cancelas abrem por aproximação e permanecem abertas durante a ocupação; o ônibus respeita pessoas e obstáculos.
- Onze viajantes e funcionário no mesmo espaço 3D da arquitetura, com oclusão pelos telhados. Os quatro passageiros do serviço de rua continuam sob seu controlador original.

O circuito adicional cruza os portais entre o recinto controlado e o acesso externo do pátio. A linha que circula pelas ruas do bairro usa o controlador `HarborTransitBus` existente.

A fonte, sua colisão e seu áudio foram deslocados juntos para o jardim em (1675, 1810). Os passeios do mercado contornam o novo terminal. O pilar do viaduto antes em (2050, 873) agora ocupa (2005, 873), na ilha central. A cobertura respeita a altura do viaduto e o letreiro fica à frente, visível sob a linha férrea.

## Validação

- `test_harbor_terminal_operations.gd -- --production`: aprovado na cena real, após as últimas alterações. Duas voltas, duas entradas, duas saídas, duas paradas, 11 pessoas, 700 amostras do volume do ônibus contra a geometria. Verifica cancelas fechadas, ausência de saltos, parada diante de obstáculo e retomada. Resultado: zero falhas; 1286,25 unidades percorridas.
- `capture_harbor_rodoviaria.gd`: aprovado em Vulkan/Forward+. Desembarque de Dante, chegada à posição inicial, embarque/desembarque de passageiros e passagem do ônibus pela cancela de saída. Resultado: zero falhas.
- `test_harbor_terminal.gd -- --initial-only`: aprovado.
- Auditoria de construção emitida pela cena real: 50 edifícios, 49 acessos, zero problemas; auditoria viária: zero erros.
- `git diff --check` dos arquivos alterados: aprovado.

O teste longo `test_harbor_terminal.gd` da linha de rua não concluiu o retorno dentro de 180 segundos: percorreu aproximadamente 1007 unidades, embarcou/desembarcou duas pessoas e partiu uma vez. Falharam as três asserções sobre retorno, segunda troca de passageiros e passagem pelas quatro ruas. Isso permanece uma limitação verificada da linha de rua, distinta do circuito do novo pátio, aprovado acima.

A auditoria ampla `test_harbor_district.gd` também apresentou nove falhas em acessos de outras regiões/saída da garagem. Os registros estão preservados para análise; não são apresentados como uma aprovação geral do mapa.

## Evidências

Diretório: `D:/geteco/artifacts/rodoviaria-3d-0910/`.

- `01_rodoviaria_no_jogo.png`: câmera de jogo e HUD.
- `02_terminal_completo.png`: visão geral sem HUD.
- `03_plataformas_onibus_parados.png`: plataformas e ônibus estacionados.
- `04_guarita_circulacao.png`: guarita e circuito.
- `05_onibus_saindo.png`: saída física com cancela aberta.
- `operations-production-final.log`, `capture-final.log`, `service-complete.log`: resultados completos.

Para reproduzir, executar o Godot com `--path D:/geteco/game --script res://tests/test_harbor_terminal_operations.gd -- --production`; acrescentar `--headless` para o teste comportamental. As capturas exigem renderização gráfica. Os testes desta alteração usaram um diretório APPDATA de teste separado das configurações pessoais.

## Variação de passageiros e rotinas

`HarborTerminalPassengerService.gd` agora realiza a troca física pela porta do ônibus da plataforma 05. Primeiro desembarcam os passageiros; depois embarca a fila. O ônibus permanece parado e com as portas abertas até o último passageiro concluir. Pessoas embarcadas ficam sem modelo visível e sem colisão no pátio.

As duas primeiras viagens têm demanda de 2 embarques/5 desembarques e 5 embarques/2 desembarques. As seguintes sorteiam de 1 a 5 por sentido, limitadas às pessoas disponíveis e à ocupação real. A população do serviço é um conjunto fixo de 12 viajantes, somado às 11 figuras do terminal; não cresce a cada volta. Aparências, velocidades, intervalo entre pessoas e pausas são variados. As duas pessoas que passeiam pela calçada agora escolhem destinos e pausas individuais.

As filas e rotas de pedestres contornam ônibus estacionados, pilares e o volume varrido pelo ônibus nas curvas. Uma pessoa obstruindo a porta impede a liberação do embarque ou a conclusão da parada.

Validação adicional aprovada:

- `test_harbor_terminal_operations.gd -- --variety`: quatro voltas completas, trocas 2/5, 5/2, 2/3 e 3/1, todas realizadas com portas abertas e ônibus parado; ocupação conservada e áreas de espera sem colisões. Zero falhas.
- `test_harbor_terminal_operations.gd -- --production`: duas voltas no mapa real, sete embarques e sete desembarques. Paradas de 18,9 e 32,5 segundos nesta execução. Zero falhas.
- Registros: `passengers-four-trips.log` e `passengers-production.log` no diretório de evidências.
- Capturas adicionais com `capture_harbor_rodoviaria.gd -- --passengers`: `06_pessoas_desembarcando.png` e `07_pessoas_embarcando.png`.

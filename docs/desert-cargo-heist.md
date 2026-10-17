# Cargas da madrugada no deserto

Atividade integrada em `runtime/desert/DesertRuntime.gd`, com implementação em
`gameplay/desert_heist/`. Duas cargas por madrugada, com saídas entre 00:00 e 05:00.
Somente um caminhão e seus dois seguranças ficam instanciados por vez.

O caminhão percorre a rodovia do sal, de oeste para leste. Dano, disparos próximos,
bloqueio ou tentativa de roubo provocam a interceptação. Dois seguranças desembarcam
com espingarda calibre 12 e proteção balística consumível. O jogador pode enfrentá-los
ou tomar o veículo e escapar. O embarque usa o sistema normal de direção.

Após o roubo, o objetivo aponta a desova ao sul da rodovia, em (-650, 0, -1510).
Estacione, desembarque e vá até a traseira. A escolta precisa estar morta ou distante.
`Abrir contêiner` movimenta as portas e revela a carga; `Recolher carga` paga R$ 4.500
ou R$ 7.200 conforme o carregamento. Recibos da economia impedem pagamento duplicado.

O estado preserva posição e saúde do caminhão, fase da carga, saúde/colete/posição
dos dois guardas e identidade do carregamento. O veículo selecionado restaurado é
adotado pela atividade, evitando criar uma segunda cópia.

## Arte e custo

Cabine longa, três eixos, grade, espelhos, tanques, escapamentos, contêiner corrugado,
portas traseiras e caixas sobre pallets. Geometria agrupada por acabamento e template
compartilhado. O modelo é preparado durante a configuração da sessão; não cria luzes
dinâmicas próprias. Os faróis usam a infraestrutura existente dos veículos.

`GETECO_DESERT_CARGO_HEIST=0` desativa a atividade para comparação A/B no mesmo build.
O custo e a qualidade visual precisam ser avaliados na cena renderizada; a preparação
da malha, sozinha, não comprova ausência de travadas na primeira aparição.

## Verificações

- `tests/test_desert_cargo_heist.gd`: janela de horário, snapshots e recibos.
- `tests/test_desert_cargo_heist_session.gd`: integração Main/.NET em save isolado;
  inclui reposicionamento explícito até a desova, portanto não certifica o percurso inteiro.
- `tests/capture/capture_desert_cargo_truck.gd`: vistas do modelo, incluindo carga aberta.
- `tests/measure/measure_desert_cargo_heist.gd`: diagnóstico renderizado de circulação,
  combate e afastamento; não equivale a benchmark release.
- `runtime/ReleaseBenchmark.gd`: rota `carga_deserto`, com contagem de atividade observada.

Todos os comandos Godot passam por `tools/run_godot_locked.sh`. Compile
`Harbor.csproj` antes de executar. Para o benchmark release, use a mesma exportação
com a atividade desligada/ligada, `--no-save --benchmark --benchmark-route=carga_deserto
--play-at=desert,-700,-1542.5 --benchmark-hour=1` e rótulos diferentes. Exija caminhão
efetivamente observado no relatório da rodada ligada.

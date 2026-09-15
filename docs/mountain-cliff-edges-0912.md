# Bordas da serra — 12/09/2026

A estrada agora tem uma borda irregular ligada à sua curva nos cinco trechos de penhasco. A face de rocha perde contraste em névoa azulada, com árvores pequenas na base. As defensas mantêm os ápices e abrem as aproximações; as placas foram aproximadas do acostamento. As aberturas cadastradas na estrada e as reservas da vila são consideradas na geração.

MountainCliffEdges usa geometria estática e um Area2D com polígonos compartilhados com o desenho. Só verifica posições enquanto pessoas/veículos estão sobrepondo o sensor. A queda começa quando o centro cruza a borda, não quando a lateral do carro apenas encosta. A descida dura 0,85 s, suspende controles durante a animação e encaminha o impacto para os fluxos existentes de dano e hospital. O projeto continua usando física 2D; o desnível é representado pela apresentação e pela zona de queda.

Validação: `tests/test_mountain_cliff_edges.gd` passou 14 checks, incluindo Dante e Summit SUV reais, descida antes do impacto, não disparar na pista, não disparar por sobreposição da carroceria, dano único, liberação do motorista e recuperação dos controles no hospital. Executado headless e com Vulkan Mobile. O teste isolado emite aviso de ausência do diretor de bombeiros ao destruir o SUV; ele não monta o distrito completo. `git diff --check` passou nos arquivos existentes alterados.

Capturas integradas e amostras: `D:/geteco/artifacts/mountain-cliffs-0912/`. Capturas finais: `final-250.png` e `final-2050.png`; testes em `test-rendered.log`; execução integrada em `final.log`. A execução integrada final não apresentou erros de script; houve avisos de interpolação da cachoeira e da câmera.

Performance **não aprovada**. Alvo provisório: 60 FPS / 16,67 ms; sinal de investigação: regressão superior a 5% em p95/p99. Ambiente: Godot 4.7.2, Vulkan Mobile, RTX 4060 Laptop, 1280×720, VSync desligado, limite 60. HarborGame com região da montanha carregada, população e sistemas da cena, 120 quadros de aquecimento e 30 segundos por ponto. JSONs preservam todas as amostras reais entre quadros.

| Cenário | FPS médio | p50 ms | p95 ms | p99 ms | Máximo ms | >33,3 ms | >66,7 ms |
|---|---:|---:|---:|---:|---:|---:|---:|
| Curva baixa, antes | 9,38 | 102,08 | 179,69 | 235,17 | 306,79 | 278 | 230 |
| Curva baixa, final | 41,26 | 20,72 | 40,07 | 51,36 | 64,78 | 192 | 0 |
| Curva nevada, antes | 6,37 | 154,20 | 225,92 | 264,88 | 267,01 | 191 | 191 |
| Curva nevada, final | 32,63 | 30,10 | 48,36 | 63,93 | 91,29 | 311 | 7 |

Estes números são diagnósticos, **não uma comparação causal válida**: a execução inicial repetia erros de `HarborClinicInterior.open_amount`, houve alterações externas no workspace durante a tarefa e outros processos Godot estavam abertos. Uma tentativa posterior encontrou erro de compilação da caverna; uma nova execução foi possível após correção externa desse arquivo. Nenhum desses componentes foi corrigido nesta tarefa. Não se atribui a diferença de FPS às bordas. A meta absoluta não foi atingida; falta comparação em ambiente estável para certificar o custo incremental. Não houve separação CPU/GPU nem medição dedicada de primeira visita.

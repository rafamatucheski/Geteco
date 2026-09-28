# Correção espacial do percurso — 25/09/2026

Implementação por um agente. O usuário reservou os testes para si e autorizou explicitamente a integração em arquivos com alterações concorrentes. Não houve descarte, checkout, restore, reset ou commit.

## Alterações

- `MountainRouteGeometry.gd`: geometria das bordas e recortes reais nas junções. Superfícies respeitam a precedência estrada principal → ramais → caminhos; os acostamentos são recortados contra todos os corredores. Recortes calculados na construção, sem novo processamento por frame.
- `MountainRouteLayout.gd`: ramais de asfalto com 5 m, ligação pelo centro da estrada, acesso à loja de armas pelo lado livre da fachada, retorno circular próximo ao heliporto e segundo acesso da vila aproveitando seu corredor já reservado.
- Caminhos de pedestres conectam loja/chalé florestais, heliporto, bunker, teleférico e boutique. Participam da reserva de terreno e do minimapa, mas não do grafo de tráfego.
- O ramal asfaltado da caverna foi substituído por trilha de 1,6 m, desviando pela lateral oeste até a margem seca. A entrada, o retorno, o interior e a recompensa conservam suas definições existentes. Rochas com colisão e três pinheiros formam cobertura na aproximação direta antiga.
- A plataforma do teleférico voltada ao percurso recebe apoio físico e rampa de 2,2 m, correspondentes à geometria visível. A outra estação mantém sua apresentação existente.
- As superfícies da montanha passam a compartilhar contorno visual e físico, com suporte nivelado ao terreno. O material, UV, transição de largura da ponte e cache multirregional do minimapa adicionados pela outra sessão foram preservados.
- A floresta é gerada com as reservas antigas antes do ajuste: apenas árvores dentro dos novos corredores são removidas, sem redistribuir as demais. Sem placas, textos decorativos, novas luzes ou novos efeitos animados.

## Validação e evidências

Revisão de código e checagem de sintaxe com Godot `--headless --check-only --script`; isso não executa o percurso e não certifica comportamento ou desempenho. Os testes de gameplay, renderização e performance ficam com o usuário, conforme solicitado.

Pendentes: caminhada e direção nas conexões, colisão varrida com corpos reais, oclusão com controle positivo, entradas/retornos, inspeção do minimapa e capturas reais antes/depois. Nenhuma captura nova foi produzida e os vídeos citados não estavam anexados nesta tarefa; as correções foram localizadas pelo código e pelas coordenadas do projeto.

Performance não medida. O custo adicional fica na preparação das rotas, recorte de superfícies por chunk e geometria estática local. Há mais segmentos no retorno e nos acessos; não se afirma ausência de regressão. Meta provisória para a futura medição: 60 FPS / 16,67 ms, mesma cena, rota, máquina, câmera, população e condições antes/depois.

Contagem de interiores permanece em 32 acessos físicos / 30 interiores distintos existentes, sem nova certificação integral.

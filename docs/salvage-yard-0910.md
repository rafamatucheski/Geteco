# Ferro-Velho do Neco

> Registro da primeira implementação. A localização, colisões e apresentação foram revisadas em [neco-geometry-0910.md](neco-geometry-0910.md); consulte esse documento para o estado atual.

O desmanche agora ocupa um pátio rural próprio, com chão de serviço, gramado, recepção, guindaste e prensa 3D, contêineres, barris, pneus, motores e oito carcaças coloridas com tetos cortados e peças soltas. A entrega acontece no mundo: baixar o eletroímã, pegar o veículo, levantar, transportar, soltar na prensa, esmagar e pagar. A câmera acompanha o pátio sem trocar de cena.

## Como jogar

- Siga o indicador **NECO / SUCATA**. No Harbor, o minimapa também mostra **N** e a estrada particular.
- Estacione na baia **ENTREGA**, saia e fale com Neco usando **E**.
- Confirme o nome do veículo e o preço no botão de entrega. O dinheiro é creditado somente depois da animação.
- São seis entregas por dia, contando encomendas especiais. O Harbor usa o dia já existente da campanha, incluindo descanso; o mapa legado usa dias de dez minutos jogáveis. Pausar e recarregar não renovam a cota.
- Neco oferece até três encomendas por dia, uma ativa por vez. O carro solicitado recebe um marcador próprio e um destino no GPS. Prazo: 2m30. Recompensa: $2400. Um carro diferente rende apenas a sucata normal.
- Prazo vencido, alvo destruído, morte ou prisão encerram a encomenda. A Monaliza, motos e veículos dos grupos de missão/emergência não são recebidos.

## Mapa e carregamento

Harbor: centro do pátio em `(-2250, 350)`, acesso pela Memorial North em `(-1250, 1250)`, com abertura de 120 px no limite norte do antigo terreno do cemitério. Legado: centro em `(-2150, -1150)`, estrada ligada à avenida central em `(870, 100)`. Os pontos, o gramado e a retomada segura ficam em `world/shared/salvage/SalvageLocation.gd`.

O gatilho antigo disparava para qualquer veículo, inclusive durante a criação do mundo. Sobreposições agora não produzem efeito. Saves dentro do pátio retomam no acesso externo; posições no antigo desmanche são migradas para um ponto seguro do respectivo mapa. Saves originais não são regravados pela migração. Salvar durante a operação da prensa é bloqueado para não gravar uma transação incompleta.

`CampaignState.salvage_state` armazena cota, dia, encomenda e prazo no formato de save existente. `RegionTravel` conserva o identificador da encomenda ao salvar um veículo conduzido. Ao restaurar o mundo, o alvo é localizado ou reconstruído a partir do estado salvo.

## Verificação

Evidências em `D:/geteco/artifacts/salvage-yard-0910/`:

- `legacy-final.log`: 32 verificações, zero falhas.
- `harbor-final-roundtrip.log`: 42 verificações, zero falhas, incluindo gravação/leitura real e substituição da cena.
- `roundtrip.log`: save/load completo também aprovado no mapa legado.
- `render-final.log`: animação e interface executadas em Vulkan / Forward+, 32 verificações, zero falhas.
- `coordinate-regression.log` e `save-gate-regression.log`: regressões existentes de coordenadas e regras de gravação aprovadas.
- O teste percorre o corredor de acesso nos dois mapas com consultas de colisão para um veículo de 78 × 38 px. Também verifica sobreposição durante o load, proteção da Monaliza, confirmação duplicada, pagamento tardio, cota diária, expiração e preservação de progresso.
- Capturas `01_patio_harbor.png`, `02_neco_harbor.png` e `03_*_harbor.png` mostram a área, a conversa e as etapas do guindaste/prensa.

Os testes usam APPDATA isolado. Persistem avisos anteriores de câmera e instâncias retidas ao encerrar mundos completos; não houve erro de script nas execuções finais. As verificações não substituem uma auditoria geral do tráfego ou de desempenho do projeto.

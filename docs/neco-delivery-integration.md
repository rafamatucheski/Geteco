# Entrega do Porto Rosso na prensa

Integração de 21/09/2026. GarageRewards inicia NecoPressDelivery; a recompensa de R$ 50.000 e a cota diária só são alteradas depois da apresentação concluída e da confirmação das condições de entrega. O recibo econômico existente continua sendo a autoridade para pagamento único.

O adaptador copia somente as malhas visíveis e seus materiais, preservando dimensões e recusando modelos maiores que a cama. Nenhum script, corpo físico ou equipamento do veículo é duplicado. O carro original fica oculto e reservado fisicamente na baia durante a apresentação; cancelamento restaura visibilidade, processamento e interação. O som hidráulico é o original de cars/salvage/SalvageAudio.gd.

Carregar save, trocar região, morrer ou descarregar a prensa cancela a entrega sem pagamento. Um save feito durante a apresentação conserva o veículo como não entregue; nenhum estado transitório de animação é persistido. A entrega de reboque para reparo permanece independente.

## Evidência

`tests/test_garage_rewards.gd`: PASS, 47 verificações. Log: `evidence/neco-delivery-test.log`. Inclui recusa de área ocupada, cancelamento, descarregamento da prensa, reinício, snapshot durante animação, conclusão, pagamento único e limite diário. Usa o componente real da prensa e o modelo original do Porto Rosso, com sessão e controlador de cenário de teste. Não comprova o fluxo completo de Harbor.

A importação completa encontrou erro de inferência em `gameplay/dispatch/overtaking/OvertakePlanner.gd:110`, variável `gap`; pasta sob edição do Claude, preservada pelo integrador. Evidência: `evidence/neco-import.log`. Revisão visual no mapa, áudio ouvido em jogo e comparação de frame time permanecem pendentes. Custo novo limitado a uma cópia temporária de malhas, um emissor de áudio e a consulta de segurança durante os 3,55 segundos da sequência; isso não constitui medição de performance.

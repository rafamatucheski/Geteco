# Revisão da validação externa — 2026-09-06

Escopo: leitura de `tests/test_harbor_real_flow_10steps.gd` e comparação com as APIs atuais. O script externo não foi editado. Os pontos abaixo são limitações do teste, **não bugs de produção comprovados**.

## Achados e critérios mínimos

- **Cena e onboarding (linhas 42–44):** adiciona HarborGame sem definir `current_scene`; aguarda apenas 20 frames, sem concluir/pular a CGI e atender o telefone. Definir a cena corrente e aguardar o estado jogável verdadeiro antes dos movimentos. Se for uma fixture de garagem, declarar explicitamente o preparo e não chamar de campanha completa.
- **Direção (linha 342):** o piloto assume frente `-car.transform.y`, enquanto PlayerCar usa `transform.x`. Usar o mesmo eixo do veículo e comprovar deslocamento contínuo com controles reais, sem corrigir posições ao longo do trajeto.
- **Conversa (linha 137):** fechar com Escape não comprova conclusão da conversa. Observar `conversation_completed` e a flag de progresso, distinguindo cancelamento de conclusão.
- **Quadro (linhas 147–171):** força desbloqueio e substitui as missões reais por `test_mission_available`/`test_mission_locked`. Isso pode testar um componente, mas não a integração com a campanha. Validar uma missão autorada disponível e outra realmente bloqueada pelo estado da campanha, sem reconfigurar o quadro.
- **Seleção bloqueada (linhas 185–190):** a ausência de um Button entre os filhos diretos não prova que a missão é inacessível pela interface. Verificar a árvore efetiva, a interação nativa e a ausência de mudança de missão/recompensa.
- **Save/load (linhas 239–247):** `save_game(slot, summary)` tem assinatura correta. Entretanto, `load_game()` apenas prepara os dados pendentes: o teste não aplica o save/recria a cena nem verifica saúde, veículo e interior restaurados. Executar a rota real de carregamento e comparar os estados restaurados.
- **Isolamento (linhas 238–256):** usa nome fixo de slot e depois apaga o arquivo. Executar com `user://` isolado, sem sobrescrever um slot pré-existente; limpar também o estado pendente entre fixtures.
- **Respawn (linha 293):** chamar `_respawn_at_hospital()` diretamente não valida morte, temporização, liberação do veículo ou recuperação dos controles. Provocar dano letal e observar o ciclo real até o hospital.

## Evidência separada já obtida nesta etapa

- `test_harbor_lofts_courtyard.gd`: quatro movimentos do Player real atravessam o pátio; as duas alas continuam bloqueando. Zero falhas.
- `test_harbor_finish_lamps.gd`: execução final com 17 postes dos três providers, sem duplicatas, dentro de seus respectivos bairros, fora das pistas/prédios/acessos e vinculados ao sinal real de dia/noite. Zero falhas, exit 0.
- `test_harbor_district.gd`: 50 prédios, 46 acessos, 2.391 amostras físicas de pista; zero falhas.
- `test_harbor_alleys.gd`: 148 amostras do shape real, 12 movimentos do Player e dois trechos sob viaduto; zero falhas.
- `test_harbor_entrances.gd`: nove portas exercitadas, nove animações de abertura/fechamento e sete portas habilitadas verificadas; zero falhas.

Esses resultados cobrem seus respectivos contratos. Não substituem uma execução válida da campanha completa nem autorizam a afirmação “10/10 etapas de jogo real” para o script externo.

## Capturas de acabamento da etapa 2

Geradas com renderização Compatibility real e inspecionadas: postes acendem à noite e apagam de dia, letreiros de chão removidos em East/North, pátio visual do Lofts preservado. O teste físico separado comprova sua travessia; uma imagem sozinha não comprova colisão.

- [Lofts — dia](D:/geteco/harbor-stage2-lofts-day.png) / [noite](D:/geteco/harbor-stage2-lofts-night.png)
- [East — dia](D:/geteco/harbor-stage2-east-day.png) / [noite](D:/geteco/harbor-stage2-east-night.png)
- [North — dia](D:/geteco/harbor-stage2-north-day.png) / [noite](D:/geteco/harbor-stage2-north-night.png)

Ainda é perceptível a repetição de massas de prédios/vegetação; não foi incluída decoração nova nesta etapa. Avisos ambientais de logs/certificados e preparação de `user://saves` apareceram na captura, sem impedir os seis PNGs ou gerar falha de script. Nenhuma conclusão de desempenho/FPS é derivada destas imagens.

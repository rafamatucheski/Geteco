# Controles e layout DualSense

Abra **Configurações → Controles** no menu principal ou na pausa.

- **Símbolos do controle:** Automático, DualSense / PlayStation ou Xbox. A escolha
  manual permite ver os símbolos PlayStation mesmo com identificação genérica.
- **Mapa do controle:** alterna entre a pé e veículo. As legendas usam as
  atribuições atuais; a lista abaixo contém também os demais comandos.
- **Personalizar:** leva diretamente à lista de teclado, mouse e controle.
- Selecione a célula desejada e pressione a nova tecla, botão, gatilho ou direção
  do analógico esquerdo. O analógico direito continua dedicado a apontar a mira.
- Durante a captura, Esc ou Options/Menu cancela. Delete/Backspace limpa a
  atribuição; a coluna do controle também possui um botão **−** para limpar.
- Conflitos retiram a atribuição da outra ação e mostram quais ações mudaram.
  Pares já compartilhados pelo jogo, como entrar/sair do veículo, são preservados.
- **Salvar** mantém a configuração entre sessões. **Cancelar** restaura a
  configuração que estava ativa ao abrir a tela. **Padrões da aba** restaura
  teclado, mouse, controle e detecção automática; salve para manter a restauração.

## Referência do padrão DualSense

| Comando | A pé | Veículo |
| --- | --- | --- |
| Analógico esquerdo | Mover | Dirigir |
| Analógico direito | Apontar a mira | Apontar a mira |
| L3 | Alternar corrida | — |
| L2 | Mirar | Frear / ré |
| R2 | Atacar / disparar | Acelerar |
| Quadrado | Ação / recarregar | — |
| Triângulo | Entrar no veículo | Sair do veículo |
| Cruz | — | Freio de mão |
| Círculo | — | Canhão do tanque |
| L1 / R1 | Arma anterior / próxima | Rádio anterior / próxima |
| R3 | — | Buzina / sirene |
| Direcional esquerdo | Inventário | Inventário |
| Direcional baixo | Mãos livres / porta-malas | Porta-malas |
| Direcional cima | — | Faróis |
| Create | Diário | Diário |
| Touchpad | Mapa / GPS | Mapa / GPS |
| Options | Pausa | Pausa |

Nos menus, Cruz/A confirma, Círculo/B volta e o direcional ou analógico esquerdo
navega. A navegação dos menus e Options/Menu permanecem disponíveis após remapear.

## Implementação e evidência

`GameInput` mantém teclado/mouse e controle em conjuntos independentes. O arquivo
`user://settings.cfg` armazena `controls.bindings`, `controls.gamepad_bindings` e
`controls.controller_layout`. Configurações anteriores sem a seção do controle
conservam seu padrão. As dicas no jogo consultam o InputMap atual; a corrida
também respeita seu novo botão. O desenho só é redesenhado por mudança de
configuração, dispositivo ou tamanho, sem um loop de atualização por frame.

Capturas da interface real, sem gravar preferências:

- `C:/Users/rafae/.codex/visualizations/2026/09/28/01a0e984-2604-7161-a752-4b6467689cce/dualsense-controls.png`
- `C:/Users/rafae/.codex/visualizations/2026/09/28/01a0e984-2604-7161-a752-4b6467689cce/dualsense-bindings.png`

Abertura e captura concluídas sem erros no log. Testes funcionais e benchmark
não foram executados nesta alteração. Não havia controle conectado na captura;
a conferência física por USB/Bluetooth e do remapeamento no aparelho permanece
pendente. A captura da tela não certifica desempenho do jogo.

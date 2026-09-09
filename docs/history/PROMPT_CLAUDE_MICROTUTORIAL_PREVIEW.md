# Claude Code — catálogo isolado de microtutoriais

Leia prototypes/loadout/index.html: é uma prévia interativa da Astra, sem integração ao save real. Crie um catálogo PT/EN e um apresentador Godot isolado para dicas contextuais discretas: primeiro porta-malas, capacidade do loadout, abrigo do frio, loja térmica, túnel, item raro e busca policial fora de uma casa.

Trabalhe exclusivamente em ui/tutorial_preview/ e tests/test_tutorial_preview.gd. API proposta: request_hint(id), dismiss_hint(), reset_preview(). Uma dica por vez, sem interromper o jogo, sem repetição durante a sessão, duração limitada e tecla dispensar configurável. Não exibir dicas em modal, combate ou direção veloz: permita que o chamador informe esses estados. Use textos curtos e controles recebidos por parâmetro, sem inventar teclas oficiais.

Não edite Player.gd, SaveManager.gd, Localization.gd, HUD, PauseMenu, MountainExpedition, áudio, trânsito, pontes, streaming ou prototypes/loadout/. A Astra fará a integração futura e a persistência. Crie demonstração independente, teste fila, bloqueio, dispensa e repetição, capture no Godot e finalize o processo de teste. Relate claramente o que foi executado. Não faça commit/reset nem desligue o computador.

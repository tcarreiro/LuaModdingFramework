# Consumer Demo — LuaModdingFramework

Cena: `res://example/consumer/consumer.tscn`. A `PremadeGallery` permanece independente.

## Estrutura

- `pages/main_menu.lua`: **primeiro script executado**, define todos os estilos (por `UI.define_style`) e monta a tela inicial. Os outros `pages/*.lua` são executados **em ordem alfabética**, no `ContentState` do `core`. Todos os templates foram definidos com `UI.define_component`.
- `consumer_catalog.gd`: registra premades, procura os scripts Lua e os executa como core, finaliza estilos e componentes; usa o `ModManager` e o `SettingsLoader` reais.
- `consumer.gd`: aplicativo consumidor. Navegação, eventos, UI reativa, dependências, gerenciamento do modal único, controles e integração com `RuntimeManager`.
- `consumer_store.gd`: preferências reativas em memória e arquivos JSON `.save` persistidos em `user://consumer/saves/slot_N.save` (N=1..3).
- `mods/`: core e dois mods opcionais; `relics` exige `ambient`. Os `settings.json` são carregados pela API existente; `ambient/settings-updates.lua` também altera as opções de `core:difficulty`, mantendo o setting na aba Core. Seus `control.lua` exercitam `script.on_init`, `script.on_load` e `storage`.
- `assets/logo.png`: conceito original da marca, PNG transparente; ícones de inventário e lixeira na mesma pasta. Os assets são replicados em `mods/core/assets/` porque `ModAssetRegistry` resolve recursos via `<mod-id>:<arquivo>`.
- `world/world.tscn`: cena-base 3D **sem personagem**, deliberadamente simples para você substituir. A HUD é instanciada a partir do template `core:game-hud` do Lua.

## Fluxo

Menu → Opções / Escolher save → modal único (Ação → Mods ou Settings) → Runtime Stage → Mundo 3D, com HUD. No jogo `ui_inventory` abre/fecha os 28 slots; `ui_cancel` fecha um modal ou abre/fecha Pausa. Pausa → Salvar persiste conteúdo e `RuntimeManager.snapshot_storage()`. A tela de load restaura configurações anteriores e usa padrões para novos mods.

## Limites atuais do framework / demo

1. O framework **não disponibiliza execução de telas Lua arbitrárias no Runtime como scripts de navegação**; este exemplo as compila como *templates declarativos* durante o Content Stage, e o consumidor GDScript controla navegação e reatividade. Não adiciona uma API falsa de Lua runtime.
2. O `UIContentRegistration` tem limite de 64 nós por template e não fornece slots declarados pelo próprio template. Por isso os painéis e widgets são templates Lua pequenos, e listas de mods, settings e inventário são instanciadas dinamicamente pelo host a partir desses templates.
3. O `ui:drag-container` recebe payloads Dictionary que não podem ser encaminhados pelo bridge genérico de eventos Lua. O host consumidor escuta diretamente o sinal Godot de drop, sem alterar nem contornar a segurança da API de mods.
4. Preferências gráficas/áudio são **mockadas**: reativas na tela mas não mudam o hardware. O mundo e a jogabilidade 3D são placeholders do consumidor.
5. O botão Salvar é explícito; novos slots não são gravados até o primeiro salvamento. O carregamento usa os `settings` e `runtime_storage` do `.save`.

## Testes sugeridos

1. Crie um jogo no slot 1, selecione `Relíquias`: `Ambientes Vivos` deve ser selecionado automaticamente. Desmarcar Ambientes Vivos também remove Relíquias.
2. Cancele a tela de Mods: a alteração pendente não deve persistir; Restaurar desmarca todos.
3. Altere uma setting e use Voltar: os defaults devem ser restaurados.
4. No inventário selecione a manopla; arraste-a para outro slot e abra o inventário novamente.
5. Abra Pausa com Esc; Salvar escreve `slot_1.save`. Reinicie o consumidor e carregue o slot 1.
6. Exclua o slot e confirme que o arquivo sumiu e a inscrição voltou para `- Novo Jogo -`.

> Este exemplo foi montado com base no código-fonte do ZIP de `lua_styles` e requer Godot 4.8 com a GDExtension Lua do projeto. A execução dos testes GUT e validação em editor ainda são necessárias.

## Premades e estilos: ajustes de integração

- O `ui:div` possui painel transparente por padrão (`StyleBoxEmpty` na cena); declare `background_color` no estilo somente quando quiser um fundo.
- `ui:label` tem `stretch_x = expand_fill` por padrão e `stretch_y = shrink_begin`, para evitar linhas verticais quando `autowrap` estiver habilitado.
- No inventário, o `ui:button` é o alvo da transição hover; o `ui:drag-container` só gerencia o arraste. O Label de quantidade usa `pointer_events="none"`.
- O consumidor liga `UIRootHost` ao nó raiz, e `UIDragPreviewLayer` desenha a cópia dos controles do slot acima dos modais, sem `set_drag_preview()`.
- O parser de estilos Lua aceita nomes de cores reconhecidos pelo Godot (`"red"`, `"transparent"`, etc.) e hexadecimal com alpha (`"#FFFFFF00"`, `"#11223388"`).
- Em GDScript: `component_instance.get_recognized_properties()` ou `registry.get_recognized_properties("ui:button", true)` retornam o schema. Em Lua: `UI.get_properties("ui:button")` no Content Stage e `game.ui.get_properties("ui:button")` ou `game.ui.get_properties(handle)` no Runtime. Contém `type`, `default` (se existir), `required` e `mod_editable`.
- `UIBuiltinIds.ITEM_SLOT` existe como ID reservado `"ui:item_slot"`; o premade ItemSlot não é registrado automaticamente, pois sua implementação está prevista em Lua.

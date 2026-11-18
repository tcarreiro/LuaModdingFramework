local heartbeat_event = script.register_event("heartbeat")

local function on_tick(event)
	assert(event.tick == game.world.get_time())

	storage.ticks = (storage.ticks or 0) + 1
	game.debug.log("[core] tick " .. event.tick .. ", contador " .. storage.ticks)

	script.raise_event(heartbeat_event, {
		count = storage.ticks
	})
end

-- on_load não pode acessar game.*. Em ambos os casos reconstruímos
-- a interface apenas no evento enviado APÓS a ativação completa.
local function on_ui_ready(_event)
	local handle = game.ui.open("core:playground-button", {
		label = "Core Lua · cliques: " .. tostring(storage.ui_clicks or 0)
	})
	assert(handle > 0, "Falha ao criar UI do mod core")

	assert(game.ui.on(handle, "pressed", function(_pressed_event)
		storage.ui_clicks = (storage.ui_clicks or 0) + 1
		assert(game.ui.set(handle, {
			label = "Core Lua · cliques: " .. storage.ui_clicks
		}))
		game.debug.log("[core] botão Lua clicado " .. storage.ui_clicks .. " vezes")
	end))

	game.debug.log("[core] UI criada através de game.ui.open/on/set")
end

local function register_handlers()
	script.on_event("on_tick", on_tick)
	script.on_event("on_ui_ready", on_ui_ready)
end

remote.add_interface("stats", {
	get_ticks = function()
		return storage.ticks or 0
	end
})

script.on_init(function()
	storage.ticks = 0
	storage.ui_clicks = 0
	register_handlers()
	game.debug.log("[core] on_init: " .. game.player.get_name())
end)

script.on_load(function()
	-- Reconstrói handlers sem modificar storage e sem acessar game.
	register_handlers()
end)

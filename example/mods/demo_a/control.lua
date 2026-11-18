local function on_heartbeat(event)
	storage.heartbeats = (storage.heartbeats or 0) + 1

	local total = remote.call("core:stats", "get_ticks")
	assert(total == event.count)

	game.debug.log(
		"[demo_a] heartbeat " .. storage.heartbeats ..
		" (core=" .. total .. ")"
	)
end

local function on_ui_ready(_event)
	local handle = game.ui.open("core:playground-button", {
		label = "Demo A · cliques: " .. tostring(storage.ui_clicks or 0)
	})
	assert(handle > 0, "Falha ao criar UI do mod demo_a")

	assert(game.ui.on(handle, "pressed", function(_pressed_event)
		storage.ui_clicks = (storage.ui_clicks or 0) + 1
		assert(game.ui.set(handle, {
			label = "Demo A · cliques: " .. storage.ui_clicks
		}))
		game.debug.log("[demo_a] clique em componente próprio: " .. storage.ui_clicks)
	end))
end

local function register_handlers()
	script.on_event("core:heartbeat", on_heartbeat)
	script.on_event("on_ui_ready", on_ui_ready)
end

script.on_init(function()
	storage.heartbeats = 0
	storage.ui_clicks = 0
	register_handlers()

	game.debug.log(
		"[demo_a] on_init: velocidade = " ..
		game.settings.get_enemy_speed()
	)
end)

script.on_load(function()
	register_handlers()
end)

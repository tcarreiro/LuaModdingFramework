
local counter_handle = nil

local function on_tick(event)
	storage.last_tick = event.tick

	game.debug.log("[demo_b] recebeu on_tick " .. tostring(event.tick))

	if counter_handle ~= nil then
		assert(game.ui.set(counter_handle, {
			title = "Demo B · tick: " .. tostring(storage.last_tick)
		}))
	end
end

local function on_ui_ready(_event)
	counter_handle = game.ui.open("demo_b:counter", {
		title = "Demo B · tick: " .. tostring(storage.last_tick or 0),
		button_label = "Demo B · cliques: " .. tostring(storage.ui_clicks or 0)
	})

	assert(counter_handle > 0, "Falha ao criar demo_b:counter")

	assert(game.ui.on(counter_handle, "pressed", function(_pressed_event)
		storage.ui_clicks = (storage.ui_clicks or 0) + 1

		assert(game.ui.set(counter_handle, {
			button_label = "Demo B · cliques: " .. tostring(storage.ui_clicks)
		}))

		game.debug.log(
			"[demo_b] componente composto recebeu clique " ..
			tostring(storage.ui_clicks)
		)
	end))

	game.debug.log("[demo_b] componente composto criado pelo Lua")
end

local function register_handlers()
	script.on_event("on_tick", on_tick)
	script.on_event("on_ui_ready", on_ui_ready)
end

script.on_init(function()
	storage.last_tick = 0
	storage.ui_clicks = 0
	register_handlers()

	game.debug.log("[demo_b] on_init")
end)

script.on_load(function()
	register_handlers()
end)

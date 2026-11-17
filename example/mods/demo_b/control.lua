local function on_tick(event)
	storage.last_tick = event.tick
	game.debug.log("[demo_b] recebeu on_tick " .. event.tick)
end

script.on_init(function()
	storage.last_tick = 0
	script.on_event("on_tick", on_tick)
	game.debug.log("[demo_b] on_init")
end)

script.on_load(function()
	script.on_event("on_tick", on_tick)
end)

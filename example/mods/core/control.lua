local heartbeat_event = script.register_event("heartbeat")

local function on_tick(event)
	assert(event.tick == game.world.get_time())

	storage.ticks = (storage.ticks or 0) + 1

	game.debug.log("[core] tick " .. event.tick .. ", contador " .. storage.ticks)

	script.raise_event(heartbeat_event, {
		count = storage.ticks
	})
end

remote.add_interface("stats", {
	get_ticks = function()
		return storage.ticks or 0
	end
})

script.on_init(function()
	storage.ticks = 0
	script.on_event("on_tick", on_tick)
	game.debug.log("[core] on_init: " .. game.player.get_name())
end)

script.on_load(function()
	-- Reconstrói o handler sem modificar storage.
	script.on_event("on_tick", on_tick)
end)

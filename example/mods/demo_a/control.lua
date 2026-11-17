local function on_heartbeat(event)
	storage.heartbeats = (storage.heartbeats or 0) + 1

	local total = remote.call("core:stats", "get_ticks")
	assert(total == event.count)

	game.debug.log(
		"[demo_a] heartbeat " .. storage.heartbeats ..
		" (core=" .. total .. ")"
	)
end

local function register_handlers()
	script.on_event("core:heartbeat", on_heartbeat)
end

script.on_init(function()
	storage.heartbeats = 0
	register_handlers()

	game.debug.log(
		"[demo_a] on_init: velocidade = " ..
		game.settings.get_enemy_speed()
	)
end)

script.on_load(function()
	register_handlers()
end)

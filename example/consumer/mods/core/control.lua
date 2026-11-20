-- Runtime Stage: lógica mockada do consumidor; sem UI nos mods de exemplo.
script.on_init(function()
    storage.sessions = 1
end)

script.on_load(function()
    -- A restauração de `storage` já foi realizada pelo RuntimeManager.
end)

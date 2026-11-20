-- Settings Stage changes a setting owned by core, without changing its owner.
assert(Settings.update("core:difficulty", {
    allowed_values = {"Fácil", "Normal", "Difícil", "Extremo"}
}))

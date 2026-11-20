# Lua UI Styles and Animations

Available in the **Content Stage**. `UI.define_style` and `UI.define_animation` are authorized for `core` by default; consumers may allow additional mod IDs through `style_registration_mods`. Definitions are not exposed to other mods unless explicitly marked `exposed_to_mods = true`.

## Flat style descriptor

```lua
UI.define_style("core:save-trash", {
    background_color = "#273751",
    border_color = "#55708F",
    border_width = 1,
    border_radius = 8,
    padding = 12,
    font_color = "#FFFFFF",
    font_size = 16,
    stretch_x = "expand_fill",
    transition_property = {"background_color", "scale"},
    transition_duration = 0.15,
    transition_delay = 0,
    transition_timing_function = "ease-out",
    states = {
        hover = {background_color = "#3A5676", scale = {x=1.05,y=1.05}},
        pressed = {scale = {x=0.95,y=0.95}}
    }
})
```

`layout`, `visual`, `colors`, `font_sizes`, `sounds` and `transition` wrapper groups are **not accepted in Lua**. Their dictionaries continue to exist internally in `UIStyleDefinition` for GDScript integrations. Native resource groups `styleboxes`, `fonts`, and compiler-generated `state_styleboxes` remain internal, not constructible from Lua tables. `parent`, `exposed_to_mods`, and `mod_overrides` remain supported. CSS-like timing functions: `linear`, `ease`, `ease-in`, `ease-out`, `ease-in-out`.

`justify_self`, `align_self` and `translate={x,y}` support layered layouts. `translate` shifts the visual without reserving space; the `ui:stack` gets its minimum size from the **first child**, and each subsequent layer is positioned relative to the **previous layer's AABB**. Use `ui:div` for horizontal and vertical rows/columns.

## Keyframes (separate from state transitions)

```lua
UI.define_animation("core:appear", {
    duration = 0.25,
    timing_function = "ease-out",
    iterations = 1,
    keyframes = {
        {time = 0, values = {opacity = 0, scale = {x=0.97,y=0.97}}},
        {time = 1, values = {opacity = 1, scale = {x=1,y=1}}}
    }
})
```

`keyframes` uses a sequential Lua array with normalized `time` in `[0,1]`. Built-in channels: `opacity` (float), `scale` (Vector2), `position` (Vector2), `rotation` (float), `tint` (HTML color). Keyframes for a channel must start at 0 and end at 1. Requires an `UIAnimationRegistry` on `UIComponentRegistry` before Content Stage, and registry finalization afterwards.

To play in Runtime Lua, after opening a component:

```lua
local handle = game.ui.open("core:my-component")
game.ui.animate(handle, "core:appear")
```

This is distinct from a style `states.hover` transition. The Runtime animation API requires an active runtime and respects `exposed_to_mods`.

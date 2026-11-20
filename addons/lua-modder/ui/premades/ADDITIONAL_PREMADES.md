# Additional premades

The following components are discovered recursively by `UIPremadeCatalog` and use the same root-script contract as the existing premades. Their IDs use the existing `ui:` namespace.

| ID | Native root | Properties | Events |
|---|---|---|---|
| `ui:slider` | `HSlider` | `min`, `max`, `step`, `value`, `ticks`, `editable` | `value_changed`, `changed`, `drag_started`, `drag_ended`, hover/focus |
| `ui:progress-bar` | `ProgressBar` | `min`, `max`, `value`, `show_percentage`, `indeterminate` | `value_changed`, `changed`, hover |
| `ui:toggle` | `CheckButton` | `label`, `checked`, `disabled` | `toggled`, `pressed`, hover/focus |
| `ui:tabs` | `TabContainer` | `tabs` (string array of titles), `selected_tab` | `tab_changed`, `tab_clicked`, hover |
| `ui:tooltip` | `MarginContainer` | `text` | hover |
| `ui:separator` | `ColorRect` | `direction` (`horizontal`/`vertical`), `color`, `thickness` | hover |
| `ui:radio-button` | `CheckBox` + `ButtonGroup` | `label`, `checked`, `disabled`, `group` | `toggled`, `pressed`, hover/focus |

All components also accept the shared properties (`style`, `visible`, `pointer_events`). Appearance customization uses the existing style system and its direct visual properties, not manually authored Theme resources or styleboxes.

## Composition notes

- **Tabs:** Children added to the default slot are the tab pages. Each page must be a `Control`; `tabs` customizes the titles of existing pages, **not** the number of pages. `selected_tab` selects an index once the page exists. Children added in Lua templates are also tab pages.
- **Tooltip:** Children added to the `default` slot form the hovered content. Godot's native text tooltip is inherited by nested `Control` descendants and updates when `text` changes. It is a text-only tooltip, not a mod-defined popup layout.
- **RadioButton:** A `ButtonGroup` is shared by radio buttons with matching `group` values **under the same immediate parent**. Separate containers yield independent groups. Use an enclosing Stack to make a group of choices.
- **Slider:** The native `HSlider` is horizontal. For a vertical slider, a separate `VSlider` premade would be appropriate.
- **Separator:** The `ColorRect` explicitly reserves its thickness. Unlike content controls, it needs a nonzero intrinsic thickness to be visible.

## Example GDScript

```gdscript
var slider := components.instantiate_component(UIBuiltinIds.SLIDER, {
	UIKeys.PROP_MIN: 0.0,
	UIKeys.PROP_MAX: 100.0,
	UIKeys.PROP_VALUE: 30.0,
	UIKeys.PROP_STEP: 5.0
})
slider.on_event(UIKeys.EVENT_VALUE_CHANGED, func(event: Dictionary) -> void:
	print("Slider changed: ", event["arguments"][0])
)
```

The example gallery at `example/premade_gallery` includes all seven controls. The GUT suite at `tests/test_ui_additional_premades.gd` provides a functional regression baseline.

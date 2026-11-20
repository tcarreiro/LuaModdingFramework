-- FIRST FILE. Loaded by ContentState as 'core' before every other *.lua.
-- Consumer visual tokens: no Theme, LCSS or StyleBox tables.
local function style(id, value)
	assert(UI.define_style("core:" .. id, value), "Failed to define style: " .. id)
end

style("page", {
	background_color = "#101725",
	stretch_x = "expand_fill", stretch_y = "expand_fill",
})
style("hero", {
	background_color = "#121D30", stretch_x = "expand_fill", stretch_y = "expand_fill",
	 border_color = "#31415E", border_width = 1 
})
style("hero-left", {
	stretch_x = "expand_fill", stretch_y = "expand_fill", stretch_ratio = 65,
	 background_color = "#17253B", padding = 28 
})
style("hero-right", {
	stretch_x = "expand_fill", stretch_y = "expand_fill", stretch_ratio = 35,
	 background_color = "#111A2B", padding = 34 , gap = 18,
})
style("footer", {
	stretch_x = "expand_fill", 
		background_color = "#0B111F", padding = 14,
		border_color = "#344563", border_width = 1
	
})
style("panel", {
	stretch_x = "expand_fill", stretch_y = "expand_fill", 
		background_color = "#1B2740", border_color = "#475A78",
		border_width = 1, border_radius = 13, padding = 23,
		drop_shadow_color = "#070B14AA", drop_shadow_size = 8
	, gap = 15
})
style("panel-dark", {
	stretch_x = "expand_fill", stretch_y = "expand_fill", 
		background_color = "#141F33", border_color = "#3A4D68",
		border_width = 1, border_radius = 12, padding = 18
	, gap = 14
})
style("panel-transparent", { stretch_x = "expand_fill", stretch_y = "expand_fill" })
style("row", { stretch_x = "expand_fill", gap = 14, cross_alignment = "center" })
style("footer-spacer", { stretch_x = "expand_fill" })
style("grow", { stretch_x = "expand_fill", stretch_y = "expand_fill", gap = 14 })
style("grow-horizontal", { stretch_x = "expand_fill", stretch_y = "expand_fill", gap = 14 })
style("column", { stretch_x = "expand_fill", gap = 14 })
style("grid", { stretch_x = "expand_fill", gap = 8 })
style("center", { stretch_x = "expand_fill", stretch_y = "expand_fill", alignment = "center", cross_alignment = "center", gap = 14 })
style("menu-buttons", { stretch_x = "expand_fill", stretch_y = "expand_fill", alignment = "end", gap = 14 })
style("menu-bottom-gap", {min_size={x=0,y=105}})
style("save-bottom-gap", {min_size={x=0,y=45}})
style("logo", { stretch_x = "expand_fill", stretch_y = "expand_fill", min_size = {x=350,y=320} })
style("title", { font_color = "#F4E9CF", font_size = 30})
style("heading", { font_color = "#D7E4FC", font_size = 23 })
style("subtitle", { font_color = "#A6BAD5", font_size = 15 })
style("text", { font_color = "#E6EDF9", font_size = 17 })
style("modal-description", { stretch_x = "expand_fill", font_color = "#E6EDF9", font_size = 17 })
style("text-muted", { font_color = "#9AAEC9", font_size = 14 })
style("text-gold", { font_color = "#F7D18B", font_size = 17 })
style("slot-title", { font_color = "#F5E6C5", font_size = 25 })
style("button", {
	stretch_x = "expand_fill", 
		background_color = "#273751", border_color = "#55708F",
		border_width = 1, border_radius = 10, padding = 16
	, font_color = "#EDF4FF", font_size=19,
	states = {
		hover = {background_color = "#364C6C"},
		pressed = {background_color = "#1F2C44"}
	}, transition_property={"background_color"},transition_duration=0.16
})
style("button-gold", {
	stretch_x = "expand_fill", 
		background_color = "#D7A855", border_color = "#F9D78B",
		border_width = 1, border_radius = 10, padding = 17
	, font_color = "#111928", font_size=19,
	states={hover={background_color="#F0CA79"},pressed={background_color="#AD7E37"}},
	transition_property={"background_color"},transition_duration=0.15
})
style("button-danger", {
	stretch_x = "expand_fill", 
		background_color = "#6F3342", border_color = "#AB5D6B",
		border_width = 1, border_radius = 10, padding = 14
	, font_color="#FBE9EC", font_size=19,
	states={hover={background_color="#924254"},pressed={background_color="#532736"}},
	transition_property={"background_color"},transition_duration=0.15
})
style("button-tab", {
	background_color="#27344A",border_radius=7,padding=12,
	font_color="#EAF2FF",
	states={hover={background_color="#4B6483"}},
	transition_property={"background_color"},transition_duration=0.13
})
style("slot-card", {
	stretch_x = "expand_fill", stretch_y = "expand_fill", 
		background_color="#202F49",border_color="#8193B4",border_width=1,
		border_radius=14,padding=26
	, font_color="#F2E2C4",font_size=21,
	states={hover={background_color="#2C4161"}},
	transition_property={"background_color"},transition_duration=0.2
})
style("trash", {
	icon_max_width = 26, icon_spacing = 0,
	scale_mode="visual_only",pivot_ratio={x=0.5,y=0.5},
	background_color="#672F3F",border_radius=10,padding=9,
	states={hover={scale={x=1.08,y=1.08},background_color="#884155"},
			pressed={scale={x=0.91,y=0.91},background_color="#A75162"}},
	transition_property={"scale","background_color"},transition_duration=0.1
})
style("modal", {
	stretch_x="expand_fill", 
		background_color="#18253A",border_color="#627693",border_width=1,
		border_radius=16,padding=24,drop_shadow_color="#000000BB",drop_shadow_size=16
	
})
style("scroll", {stretch_x="expand_fill",stretch_y="expand_fill",gap=10,padding=10})
style("split-left", {stretch_x="expand_fill",stretch_y="expand_fill",stretch_ratio=47,
	background_color="#101B2E",padding=15,border_radius=9,gap=12})
style("split-right", {stretch_x="expand_fill",stretch_y="expand_fill",stretch_ratio=53,
	background_color="#1F2D46",padding=20,border_radius=9,gap=14})
style("setting-row", {stretch_x="expand_fill",gap=12,
	background_color="#263550",padding=11,border_radius=6})
style("input", {stretch_x="expand_fill",
	background_color="#18263C",border_color="#546987",border_width=1,
	border_radius=7,padding=10
	,font_color="#F0F3FC"
})
style("hud", {background_color="#1A293D",border_color="#6B8297",border_width=1,
	border_radius=12,padding=13})
style("health", {stretch_x="expand_fill",min_size={x=265,y=24}})
style("inventory-drag-root", {stretch_x="expand_fill",stretch_y="expand_fill",
	background_color="transparent",padding=0})
style("inventory-slot", {stretch_x="expand_fill",stretch_y="expand_fill",
	icon_max_width = 42, icon_spacing = 0, background_color="#1C2B43",border_color="#495B75",
	border_width=1,border_radius=6,padding=8,font_color="#F6E5C6",
	states={hover={background_color="#304767"}},
	transition_property={"background_color"},transition_duration=0.12})
style("slot-inner", { stretch_x="expand_fill",stretch_y="expand_fill" })
style("stack-fill", { stretch_x="expand_fill", stretch_y="expand_fill" })
style("quantity", {font_color="#FFDF9F",font_size=13,justify_self="end",align_self="end",translate={x=-6,y=-6}})
style("inventory-slot-selected", {icon_max_width = 42, icon_spacing = 0, background_color="#4A3E32",border_color="#F1C679",
	border_width=2,border_radius=6,padding=8,font_color="#FFEDCE"})

style("trash-overlap", {
	parent = "core:trash",
	min_size = {x=50, y=48},
	justify_self = "center", align_self = "end",
	translate = {x=0, y=24}
})

UI.define_component("core:main-menu", {
	properties={version={type="string",default="1.0.0"}},
	tree={component="ui:div", props={style="core:page",direction="vertical"},children={
		{component="ui:div",name="hero",props={style="core:hero",direction="horizontal"},children={
			{component="ui:div",props={style="core:hero-left"},children={
				{component="ui:sprite",name="logo",props={texture="core:logo.png",style="core:logo",playing=false}}
			}},
			{component="ui:div",props={style="core:hero-right"},children={
				{component="ui:div",props={style="core:menu-buttons"},children={
					{component="ui:label",props={text="EXEMPLO DO CONSUMIDOR",style="core:subtitle"}},
					{component="ui:button",name="play",props={label="Jogar",style="core:button-gold"}},
					{component="ui:button",name="settings",props={label="Configurações",style="core:button"}},
					{component="ui:button",name="exit",props={label="Sair",style="core:button"}},
					{component="ui:label",props={text="",style="core:menu-bottom-gap"}}
				}}
			}}
		}},
		{component="ui:div",props={style="core:footer",direction="horizontal"},children={
			{component="ui:label",props={text="LuaModdingFramework  ·  Consumer Demo",style="core:text-muted"}},
			{component="ui:label",props={text="",style="core:footer-spacer"}},
			{component="ui:label",props={text={ ["$prop"]="version" },style="core:text-muted",align="right"}}
		}}
	}},
	events={play={source="play",event="pressed"},settings={source="settings",event="pressed"},exit={source="exit",event="pressed"}}
})

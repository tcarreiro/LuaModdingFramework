-- Audio, graphics, game and controls. Inputs added by consumer using Lua row templates.
UI.define_component("core:options-screen", {
    tree={component="ui:div",props={style="core:page"},children={
        {component="ui:div",props={style="core:panel"},children={
            {component="ui:label",props={text="Configurações",style="core:title"}},
            {component="ui:div",props={direction="horizontal",style="core:row"},children={
                {component="ui:button",name="audio",props={label="Áudio",style="core:button-tab"}},
                {component="ui:button",name="graphics",props={label="Gráfico",style="core:button-tab"}},
                {component="ui:button",name="game",props={label="Jogo",style="core:button-tab"}},
                {component="ui:button",name="controls",props={label="Controle",style="core:button-tab"}}
            }},
            {component="ui:scroll",name="options",props={style="core:scroll"}},
            {component="ui:div",props={direction="horizontal",style="core:row"},children={
                {component="ui:button",name="back",props={label="Voltar",style="core:button"}},
                {component="ui:button",name="restore",props={label="Restaurar",style="core:button"}},
                {component="ui:button",name="apply",props={label="Aplicar",style="core:button-gold"}}
            }}
        }}
    }},
    events={audio={source="audio",event="pressed"},graphics={source="graphics",event="pressed"},
        game={source="game",event="pressed"},controls={source="controls",event="pressed"},
        back={source="back",event="pressed"},restore={source="restore",event="pressed"},apply={source="apply",event="pressed"}}
})

UI.define_component("core:option-bool", {
    properties={label={type="string",default="Opção"},checked={type="bool",default=false}},
    tree={component="ui:div",props={style="core:setting-row",direction="horizontal"},children={
        {component="ui:toggle",name="value",props={label={["$prop"]="label"},checked={["$prop"]="checked"}}}
    }},events={changed={source="value",event="toggled"}}
})
UI.define_component("core:option-choice", {
    properties={label={type="string",default="Opção"},selected={type="int",default=0},options={type="array",default={}}},
    tree={component="ui:div",props={style="core:setting-row",direction="horizontal"},children={
        {component="ui:label",props={text={["$prop"]="label"},style="core:text"}},
        {component="ui:dropdown",name="value",props={options={["$prop"]="options"},selected={["$prop"]="selected"}}}
    }},events={changed={source="value",event="item_selected"}}
})
UI.define_component("core:option-range", {
    properties={label={type="string",default="Volume"},value={type="float",default=50.0},minimum={type="float",default=0.0},maximum={type="float",default=100.0}},
    tree={component="ui:div",props={style="core:setting-row",direction="vertical"},children={
        {component="ui:label",props={text={["$prop"]="label"},style="core:text"}},
        {component="ui:slider",name="value",props={min={["$prop"]="minimum"},max={["$prop"]="maximum"},value={["$prop"]="value"},step=1.0}}
    }},events={changed={source="value",event="value_changed"}}
})

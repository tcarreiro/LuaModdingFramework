-- Gameplay UI is also Lua-authored, then instantiated by the consumer host.
UI.define_component("core:game-hud", {
    properties={health={type="float",default=100.0}},
    tree={component="ui:div",props={style="core:hud"},children={
        {component="ui:label",props={text="SAÚDE",style="core:subtitle"}},
        {component="ui:progress-bar",name="health",props={min=0.0,max=100.0,
            value={["$prop"]="health"},show_percentage=true,style="core:health"}},
        {component="ui:label",props={text="I  ·  Inventário     Esc  ·  Pausa",style="core:text-muted"}}
    }}
})
UI.define_component("core:inventory-panel", {
    tree={component="ui:div",props={style="core:grow"},children={
        {component="ui:div",props={style="core:row",direction="horizontal"},children={
            {component="ui:label",props={text="Inventário",style="core:title"}},
            {component="ui:button",name="close",props={label="✕",style="core:button-tab"}}
        }},
        {component="ui:div",props={direction="horizontal",style="core:grow-horizontal"},children={
            {component="ui:div",props={style="core:split-left"},children={
                {component="ui:label",props={text="MOCHILA  ·  28 SLOTS",style="core:subtitle"}},
                {component="ui:grid",name="slots",props={columns=7,style="core:grid"}}
            }},
            {component="ui:div",props={style="core:split-right"},children={
                {component="ui:label",props={text="DETALHES DO ITEM",style="core:subtitle"}},
                {component="ui:div",name="description",props={style="core:column"}}
            }}
        }}
    }},events={close={source="close",event="pressed"}}
})
UI.define_component("core:inventory-cell", {
    properties={quantity={type="string",default=""},texture={type="string",default=""}},
    tree={component="ui:drag-container",props={style="core:inventory-drag-root"},children={
        {component="ui:stack",props={style="core:slot-inner"},children={
            {component="ui:button",name="choose",props={label="",style="core:inventory-slot",
                icon={["$prop"]="texture"},icon_alignment="center"}},
            {component="ui:label",name="count",props={text={["$prop"]="quantity"},style="core:quantity",align="right",pointer_events="none"}}
        }}
    }},events={select={source="choose",event="pressed"}}
})
UI.define_component("core:pause-panel", {
    tree={component="ui:div",props={style="core:center"},children={
        {component="ui:label",props={text="Jogo pausado",style="core:title"}},
        {component="ui:button",name="resume",props={label="Resume",style="core:button-gold"}},
        {component="ui:button",name="save",props={label="Salvar",style="core:button"}},
        {component="ui:button",name="exit",props={label="Sair",style="core:button-danger"}}
    }},events={resume={source="resume",event="pressed"},save={source="save",event="pressed"},exit={source="exit",event="pressed"}}
})
UI.define_component("core:loading-panel", {
    properties={message={type="string",default="Carregando o mundo..."}},
    tree={component="ui:div",props={style="core:center"},children={
        {component="ui:label",props={text="✦",style="core:title",align="center"}},
        {component="ui:label",props={text={["$prop"]="message"},style="core:heading",align="center"}},
        {component="ui:progress-bar",props={indeterminate=true,show_percentage=false,min=0.0,max=100.0,value=60.0,style="core:health"}}
    }}
})

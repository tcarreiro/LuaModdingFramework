UI.define_component("core:mods-panel", {
    tree={component="ui:div",props={style="core:grow"},children={
        {component="ui:label",props={text="Gerenciar mods",style="core:title"}},
        {component="ui:div",props={direction="horizontal",style="core:grow-horizontal"},children={
            {component="ui:div",props={style="core:split-left"},children={
                {component="ui:label",props={text="MODS DISPONÍVEIS",style="core:subtitle"}},
                {component="ui:scroll",name="list",props={style="core:scroll"}}
            }},
            {component="ui:div",props={style="core:split-right"},children={
                {component="ui:label",props={text="DETALHES",style="core:subtitle"}},
                {component="ui:label",name="details",props={text="Selecione um mod à esquerda.",style="core:text",autowrap=true}}
            }}
        }},
        {component="ui:div",props={direction="horizontal",style="core:row"},children={
            {component="ui:button",name="back",props={label="Voltar",style="core:button"}},
            {component="ui:button",name="restore",props={label="Restaurar",style="core:button"}},
            {component="ui:button",name="ok",props={label="Ok",style="core:button-gold"}}
        }}
    }},events={back={source="back",event="pressed"},restore={source="restore",event="pressed"},ok={source="ok",event="pressed"}}
})
UI.define_component("core:mod-row", {
    properties={title={type="string",default="Mod"},checked={type="bool",default=false}},
    tree={component="ui:div",props={direction="horizontal",style="core:row"},children={
        {component="ui:checkbox",name="enabled",props={label={["$prop"]="title"},checked={["$prop"]="checked"}}},
        {component="ui:button",name="inspect",props={label="Detalhes",style="core:button-tab"}}
    }},events={changed={source="enabled",event="toggled"},inspect={source="inspect",event="pressed"}}
})

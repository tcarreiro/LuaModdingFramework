UI.define_component("core:save-screen", {
    tree={component="ui:div",props={style="core:page"},children={
        {component="ui:div",props={style="core:panel"},children={
            {component="ui:label",props={text="Escolha uma expedição",style="core:title"}},
            {component="ui:label",props={text="Três espaços para criar ou continuar sua jornada",style="core:subtitle"}},
            {component="ui:div",name="cards",props={style="core:grow-horizontal",direction="horizontal"}},
            {component="ui:label",props={text="",style="core:save-bottom-gap"}},
            {component="ui:button",name="back",props={label="Voltar",style="core:button"}}
        }}
    }},events={back={source="back",event="pressed"}}
})
UI.define_component("core:save-card", {
    properties={text={type="string",default="- Novo Jogo -"},has_save={type="bool",default=false}},
    tree={component="ui:stack",props={style="core:stack-fill"},children={
        {component="ui:button",name="choose",props={label={["$prop"]="text"},style="core:slot-card"}},
        {component="ui:button",name="delete",props={label="",style="core:trash-overlap",icon="core:trash.png",icon_alignment="center",visible={["$prop"]="has_save"}}}
    }},events={choose={source="choose",event="pressed"},delete={source="delete",event="pressed"}}
})

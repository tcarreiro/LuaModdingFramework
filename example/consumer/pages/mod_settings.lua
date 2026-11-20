-- The SettingsRegistry supplies settings grouped by owner_mod_id. Changes by
-- other mods do NOT move the setting from its owner's tab.
UI.define_component("core:mod-settings-panel", {
    tree={component="ui:div",props={style="core:grow"},children={
        {component="ui:label",props={text="Configurações dos mods",style="core:title"}},
        {component="ui:div",props={direction="horizontal",style="core:grow-horizontal"},children={
            {component="ui:div",props={style="core:split-left"},children={
                {component="ui:label",props={text="MOD",style="core:subtitle"}},
                {component="ui:scroll",name="owners",props={style="core:scroll"}}
            }},
            {component="ui:div",props={style="core:split-right"},children={
                {component="ui:label",name="owner_name",props={text="Core",style="core:heading"}},
                {component="ui:scroll",name="settings",props={style="core:scroll"}}
            }}
        }},
        {component="ui:div",props={direction="horizontal",style="core:row"},children={
            {component="ui:button",name="back",props={label="Voltar",style="core:button"}},
            {component="ui:button",name="restore",props={label="Restaurar",style="core:button"}},
            {component="ui:button",name="ok",props={label="Ok",style="core:button-gold"}}
        }}
    }},events={back={source="back",event="pressed"},restore={source="restore",event="pressed"},ok={source="ok",event="pressed"}}
})

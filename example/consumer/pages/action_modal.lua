-- Content of the SAME native ui:modal instance; no separate modal per stage.
UI.define_component("core:action-modal", {
	properties={title={type="string",default="Nova expedição"}},
	tree={component="ui:div",props={style="core:center"},children={
		{component="ui:label",props={text={["$prop"]="title"},style="core:title",align="center"}},
		{component="ui:label",props={text="Selecione a ação desejada",style="core:subtitle",align="center"}},
		{component="ui:button",name="start",props={label="Jogar",style="core:button-gold"}},
		{component="ui:button",name="mods",props={label="Mods",style="core:button"}},
		{component="ui:button",name="cancel",props={label="Cancelar",style="core:button"}}
	}},events={start={source="start",event="pressed"},mods={source="mods",event="pressed"},cancel={source="cancel",event="pressed"}}
})
UI.define_component("core:confirm-modal", {
	properties={title={type="string",default="Tem certeza?"},description={type="string",default="Esta ação não pode ser desfeita."}},
	tree={component="ui:div",props={style="core:center"},children={
		{component="ui:label",props={text={["$prop"]="title"},style="core:title",align="center"}},
		{component="ui:scroll",props={style="core:scroll"}, children={
			{component="ui:label",props={text={["$prop"]="description"},style="core:modal-description",align="left",autowrap=true}},
		}},
		{component="ui:button",name="yes",props={label="Confirmar",style="core:button-danger"}},
		{component="ui:button",name="no",props={label="Cancelar",style="core:button"}}
	}},events={yes={source="yes",event="pressed"},no={source="no",event="pressed"}}
})

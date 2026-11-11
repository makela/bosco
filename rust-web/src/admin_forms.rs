//! The admin's form fields, as IHP's `formFor` with Tailwind makes them: a
//! label over the field, what to fix under it in red, and a hint in grey.

use maud::{Markup, html};

/// One field: its name in the form, its id, label and what's in it
pub struct Field<'a> {
    pub name: &'a str,
    /// The form's model, the start of the field's id: "product_price"
    pub model: &'a str,
    pub label: &'a str,
    pub value: &'a str,
    pub required: bool,
    pub autofocus: bool,
    pub error: Option<&'a str>,
    /// A hint under the field
    pub help: Option<&'a str>,
}

impl<'a> Field<'a> {
    pub fn new(model: &'a str, name: &'a str, label: &'a str, value: &'a str) -> Self {
        Self {
            name,
            model,
            label,
            value,
            required: false,
            autofocus: false,
            error: None,
            help: None,
        }
    }

    pub fn required(self) -> Self {
        Self {
            required: true,
            ..self
        }
    }

    pub fn autofocus(self) -> Self {
        Self {
            autofocus: true,
            ..self
        }
    }

    pub fn error(self, error: Option<&'a str>) -> Self {
        Self { error, ..self }
    }

    pub fn help(self, help: &'a str) -> Self {
        Self {
            help: Some(help),
            ..self
        }
    }

    fn id(&self) -> String {
        format!("{}_{}", self.model, self.name)
    }

    fn class(&self) -> &'static str {
        if self.error.is_some() {
            "focus:ring-blue-500 focus:border-blue-500 block w-full border-gray-300 rounded-md is-invalid"
        } else {
            "focus:ring-blue-500 focus:border-blue-500 block w-full border-gray-300 rounded-md"
        }
    }

    /// The label, the field, and what's under it
    fn group(&self, input: Markup) -> Markup {
        let id = self.id();
        html! {
            div class="flex flex-col my-6 space-y-2" id={ "form-group-" (id) } {
                label class="font-medium text-gray-700" for=(id) { (self.label) }
                (input)
                @if let Some(error) = self.error {
                    div class="text-red-500 text-xs italic" { (error) }
                }
                @if let Some(help) = self.help {
                    p class="text-gray-600 text-xs italic" { (help) }
                }
            }
        }
    }

    pub fn text(&self) -> Markup {
        self.input("text")
    }

    pub fn number(&self) -> Markup {
        self.input("number")
    }

    fn input(&self, kind: &str) -> Markup {
        self.group(html! {
            input type=(kind) name=(self.name) id=(self.id()) value=(self.value)
                required[self.required] autofocus[self.autofocus] class=(self.class());
        })
    }

    pub fn textarea(&self) -> Markup {
        self.group(html! {
            textarea name=(self.name) id=(self.id()) required[self.required]
                autofocus[self.autofocus] class=(self.class()) { (self.value) }
        })
    }

    /// A choice of `options`, (value, label), with "Please select" first
    /// while nothing is chosen
    pub fn select(&self, options: &[(String, String)]) -> Markup {
        let chosen = options.iter().any(|(value, _)| value == self.value);
        self.group(html! {
            select name=(self.name) id=(self.id()) required[self.required]
                autofocus[self.autofocus] class=(self.class()) {
                @if !chosen {
                    option value="" selected disabled { "Please select" }
                }
                @for (value, label) in options {
                    option value=(value) selected[value == self.value] { (label) }
                }
            }
        })
    }

    /// A checkbox, `value` "on" when ticked. A hidden "off" after it sends
    /// the field when it isn't ticked, so it's always in the form.
    pub fn checkbox(&self) -> Markup {
        let id = self.id();
        html! {
            div class="flex flex-col my-6 space-y-2" id={ "form-group-" (id) } {
                div.form-check {
                    div class="flex flex-row space-x-2" {
                        div {
                            input type="checkbox" name=(self.name) class="form-check-input" id=(id)
                                checked[self.value == "on"];
                            input type="hidden" name=(self.name) value="off";
                        }
                        div class="flex flex-col" {
                            label class="font-medium text-gray-700 form-check-label" for=(id) { (self.label) }
                            @if let Some(help) = self.help {
                                p class="text-gray-600 text-xs italic" { (help) }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// The form's submit button
pub fn submit(label: &str) -> Markup {
    html! {
        button class="bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded" type="submit" { (label) }
    }
}

/// A form's field values as IHP's `fill` reads them: the first of a
/// repeated one (a checkbox comes before its hidden "off"); None when it
/// wasn't sent, so the field keeps what it had
pub fn get<'a>(fields: &'a [(String, String)], name: &str) -> Option<&'a str> {
    fields
        .iter()
        .find(|(key, _)| key == name)
        .map(|(_, value)| value.as_str())
}

/// A checkbox's value: ticked is "on", as IHP's ParamReader Bool also takes
/// "true"
pub fn is_on(value: &str) -> bool {
    value == "on" || value.eq_ignore_ascii_case("true")
}

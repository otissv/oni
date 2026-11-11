# Menubar

`Menubar` is a persistent application command bar, following the composition of the [shadcn Base UI menubar](https://ui.shadcn.com/docs/components/base/menubar). Import it from `oni/widgets`. The app owns the active top-level menu value, checkbox values, and radio selections. Oni retains keyboard focus, submenu navigation, and the typeahead buffer in `State.widget`, so interaction state survives a hot reload.

```odin
import w "oni/widgets"
import set "oni/set"

commands :: proc() {
    w.Menubar({
        config = {id = "commands", value = app.menu},
        on_value_change = proc(value: string) { app.menu = value },
        child = proc(_: w.Menubar_State) {
            w.Menubar_Menu({
                config = {value = "file"},
                child = proc(_: w.Menubar_Menu_State) {
                    w.Menubar_Trigger({config = {text_value = "File"}})
                    w.Menubar_Content({child = proc(_: w.Menubar_Content_State) {
                        w.Menubar_Item({
                            config = {id = "save", text_value = "Save"},
                            on_select = save_document,
                            child = proc(_: w.Menubar_Item_State) {
                                w.Text({config = {text = "Save", width = set.Width(.FIT)}})
                                w.Menubar_Shortcut({config = {text = "Ctrl+S"}})
                            },
                        })
                    }})
                },
            })
        },
    })
}

save_document :: proc(_: w.Menubar_Item_Event) -> bool {
    save_current_document()
    return true
}
```

Here `app` denotes the consumer's persistent application state; `save_current_document` is its command implementation. An empty `config.value` closes the bar. Each `Menubar_Menu` must have a unique nonempty `config.value`, with its trigger declared before its content. Always declare content in both UI passes: the widget decides whether its panel exists. A Draw-pass request affects panel visibility on the next Layout pass, preserving the solved tree for the current frame. If the app declines a requested value, the next frame continues to use the value the app supplies.

## Composition

| Part | Purpose |
| --- | --- |
| `Menubar` | Styled horizontal bar and controlled active menu |
| `Menubar_Menu` | Structural scope for one value, trigger, and content |
| `Menubar_Trigger` | Top-level command category |
| `Menubar_Content` | Floating, scrollable command panel |
| `Menubar_Group`, `Menubar_Label` | Styled command groups and headings |
| `Menubar_Item` | Action with optional cancellation |
| `Menubar_Checkbox_Item` | Controlled checked or indeterminate option |
| `Menubar_Radio_Group`, `Menubar_Radio_Item` | Controlled single selection |
| `Menubar_Separator`, `Menubar_Shortcut` | Separator and visual shortcut hint |
| `Menubar_Sub`, `Menubar_Sub_Trigger`, `Menubar_Sub_Content` | Nested command category |

Every visual part accepts the usual `Widget_Config` styles. `Menubar_Menu_Config` contains only `value` and `disabled`; `Menubar_Sub_Config` contains only `id` and `disabled`, because these parts introduce structural scopes rather than layout boxes. Parts outside their required root or content scope are inert. Duplicate trigger ids or top-level values are rejected. Use stable, globally unique author ids when targeting focus programmatically.

## Configuration and callbacks

| Config | Fields and defaults |
| --- | --- |
| `Menubar_Config` | `value = ""`; `loop = .ON`; `navigation_direction = .LTR`; ordinary widget styles and lifecycle flags |
| `Menubar_Menu_Config` | Required unique `value`; `disabled = set.Disabled(false)` |
| `Menubar_Content_Config` | `anchor_align = .START`; zero `anchor_gap` uses 4 logical pixels; nonpositive `viewport_margin` uses 8 logical pixels |
| `Menubar_Item_Config` and trigger/item aliases | `text_value`, `value`, `checked`, `indeterminate`, `inset`, `destructive`, `close_on_select`, widget styles and lifecycle flags |
| `Menubar_Radio_Group_Config` | Caller-owned `value` and ordinary widget styles |
| `Menubar_Label_Config` | Text configuration, `inset`, and lifecycle flags |
| `Menubar_Group_Config` and separator alias | Widget styles and lifecycle flags |

`on_value_change: proc(value: string)` on the root requests the active category. `Menubar_Get_Value()` returns the current scoped value and an `ok` flag; it is inert outside the root callback. The returned string is borrowed and should not be retained beyond the frame unless the app owns or copies it.

`on_select: proc(event: Menubar_Item_Event) -> bool` accepts an action with `true`, or cancels selection, toggle, and dismissal with `false`. It is optional. Successful selection closes the entire menu chain and restores focus to the category trigger. Set `config.close_on_select = set.Bool(false)` to keep the menu open. `on_click` observes an accepted activation. Triggers and items also support ordinary widget lifecycle, pointer, and key callbacks; `unmount` and `can_interactive_during_mount` belong on their config.

Checkboxes take `config.checked` and optional `config.indeterminate`, then request a boolean through `on_checked_change`. Activating an indeterminate option requests `true`. Radio items take nonempty `config.value` strings inside a `Menubar_Radio_Group`, whose `on_value_change` requests the next selection. Re-selecting the checked radio does not report a duplicate value. Both selection types show their own indicators and accept a custom `child`; without a child, `text_value` supplies the visible label. Supply `text_value` for typeahead even when rendering a custom label or icon.

`Menubar_Label` supports inset alignment with checkable items. `Menubar_Item` supports destructive coloring and inset alignment. `Menubar_Shortcut` displays a hint and does not install a shortcut binding; register executable commands through the engine shortcuts API.

## Interaction and placement

The bar contributes one enabled trigger to the Tab order. Left and Right move between categories; while a category is open, they switch its menu. Up and Down on a category open it at the last or first enabled item respectively. In content, Up and Down navigate enabled items, Home and End select the first and last enabled item, and Enter or Space activate. Typeahead matches Unicode labels without case sensitivity, expires after 750 ms, and cycles repeated characters. Keyboard focus scrolls an offscreen item into view on the next layout.

The forward horizontal arrow opens a submenu; the backward arrow closes a submenu and restores focus to its trigger. Escape closes one submenu level or closes the top-level menu and restores category focus. Tab and Shift+Tab close the menus and traverse relative to the category's position in the surrounding UI. Outside pointer presses dismiss without restoring focus over the clicked control. Moving the pointer across enabled categories switches an already open menu; moving across a submenu trigger opens that submenu. Disabled items, hidden items, and noninteractive mount/unmount phases do not participate in navigation or activation.

`navigation_direction = .RTL` reverses the bar and item layout, text direction defaults, horizontal navigation, submenu sides, and shortcut alignment. Explicit text styles remain available through `set.*`. Panels use `.POPOVER` space, flip at viewport edges, and constrain their dimensions to available space. Content can be styled with a fixed height to expose its scrollport. Anchor placement runs during Layout only, with parent panels positioned before their submenu anchors.

Menus respect existing modal focus scopes. Their pointer ownership also propagates through enclosing popup scopes, so interacting with a menu's floating content does not dismiss its containing popup.

## Lifetime and limits

Root runtime records use numeric UI ids as keys. The retained fields contain ids, a 32-level submenu path, and a 128-byte UTF-8 typeahead buffer; they retain no app callbacks or borrowed strings between frames. Entry arrays and their borrowed strings use the frame scratch allocator and survive the Layout/Draw pair only. Missing roots are pruned after one absent frame; `widget_ctx_shutdown` releases the runtime map. The consumer owns its controlled values and must retain or copy nonliteral strings it chooses to store.

Submenus beyond 32 levels are inert. Typeahead resets when the accumulated prefix would exceed 128 bytes and ignores an individual input larger than that buffer. The menu count and item count have no fixed table limit. Temporary context pointers are restored before their call returns, including nested roots and radio groups.

The consumer documentation app includes the component under Widgets → Menubar. Regression coverage lives in `widgets/menubar_test.odin` and `layout_popup_test.odin`; use `scripts/test_all.sh` to keep strict compilation and allocator leak checks enabled.

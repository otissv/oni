package oni_widgets

import o ".."
import set "../set"
import "core:testing"


@(test)
preserve_apply_defaults_sets_wrap_align_and_line_height :: proc(t: ^testing.T) {
	cfg := preserve_apply_defaults({text = "x"})
	testing.expect(t, cfg.wrap.value.(o.Text_Wrap_Kind) == .PRESERVE)
	testing.expect(t, cfg.align.value.(o.Text_Align_Kind) == .LEFT)
	testing.expect(t, cfg.line_height.value.(f32) == 1.35)
}

@(test)
preserve_apply_defaults_keeps_explicit_overrides :: proc(t: ^testing.T) {
	cfg := preserve_apply_defaults(
		{
			text = "x",
			wrap = set.Wrap(.BALANCE),
			align = set.Align(.CENTER),
			line_height = set.F32(2),
		},
	)
	testing.expect(t, cfg.wrap.value.(o.Text_Wrap_Kind) == .BALANCE)
	testing.expect(t, cfg.align.value.(o.Text_Align_Kind) == .CENTER)
	testing.expect(t, cfg.line_height.value.(f32) == 2)
}

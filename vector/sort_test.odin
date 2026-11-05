#+test
package oni_vector

import "core:testing"

@(test)
sweep_small_sorts_preserve_exact_order_and_budget :: proc(t: ^testing.T) {
	events := [5]Rational{{num = 3, den = 2}, {num = -2, den = 3}, {num = 1, den = 2}, {num = 2, den = 4}, {num = 9, den = 2}}
	work := Exact_Work{allowed = 10000, width = DEFAULT_LIMITS.max_integer_bits}
	budget := Sort_Context{remaining = 1000, exact = &work}
	sort_events(events[:], &budget)
	testing.expect_value(t, budget.err, Error.None)
	for i in 1 ..< len(events) {
		order, err := rational_compare(events[i - 1], events[i])
		testing.expect_value(t, err, Error.None)
		testing.expect(t, order <= 0)
	}
	crossings := [3]Crossing{{x = {num = 1, den = 2}, edge = 7}, {x = {num = -1, den = 2}, edge = 3}, {x = {num = 2, den = 4}, edge = 2}}
	sort_crossings(crossings[:], &budget)
	testing.expect_value(t, crossings[0].edge, 3)
	testing.expect_value(t, crossings[1].edge, 2)
	testing.expect_value(t, crossings[2].edge, 7)
	budget = {remaining = 0, exact = &work}
	sort_events(events[:], &budget)
	testing.expect_value(t, budget.err, Error.Limit_Exceeded)
}

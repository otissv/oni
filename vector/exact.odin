package oni_vector

// All rational numerators/denominators are bounded i128. Cross-products need
// at most 256 bits, so a fixed four-limb fallback avoids unbounded allocation.
@(private)
Exact_Work :: struct { used, allowed, width: int, err: Error }

@(private)
exact_charge :: proc(work: ^Exact_Work, operations: int) -> bool {
	if work == nil { return true }
	if work.err != .None { return false }
	if operations > work.allowed - work.used { work.err = .Limit_Exceeded; return false }
	work.used += operations
	return true
}

@(private)
exact_product :: proc(a, b: u128, work: ^Exact_Work) -> (out: [4]u64, err: Error) {
	if work != nil && work.width < 256 { return out, .Limit_Exceeded }
	x, y := [2]u64{u64(a), u64(a >> 64)}, [2]u64{u64(b), u64(b >> 64)}
	for i in 0 ..< 2 {
		carry := u128(0)
		for j in 0 ..< 2 {
			// One multiply, two additions, and a carry extraction per limb pair.
			if !exact_charge(work, 4) { return out, .Limit_Exceeded }
			value := u128(x[i]) * u128(y[j]) + u128(out[i + j]) + carry
			out[i + j], carry = u64(value), value >> 64
		}
		out[i + 2] = u64(carry)
	}
	return out, .None
}

@(private)
exact_compare_products :: proc(a, b, c, d: i128, work: ^Exact_Work) -> (int, Error) {
	if !exact_charge(work, 4) { return 0, .Limit_Exceeded }
	negative_left, negative_right := (a < 0) != (b < 0), (c < 0) != (d < 0)
	if negative_left != negative_right { return negative_left ? -1 : 1, .None }
	// Unsigned magnitude also handles the minimum signed integer.
	ma, mb := a < 0 ? u128(-(a + 1)) + 1 : u128(a), b < 0 ? u128(-(b + 1)) + 1 : u128(b)
	mc, md := c < 0 ? u128(-(c + 1)) + 1 : u128(c), d < 0 ? u128(-(d + 1)) + 1 : u128(d)
	left, le := exact_product(ma, mb, work)
	if le != .None { return 0, le }
	right, re := exact_product(mc, md, work)
	if re != .None { return 0, re }
	for i := 3; i >= 0; i -= 1 {
		if !exact_charge(work, 1) { return 0, .Limit_Exceeded }
		if left[i] != right[i] { return (left[i] < right[i]) != negative_left ? -1 : 1, .None }
	}
	return 0, .None
}

package oni_vector

// Releases arena-owned SVG data without freeing the asset shell pointer.
svg_asset_retire :: proc(asset: ^Svg_Asset) {
	if asset == nil {
		return
	}

	allocator := asset.allocator
	if asset.arena != nil {
		scratch_arena_destroy(asset.arena)
		free(asset.arena, allocator)
	}

	asset^ = {allocator = allocator}
}

// Replaces an existing asset on success. Failed reload leaves the prior revision intact.
Reload_Svg_From_String :: proc(asset: ^Svg_Asset, source: string, opts := Svg_Load_Options{}) -> Svg_Load_Result {
	if asset == nil {
		result: Svg_Load_Result
		result.allocator = context.allocator
		result.diagnostics = make([dynamic]Svg_Diagnostic, context.allocator)
		svg_push(&result, .Invalid_Handle, "nil SVG asset", 0, 0)

		return result
	}

	replacement, loaded := Load_Svg_From_String(source, opts, asset.allocator)
	if !loaded.ok {
		Destroy_Svg_Asset(replacement)

		return loaded
	}

	svg_asset_retire(asset)
	asset^ = replacement^
	free(replacement, asset.allocator)
	loaded.ok = true

	return loaded
}

Reload_Svg_From_File :: proc(asset: ^Svg_Asset, path: string, opts := Svg_Load_Options{}) -> Svg_Load_Result {
	if asset == nil {
		result: Svg_Load_Result
		result.allocator = context.allocator
		result.diagnostics = make([dynamic]Svg_Diagnostic, context.allocator)
		svg_push(&result, .Invalid_Handle, "nil SVG asset", 0, 0)

		return result
	}

	replacement, loaded := Load_Svg_From_File(path, opts, asset.allocator)
	if !loaded.ok {
		Destroy_Svg_Asset(replacement)

		return loaded
	}

	svg_asset_retire(asset)
	asset^ = replacement^
	free(replacement, asset.allocator)
	loaded.ok = true

	return loaded
}

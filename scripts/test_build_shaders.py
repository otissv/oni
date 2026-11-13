#!/usr/bin/env python3
"""Shader build contracts; compilers are substituted to exercise failure paths."""

import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("build_shaders", Path(__file__).with_name("build_shaders.py"))
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


class ShaderBuildTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="oni shader contracts ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "shaders").mkdir()
        for shader in builder.SHADERS:
            shutil.copyfile(builder.ROOT / "shaders" / shader[1], self.root / "shaders" / shader[1])
        self.calls = []
        self.fail_format = None
        self.bad_metadata = False
        self.bad_msl = False
        self.corrupt_format = None
        self.addCleanup(patch.stopall)
        patch.object(builder, "run", side_effect=self.compile).start()
        patch.object(builder, "resolve_tool", side_effect=lambda name: name).start()

    def compile(self, args):
        self.calls.append(args)
        output = Path(args[args.index("-o") + 1])
        dest = args[args.index("-d") + 1] if "-d" in args else "SPIRV"
        if dest == self.fail_format:
            raise builder.BuildError("compiler failure")
        if dest == self.corrupt_format:
            output.write_bytes(b"broken")
            return
        if dest == "SPIRV":
            output.write_bytes(bytes.fromhex("03022307") + bytes(16))
        elif dest == "DXIL":
            output.write_bytes(b"DXBC" + bytes(40))
        elif dest == "MSL":
            source = "vertex float4 main0() {}" if self.bad_msl else "vertex float4 main0() {} // [[color(0), index(0)]] [[color(0), index(1)]]"
            output.write_text(source)
        else:
            shader = next(s for s in builder.SHADERS if builder.artifact_name(s[1], "spv") == Path(args[1]).name)
            output.write_text(json.dumps({"uniform_buffers": shader[3], "samplers": 99 if self.bad_metadata else shader[4], "storage_buffers": 0, "storage_textures": 0}))

    def snapshot(self):
        paths = [self.root / "gpu_shader_assets.odin", self.root / "shaders" / "compiled.json"]
        paths.extend(self.root / "shaders" / builder.artifact_name(s[1], fmt) for s in builder.SHADERS for fmt in builder.FORMATS)
        return {p.relative_to(self.root): p.read_bytes() for p in paths if p.is_file()}

    def test_all_formats_and_registry_are_built_then_reused_without_tools(self):
        builder.build(self.root)
        for shader in builder.SHADERS:
            for fmt in ("spv", "msl", "dxil"):
                self.assertTrue((self.root / "shaders" / builder.artifact_name(shader[1], fmt)).is_file())
        self.assertIn("[GPU_Shader]GPU_Shader_Asset", (self.root / "gpu_shader_assets.odin").read_text())
        self.calls.clear()
        with patch.object(builder, "resolve_tool", side_effect=AssertionError("unneeded compiler")):
            builder.build(self.root)
            builder.build(self.root, check=True)
        self.assertEqual(self.calls, [])

    def test_source_edit_and_corrupt_or_missing_artifacts_are_rejected(self):
        builder.build(self.root)
        source = self.root / "shaders" / builder.SHADERS[0][1]
        original = source.read_bytes()
        source.write_bytes(original + b"\n// edited\n")
        with self.assertRaises(builder.BuildError):
            builder.build(self.root, check=True)
        source.write_bytes(original)
        for fmt in ("spv", "msl", "dxil"):
            path = self.root / "shaders" / builder.artifact_name(builder.SHADERS[0][1], fmt)
            original = path.read_bytes()
            path.write_bytes(b"corrupt")
            with self.assertRaises(builder.BuildError):
                builder.build(self.root, check=True)
            path.unlink()
            with self.assertRaises(builder.BuildError):
                builder.build(self.root, check=True)
            path.write_bytes(original)

    def test_failed_rebuild_preserves_last_complete_bundle(self):
        builder.build(self.root)
        original = self.snapshot()
        self.fail_format = "DXIL"
        with self.assertRaises(builder.BuildError):
            builder.build(self.root, force=True)
        self.assertEqual(original, self.snapshot())
        self.assertFalse(list((self.root / "shaders").glob(".staging-*")))

    def test_resource_metadata_mismatch_prevents_publication(self):
        self.bad_metadata = True
        with self.assertRaises(builder.BuildError):
            builder.build(self.root)
        self.assertFalse((self.root / "gpu_shader_assets.odin").exists())

    def test_lost_dual_source_outputs_prevent_publication(self):
        self.bad_msl = True
        with self.assertRaises(builder.BuildError):
            builder.build(self.root)
        self.assertFalse((self.root / "gpu_shader_assets.odin").exists())

    def test_corrupt_stamp_and_generated_registry_are_rejected(self):
        builder.build(self.root)
        stamp = self.root / "shaders" / "compiled.json"
        stamp.write_text("{")
        with self.assertRaises(builder.BuildError):
            builder.build(self.root, check=True)
        builder.build(self.root)
        (self.root / "gpu_shader_assets.odin").write_text("broken")
        with self.assertRaises(builder.BuildError):
            builder.build(self.root, check=True)

    def test_invalid_compiler_outputs_are_rejected_without_publication(self):
        for fmt in ("SPIRV", "DXIL", "MSL", "JSON"):
            with self.subTest(fmt=fmt):
                self.corrupt_format = fmt
                with self.assertRaises((builder.BuildError, ValueError)):
                    builder.build(self.root)
                self.assertEqual(self.snapshot(), {})

    def test_source_change_during_compile_preserves_previous_bundle(self):
        builder.build(self.root)
        original = self.snapshot()
        compile_shader = builder.compile_shader

        def edit_then_compile(*args):
            compile_shader(*args)
            # Each worker edits its own source, avoiding a test-only write race.
            source = self.root / "shaders" / args[0][1]
            source.write_bytes(source.read_bytes() + b"\n// changed while compiling\n")

        with patch.object(builder, "compile_shader", side_effect=edit_then_compile):
            with self.assertRaises(builder.BuildError):
                builder.build(self.root, force=True)
        self.assertEqual(self.snapshot(), original)


if __name__ == "__main__":
    unittest.main()

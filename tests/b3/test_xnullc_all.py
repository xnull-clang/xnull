#!/usr/bin/env python3
"""xnullc_all.py 的 K-07 文件通道单测（不依赖 xnullc 是否已实现新 flag）。"""
import os
import tempfile
import unittest

import xnullc_all as H


class K07LimitTest(unittest.TestCase):
    def test_limit_bytes(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "ast.txt")
            note = H.write_limited(p, "x" * (H.LIMIT_BYTES + 1))
            self.assertIn("超过 16MiB", note)
            self.assertFalse(os.path.exists(p))

    def test_write_failure(self):
        note = H.write_limited("/nonexistent-b3-09-dir/ast.txt", "x")
        self.assertIn("写入失败", note)

    def test_write_ok(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "bundle.json")
            self.assertEqual(H.write_limited(p, '{"files":[]}'), "")
            self.assertEqual(open(p, "rb").read(), b'{"files":[]}')

    def test_classify_missing_file(self):
        self.assertTrue(H.is_limit_error(
            1, "readFileText: /tmp/b3/ast.txt: No such file", []))

    def test_classify_path_in_error(self):
        self.assertTrue(H.is_limit_error(1, "读取失败 /tmp/b3/ast.txt", ["/tmp/b3/ast.txt"]))

    def test_classify_argmax(self):
        self.assertTrue(H.is_limit_error(
            125, "[Errno 7] Argument list too long: xnullc", []))

    def test_normal_failure_not_limit(self):
        self.assertFalse(H.is_limit_error(1, "parse error: unexpected token", []))


if __name__ == "__main__":
    unittest.main()

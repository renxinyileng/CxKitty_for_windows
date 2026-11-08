"""离线验证启动检查能发现旧版本, 并正确处理各平台依赖。"""
import contextlib
import importlib.util
import io
import sys
import tempfile
import unittest
from importlib import metadata
from pathlib import Path
from unittest.mock import patch

from packaging.markers import default_environment

import check_env


class VersionCheckTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.requirements = Path(self.temp.name) / "requirements.txt"

    def check_versions(self, text, versions):
        self.requirements.write_text(text, encoding="utf-8-sig")

        def installed_version(name):
            if name not in versions:
                raise metadata.PackageNotFoundError(name)
            return versions[name]

        with patch.object(check_env.metadata, "version", side_effect=installed_version):
            return check_env.version_issues(self.requirements)

    def test_rejects_old_transitive_dependency(self):
        issues = self.check_versions("multidict==6.9.1\n", {"multidict": "6.7.1"})
        self.assertEqual(len(issues), 1)
        self.assertIn("6.7.1", issues[0])
        self.assertIn("==6.9.1", issues[0])

    def test_current_versions_pass_with_index_comments_and_bom(self):
        self.assertEqual(
            self.check_versions(
                "--index-url https://pypi.org/simple\n\n# locked dependency\n"
                "multidict==6.9.1\n",
                {"multidict": "6.9.1"},
            ),
            [],
        )

    def test_platform_markers_select_correct_opencv(self):
        requirements = (
            'opencv-python==5.0.0.93; sys_platform == "win32" or sys_platform == "darwin"\n'
            'opencv-python-headless==5.0.0.93; sys_platform == "linux"\n'
        )
        for platform in ("win32", "darwin", "linux"):
            package = "opencv-python-headless" if platform == "linux" else "opencv-python"
            environment = {**default_environment(), "sys_platform": platform}
            with self.subTest(platform=platform), patch(
                "packaging.markers.default_environment", return_value=environment
            ):
                self.assertEqual(self.check_versions(requirements, {package: "5.0.0.93"}), [])

    def test_missing_transitive_dependency_fails(self):
        self.assertEqual(self.check_versions("multidict==6.9.1\n", {}), ["缺少 multidict"])

    def test_malformed_version_fails(self):
        self.assertTrue(self.check_versions("multidict==6.9.1\n", {"multidict": "broken"}))

    def test_malformed_requirements_fail(self):
        self.assertTrue(self.check_versions("not a requirement!\n", {}))

    def test_missing_requirements_fail(self):
        self.assertTrue(check_env.version_issues(self.requirements))

    def test_packaging_missing_requests_repair(self):
        with patch.dict(sys.modules, {"packaging.requirements": None}):
            self.assertIn("packaging", check_env.version_issues(self.requirements)[0])

    def test_deleted_module_detected_even_with_metadata(self):
        with patch.object(check_env, "REQUIRED", {"qrcode": "qrcode"}), patch.object(
            importlib.util, "find_spec", return_value=None
        ):
            self.assertEqual(check_env.missing_packages(), ["qrcode"])

    def test_main_rejects_version_mismatch_even_when_modules_exist(self):
        with patch.object(check_env, "missing_packages", return_value=[]), patch.object(
            check_env, "version_issues", return_value=["multidict: 需要升级"]
        ), patch.object(sys, "argv", ["check_env.py", "--quiet"]):
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                self.assertEqual(check_env.main(), 1)
            self.assertEqual(output.getvalue(), "")

    def test_unsupported_python_does_not_skip_all_version_checks(self):
        with patch.object(sys, "version_info", (3, 14, 0)), patch.object(
            sys, "argv", ["check_env.py", "--quiet"]
        ):
            self.assertEqual(check_env.main(), 1)


if __name__ == "__main__":
    unittest.main()

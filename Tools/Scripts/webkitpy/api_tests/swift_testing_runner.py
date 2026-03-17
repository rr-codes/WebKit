# Copyright (C) 2026 Apple Inc. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1.  Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2.  Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY APPLE INC. AND ITS CONTRIBUTORS ``AS IS'' AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL APPLE INC. OR ITS CONTRIBUTORS BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
# ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import json
import logging
import shutil
import subprocess
import tempfile
import time
from typing import Optional

from webkitpy.api_tests.runner import Runner

_log = logging.getLogger(__name__)


class SwiftTestingRunner(object):
    SWIFT_TESTING_PREFIX = "SwiftTesting"

    def __init__(self, port, stream):
        self._port = port
        self._stream = stream
        self.results = {}

    def _workspace_path(self) -> Optional[str]:
        webkit_base = self._port.webkit_base()
        internal_workspace = self._port.host.filesystem.join(
            webkit_base, "..", "Internal", "WebKit", "WebKit.xcworkspace"
        )
        if self._port.host.filesystem.exists(internal_workspace):
            return self._port.host.filesystem.abspath(internal_workspace)
        fallback_workspace = self._port.host.filesystem.join(
            webkit_base, "WebKit.xcworkspace"
        )
        if self._port.host.filesystem.exists(fallback_workspace):
            return self._port.host.filesystem.abspath(fallback_workspace)
        return None

    def _configuration(self) -> str:
        config = self._port.get_option("configuration")
        if config and config.lower() == "release":
            return "Release"
        return "Debug"

    def _build_dir_args(self) -> list[str]:
        build_path = self._port._build_path()
        build_dir = self._port.host.filesystem.dirname(build_path)
        return [f"SYMROOT={build_dir}", f"OBJROOT={build_dir}"]

    def _destination(self) -> str:
        return "platform=macOS"

    def _scheme(self) -> str:
        return "Everything up to WebKit + Tools"

    @staticmethod
    def _only_testing_arg(test_name: str) -> str:
        """Convert a SwiftTesting.Suite.method name to an -only-testing: xcodebuild arg."""
        stripped = test_name[len(SwiftTestingRunner.SWIFT_TESTING_PREFIX) + 1:]
        parts = stripped.split(".")
        return f"-only-testing:TestWebKitAPIBundle/{'/'.join(parts)}"

    @staticmethod
    def _is_suite_level(test_name):
        """A suite-level name has no method component, e.g. SwiftTesting.SuiteName"""
        stripped = test_name[len(SwiftTestingRunner.SWIFT_TESTING_PREFIX) + 1:]
        return "." not in stripped

    def run(self, test_names: list[str]):
        workspace = self._workspace_path()
        if not workspace:
            _log.error("No xcworkspace found, cannot run Swift Testing tests")
            return

        verbose = self._port.get_option("verbose")
        timeout = self._port.get_option("timeout")

        has_suite_level = any(self._is_suite_level(t) for t in test_names)

        run_all = len(test_names) == 1 and test_names[0] == self.SWIFT_TESTING_PREFIX
        if run_all:
            has_suite_level = True

        result_bundle_dir = tempfile.mkdtemp()
        result_bundle_path = result_bundle_dir + ".xcresult"
        shutil.rmtree(result_bundle_dir)

        command = [
            "xcodebuild",
            "test-without-building",
            "-workspace",
            workspace,
            "-scheme",
            self._scheme(),
            "-destination",
            self._destination(),
            "-configuration",
            self._configuration(),
            "-collect-test-diagnostics",
            "never",
            "-resultBundlePath",
            result_bundle_path,
        ]

        if not run_all:
            for test_name in test_names:
                if self._is_suite_level(test_name):
                    stripped = test_name[len(self.SWIFT_TESTING_PREFIX) + 1:]
                    command.append(f"-only-testing:TestWebKitAPIBundle/{stripped}")
                else:
                    command.append(self._only_testing_arg(test_name))
        else:
            command.append("-only-testing:TestWebKitAPIBundle")

        if timeout:
            command.extend(["-default-test-execution-time-allowance", str(timeout)])

        command.extend(self._build_dir_args())

        started = time.time()

        try:
            _log.debug(f"Running Swift tests: {' '.join(command)}")
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
            )

            for line in process.stdout or []:
                if verbose:
                    self._stream.writeln(line.rstrip())

            process.wait()

            self._parse_xcresult(result_bundle_path, test_names, has_suite_level)

        except Exception as e:
            elapsed = time.time() - started
            _log.error(f"Exception running Swift tests: {e}")
            for test_name in test_names:
                if test_name not in self.results:
                    self.results[test_name] = (Runner.STATUS_CRASHED, str(e), elapsed)
        finally:
            if self._port.host.filesystem.exists(result_bundle_path):
                shutil.rmtree(result_bundle_path, ignore_errors=True)

    def _parse_xcresult(self, result_bundle_path: str, test_names: list[str], has_suite_level: bool):
        """Parse test results from an xcresult bundle using xcresulttool."""
        try:
            output = subprocess.run(
                [
                    "xcrun",
                    "xcresulttool",
                    "get",
                    "test-results",
                    "tests",
                    "--path",
                    result_bundle_path,
                ],
                capture_output=True,
                text=True,
                check=True,
            )
            data = json.loads(output.stdout)
        except (subprocess.CalledProcessError, json.JSONDecodeError, ValueError) as e:
            _log.error(f"Failed to parse xcresult bundle: {e}")
            for test_name in test_names:
                if test_name not in self.results:
                    self.results[test_name] = (Runner.STATUS_CRASHED, str(e), 0)
            return

        # Collect all test case nodes from the recursive tree
        test_cases = []
        self._collect_test_cases(data.get("testNodes", []), [], test_cases)

        if has_suite_level:
            run_all = len(test_names) == 1 and test_names[0] == self.SWIFT_TESTING_PREFIX

            if run_all:
                # Running the entire bundle — discover all tests from output
                for tc in test_cases:
                    suites = [s for s in tc["suites"] if s != "TestWebKitAPIBundle"]
                    suite_path = ".".join(suites) if suites else "Unknown"
                    full_name = f"{self.SWIFT_TESTING_PREFIX}.{suite_path}.{tc['name']}"
                    status = self._map_result(tc["result"])
                    duration = tc["duration"]
                    failure_output = (
                        "\n".join(tc["failure_messages"]) if tc["failure_messages"] else ""
                    )
                    self.results[full_name] = (status, failure_output, duration)
                    status_name = Runner.NAME_FOR_STATUS[status]
                    elapsed_log = (
                        f" (took {round(duration, 1)} seconds)"
                        if duration > Runner.ELAPSED_THRESHOLD
                        else ""
                    )
                    self._stream.writeln(f"{full_name} {status_name}{elapsed_log}")
            else:
                # Group suite-level names so we can discover tests from output
                suite_level_suites = set()
                targeted_tests = []
                for t in test_names:
                    if self._is_suite_level(t):
                        suite_level_suites.add(t[len(self.SWIFT_TESTING_PREFIX) + 1:])
                    else:
                        targeted_tests.append(t)

                # Apply suite-level results for discovered tests
                for suite_name in suite_level_suites:
                    suite_cases = [tc for tc in test_cases if suite_name in tc["suites"]]
                    self._apply_suite_level_results(suite_cases, suite_name)

                # Apply targeted results for explicitly named tests
                if targeted_tests:
                    self._apply_targeted_results(test_cases, targeted_tests)
        else:
            self._apply_targeted_results(test_cases, test_names)

    def _collect_test_cases(self, nodes, parent_suites, test_cases):
        """Recursively walk testNodes to find Test Case leaf nodes."""
        for node in nodes:
            node_type = node.get("nodeType", "")
            name = node.get("name", "")
            children = node.get("children", [])

            if node_type == "Test Suite":
                self._collect_test_cases(children, parent_suites + [name], test_cases)
            elif node_type == "Test Case":
                failure_messages = []
                for child in children:
                    if child.get("nodeType") == "Failure Message":
                        failure_messages.append(child.get("name", ""))

                test_cases.append(
                    {
                        "name": name,
                        "nodeIdentifier": node.get("nodeIdentifier", ""),
                        "result": node.get("result", ""),
                        "duration": node.get("durationInSeconds", 0),
                        "suites": parent_suites,
                        "failure_messages": failure_messages,
                    }
                )
            else:
                # Recurse into any other container nodes (e.g. Test Plan, Test Bundle)
                self._collect_test_cases(children, parent_suites, test_cases)

    def _map_result(self, result_str: str):
        if result_str == "Passed":
            return Runner.STATUS_PASSED
        elif result_str == "Failed":
            return Runner.STATUS_FAILED
        elif result_str == "Skipped":
            return Runner.STATUS_DISABLED
        return Runner.STATUS_CRASHED

    def _apply_suite_level_results(self, test_cases: list[dict[str, str]], suite_name: str):
        """Apply results when running at suite level (discover tests from output)."""
        for tc in test_cases:
            method_name = tc["name"]
            full_name = f"{self.SWIFT_TESTING_PREFIX}.{suite_name}.{method_name}"
            status = self._map_result(tc["result"])
            duration = float(tc["duration"])
            failure_output = (
                "\n".join(tc["failure_messages"]) if tc["failure_messages"] else ""
            )

            self.results[full_name] = (status, failure_output, duration)
            status_name = Runner.NAME_FOR_STATUS[status]
            elapsed_log = (
                f" (took {round(duration, 1)} seconds)"
                if duration > Runner.ELAPSED_THRESHOLD
                else ""
            )
            self._stream.writeln(f"{full_name} {status_name}{elapsed_log}")

    def _apply_targeted_results(self, test_cases: list[dict[str, str]], suite_tests: list[str]):
        """Apply results when running specific tests."""
        # Build a map from method name to test case result
        tc_by_method = {}
        for tc in test_cases:
            tc_by_method[tc["name"]] = tc
            # Also index by nodeIdentifier's last component for robustness
            node_id = tc["nodeIdentifier"]
            if "/" in node_id:
                tc_by_method[node_id.split("/")[-1]] = tc

        for test_name in suite_tests:
            stripped = test_name[len(self.SWIFT_TESTING_PREFIX) + 1:]
            method = stripped.split(".", 1)[1] if "." in stripped else stripped

            tc = tc_by_method.get(method)
            if tc:
                status = self._map_result(tc["result"])
                duration = tc["duration"]
                failure_output = (
                    "\n".join(tc["failure_messages"]) if tc["failure_messages"] else ""
                )
            else:
                # Test was requested but not found in results — likely crashed before running
                status = Runner.STATUS_CRASHED
                duration = 0
                failure_output = f"Test {test_name} not found in xcresult output"

            self.results[test_name] = (status, failure_output, duration)
            status_name = Runner.NAME_FOR_STATUS[status]
            elapsed_log = (
                f" (took {round(duration, 1)} seconds)"
                if duration > Runner.ELAPSED_THRESHOLD
                else ""
            )
            self._stream.writeln(f"{test_name} {status_name}{elapsed_log}")

    def result_map_by_status(self, status=None):
        result_map = {}
        for test_name, result in self.results.items():
            if result[0] == status:
                result_map[test_name] = result[1]
        return result_map

"""Purpose: Prove the BYO subnet tag tool's read and exact-delete contracts.

What this is not: These fixtures are not evidence of a live ROSA or EC2 operation.
Prerequisites: Python 3.11+ and the repository's tool source.
Authoritative references: https://docs.python.org/3/library/unittest.html
"""

from __future__ import annotations

import importlib.util
import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from dataclasses import dataclass
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "operations" / "byo-subnet-tags.py"
SPEC = importlib.util.spec_from_file_location("byo_subnet_tags", MODULE_PATH)
assert SPEC and SPEC.loader
TOOL = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = TOOL
SPEC.loader.exec_module(TOOL)

CLUSTER_A = "a" * 32
CLUSTER_B = "b" * 32
SUBNET_A = "subnet-0abc"
SUBNET_B = "subnet-0def"


@dataclass
class FakeInventory:
    observations: dict[str, object]

    def observe(self, cluster_id: str) -> object:
        return self.observations[cluster_id]


class FakeAws:
    def __init__(self, maps: dict[str, dict[str, str]]) -> None:
        self.maps = json.loads(json.dumps(maps))
        self.consistent_reads = 0
        self.complete_reads = 0
        self.deleted: list[tuple[str, str, str]] = []
        self.after_delete_hook = None

    def read_consistent_maps(self, subnet_ids: list[str]) -> dict[str, dict[str, str]]:
        self.consistent_reads += 1
        return {subnet_id: dict(self.maps[subnet_id]) for subnet_id in subnet_ids}

    def read_complete_maps(self, subnet_ids: list[str]) -> dict[str, dict[str, str]]:
        self.complete_reads += 1
        if self.after_delete_hook is not None and self.deleted:
            self.after_delete_hook(self.maps)
            self.after_delete_hook = None
        return {subnet_id: dict(self.maps[subnet_id]) for subnet_id in subnet_ids}

    def delete_exact_tag(self, subnet_id: str, key: str, value: str) -> None:
        self.deleted.append((subnet_id, key, value))
        if self.maps[subnet_id].get(key) != value:
            raise AssertionError("test attempted a non-exact delete")
        del self.maps[subnet_id][key]


class FailingDeleteAws(FakeAws):
    def __init__(self, tag_maps: dict[str, dict[str, str]], fail_at: int) -> None:
        super().__init__(tag_maps)
        self.fail_at = fail_at
        self.delete_attempts = 0
        self.create_calls = 0

    def delete_exact_tag(self, subnet_id: str, key: str, value: str) -> None:
        self.delete_attempts += 1
        if self.delete_attempts == self.fail_at:
            raise TOOL.ToolError("AWS EC2 mutation failed: fixture denial")
        super().delete_exact_tag(subnet_id, key, value)

    def create_exact_tag(self, subnet_id: str, key: str, value: str) -> None:
        self.create_calls += 1


def maps() -> dict[str, dict[str, str]]:
    return {
        SUBNET_A: {
            "Name": "private-a",
            "aws:cloudformation:stack-id": "system",
            f"kubernetes.io/cluster/{CLUSTER_A}": "shared",
            f"kubernetes.io/cluster/{CLUSTER_B}": "shared",
        },
        SUBNET_B: {
            "Name": "private-b",
            "environment": "test",
            f"kubernetes.io/cluster/{CLUSTER_A}": "shared",
        },
    }


def observation(state: str, detail: str = "fixture") -> object:
    return TOOL.InventoryObservation(state, detail)


class CheckTests(unittest.TestCase):
    def test_check_is_read_only_and_excludes_aws_tags_from_capacity(self) -> None:
        aws = FakeAws(maps())

        result = TOOL.run_check(aws, [SUBNET_A, SUBNET_B], None)

        self.assertEqual(result, 0)
        self.assertEqual(aws.deleted, [])
        self.assertEqual(aws.complete_reads, 0)
        report = TOOL.build_report("check", maps())
        summaries = {item.subnet_id: item for item in report.subnets}
        self.assertEqual(summaries[SUBNET_A].user_tags, 3)
        self.assertEqual(summaries[SUBNET_A].remaining_slots, 47)
        self.assertEqual(len(summaries[SUBNET_A].cluster_keys), 2)

    def test_check_returns_nonzero_when_user_tag_limit_is_reached(self) -> None:
        full = {SUBNET_A: {f"tag-{index}": "value" for index in range(50)}}
        aws = FakeAws(full)

        self.assertEqual(TOOL.run_check(aws, [SUBNET_A], None), 2)
        self.assertEqual(aws.deleted, [])


class ClassificationTests(unittest.TestCase):
    def test_three_inventory_states_remain_distinct(self) -> None:
        tag_maps = {
            SUBNET_A: {
                f"kubernetes.io/cluster/{CLUSTER_A}": "shared",
                f"kubernetes.io/cluster/{CLUSTER_B}": "shared",
            }
        }
        inventory = FakeInventory(
            {
                CLUSTER_A: observation("present", "found"),
                CLUSTER_B: observation("absent", "not found"),
            }
        )

        report = TOOL.build_report("clean", tag_maps, inventory, set())

        states = {row.cluster_id: row.state for row in report.rows}
        self.assertEqual(states, {CLUSTER_A: "present", CLUSTER_B: "absent"})
        self.assertEqual(report.deletable, 1)
        self.assertEqual(report.refused, 1)

    def test_inventory_error_is_unobserved_and_not_absent(self) -> None:
        inventory = FakeInventory({CLUSTER_A: observation("unobserved", "HTTP 401")})

        report = TOOL.build_report(
            "clean",
            {SUBNET_A: {f"kubernetes.io/cluster/{CLUSTER_A}": "shared"}},
            inventory,
            set(),
        )

        self.assertEqual(report.rows[0].state, "unobserved")
        self.assertEqual(report.rows[0].action, "keep")
        self.assertEqual(report.rows[0].absence_basis, "NONE")

    def test_assertion_fills_unobserved_gap_and_is_marked(self) -> None:
        inventory = FakeInventory({CLUSTER_A: observation("unobserved", "timeout")})

        report = TOOL.build_report(
            "clean",
            {SUBNET_A: {f"kubernetes.io/cluster/{CLUSTER_A}": "shared"}},
            inventory,
            {CLUSTER_A},
        )

        self.assertEqual(report.rows[0].state, "asserted-absent")
        self.assertEqual(report.rows[0].action, "delete")
        self.assertEqual(report.rows[0].absence_basis, "ASSERTED")

    def test_assertion_cannot_override_present_inventory(self) -> None:
        inventory = FakeInventory({CLUSTER_A: observation("present", "found")})

        with self.assertRaisesRegex(TOOL.ToolError, "cannot override present"):
            TOOL.build_report(
                "clean",
                {SUBNET_A: {f"kubernetes.io/cluster/{CLUSTER_A}": "shared"}},
                inventory,
                {CLUSTER_A},
            )

    def test_unused_assertion_refuses_typo_or_wrong_scope(self) -> None:
        inventory = FakeInventory({CLUSTER_A: observation("absent")})

        with self.assertRaisesRegex(TOOL.ToolError, "were not found"):
            TOOL.build_report(
                "clean",
                {SUBNET_A: {f"kubernetes.io/cluster/{CLUSTER_A}": "shared"}},
                inventory,
                {CLUSTER_B},
            )


class CleanTests(unittest.TestCase):
    def test_clean_without_apply_never_mutates(self) -> None:
        aws = FakeAws(maps())
        inventory = FakeInventory(
            {CLUSTER_A: observation("absent"), CLUSTER_B: observation("absent")}
        )

        result = TOOL.run_clean(
            aws,
            inventory,
            [SUBNET_A, SUBNET_B],
            set(),
            False,
            False,
            None,
            None,
        )

        self.assertEqual(result, 0)
        self.assertEqual(aws.deleted, [])
        self.assertEqual(aws.complete_reads, 0)

    def test_apply_deletes_only_exact_proved_keys_and_preserves_every_other_tag(self) -> None:
        aws = FakeAws(maps())
        inventory = FakeInventory(
            {CLUSTER_A: observation("absent"), CLUSTER_B: observation("present")}
        )
        before = json.loads(json.dumps(aws.maps))
        with tempfile.TemporaryDirectory() as directory:
            report_path = Path(directory) / "report.json"
            result = TOOL.run_clean(
                aws,
                inventory,
                [SUBNET_A, SUBNET_B],
                set(),
                True,
                True,
                Path(directory),
                report_path,
            )
            snapshots = list(Path(directory).glob("subnet-tags-before-*.json"))
            payload = json.loads(report_path.read_text(encoding="utf-8"))

        self.assertEqual(result, 0)
        self.assertEqual(
            aws.deleted,
            [
                (SUBNET_A, f"kubernetes.io/cluster/{CLUSTER_A}", "shared"),
                (SUBNET_B, f"kubernetes.io/cluster/{CLUSTER_A}", "shared"),
            ],
        )
        self.assertEqual(len(snapshots), 1)
        self.assertNotIn("apply_result", payload)
        self.assertEqual(aws.maps[SUBNET_A]["Name"], before[SUBNET_A]["Name"])
        self.assertEqual(
            aws.maps[SUBNET_A][f"kubernetes.io/cluster/{CLUSTER_B}"], "shared"
        )

    def test_apply_detects_any_non_target_byte_difference(self) -> None:
        aws = FakeAws(maps())
        inventory = FakeInventory(
            {CLUSTER_A: observation("absent"), CLUSTER_B: observation("present")}
        )
        aws.after_delete_hook = lambda current: current[SUBNET_A].update({"Name": "changed"})

        with (
            tempfile.TemporaryDirectory() as directory,
            self.assertRaisesRegex(TOOL.ToolError, "post-delete maps differ"),
        ):
            TOOL.run_clean(
                aws,
                inventory,
                [SUBNET_A, SUBNET_B],
                set(),
                True,
                True,
                Path(directory),
                None,
            )

    def test_apply_refuses_if_tag_map_changes_after_snapshot(self) -> None:
        class ChangingAws(FakeAws):
            def read_complete_maps(self, subnet_ids: list[str]) -> dict[str, dict[str, str]]:
                value = super().read_complete_maps(subnet_ids)
                if self.complete_reads == 1:
                    value[SUBNET_A]["new-tag"] = "appeared"
                return value

        aws = ChangingAws(maps())
        inventory = FakeInventory(
            {CLUSTER_A: observation("absent"), CLUSTER_B: observation("present")}
        )

        with (
            tempfile.TemporaryDirectory() as directory,
            self.assertRaisesRegex(TOOL.ToolError, "changed before deletion"),
        ):
            TOOL.run_clean(
                aws,
                inventory,
                [SUBNET_A, SUBNET_B],
                set(),
                True,
                True,
                Path(directory),
                None,
            )
        self.assertEqual(aws.deleted, [])

    def test_apply_requires_snapshot_destination(self) -> None:
        aws = FakeAws(maps())
        inventory = FakeInventory(
            {CLUSTER_A: observation("absent"), CLUSTER_B: observation("present")}
        )

        with self.assertRaisesRegex(TOOL.ToolError, "--snapshot-dir is required"):
            TOOL.run_clean(
                aws,
                inventory,
                [SUBNET_A, SUBNET_B],
                set(),
                True,
                True,
                None,
                None,
            )
        self.assertEqual(aws.deleted, [])

    def test_interactive_apply_requires_exact_confirmation(self) -> None:
        aws = FakeAws(maps())
        inventory = FakeInventory(
            {CLUSTER_A: observation("absent"), CLUSTER_B: observation("present")}
        )

        with (
            tempfile.TemporaryDirectory() as directory,
            self.assertRaisesRegex(TOOL.ToolError, "confirmation did not match"),
        ):
            TOOL.run_clean(
                aws,
                inventory,
                [SUBNET_A, SUBNET_B],
                set(),
                True,
                False,
                Path(directory),
                None,
                input_fn=lambda _: "no",
            )
        self.assertEqual(aws.deleted, [])

    def test_json_report_records_proved_and_refused_rows(self) -> None:
        aws = FakeAws(maps())
        inventory = FakeInventory(
            {CLUSTER_A: observation("absent"), CLUSTER_B: observation("present")}
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "report.json"
            TOOL.run_clean(
                aws,
                inventory,
                [SUBNET_A, SUBNET_B],
                set(),
                False,
                False,
                None,
                path,
            )
            payload = json.loads(path.read_text(encoding="utf-8"))

        self.assertEqual(payload["deletable"], 2)
        self.assertEqual(payload["refused"], 1)
        self.assertEqual({row["absence_basis"] for row in payload["rows"]}, {"PROVED", "NONE"})

    def test_delete_failure_reports_acknowledged_extent_without_rollback_or_reread(self) -> None:
        inventory = FakeInventory(
            {CLUSTER_A: observation("absent"), CLUSTER_B: observation("present")}
        )
        for fail_at, expected_deleted in ((1, []), (2, [(SUBNET_A, CLUSTER_A)])):
            with self.subTest(fail_at=fail_at), tempfile.TemporaryDirectory() as directory:
                aws = FailingDeleteAws(maps(), fail_at)
                root = Path(directory)
                report_path = root / "report.json"
                stderr = io.StringIO()
                stdout = io.StringIO()
                argv = [
                    "clean",
                    "--subnet-id",
                    SUBNET_A,
                    "--subnet-id",
                    SUBNET_B,
                    "--region",
                    "us-east-1",
                    "--snapshot-dir",
                    str(root / "snapshots"),
                    "--report-json",
                    str(report_path),
                    "--apply",
                    "--yes",
                ]
                with (
                    mock.patch.object(TOOL, "AwsCli", return_value=aws),
                    mock.patch.object(TOOL, "OcmInventory", return_value=inventory),
                    redirect_stdout(stdout),
                    redirect_stderr(stderr),
                ):
                    result = TOOL.main(argv)

                output = stderr.getvalue()
                payload = json.loads(report_path.read_text(encoding="utf-8"))
                snapshots = list((root / "snapshots").glob("subnet-tags-before-*.json"))

                self.assertEqual(result, 2)
                self.assertIn("SNAPSHOT path=", output)
                self.assertIn("REFUSED: AWS EC2 mutation failed: fixture denial", output)
                self.assertLess(
                    output.index("SNAPSHOT path="),
                    output.index("REFUSED: AWS EC2 mutation failed: fixture denial"),
                )
                self.assertEqual(len(snapshots), 1)
                self.assertEqual(aws.complete_reads, 1)
                self.assertEqual(aws.create_calls, 0)
                self.assertEqual(
                    [(item["subnet_id"], item["tag_key"].removeprefix(TOOL.CLUSTER_TAG_PREFIX))
                     for item in payload["apply_result"]["deleted"]],
                    expected_deleted,
                )
                self.assertEqual(payload["apply_result"]["status"], "failed")
                self.assertEqual(
                    payload["apply_result"]["error"],
                    "AWS EC2 mutation failed: fixture denial",
                )
                self.assertEqual(payload["apply_result"]["snapshot_path"], str(snapshots[0]))
                if expected_deleted:
                    deleted_line = (
                        f"DELETED subnet={SUBNET_A} "
                        f"key={TOOL.CLUSTER_TAG_PREFIX}{CLUSTER_A}"
                    )
                    self.assertIn(deleted_line, output)
                    self.assertLess(
                        output.index(deleted_line), output.index("SNAPSHOT path=")
                    )
                else:
                    self.assertNotIn("DELETED subnet=", output)


class InputTests(unittest.TestCase):
    def test_subnet_list_rejects_discovery_shaped_or_invalid_values(self) -> None:
        with self.assertRaisesRegex(TOOL.ToolError, "invalid subnet id"):
            TOOL.unique_subnets(["vpc-0123"])

    def test_source_has_one_exact_delete_call_and_no_force_option(self) -> None:
        source = MODULE_PATH.read_text(encoding="utf-8")

        self.assertEqual(source.count('"delete-tags"'), 1)
        self.assertNotIn('"create-tags"', source)
        self.assertNotIn("--force", source)
        self.assertNotIn("describe-vpcs", source)

    def test_network_validator_delegates_only_to_check(self) -> None:
        source = (ROOT / "scripts" / "validate" / "byo-network.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn('byo-subnet-tags.py" check', source)
        self.assertNotIn('byo-subnet-tags.py" clean', source)

    def test_jenkins_apply_requires_both_visible_mutation_flags(self) -> None:
        source = (
            ROOT / "examples" / "byo-subnet-tags" / "jenkins" / "Jenkinsfile"
        ).read_text(encoding="utf-8")

        self.assertIn("clean --apply --yes", source)
        self.assertIn("defaultValue: false", source)
        self.assertIn("archiveArtifacts", source)

    def test_iam_policy_scopes_only_delete_to_exact_subnet_resources(self) -> None:
        path = ROOT / "examples" / "byo-subnet-tags" / "jenkins" / "iam-policy.json"
        policy = json.loads(path.read_text(encoding="utf-8"))
        read, delete = policy["Statement"]

        self.assertEqual(read["Resource"], "*")
        self.assertEqual(delete["Action"], "ec2:DeleteTags")
        self.assertEqual(delete["Resource"], ["<subnet-arn-1>", "<subnet-arn-2>"])
        self.assertEqual(
            delete["Condition"]["ForAllValues:StringLike"]["aws:TagKeys"],
            "kubernetes.io/cluster/*",
        )

    def test_each_path_guide_contains_the_complete_path_contract(self) -> None:
        guides = {
            "manual": ROOT / "docs" / "operations" / "byo-subnet-tags-manual.md",
            "jenkins": ROOT / "docs" / "operations" / "byo-subnet-tags-jenkins.md",
        }
        required = ["## Prerequisites", "## Cleanup", "## Troubleshooting"]

        for name, path in guides.items():
            with self.subTest(path=name):
                text = path.read_text(encoding="utf-8")
                for heading in required:
                    self.assertIn(heading, text)
                self.assertIn("scripts/operations/byo-subnet-tags.py", text)
                self.assertIn("--apply", text)
                self.assertIn("--assume-absent", text)
                self.assertIn("unobserved", text)


if __name__ == "__main__":
    unittest.main()

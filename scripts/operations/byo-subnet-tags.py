#!/usr/bin/env python3
"""Purpose: Inspect and explicitly clean ROSA ownership tags on named BYO subnets.

What this is not: This is not a VPC discovery tool or unattended destroy hook.
Prerequisites: Python 3.11+, AWS CLI credentials, and an optional owner-only OCM token file.
Authoritative references: https://docs.aws.amazon.com/cli/latest/reference/ec2/delete-tags.html
"""

from __future__ import annotations

import argparse
import copy
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable
from dataclasses import asdict, dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Protocol

CLUSTER_TAG_PREFIX = "kubernetes.io/cluster/"
MAX_USER_TAGS = 50
WARNING_REMAINING = 5
DEFAULT_OCM_API = "https://api.openshift.com/api/clusters_mgmt/v1"
ROSA_CLUSTER_ID = re.compile(r"^[a-z0-9]{32}$")


class ToolError(RuntimeError):
    """A fail-closed condition that makes reporting or mutation unsafe."""


class AwsApi(Protocol):
    """The EC2 operations used by the two command paths."""

    def read_consistent_maps(self, subnet_ids: list[str]) -> dict[str, dict[str, str]]:
        """Read tags through both EC2 read APIs and require exact agreement."""

    def read_complete_maps(self, subnet_ids: list[str]) -> dict[str, dict[str, str]]:
        """Read authoritative complete tag maps from DescribeSubnets."""

    def delete_exact_tag(self, subnet_id: str, key: str, value: str) -> None:
        """Delete one exact key and its observed value from one exact subnet."""


@dataclass(frozen=True)
class InventoryObservation:
    state: str
    detail: str


@dataclass(frozen=True)
class TagRow:
    subnet_id: str
    tag_key: str
    cluster_id: str
    state: str
    action: str
    absence_basis: str
    detail: str


@dataclass(frozen=True)
class SubnetSummary:
    subnet_id: str
    user_tags: int
    remaining_slots: int
    cluster_keys: list[str]


@dataclass(frozen=True)
class Report:
    command: str
    subnets: list[SubnetSummary]
    rows: list[TagRow]
    keys_found: int
    deletable: int
    refused: int
    slots_recoverable: int


class AwsCli:
    """Invoke AWS CLI without a shell so identifiers are never re-parsed."""

    def __init__(self, region: str) -> None:
        self.region = region

    def _run(self, args: list[str]) -> dict[str, object]:
        command = ["aws", "ec2", *args, "--region", self.region, "--output", "json"]
        completed = subprocess.run(command, check=False, capture_output=True, text=True)
        if completed.returncode != 0:
            detail = completed.stderr.strip() or "AWS CLI returned no diagnostic"
            raise ToolError(f"AWS EC2 read failed: {detail}")
        try:
            value = json.loads(completed.stdout)
        except json.JSONDecodeError as exc:
            raise ToolError(f"AWS EC2 returned invalid JSON: {exc}") from exc
        if not isinstance(value, dict):
            raise ToolError("AWS EC2 returned an unexpected JSON shape")
        return value

    def _run_empty(self, args: list[str]) -> None:
        command = ["aws", "ec2", *args, "--region", self.region]
        completed = subprocess.run(command, check=False, capture_output=True, text=True)
        if completed.returncode != 0:
            detail = completed.stderr.strip() or "AWS CLI returned no diagnostic"
            raise ToolError(f"AWS EC2 mutation failed: {detail}")

    def _describe_tags(self, subnet_ids: list[str]) -> dict[str, dict[str, str]]:
        values = ",".join(subnet_ids)
        payload = self._run(
            ["describe-tags", "--filters", f"Name=resource-id,Values={values}"]
        )
        result = {subnet_id: {} for subnet_id in subnet_ids}
        tags = payload.get("Tags")
        if not isinstance(tags, list):
            raise ToolError("DescribeTags response has no Tags list")
        for item in tags:
            if not isinstance(item, dict):
                raise ToolError("DescribeTags returned a non-object tag")
            subnet_id = item.get("ResourceId")
            key = item.get("Key")
            value = item.get("Value")
            if subnet_id not in result or not isinstance(key, str) or not isinstance(value, str):
                raise ToolError("DescribeTags returned an unexpected resource or tag shape")
            result[subnet_id][key] = value
        return result

    def read_complete_maps(self, subnet_ids: list[str]) -> dict[str, dict[str, str]]:
        payload = self._run(["describe-subnets", "--subnet-ids", *subnet_ids])
        subnets = payload.get("Subnets")
        if not isinstance(subnets, list):
            raise ToolError("DescribeSubnets response has no Subnets list")
        result: dict[str, dict[str, str]] = {}
        for subnet in subnets:
            if not isinstance(subnet, dict) or not isinstance(subnet.get("SubnetId"), str):
                raise ToolError("DescribeSubnets returned an unexpected subnet shape")
            subnet_id = subnet["SubnetId"]
            if subnet_id not in subnet_ids or subnet_id in result:
                raise ToolError("DescribeSubnets returned an unexpected or duplicate subnet")
            tag_map: dict[str, str] = {}
            tags = subnet.get("Tags", [])
            if not isinstance(tags, list):
                raise ToolError(f"DescribeSubnets returned invalid tags for {subnet_id}")
            for item in tags:
                if not isinstance(item, dict):
                    raise ToolError(f"DescribeSubnets returned a non-object tag for {subnet_id}")
                key = item.get("Key")
                value = item.get("Value")
                if not isinstance(key, str) or not isinstance(value, str):
                    raise ToolError(f"DescribeSubnets returned an invalid tag for {subnet_id}")
                tag_map[key] = value
            result[subnet_id] = tag_map
        missing = sorted(set(subnet_ids) - set(result))
        if missing:
            raise ToolError(f"DescribeSubnets did not return: {', '.join(missing)}")
        return result

    def read_consistent_maps(self, subnet_ids: list[str]) -> dict[str, dict[str, str]]:
        tag_maps = self._describe_tags(subnet_ids)
        subnet_maps = self.read_complete_maps(subnet_ids)
        if tag_maps != subnet_maps:
            raise ToolError(
                "DescribeTags and DescribeSubnets disagree; retry after EC2 tag indexes converge"
            )
        return subnet_maps

    def delete_exact_tag(self, subnet_id: str, key: str, value: str) -> None:
        if not key.startswith(CLUSTER_TAG_PREFIX) or "*" in key or "?" in key:
            raise ToolError(f"refusing non-exact cluster tag key: {key}")
        self._run_empty(
            [
                "delete-tags",
                "--resources",
                subnet_id,
                "--tags",
                json.dumps([{"Key": key, "Value": value}]),
            ]
        )


class OcmInventory:
    """Read one exact cluster id from the owning OCM API."""

    def __init__(self, token_file: Path | None, api_url: str = DEFAULT_OCM_API) -> None:
        self.token_file = token_file
        self.api_url = api_url.rstrip("/")

    def observe(self, cluster_id: str) -> InventoryObservation:
        if not ROSA_CLUSTER_ID.fullmatch(cluster_id):
            return InventoryObservation(
                "unobserved", "tag suffix is not a 32-character ROSA cluster id"
            )
        if self.token_file is None:
            return InventoryObservation("unobserved", "no OCM token file was supplied")
        try:
            if self.token_file.stat().st_mode & 0o077:
                return InventoryObservation(
                    "unobserved", "OCM token file permits group or other access"
                )
            token = self.token_file.read_text(encoding="utf-8").strip()
        except OSError as exc:
            return InventoryObservation("unobserved", f"OCM token file read failed: {exc}")
        if not token:
            return InventoryObservation("unobserved", "OCM token file is empty")

        query = urllib.parse.urlencode(
            {"search": f"id = '{cluster_id}'", "page": 1, "size": 1}
        )
        request = urllib.request.Request(
            f"{self.api_url}/clusters?{query}",
            headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
        )
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                payload = json.load(response)
        except urllib.error.HTTPError as exc:
            return InventoryObservation("unobserved", f"OCM returned HTTP {exc.code}")
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            return InventoryObservation("unobserved", f"OCM inventory read failed: {exc}")

        items = payload.get("items") if isinstance(payload, dict) else None
        total = payload.get("total") if isinstance(payload, dict) else None
        if not isinstance(items, list) or not isinstance(total, int) or total < 0:
            return InventoryObservation(
                "unobserved", "OCM response has no valid items list and total"
            )
        exact = [item for item in items if isinstance(item, dict) and item.get("id") == cluster_id]
        if total == 1 and len(exact) == 1:
            return InventoryObservation("present", "owning inventory returned the cluster")
        if total == 0 and not exact:
            return InventoryObservation("absent", "owning inventory returned no exact cluster")
        return InventoryObservation(
            "unobserved", "OCM exact-id response was internally inconsistent"
        )


def cluster_tags(tag_maps: dict[str, dict[str, str]]) -> list[tuple[str, str, str, str]]:
    rows: list[tuple[str, str, str, str]] = []
    for subnet_id in sorted(tag_maps):
        for key, value in sorted(tag_maps[subnet_id].items()):
            if key.startswith(CLUSTER_TAG_PREFIX):
                rows.append((subnet_id, key, key.removeprefix(CLUSTER_TAG_PREFIX), value))
    return rows


def subnet_summaries(tag_maps: dict[str, dict[str, str]]) -> list[SubnetSummary]:
    summaries = []
    for subnet_id in sorted(tag_maps):
        tags = tag_maps[subnet_id]
        user_tags = sum(not key.startswith("aws:") for key in tags)
        summaries.append(
            SubnetSummary(
                subnet_id=subnet_id,
                user_tags=user_tags,
                remaining_slots=max(0, MAX_USER_TAGS - user_tags),
                cluster_keys=sorted(key for key in tags if key.startswith(CLUSTER_TAG_PREFIX)),
            )
        )
    return summaries


def build_report(
    command: str,
    tag_maps: dict[str, dict[str, str]],
    inventory: OcmInventory | object | None = None,
    assumed_absent: set[str] | None = None,
) -> Report:
    assumed_absent = assumed_absent or set()
    found = cluster_tags(tag_maps)
    candidate_ids = {cluster_id for _, _, cluster_id, _ in found}
    unused = sorted(assumed_absent - candidate_ids)
    if unused:
        raise ToolError(f"--assume-absent ids were not found in the supplied subnets: {', '.join(unused)}")

    observations: dict[str, InventoryObservation] = {}
    if command == "clean":
        if inventory is None or not hasattr(inventory, "observe"):
            raise ToolError("clean requires an owning-inventory reader")
        for cluster_id in sorted(candidate_ids):
            observation = inventory.observe(cluster_id)  # type: ignore[attr-defined]
            if observation.state not in {"absent", "present", "unobserved"}:
                raise ToolError(f"inventory returned an invalid state for {cluster_id}")
            if observation.state == "present" and cluster_id in assumed_absent:
                raise ToolError(
                    f"--assume-absent cannot override present cluster {cluster_id}"
                )
            if observation.state == "unobserved" and cluster_id in assumed_absent:
                observation = InventoryObservation(
                    "asserted-absent", f"caller assertion; inventory detail: {observation.detail}"
                )
            observations[cluster_id] = observation

    rows: list[TagRow] = []
    for subnet_id, key, cluster_id, _ in found:
        if command == "check":
            rows.append(TagRow(subnet_id, key, cluster_id, "not-queried", "keep", "none", "check is read-only"))
            continue
        observation = observations[cluster_id]
        deletable = observation.state in {"absent", "asserted-absent"}
        basis = {
            "absent": "PROVED",
            "asserted-absent": "ASSERTED",
        }.get(observation.state, "NONE")
        rows.append(
            TagRow(
                subnet_id,
                key,
                cluster_id,
                observation.state,
                "delete" if deletable else "keep",
                basis,
                observation.detail,
            )
        )

    deletable = sum(row.action == "delete" for row in rows)
    return Report(
        command=command,
        subnets=subnet_summaries(tag_maps),
        rows=rows,
        keys_found=len(rows),
        deletable=deletable,
        refused=len(rows) - deletable if command == "clean" else 0,
        slots_recoverable=deletable,
    )


def print_report(report: Report) -> None:
    for subnet in report.subnets:
        status = "OK"
        if subnet.remaining_slots == 0:
            status = "FULL"
        elif subnet.remaining_slots <= WARNING_REMAINING:
            status = "WARNING"
        print(
            f"SUBNET {subnet.subnet_id} user_tags={subnet.user_tags} "
            f"remaining={subnet.remaining_slots} status={status}"
        )
        for key in subnet.cluster_keys:
            print(f"  CLUSTER_KEY {key}")
    for row in report.rows:
        print(
            f"TAG subnet={row.subnet_id} key={row.tag_key} cluster={row.cluster_id} "
            f"state={row.state} action={row.action} absence={row.absence_basis} "
            f"detail={row.detail}"
        )
    print(
        f"SUMMARY keys_found={report.keys_found} deletable={report.deletable} "
        f"refused={report.refused} slots_recoverable={report.slots_recoverable}"
    )


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.fchmod(descriptor, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        json.dump(value, handle, indent=2, sort_keys=True)
        handle.write("\n")


def write_report(path: Path | None, report: Report) -> None:
    if path is not None:
        write_json(path, asdict(report))


def completed_deletions(targets: dict[str, set[str]]) -> list[dict[str, str]]:
    """Return API-acknowledged deletions in stable report order."""
    return [
        {"subnet_id": subnet_id, "tag_key": key}
        for subnet_id in sorted(targets)
        for key in sorted(targets[subnet_id])
    ]


def write_apply_result(
    path: Path | None,
    report: Report,
    status: str,
    targets: dict[str, set[str]],
    snapshot_path: Path,
    error: str | None = None,
) -> None:
    if path is None:
        return
    payload = asdict(report)
    payload["apply_result"] = {
        "status": status,
        "deleted": completed_deletions(targets),
        "snapshot_path": str(snapshot_path),
        "error": error,
    }
    write_json(path, payload)


def report_delete_failure(
    report_path: Path | None,
    report: Report,
    targets: dict[str, set[str]],
    snapshot_path: Path,
    error: ToolError,
) -> None:
    completed = completed_deletions(targets)
    print(f"APPLY_FAILED deleted={len(completed)}", file=sys.stderr)
    for item in completed:
        print(
            f"  DELETED subnet={item['subnet_id']} key={item['tag_key']}",
            file=sys.stderr,
        )
    print(f"  SNAPSHOT path={snapshot_path}", file=sys.stderr)
    write_apply_result(
        report_path,
        report,
        "failed",
        targets,
        snapshot_path,
        str(error),
    )


def write_snapshot(snapshot_dir: Path, tag_maps: dict[str, dict[str, str]]) -> Path:
    if snapshot_dir.exists():
        if snapshot_dir.stat().st_mode & 0o077:
            raise ToolError("snapshot directory permits group or other access")
    else:
        snapshot_dir.mkdir(mode=0o700, parents=True)
    timestamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%S.%fZ")
    path = snapshot_dir / f"subnet-tags-before-{timestamp}.json"
    if path.exists():
        raise ToolError(f"refusing to overwrite snapshot: {path}")
    write_json(path, {"captured_at": datetime.now(UTC).isoformat(), "subnets": tag_maps})
    return path


def confirm_deletion(count: int, input_fn: Callable[[str], str]) -> None:
    expected = f"delete {count} exact tags"
    supplied = input_fn(f"Type '{expected}' to continue: ").strip()
    if supplied != expected:
        raise ToolError("deletion confirmation did not match; nothing was changed")


def run_check(aws: AwsApi, subnet_ids: list[str], report_path: Path | None) -> int:
    tag_maps = aws.read_consistent_maps(subnet_ids)
    report = build_report("check", tag_maps)
    print_report(report)
    write_report(report_path, report)
    return 2 if any(item.remaining_slots == 0 for item in report.subnets) else 0


def run_clean(
    aws: AwsApi,
    inventory: OcmInventory | object,
    subnet_ids: list[str],
    assumed_absent: set[str],
    apply: bool,
    yes: bool,
    snapshot_dir: Path | None,
    report_path: Path | None,
    input_fn: Callable[[str], str] = input,
) -> int:
    tag_maps = aws.read_consistent_maps(subnet_ids)
    report = build_report("clean", tag_maps, inventory, assumed_absent)
    print_report(report)
    write_report(report_path, report)
    if not apply or report.deletable == 0:
        print("DRY_RUN no tags deleted" if not apply else "APPLY no deletable tags found")
        return 0
    if snapshot_dir is None:
        raise ToolError("--snapshot-dir is required with --apply")
    if not yes:
        confirm_deletion(report.deletable, input_fn)

    snapshot = copy.deepcopy(tag_maps)
    snapshot_path = write_snapshot(snapshot_dir, snapshot)
    current = aws.read_complete_maps(subnet_ids)
    if current != snapshot:
        raise ToolError(f"tag maps changed before deletion; snapshot retained at {snapshot_path}")

    targets: dict[str, set[str]] = {subnet_id: set() for subnet_id in subnet_ids}
    values = {(subnet_id, key): value for subnet_id, key, _, value in cluster_tags(snapshot)}
    for row in report.rows:
        if row.action == "delete":
            try:
                aws.delete_exact_tag(
                    row.subnet_id,
                    row.tag_key,
                    values[(row.subnet_id, row.tag_key)],
                )
            except ToolError as exc:
                # Report only deletes EC2 acknowledged; reconciliation remains operator-led.
                report_delete_failure(
                    report_path,
                    report,
                    targets,
                    snapshot_path,
                    exc,
                )
                raise
            targets[row.subnet_id].add(row.tag_key)

    expected = copy.deepcopy(snapshot)
    for subnet_id, keys in targets.items():
        for key in keys:
            expected[subnet_id].pop(key)
    observed = aws.read_complete_maps(subnet_ids)
    if observed != expected:
        raise ToolError(
            "post-delete maps differ from the exact expected maps; "
            f"snapshot retained at {snapshot_path}"
        )
    print(f"APPLIED deleted={report.deletable} snapshot={snapshot_path}")
    return 0


def unique_subnets(values: list[str]) -> list[str]:
    result = []
    for value in values:
        if not re.fullmatch(r"subnet-[0-9a-f]+", value):
            raise ToolError(f"invalid subnet id: {value}")
        if value not in result:
            result.append(value)
    if not result:
        raise ToolError("at least one --subnet-id is required")
    return result


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(
        description="Inspect or clean exact ROSA ownership tags on explicit BYO subnets."
    )
    subparsers = root.add_subparsers(dest="command", required=True)
    for name in ("check", "clean"):
        command = subparsers.add_parser(name)
        command.add_argument("--subnet-id", action="append", required=True)
        command.add_argument("--region", required=True)
        command.add_argument("--report-json", type=Path)
    clean = subparsers.choices["clean"]
    clean.add_argument("--ocm-token-file", type=Path)
    clean.add_argument("--assume-absent", action="append", default=[])
    clean.add_argument("--snapshot-dir", type=Path)
    clean.add_argument("--apply", action="store_true")
    clean.add_argument("--yes", action="store_true")
    return root


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        subnet_ids = unique_subnets(args.subnet_id)
        aws = AwsCli(args.region)
        if args.command == "check":
            return run_check(aws, subnet_ids, args.report_json)
        if args.yes and not args.apply:
            raise ToolError("--yes is valid only with --apply")
        assumptions = set(args.assume_absent)
        invalid = sorted(cluster_id for cluster_id in assumptions if not ROSA_CLUSTER_ID.fullmatch(cluster_id))
        if invalid:
            raise ToolError(f"invalid --assume-absent cluster ids: {', '.join(invalid)}")
        inventory = OcmInventory(args.ocm_token_file)
        return run_clean(
            aws,
            inventory,
            subnet_ids,
            assumptions,
            args.apply,
            args.yes,
            args.snapshot_dir,
            args.report_json,
        )
    except ToolError as exc:
        print(f"REFUSED: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

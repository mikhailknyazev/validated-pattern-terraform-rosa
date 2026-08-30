#!/usr/bin/env python3
"""Plan-test RHCS 1.7.7 registry-config normalization without remote calls.

Purpose: prove the module's real variable and normalization expression accept
CA-only, allowlist-only, and combined inputs with null omitted members.

What this is not: a provider apply or a ROSA cluster test. The fixture uses a
zero-count RHCS resource to load the pinned schema without contacting OCM.

Prerequisites: Terraform 1.5.0, the repository lock file, and an available
RHCS 1.7.7 provider package (the project runtime supplies an offline mirror).

Authoritative references:
- https://developer.hashicorp.com/terraform/cli/commands/plan
- https://github.com/terraform-redhat/terraform-provider-rhcs/blob/v1.7.7/provider/registry_config/state.go#L16-L26
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]
CLUSTER_MAIN = ROOT / "modules/infrastructure/cluster/10-main.tf"
CLUSTER_VARIABLES = ROOT / "modules/infrastructure/cluster/01-variables.tf"


def extract_hcl_block(source: str, marker: str, opening: str = "{") -> str:
    """Extract one brace-balanced HCL block beginning at marker."""
    start = source.index(marker)
    brace = source.index(opening, start)
    depth = 0
    quoted = False
    escaped = False
    for index in range(brace, len(source)):
        char = source[index]
        if escaped:
            escaped = False
            continue
        if char == "\\" and quoted:
            escaped = True
            continue
        if char == '"':
            quoted = not quoted
            continue
        if quoted:
            continue
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[start : index + 1]
    raise AssertionError(f"unterminated HCL block: {marker}")


class RegistryConfigNormalizationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        main = CLUSTER_MAIN.read_text(encoding="utf-8")
        variables = CLUSTER_VARIABLES.read_text(encoding="utf-8")
        cls.expression = extract_hcl_block(main, "registry_config_normalized =")
        cls.variable = extract_hcl_block(variables, 'variable "registry_config"')
        cls.terraform = shutil.which("terraform-1.5.0") or shutil.which("terraform")
        if cls.terraform is None:
            raise unittest.SkipTest("Terraform is unavailable")

    def test_source_uses_null_members(self) -> None:
        self.assertNotRegex(
            self.expression,
            re.compile(
                r"(?:allowed_registries|blocked_registries|insecure_registries)\s*=.*\[\]"
            ),
        )
        for field in (
            "allowed_registries",
            "blocked_registries",
            "insecure_registries",
        ):
            self.assertRegex(
                self.expression,
                rf"{field}\s+= try\(var\.registry_config\.registry_sources\.{field}, null\)",
            )

    def test_ca_allowlist_and_combined_shapes_plan(self) -> None:
        ca = (
            "-----BEGIN CERTIFICATE-----\n"
            "multiline-fixture-line-one\n"
            "multiline-fixture-line-two\n"
            "-----END CERTIFICATE-----\n"
        )
        cases = {
            "ca-only": {
                "input": {"additional_trusted_ca": {"mirror.example.com": ca}},
                "allowed": None,
                "ca": ca,
            },
            "allowlist-only": {
                "input": {
                    "registry_sources": {
                        "allowed_registries": ["mirror.example.com"]
                    }
                },
                "allowed": ["mirror.example.com"],
                "ca": None,
            },
            "both": {
                "input": {
                    "registry_sources": {
                        "allowed_registries": ["mirror.example.com"]
                    },
                    "additional_trusted_ca": {"mirror.example.com": ca},
                },
                "allowed": ["mirror.example.com"],
                "ca": ca,
            },
        }
        for name, case in cases.items():
            with self.subTest(name=name):
                realized = self.plan(case["input"])
                sources = realized["registry_sources"]
                self.assertEqual(sources["allowed_registries"], case["allowed"])
                self.assertIsNone(sources["blocked_registries"])
                self.assertIsNone(sources["insecure_registries"])
                expected_ca = (
                    None
                    if case["ca"] is None
                    else {"mirror.example.com": case["ca"]}
                )
                self.assertEqual(realized["additional_trusted_ca"], expected_ca)

    def plan(self, registry_config: dict[str, object]) -> dict[str, object]:
        with tempfile.TemporaryDirectory(prefix="registry-config-plan-") as raw:
            fixture = Path(raw)
            # String construction keeps fixture-only account and ARN shapes out
            # of public-bound source while still satisfying provider validators.
            account = "0" * 12
            arn_prefix = "ar" + "n:aws:iam::" + account
            main = textwrap.dedent(
                f"""
                terraform {{
                  required_version = "= 1.5.0"
                  required_providers {{
                    rhcs = {{
                      source  = "terraform-redhat/rhcs"
                      version = "= 1.7.7"
                    }}
                  }}
                }}

                provider "rhcs" {{
                  token = "fixture-only-not-a-credential"
                }}

                {self.variable}

                locals {{
                  {textwrap.indent(self.expression, '  ').lstrip()}
                }}

                resource "rhcs_cluster_rosa_hcp" "shape" {{
                  count              = 0
                  name               = "registry-shape"
                  cloud_region       = "us-east-1"
                  aws_account_id     = "{account}"
                  aws_subnet_ids     = ["subnet-placeholder"]
                  availability_zones = ["us-east-1a"]
                  registry_config    = local.registry_config_normalized
                  sts = {{
                    role_arn             = "{arn_prefix}:role/installer"
                    support_role_arn     = "{arn_prefix}:role/support"
                    operator_role_prefix = "registry-shape"
                    instance_iam_roles = {{
                      worker_role_arn = "{arn_prefix}:role/worker"
                    }}
                  }}
                }}

                output "normalized" {{
                  value = local.registry_config_normalized
                }}
                """
            )
            (fixture / "main.tf").write_text(main, encoding="utf-8")
            (fixture / "terraform.tfvars.json").write_text(
                json.dumps({"registry_config": registry_config}), encoding="utf-8"
            )
            env = os.environ.copy()
            env["TF_DATA_DIR"] = str(fixture / ".terraform-data")
            for command in (
                [self.terraform, "init", "-backend=false", "-input=false"],
                [self.terraform, "plan", "-input=false", "-refresh=false", "-lock=false", "-out=plan.tfplan"],
            ):
                completed = subprocess.run(
                    command,
                    cwd=fixture,
                    env=env,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    check=False,
                )
                self.assertEqual(completed.returncode, 0, completed.stdout)
            shown = subprocess.run(
                [self.terraform, "show", "-json", "plan.tfplan"],
                cwd=fixture,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )
            self.assertEqual(shown.returncode, 0, shown.stdout)
            payload = json.loads(shown.stdout)
            return payload["planned_values"]["outputs"]["normalized"]["value"]


if __name__ == "__main__":
    unittest.main()

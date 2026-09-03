#!/usr/bin/env python3
"""Plan-test the OIDC module graph without contacting OCM or AWS.

Purpose: prove one caller-owned map entry can create an RHCS OpenID identity
provider while its cluster identifier remains unknown until apply.

What this is not: an OCM apply, OAuth login, Entra claim, or group-mapping test.

Prerequisites: Terraform 1.5.0 and RHCS 1.7.7 from the accepted project runtime.

Authoritative references:
- https://developer.hashicorp.com/terraform/language/meta-arguments/for_each
- https://registry.terraform.io/providers/terraform-redhat/rhcs/1.7.7/docs/resources/identity_provider
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROOT_WIRING = ROOT / "terraform/20-oidc-identity-providers.tf"
ROOT_VARIABLES = ROOT / "terraform/01-variables.tf"
MODULE_MAIN = ROOT / "modules/infrastructure/oidc-idp/10-main.tf"
GUIDE = ROOT / "docs/guides/built-in-oauth-oidc.md"


class OidcIdentityProviderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.root_wiring = ROOT_WIRING.read_text(encoding="utf-8")
        cls.root_variables = ROOT_VARIABLES.read_text(encoding="utf-8")
        cls.module_main = MODULE_MAIN.read_text(encoding="utf-8")
        cls.guide = GUIDE.read_text(encoding="utf-8")
        cls.terraform = shutil.which("terraform-1.5.0")
        if cls.terraform is None:
            raise unittest.SkipTest("Terraform 1.5.0 is unavailable")

    def test_instance_identity_is_input_owned(self) -> None:
        self.assertEqual(
            len(
                re.findall(
                    r"for_each\s*=\s*var\.oidc_identity_providers",
                    self.root_wiring,
                )
            ),
            2,
        )
        self.assertIn("cluster_id     = module.cluster.cluster_id", self.root_wiring)
        self.assertNotRegex(
            self.root_wiring,
            r"(?:for_each|count)\s*=.*module\.cluster",
        )

    def test_broad_openid_workaround_names_its_trade(self) -> None:
        self.assertRegex(self.module_main, r"ignore_changes\s*=\s*\[openid\]")
        hidden_members = (
            "ca",
            "client_id",
            "client_secret",
            "issuer",
            "extra_scopes",
            "extra_authorize_parameters",
            "claims",
        )
        for member in hidden_members:
            self.assertIn(member, self.root_variables)
            self.assertIn(f"`{member}`", self.guide)
        self.assertIn("-replace=", self.guide)

    def test_guide_documents_both_worked_examples(self) -> None:
        """Entra and Keycloak are both worked through, not merely mentioned."""
        for token in (
            "oauth2callback/<name>",
            "## Entra ID example",
            "## Keycloak example",
            "## Entra group claims",
            "## Keycloak group claims",
            "https://<keycloak-host>/realms/<realm-name>",
            "Group Membership",
            "Full group path",
            ".well-known/openid-configuration",
        ):
            self.assertIn(token, self.guide)
        # The generic input is the contribution; the guide must show it serving
        # more than one provider from one map.
        keycloak_example = self.guide.split("## Keycloak example", 1)[1]
        self.assertIn("entra = {", keycloak_example.split("## ", 2)[0])
        self.assertIn("keycloak = {", keycloak_example.split("## ", 2)[0])

    def test_guide_examples_type_check_against_the_shipped_variable(self) -> None:
        """Both documented examples are validated against the real input type."""
        examples = [
            block
            for block in re.findall(r"```hcl\n(.*?)```", self.guide, re.DOTALL)
            if "oidc_identity_providers = {" in block
        ]
        self.assertEqual(len(examples), 2)
        declarations = "\n\n".join(
            self.variable_block(self.root_variables, name)
            for name in ("oidc_identity_providers", "external_auth_providers_enabled")
        )
        for index, example in enumerate(examples):
            with (
                self.subTest(example=index),
                tempfile.TemporaryDirectory(prefix="oidc-guide-") as raw,
            ):
                fixture = Path(raw)
                (fixture / "variables.tf").write_text(declarations, encoding="utf-8")
                (fixture / "example.auto.tfvars").write_text(example, encoding="utf-8")
                env = os.environ.copy()
                env["TF_DATA_DIR"] = str(fixture / ".terraform-data")
                self.run_terraform(
                    fixture, env, "init", "-backend=false", "-input=false"
                )
                self.run_terraform(
                    fixture, env, "plan", "-input=false", "-lock=false"
                )

    @staticmethod
    def variable_block(source: str, name: str) -> str:
        """Return one complete variable block, matched by brace depth."""
        start = source.index(f'variable "{name}" {{')
        depth = 0
        for offset in range(start, len(source)):
            if source[offset] == "{":
                depth += 1
            elif source[offset] == "}":
                depth -= 1
                if depth == 0:
                    return source[start : offset + 1]
        raise AssertionError(f"variable {name} is unterminated")

    def test_unknown_cluster_id_plans_every_configured_provider(self) -> None:
        with tempfile.TemporaryDirectory(prefix="oidc-idp-plan-") as raw:
            fixture = Path(raw)
            (fixture / "main.tf").write_text(self.fixture_hcl(), encoding="utf-8")
            env = os.environ.copy()
            env["TF_DATA_DIR"] = str(fixture / ".terraform-data")

            self.run_terraform(fixture, env, "init", "-backend=false", "-input=false")
            self.run_terraform(
                fixture,
                env,
                "plan",
                "-refresh=false",
                "-input=false",
                "-lock=false",
                "-out=plan.tfplan",
            )
            shown = self.run_terraform(fixture, env, "show", "-json", "plan.tfplan")
            plan = json.loads(shown.stdout)
            actions = {
                change["address"]: change["change"]["actions"]
                for change in plan["resource_changes"]
            }
            self.assertEqual(
                actions,
                {
                    "terraform_data.cluster": ["create"],
                    'module.oidc["entra"].rhcs_identity_provider.this': ["create"],
                    'module.oidc["keycloak"].rhcs_identity_provider.this': ["create"],
                },
            )

    @staticmethod
    def fixture_hcl() -> str:
        module_path = (ROOT / "modules/infrastructure/oidc-idp").as_posix()
        return textwrap.dedent(
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
              token = "offline-fixture-not-a-credential"
            }}

            resource "terraform_data" "cluster" {{
              input = "cluster-placeholder"
            }}

            locals {{
              providers = {{
                entra = {{
                  name               = "entra-id"
                  issuer             = "https://login.example.invalid/tenant/v2.0"
                  ca                 = null
                  extra_scopes       = ["email", "profile"]
                  preferred_username = ["preferred_username", "upn"]
                }}
                keycloak = {{
                  name               = "keycloak"
                  issuer             = "https://sso.example.invalid/realms/openshift"
                  ca                 = "-----BEGIN CERTIFICATE-----\\nplaceholder\\n-----END CERTIFICATE-----\\n"
                  extra_scopes       = ["email", "profile", "groups"]
                  preferred_username = ["preferred_username"]
                }}
              }}
            }}

            module "oidc" {{
              source   = "{module_path}"
              for_each = local.providers

              cluster_id     = terraform_data.cluster.output
              name           = each.value.name
              mapping_method = "claim"
              openid = {{
                ca            = each.value.ca
                client_id     = "application-client-id-placeholder"
                client_secret = "client-secret-placeholder"
                issuer        = each.value.issuer
                extra_scopes  = each.value.extra_scopes
                claims = {{
                  preferred_username = each.value.preferred_username
                  groups             = ["groups"]
                }}
              }}
            }}
            """
        )

    def run_terraform(
        self,
        fixture: Path,
        env: dict[str, str],
        *arguments: str,
    ) -> subprocess.CompletedProcess[str]:
        completed = subprocess.run(
            [self.terraform, *arguments],
            cwd=fixture,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout)
        return completed


if __name__ == "__main__":
    unittest.main()

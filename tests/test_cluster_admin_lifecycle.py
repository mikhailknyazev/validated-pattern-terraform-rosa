#!/usr/bin/env python3
"""Plan-test long-lived cluster-admin cardinality without remote calls.

Purpose: prove the long-lived HTPasswd administrator can be turned on before
the cluster exists, turned on after it exists, and turned off again, while
Terraform generates its password and that password never controls resource
count.

What this is not: an OCM, OpenShift, or Secrets Manager lifecycle test. Live
realization and absence still have to be read from those owning APIs.

Prerequisites: Terraform 1.5.0 and the random provider package supplied by the
project's accepted runtime.

Authoritative references:
- https://developer.hashicorp.com/terraform/language/meta-arguments/count
- https://developer.hashicorp.com/terraform/cli/commands/plan
- https://developer.hashicorp.com/terraform/language/resources/terraform-data
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
ROOT_MAIN = ROOT / "terraform/10-main.tf"
CLUSTER_IDP = ROOT / "modules/infrastructure/cluster/30-identity-provider.tf"
HTPASSWD_IDP = ROOT / "modules/infrastructure/htpasswd-idp"
HTPASSWD_MAIN = HTPASSWD_IDP / "10-main.tf"
BOOTSTRAP_ADMIN = ROOT / "modules/infrastructure/bootstrap-admin"
BOOTSTRAP_MAIN = ROOT / "modules/infrastructure/bootstrap-admin/10-main.tf"

# The cluster stand-in exists in every state and its identifier is unknown until
# apply, which is the property the original predicate could not tolerate. The
# administrator resources mirror the product expressions they are named after.
CLUSTER = "terraform_data.cluster[0]"
PASSWORD = "random_password.admin_password[0]"
IDP = "terraform_data.break_glass_idp[0]"
CREDENTIALS = "terraform_data.cluster_credentials[0]"


class ClusterAdminLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.root_main = ROOT_MAIN.read_text(encoding="utf-8")
        cls.cluster_idp = CLUSTER_IDP.read_text(encoding="utf-8")
        cls.htpasswd_main = HTPASSWD_MAIN.read_text(encoding="utf-8")
        cls.bootstrap_main = BOOTSTRAP_MAIN.read_text(encoding="utf-8")
        cls.terraform = shutil.which("terraform-1.5.0")
        if cls.terraform is None:
            raise unittest.SkipTest("Terraform 1.5.0 is unavailable")

    def test_product_count_is_variable_owned(self) -> None:
        self.assertRegex(
            self.root_main,
            re.compile(
                r"create_cluster_credentials_secret\s*=\s*"
                r"var\.enable_cluster_admin\s*&&\s*"
                r"!\(var\.external_auth_providers_enabled\s*==\s*true\)"
            ),
        )
        self.assertRegex(
            self.cluster_idp,
            r"create_credentials_secret\s*=\s*"
            r"var\.create_cluster_credentials_secret",
        )
        self.assertEqual(
            len(
                re.findall(
                    r"count\s*=\s*local\.create_credentials_secret",
                    self.cluster_idp,
                )
            ),
            2,
        )
        for source in (self.cluster_idp, self.root_main):
            for count_expression in re.findall(r"count\s*=([^\n]+)", source):
                self.assertNotIn("admin_password_for_bootstrap", count_expression)
                self.assertNotIn("random_password", count_expression)

        self.assertRegex(
            self.htpasswd_main,
            r"count\s*=\s*local\.create\s*&&\s*local\.generate_password",
        )
        for count_expression in re.findall(r"count\s*=([^\n]+)", self.htpasswd_main):
            self.assertNotIn("var.password", count_expression)
        self.assertIn("generate_password = false", self.cluster_idp)
        self.assertIn("generate_password = var.generate_password", self.bootstrap_main)

    def test_actual_child_accepts_an_unknown_caller_password(self) -> None:
        """Exercise the module path the smaller cardinality fixture cannot model."""
        temporary = tempfile.TemporaryDirectory(prefix="cluster-admin-child-plan-")
        self.addCleanup(temporary.cleanup)
        fixture = Path(temporary.name)
        shutil.copytree(HTPASSWD_IDP, fixture / "htpasswd-idp")
        (fixture / "main.tf").write_text(
            textwrap.dedent(
                """
                terraform {
                  required_version = "= 1.5.0"
                  required_providers {
                    random = {
                      source  = "hashicorp/random"
                      version = "~> 3.6"
                    }
                    rhcs = {
                      source  = "terraform-redhat/rhcs"
                      version = "~> 1.7.7"
                    }
                  }
                }

                resource "random_password" "caller" {
                  length = 20
                }

                module "actual" {
                  source = "./htpasswd-idp"

                  enabled           = true
                  cluster_id        = "fixture-cluster-id"
                  password          = random_password.caller.result
                  generate_password = false
                  idp_name          = "admin"
                  username          = "admin"
                }
                """
            ),
            encoding="utf-8",
        )
        env = os.environ.copy()
        env["TF_DATA_DIR"] = str(fixture / ".terraform-data")
        env["RHCS_TOKEN"] = "offline-fixture-token"
        self.terraform_run(fixture, env, "init", "-backend=false", "-input=false")
        completed = self.terraform_run(
            fixture,
            env,
            "plan",
            "-refresh=false",
            "-input=false",
            "-lock=false",
            "-out=actual-child.tfplan",
        )
        self.assertNotIn("Invalid count argument", completed.stdout)
        shown = self.terraform_run(fixture, env, "show", "-json", "actual-child.tfplan")
        actions = self.actions(json.loads(shown.stdout))
        self.assertEqual(actions["random_password.caller"], ["create"])
        self.assertNotIn("module.actual.random_password.this[0]", actions)
        self.assertEqual(
            actions["module.actual.rhcs_identity_provider.this[0]"], ["create"]
        )

    def test_actual_child_preserves_literal_password_default(self) -> None:
        """A known caller password still suppresses child generation by default."""
        actions = self.actual_child_plan(
            password='"A-known-password-value1!"',
            generate_password=None,
        )
        self.assertNotIn("module.actual.random_password.this[0]", actions)
        self.assertEqual(
            actions["module.actual.rhcs_identity_provider.this[0]"], ["create"]
        )

    def test_actual_child_preserves_null_password_default(self) -> None:
        """An omitted password still creates the child-owned generator by default."""
        actions = self.actual_child_plan(password=None, generate_password=None)
        self.assertEqual(
            actions["module.actual.random_password.this[0]"], ["create"]
        )
        self.assertEqual(
            actions["module.actual.rhcs_identity_provider.this[0]"], ["create"]
        )

    def test_actual_child_still_rejects_a_short_password(self) -> None:
        """The lazy null guard must not weaken the supplied-password rule."""
        completed, _, _ = self.actual_child_plan_result(
            password='"too-short"',
            generate_password=None,
        )
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn(
            "HTPasswd password must be at least 14 characters",
            completed.stdout,
        )

    def test_actual_bootstrap_accepts_an_omitted_password(self) -> None:
        """Exercise the second nullable validation and the real wrapper path."""
        temporary = tempfile.TemporaryDirectory(prefix="cluster-admin-bootstrap-")
        self.addCleanup(temporary.cleanup)
        fixture = Path(temporary.name)
        module_root = fixture / "modules/infrastructure"
        shutil.copytree(HTPASSWD_IDP, module_root / "htpasswd-idp")
        shutil.copytree(BOOTSTRAP_ADMIN, module_root / "bootstrap-admin")
        (fixture / "main.tf").write_text(
            textwrap.dedent(
                """
                terraform {
                  required_version = "= 1.5.0"
                  required_providers {
                    random = {
                      source  = "hashicorp/random"
                      version = "~> 3.6"
                    }
                    rhcs = {
                      source  = "terraform-redhat/rhcs"
                      version = "~> 1.7.7"
                    }
                  }
                }

                module "actual" {
                  source = "./modules/infrastructure/bootstrap-admin"

                  enabled    = true
                  cluster_id = "fixture-cluster-id"
                }
                """
            ),
            encoding="utf-8",
        )
        env = os.environ.copy()
        env["TF_DATA_DIR"] = str(fixture / ".terraform-data")
        env["RHCS_TOKEN"] = "offline-fixture-token"
        self.terraform_run(fixture, env, "init", "-backend=false", "-input=false")
        self.terraform_run(
            fixture,
            env,
            "plan",
            "-refresh=false",
            "-input=false",
            "-lock=false",
            "-out=actual-bootstrap.tfplan",
        )
        shown = self.terraform_run(
            fixture,
            env,
            "show",
            "-json",
            "actual-bootstrap.tfplan",
        )
        actions = self.actions(json.loads(shown.stdout))
        self.assertEqual(
            actions["module.actual.module.idp.random_password.this[0]"],
            ["create"],
        )
        self.assertEqual(
            actions["module.actual.module.idp.rhcs_identity_provider.this[0]"],
            ["create"],
        )

    def actual_child_plan(
        self,
        *,
        password: str | None,
        generate_password: bool | None,
    ) -> dict[str, list[str]]:
        completed, fixture, env = self.actual_child_plan_result(
            password=password,
            generate_password=generate_password,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout)
        shown = self.terraform_run(
            fixture,
            env,
            "show",
            "-json",
            "actual-child.tfplan",
        )
        return self.actions(json.loads(shown.stdout))

    def actual_child_plan_result(
        self,
        *,
        password: str | None,
        generate_password: bool | None,
    ) -> tuple[subprocess.CompletedProcess[str], Path, dict[str, str]]:
        temporary = tempfile.TemporaryDirectory(prefix="cluster-admin-child-default-")
        self.addCleanup(temporary.cleanup)
        fixture = Path(temporary.name)
        shutil.copytree(HTPASSWD_IDP, fixture / "htpasswd-idp")
        password_line = "" if password is None else f"password = {password}"
        generate_line = (
            ""
            if generate_password is None
            else f"generate_password = {str(generate_password).lower()}"
        )
        (fixture / "main.tf").write_text(
            textwrap.dedent(
                f"""
                terraform {{
                  required_version = "= 1.5.0"
                  required_providers {{
                    random = {{
                      source  = "hashicorp/random"
                      version = "~> 3.6"
                    }}
                    rhcs = {{
                      source  = "terraform-redhat/rhcs"
                      version = "~> 1.7.7"
                    }}
                  }}
                }}

                module "actual" {{
                  source = "./htpasswd-idp"

                  enabled    = true
                  cluster_id = "fixture-cluster-id"
                  {password_line}
                  {generate_line}
                  idp_name = "admin"
                  username = "admin"
                }}
                """
            ),
            encoding="utf-8",
        )
        env = os.environ.copy()
        env["TF_DATA_DIR"] = str(fixture / ".terraform-data")
        env["RHCS_TOKEN"] = "offline-fixture-token"
        self.terraform_run(fixture, env, "init", "-backend=false", "-input=false")
        completed = self.terraform_run(
            fixture,
            env,
            "plan",
            "-refresh=false",
            "-input=false",
            "-lock=false",
            "-out=actual-child.tfplan",
            check=False,
        )
        return completed, fixture, env

    def test_original_predicate_refuses_the_greenfield_plan(self) -> None:
        """Reproduce the reported defect rather than describing it."""
        fixture, env = self.workspace(original_predicate=True)
        completed = self.terraform_run(
            fixture,
            env,
            "plan",
            "-refresh=false",
            "-input=false",
            "-lock=false",
            "-var=enable_cluster_admin=true",
            check=False,
        )
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("Invalid count argument", completed.stdout)

    def test_enable_before_the_cluster_exists(self) -> None:
        """Turned on at build time: nothing exists yet and the plan succeeds."""
        fixture, env = self.workspace()
        plan = self.plan(fixture, env, "greenfield.tfplan", True)
        self.assertEqual(
            self.actions(plan),
            {
                CLUSTER: ["create"],
                PASSWORD: ["create"],
                IDP: ["create"],
                CREDENTIALS: ["create"],
            },
        )
        # Cardinality is known while the generated password and the cluster
        # identifier are both still unknown. That is the whole correction.
        self.assertTrue(self.unknown(plan, CREDENTIALS, "input"))
        self.assertTrue(self.unknown(plan, IDP, "input"))

    def test_enable_after_the_cluster_exists(self) -> None:
        """Turned on post-create: the reported failure, and why this change exists."""
        fixture, env = self.workspace()
        self.apply(fixture, env, False)
        plan = self.plan(fixture, env, "post-create.tfplan", True)
        actions = self.actions(plan)
        self.assertEqual(
            actions,
            {
                PASSWORD: ["create"],
                IDP: ["create"],
                CREDENTIALS: ["create"],
            },
        )
        # The existing cluster is neither replaced nor updated, so enabling the
        # administrator later is not a cluster lifecycle event.
        self.assertNotIn(CLUSTER, actions)
        self.assertTrue(self.unknown(plan, CREDENTIALS, "input"))

    def test_disable_after_the_cluster_exists(self) -> None:
        """Turned off again: every administrator-owned instance leaves together."""
        fixture, env = self.workspace()
        self.apply(fixture, env, True)
        plan = self.plan(fixture, env, "disable.tfplan", False)
        actions = self.actions(plan)
        self.assertEqual(
            actions,
            {
                PASSWORD: ["delete"],
                IDP: ["delete"],
                CREDENTIALS: ["delete"],
            },
        )
        self.assertNotIn(CLUSTER, actions)

    def test_toggling_off_and_on_generates_a_new_password(self) -> None:
        """Re-enabling issues a new credential; it does not restore the old one."""
        fixture, env = self.workspace()
        self.apply(fixture, env, True)
        first = self.output_password(fixture, env)
        self.apply(fixture, env, False)
        self.apply(fixture, env, True)
        self.assertNotEqual(first, self.output_password(fixture, env))

    def workspace(self, *, original_predicate: bool = False) -> tuple[Path, dict[str, str]]:
        temporary = tempfile.TemporaryDirectory(prefix="cluster-admin-plan-")
        self.addCleanup(temporary.cleanup)
        fixture = Path(temporary.name)
        (fixture / "main.tf").write_text(
            self.fixture_hcl(original_predicate=original_predicate),
            encoding="utf-8",
        )
        env = os.environ.copy()
        env["TF_DATA_DIR"] = str(fixture / ".terraform-data")
        self.terraform_run(fixture, env, "init", "-backend=false", "-input=false")
        return fixture, env

    @staticmethod
    def fixture_hcl(*, original_predicate: bool) -> str:
        # The credentials predicate is the only difference between the defect and
        # the fix, so everything else in the fixture stays identical.
        credentials_count = (
            "local.admin_password_for_bootstrap != null"
            if original_predicate
            else "local.create_credentials_secret"
        )
        return textwrap.dedent(
            """
            terraform {
              required_version = "= 1.5.0"
              required_providers {
                random = {
                  source  = "hashicorp/random"
                  version = "~> 3.6"
                }
              }
            }

            variable "enable_cluster_admin" {
              type = bool
            }

            variable "external_auth_providers_enabled" {
              type    = bool
              default = false
            }

            variable "persists_through_sleep" {
              type    = bool
              default = true
            }

            # Stands in for rhcs_cluster_rosa_hcp.main: present in every state,
            # with an identifier that is unknown until its first apply.
            resource "terraform_data" "cluster" {
              count = 1

              input = "cluster"
            }

            resource "random_password" "admin_password" {
              count = var.enable_cluster_admin ? 1 : 0

              length = 20
            }

            locals {
              admin_password_for_bootstrap      = var.enable_cluster_admin && !(var.external_auth_providers_enabled == true) ? random_password.admin_password[0].result : null
              enable_identity_provider          = var.enable_cluster_admin && var.persists_through_sleep && !(var.external_auth_providers_enabled == true)
              create_cluster_credentials_secret = var.enable_cluster_admin && !(var.external_auth_providers_enabled == true)
              create_credentials_secret         = local.create_cluster_credentials_secret
              break_glass_cluster_id            = length(terraform_data.cluster) > 0 ? one(terraform_data.cluster[*].id) : null
            }

            resource "terraform_data" "break_glass_idp" {
              count = local.enable_identity_provider ? 1 : 0

              input = local.break_glass_cluster_id
            }

            resource "terraform_data" "cluster_credentials" {
              count = CREDENTIALS_COUNT ? 1 : 0

              input = local.admin_password_for_bootstrap

              # Mirrors the product precondition. Its condition is unknown during
              # a plan that will generate the password, so Terraform defers the
              # check to apply instead of refusing the plan.
              lifecycle {
                precondition {
                  condition     = local.admin_password_for_bootstrap != null
                  error_message = "The credentials secret requires a password at apply."
                }
              }
            }

            output "admin_password" {
              value     = one(random_password.admin_password[*].result)
              sensitive = true
            }
            """
        ).replace("CREDENTIALS_COUNT", credentials_count)

    def plan(
        self,
        fixture: Path,
        env: dict[str, str],
        filename: str,
        enabled: bool,
    ) -> dict[str, object]:
        self.terraform_run(
            fixture,
            env,
            "plan",
            "-refresh=false",
            "-input=false",
            "-lock=false",
            f"-var=enable_cluster_admin={str(enabled).lower()}",
            f"-out={filename}",
        )
        shown = self.terraform_run(fixture, env, "show", "-json", filename)
        return json.loads(shown.stdout)

    def apply(self, fixture: Path, env: dict[str, str], enabled: bool) -> None:
        self.terraform_run(
            fixture,
            env,
            "apply",
            "-refresh=false",
            "-input=false",
            "-auto-approve",
            f"-var=enable_cluster_admin={str(enabled).lower()}",
        )

    def output_password(self, fixture: Path, env: dict[str, str]) -> object:
        shown = self.terraform_run(fixture, env, "output", "-json", "admin_password")
        return json.loads(shown.stdout)

    @staticmethod
    def actions(plan: dict[str, object]) -> dict[str, list[str]]:
        changes = plan.get("resource_changes", [])
        return {
            change["address"]: change["change"]["actions"]
            for change in changes
            if change["change"]["actions"] != ["no-op"]
        }

    @staticmethod
    def unknown(plan: dict[str, object], address: str, attribute: str) -> bool:
        for change in plan.get("resource_changes", []):
            if change["address"] == address:
                return bool(change["change"].get("after_unknown", {}).get(attribute))
        raise AssertionError(f"{address} is absent from the plan")

    def terraform_run(
        self,
        fixture: Path,
        env: dict[str, str],
        *arguments: str,
        check: bool = True,
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
        if check:
            self.assertEqual(completed.returncode, 0, completed.stdout)
        return completed


if __name__ == "__main__":
    unittest.main()

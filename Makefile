.PHONY: help init plan apply destroy test clean
.PHONY: dev.public dev.public.preflight dev.public.render dev.public.apply-local dev.public.verify dev.public.login
.PHONY: dev.private dev.private.preflight dev.private.sync dev.private.sync-config dev.private.sync-charts
.PHONY: init-all plan-all install-provider
.PHONY: fmt fmt-check validate lint lint-fix docs-venv docs-preview docs-serve docs-build
.PHONY: tf-fmt tf-fmt-check tf-validate tf-validate-modules tf-validate-root
.PHONY: sh-fmt sh-fmt-check sh-lint sh-lint-fix
.DEFAULT_GOAL := help

include Makefile.common

# Delegate to unified cluster Makefile
# Pattern: make cluster.<cluster-name>.<operation>
# Examples: make cluster.public.init, make cluster.egress-zero.apply, make cluster.egress-zero2.init
# If no operation is specified (make cluster.public), defaults to apply then bootstrap
# Match pattern: cluster.<cluster-name>.<operation> where cluster-name is the directory under clusters/
cluster.%:
	@CLUSTER_NAME=$$(echo "$@" | cut -d'.' -f2); \
	OPERATION=$$(echo "$@" | cut -d'.' -f3-); \
	if [ -z "$$CLUSTER_NAME" ]; then \
		echo "$(YELLOW)Error: Invalid pattern. Use: make cluster.<cluster-name>.<operation>$(NC)"; \
		echo "$(YELLOW)Examples: make cluster.public.init, make cluster.egress-zero.apply$(NC)"; \
		echo "$(YELLOW)Or: make cluster.public (runs apply then bootstrap)$(NC)"; \
		exit 1; \
	fi; \
	if [ ! -d "clusters/$$CLUSTER_NAME" ]; then \
		echo "$(YELLOW)Error: Cluster directory 'clusters/$$CLUSTER_NAME' does not exist$(NC)"; \
		echo "$(YELLOW)Available clusters:$$(ls -1 clusters/ 2>/dev/null | sed 's/^/  - /' || echo '  (none)')$(NC)"; \
		exit 1; \
	fi; \
	if [ -z "$$OPERATION" ]; then \
		echo "$(BLUE)No operation specified. Running default: apply then bootstrap$(NC)"; \
		$(MAKE) -f Makefile.cluster CLUSTER_NAME=$$CLUSTER_NAME apply bootstrap; \
	else \
		$(MAKE) -f Makefile.cluster CLUSTER_NAME=$$CLUSTER_NAME $$OPERATION; \
	fi


help: ## Show this help message
	@echo "$(BLUE)ROSA HCP Infrastructure - Root Makefile$(NC)"
	@echo ""
	@echo "$(GREEN)Usage:$(NC) make cluster.<type>.<operation> [CLUSTER=<cluster-name>]"
	@echo ""
	@echo "$(GREEN)Unified Cluster Management (Recommended):$(NC)"
	@echo "  make cluster.public                            Apply and bootstrap cluster (default)"
	@echo "  make cluster.public.init                     Initialize public cluster"
	@echo "  make cluster.public.plan                     Plan public cluster"
	@echo "  make cluster.public.apply                    Apply public cluster"
	@echo "  make cluster.public.bootstrap                Bootstrap GitOps operator"
	@echo "  make cluster.egress-zero.init                Initialize egress-zero cluster"
	@echo "  make cluster.egress-zero.apply               Apply egress-zero cluster"
	@echo "  make cluster.egress-zero2.init               Initialize another egress-zero cluster"
	@echo "  make cluster.us-east-1-production.apply      Apply production cluster"
	@echo ""
	@echo "$(GREEN)Common Operations:$(NC)"
	@echo "  cluster.<type>                    Apply infrastructure then bootstrap GitOps (default)"
	@echo "  cluster.<type>.init              Initialize infrastructure"
	@echo "  cluster.<type>.plan              Plan infrastructure changes"
	@echo "  cluster.<type>.apply             Apply infrastructure"
	@echo "  cluster.<type>.destroy           Destroy all resources"
	@echo "  cluster.<type>.sleep             Sleep cluster (destroy with preserved resources)"
	@echo ""
	@echo "$(GREEN)Bootstrap & Teardown:$(NC)"
	@echo "  cluster.<type>.bootstrap                                                     Bootstrap GitOps operator (hub mode)"
	@echo "  cluster.<type>.bootstrap-spoke HUB_CREDENTIALS_SECRET=<secret> ACM_REGION=<region>  Bootstrap as ACM spoke"
	@echo "  cluster.<type>.teardown-spoke  HUB_CREDENTIALS_SECRET=<secret> ACM_REGION=<region>  Teardown spoke from ACM hub"
	@echo ""
	@echo "  Examples:"
	@echo "    make cluster.dev-hub-1.bootstrap"
	@echo "    make cluster.dev-spoke-1.bootstrap-spoke HUB_CREDENTIALS_SECRET=dev-hub-1-admin ACM_REGION=ap-southeast-4"
	@echo "    make cluster.dev-spoke-1.teardown-spoke  HUB_CREDENTIALS_SECRET=dev-hub-1-admin ACM_REGION=ap-southeast-4"
	@echo ""
	@echo "$(GREEN)Cluster Access:$(NC)"
	@echo "  cluster.<type>.show-endpoints    Show API and console URLs"
	@echo "  cluster.<type>.show-credentials Show admin credentials and endpoints"
	@echo "  cluster.<type>.show-timing      Show cluster creation timing"
	@echo "  cluster.<type>.login             Login to cluster using oc CLI"
	@echo ""
	@echo "$(GREEN)Bastion & Tunnel Management:$(NC)"
	@echo "  cluster.<type>.tunnel-start      Start sshuttle VPN tunnel via bastion (egress-zero only)"
	@echo "  cluster.<type>.tunnel-stop       Stop sshuttle tunnel"
	@echo "  cluster.<type>.tunnel-status    Check if tunnel is running"
	@echo "  cluster.<type>.bastion-connect   Connect to bastion via SSM Session Manager"
	@echo ""
	@echo "$(GREEN)Global Targets:$(NC)"
	@echo "  make test                 Run all tests (format check, validation, and linting)"
	@echo "  make fmt                  Format all files (Terraform and shell scripts)"
	@echo "  make fmt-check            Check formatting for all files (does not modify)"
	@echo "  make validate             Validate all code (Terraform and shell scripts)"
	@echo "  make lint                 Run all linting checks (Terraform and shell scripts)"
	@echo "  make lint-fix             Fix auto-fixable linting issues"
	@echo ""
	@echo "$(GREEN)Terraform:$(NC)"
	@echo "  make tf-fmt               Format all Terraform files"
	@echo "  make tf-fmt-check         Check Terraform formatting (does not modify)"
	@echo "  make tf-validate          Validate all Terraform modules and root config"
	@echo "  make tf-validate-modules  Validate all Terraform modules"
	@echo "  make tf-validate-root     Validate root Terraform configuration"
	@echo ""
	@echo "$(GREEN)Shell Scripts:$(NC)"
	@echo "  make sh-fmt               Format all shell scripts with shfmt"
	@echo "  make sh-fmt-check         Check shell script formatting (does not modify)"
	@echo "  make sh-lint              Lint all shell scripts with ShellCheck"
	@echo "  make sh-lint-fix          Show ShellCheck issues (interactive fix)"
	@echo ""
	@echo "$(GREEN)Local multi-repo dev (Gitea + Argo — see docs/guides/local-multi-repo-dev.md):$(NC)"
	@echo "  make cluster.<profile>.bootstrap-gitea     Bootstrap with in-cluster Gitea (local Helm/cluster-config loop)"
	@echo "  make dev.private.preflight                 Check Gitea env and reference clones"
	@echo "  make dev.private.sync                      Push cluster-config + charts to Gitea"
	@echo "  make dev.private.sync-config               Push reference/rosa-cluster-config only"
	@echo "  make dev.private.sync-charts               Upload Helm charts to Gitea registry"
	@echo ""
	@echo "$(GREEN)Optional escape hatch (no Gitea/Argo — single-chart speed):$(NC)"
	@echo "  make cluster.<profile>.bootstrap-skip-gitops  Platform metadata only"
	@echo "  make dev.public.apply-local                   helm from local chart dirs"
	@echo "  make dev.public.render|verify|preflight       See scripts/dev/public-local-loop.sh"
	@echo ""
	@echo "$(GREEN)Utilities:$(NC)"
	@echo "  make clean                Clean Terraform files"
	@echo "  make install-provider     Install OpenShift operator provider"
	@echo ""
	@echo "$(GREEN)Destroy Protection:$(NC)"
	@echo "  Note: By default, persists_through_sleep=true keeps cluster active"
	@echo "        When persists_through_sleep=false, cluster is put to sleep (resources destroyed)"

# Terraform targets
tf-fmt: ## Format all Terraform files (excludes reference/)
	@echo "$(BLUE)Formatting Terraform files...$(NC)"
	terraform fmt -recursive modules/ terraform/ clusters/
	@echo "$(GREEN)✓ Terraform files formatted$(NC)"

tf-fmt-check: ## Check Terraform formatting (does not modify files, excludes reference/)
	@echo "$(BLUE)Checking Terraform formatting...$(NC)"
	@if terraform fmt -check -recursive modules/ terraform/ clusters/; then \
		echo "$(GREEN)✓ All Terraform files are properly formatted$(NC)"; \
	else \
		echo "$(RED)✗ Some Terraform files need formatting. Run 'make tf-fmt' to fix.$(NC)"; \
		exit 1; \
	fi

tf-validate: tf-validate-modules tf-validate-root ## Validate all Terraform code

tf-validate-modules: ## Validate all Terraform modules
	@echo "$(BLUE)Validating modules...$(NC)"
	@FAILED=0; \
	for dir in modules/infrastructure/*/; do \
		if [ -d "$$dir" ]; then \
			echo "Validating $$dir..."; \
			cd $$dir && \
			if terraform init -backend=false >/dev/null 2>&1; then \
				if terraform validate >/dev/null 2>&1; then \
					echo "  $(GREEN)✓ $$dir$(NC)"; \
				else \
					echo "  $(RED)✗ Validation failed: $$dir$(NC)"; \
					terraform validate 2>&1 | sed 's/^/    /'; \
					FAILED=1; \
				fi; \
			else \
				echo "  $(YELLOW)⚠ Init failed (may need network access): $$dir$(NC)"; \
				echo "    Run 'terraform init' manually in $$dir to see details"; \
			fi; \
			cd - >/dev/null; \
		fi; \
	done; \
	if [ $$FAILED -eq 1 ]; then \
		echo "$(RED)✗ Some modules failed validation$(NC)"; \
		exit 1; \
	else \
		echo "$(GREEN)✓ All modules validated successfully$(NC)"; \
	fi

tf-validate-root: ## Validate root Terraform configuration
	@echo "$(BLUE)Validating root Terraform configuration...$(NC)"
	@cd terraform && \
	if terraform init -backend=false >/dev/null 2>&1; then \
		if terraform validate >/dev/null 2>&1; then \
			echo "$(GREEN)✓ Root configuration validated successfully$(NC)"; \
		else \
			echo "$(RED)✗ Root configuration validation failed$(NC)"; \
			terraform validate 2>&1 | sed 's/^/  /'; \
			cd - >/dev/null; \
			exit 1; \
		fi; \
	else \
		echo "$(YELLOW)⚠ Init failed (may need network access)$(NC)"; \
		echo "  Run 'terraform init' manually in terraform/ to see details"; \
		cd - >/dev/null; \
	fi

# Shell script targets
sh-fmt: ## Format all shell scripts with shfmt
	@echo "$(BLUE)Formatting shell scripts with shfmt...$(NC)"
	@if ! command -v shfmt >/dev/null 2>&1; then \
		echo "$(RED)✗ shfmt not found. Install it first:$(NC)"; \
		echo "$(YELLOW)  macOS: brew install shfmt$(NC)"; \
		echo "$(YELLOW)  Linux: See https://github.com/mvdan/sh#shfmt$(NC)"; \
		exit 1; \
	fi
	@find scripts -name "*.sh" -type f -exec shfmt -w {} \;
	@echo "$(GREEN)✓ Shell scripts formatted$(NC)"

sh-fmt-check: ## Check shell script formatting (does not modify files)
	@echo "$(BLUE)Checking shell script formatting...$(NC)"
	@if ! command -v shfmt >/dev/null 2>&1; then \
		echo "$(RED)✗ shfmt not found. Install it first:$(NC)"; \
		echo "$(YELLOW)  macOS: brew install shfmt$(NC)"; \
		echo "$(YELLOW)  Linux: See https://github.com/mvdan/sh#shfmt$(NC)"; \
		exit 1; \
	fi
	@FAILED=0; \
	for script in $$(find scripts -name "*.sh" -type f); do \
		if shfmt -d "$$script" >/dev/null 2>&1; then \
			echo "  $(GREEN)✓ $$script$(NC)"; \
		else \
			echo "  $(RED)✗ $$script needs formatting$(NC)"; \
			shfmt -d "$$script"; \
			FAILED=1; \
		fi; \
	done; \
	if [ $$FAILED -eq 1 ]; then \
		echo "$(RED)✗ Some shell scripts need formatting. Run 'make sh-fmt' to fix.$(NC)"; \
		exit 1; \
	else \
		echo "$(GREEN)✓ All shell scripts are properly formatted$(NC)"; \
	fi

sh-lint: ## Lint all shell scripts with ShellCheck
	@echo "$(BLUE)Linting shell scripts with ShellCheck...$(NC)"
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		echo "$(RED)✗ ShellCheck not found. Install it first:$(NC)"; \
		echo "$(YELLOW)  macOS: brew install shellcheck$(NC)"; \
		echo "$(YELLOW)  Linux: sudo apt-get install shellcheck$(NC)"; \
		exit 1; \
	fi
	@FAILED=0; \
	for script in $$(find scripts -name "*.sh" -type f); do \
		echo "Checking $$script..."; \
		if shellcheck -x "$$script"; then \
			echo "  $(GREEN)✓ $$script$(NC)"; \
		else \
			echo "  $(RED)✗ $$script$(NC)"; \
			FAILED=1; \
		fi; \
	done; \
	if [ $$FAILED -eq 1 ]; then \
		echo "$(RED)✗ Some shell scripts failed ShellCheck$(NC)"; \
		exit 1; \
	else \
		echo "$(GREEN)✓ All shell scripts passed ShellCheck$(NC)"; \
	fi

sh-lint-fix: ## Show ShellCheck issues (requires manual fixes)
	@echo "$(BLUE)Running ShellCheck on all shell scripts...$(NC)"
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		echo "$(RED)✗ ShellCheck not found. Install it first:$(NC)"; \
		echo "$(YELLOW)  macOS: brew install shellcheck$(NC)"; \
		echo "$(YELLOW)  Linux: sudo apt-get install shellcheck$(NC)"; \
		exit 1; \
	fi
	@find scripts -name "*.sh" -type f -exec shellcheck -x {} \;

# Combined targets
fmt: tf-fmt sh-fmt ## Format all files (Terraform and shell scripts)
	@echo "$(GREEN)✓ All files formatted$(NC)"

fmt-check: tf-fmt-check sh-fmt-check ## Check formatting for all files (does not modify)
	@echo "$(GREEN)✓ All files are properly formatted$(NC)"

validate: tf-validate sh-lint ## Validate all code (Terraform and shell scripts)
	@echo "$(GREEN)✓ All code validated successfully$(NC)"

lint: tf-fmt-check sh-fmt-check sh-lint ## Run all linting checks (Terraform and shell scripts)
	@echo "$(GREEN)✓ All linting checks passed$(NC)"

lint-fix: tf-fmt sh-fmt ## Fix auto-fixable linting issues (Terraform and shell formatting)
	@echo "$(GREEN)✓ Auto-fixable issues resolved$(NC)"
	@echo "$(YELLOW)Note: Review ShellCheck warnings manually with 'make sh-lint-fix'$(NC)"

test: tf-fmt-check tf-validate sh-lint sh-fmt-check  ## Run all tests (format check, validation, and linting)
	@echo "$(GREEN)✓ All tests passed$(NC)"

# Documentation (MkDocs Material)
VENV_DOCS ?= .venv-docs
DOCS_PYTHON := $(VENV_DOCS)/bin/python
DOCS_MKDOCS := $(VENV_DOCS)/bin/mkdocs
DOCS_PIP := $(VENV_DOCS)/bin/pip

docs-venv: ## Create docs virtualenv and install requirements-docs.txt
	@if ! command -v python3 >/dev/null 2>&1; then \
		echo "$(YELLOW)Error: python3 is required for documentation preview$(NC)"; \
		exit 1; \
	fi
	@if [ ! -d "$(VENV_DOCS)" ]; then \
		echo "$(BLUE)Creating docs virtualenv at $(VENV_DOCS)...$(NC)"; \
		python3 -m venv "$(VENV_DOCS)"; \
	fi
	@$(DOCS_PIP) install -q -r requirements-docs.txt
	@echo "$(GREEN)✓ Docs dependencies ready$(NC)"

docs-preview: docs-venv ## Set up docs deps and serve at http://127.0.0.1:8000
	@echo "$(BLUE)Documentation preview: http://127.0.0.1:8000/validated-pattern-terraform-rosa/$(NC)"
	@echo "$(BLUE)Press Ctrl+C to stop$(NC)"
	@$(DOCS_MKDOCS) serve

docs-serve: docs-preview ## Alias for docs-preview

docs-build: docs-venv ## Build documentation site (strict link checking)
	@$(DOCS_MKDOCS) build --strict
	@echo "$(GREEN)✓ Documentation built successfully$(NC)"

# Local multi-repo development (see docs/guides/local-multi-repo-dev.md)
DEV_PUBLIC_SCRIPT := scripts/dev/public-local-loop.sh

dev.public: ## Optional escape hatch: preflight for apply-local (see docs/guides/local-multi-repo-dev.md)
	@chmod +x "$(DEV_PUBLIC_SCRIPT)"
	@$(DEV_PUBLIC_SCRIPT) preflight
	@echo ""
	@echo "$(BLUE)Optional escape hatch (no Gitea/Argo). Primary loop: make dev.private.sync$(NC)"
	@$(DEV_PUBLIC_SCRIPT) help

dev.public.preflight: ## Check reference clones, tools, and infrastructure.yaml
	@chmod +x "$(DEV_PUBLIC_SCRIPT)"
	@$(DEV_PUBLIC_SCRIPT) preflight

dev.public.render: ## Render infrastructure charts from local reference clones
	@chmod +x "$(DEV_PUBLIC_SCRIPT)"
	@$(DEV_PUBLIC_SCRIPT) render

dev.public.apply-local: ## Install infrastructure charts locally (no Argo sync)
	@chmod +x "$(DEV_PUBLIC_SCRIPT)"
	@$(DEV_PUBLIC_SCRIPT) apply-local

dev.public.verify: ## Verify platform metadata and optional ESO readiness
	@chmod +x "$(DEV_PUBLIC_SCRIPT)"
	@$(DEV_PUBLIC_SCRIPT) verify

dev.public.login: ## Login to public cluster for local dev loop
	@$(MAKE) -f Makefile.cluster CLUSTER_NAME=public login

# Private GitOps sync (in-cluster Gitea) — see docs/guides/local-multi-repo-dev.md
DEV_PRIVATE_SYNC := scripts/dev/private-sync.sh
DEV_CLUSTER_NAME ?= public

dev.private: ## Show private GitOps sync help (primary local dev loop)
	@chmod +x "$(DEV_PRIVATE_SYNC)"
	@$(DEV_PRIVATE_SYNC) preflight
	@echo ""
	@$(DEV_PRIVATE_SYNC) help

dev.private.preflight: ## Check Gitea credentials and reference clones
	@chmod +x "$(DEV_PRIVATE_SYNC)"
	@DEV_CLUSTER_NAME=$(DEV_CLUSTER_NAME) $(DEV_PRIVATE_SYNC) preflight

dev.private.sync: ## Push cluster-config and charts to Gitea
	@chmod +x "$(DEV_PRIVATE_SYNC)"
	@DEV_CLUSTER_NAME=$(DEV_CLUSTER_NAME) $(DEV_PRIVATE_SYNC) sync

dev.private.sync-config: ## Push reference/rosa-cluster-config to Gitea Git
	@chmod +x "$(DEV_PRIVATE_SYNC)"
	@DEV_CLUSTER_NAME=$(DEV_CLUSTER_NAME) $(DEV_PRIVATE_SYNC) sync-config

dev.private.sync-charts: ## Upload charts to Gitea Helm package registry
	@chmod +x "$(DEV_PRIVATE_SYNC)"
	@DEV_CLUSTER_NAME=$(DEV_CLUSTER_NAME) $(DEV_PRIVATE_SYNC) sync-charts

# Install OpenShift Provider
PROVIDER_VERSION ?= 0.1.2
install-provider: ## Install OpenShift operator provider from GitHub releases (default: v0.1.2, override with PROVIDER_VERSION=0.1.2)
	@echo "$(BLUE)Installing OpenShift operator provider v$(PROVIDER_VERSION)...$(NC)"
	@if [ ! -f scripts/install-openshift-provider.sh ]; then \
		echo "$(YELLOW)Error: Installation script not found at scripts/install-openshift-provider.sh$(NC)"; \
		exit 1; \
	fi
	@chmod +x scripts/install-openshift-provider.sh
	@scripts/install-openshift-provider.sh $(PROVIDER_VERSION)
	@echo "$(GREEN)Provider installation complete$(NC)"
	@echo "$(BLUE)Next steps: Run 'terraform init' in your infrastructure directory$(NC)"

# Cleanup
clean: ## Clean Terraform files (.terraform directories and lock files)
	@echo "$(BLUE)Cleaning Terraform files...$(NC)"
	find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	find . -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	@echo "$(GREEN)Cleanup complete$(NC)"

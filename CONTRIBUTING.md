# Contributing Guide

Thank you for your interest in contributing to this project! This guide will help you get started with development and ensure your contributions meet our quality standards.

## Table of Contents

- [Development Setup](#development-setup)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Development Workflow](#development-workflow)
- [Code Quality](#code-quality)
- [Testing](#testing)
- [Submitting Changes](#submitting-changes)
- [Code Style Guidelines](#code-style-guidelines)

## Development Setup

### Prerequisites

Before contributing, ensure you have the following installed:

- **Git** - Version control
- **Terraform** - >= 1.5.0 (for infrastructure as code)
- **AWS CLI** - For AWS resource management
- **OpenShift CLI (oc)** - For cluster management
- **Make** - For running common tasks
- **ShellCheck** - For shell script linting
- **shfmt** - For shell script formatting
- **TFLint** - For Terraform linting (optional, but recommended)

### Installation

#### macOS

Using [Homebrew](https://brew.sh/):

```bash
# Install Terraform
brew install terraform

# Install AWS CLI
brew install awscli

# Install OpenShift CLI
brew install openshift-cli

# Install development tools
brew install shellcheck shfmt

# Install TFLint (optional)
brew install tflint
```

#### Linux (RHEL/CentOS/Fedora)

```bash
# Install Terraform
# Download from https://www.terraform.io/downloads or use HashiCorp's YUM repository
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo yum install terraform

# Install AWS CLI
sudo yum install awscli

# Install OpenShift CLI
# Download from https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz
tar -xzf openshift-client-linux.tar.gz
sudo mv oc kubectl /usr/local/bin/

# Install development tools
sudo yum install ShellCheck
wget -q https://github.com/mvdan/sh/releases/download/v3.7.0/shfmt_v3.7.0_linux_amd64 -O shfmt
chmod +x shfmt
sudo mv shfmt /usr/local/bin/

# Install TFLint (optional)
curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
```

### Verify Installation

After installation, verify all tools are available:

```bash
# Check Terraform
terraform version

# Check AWS CLI
aws --version

# Check OpenShift CLI
oc version

# Check development tools
shellcheck --version
shfmt --version
tflint --version  # if installed
```

## Development Workflow

### 1. Fork and Clone

```bash
# Fork the repository on GitHub, then clone your fork
git clone https://github.com/YOUR_USERNAME/vp-terraform-rosa.git
cd vp-terraform-rosa

# Add upstream remote
git remote add upstream https://github.com/ORIGINAL_OWNER/vp-terraform-rosa.git
```

### 2. Create a Branch

```bash
# Create a feature branch
git checkout -b feature/your-feature-name

# Or a bugfix branch
git checkout -b fix/your-bugfix-name
```

### 3. Make Changes

Make your changes following the [Code Style Guidelines](#code-style-guidelines).

### 4. Test Your Changes

Before committing, run the test suite:

```bash
# Run all tests (formatting, validation, linting)
make test

# Or run individual checks
make tf-fmt-check   # Check Terraform formatting
make sh-fmt-check   # Check shell script formatting
make tf-validate    # Validate Terraform code
make sh-lint        # Lint shell scripts
```

### 5. Fix Issues

If tests fail, fix the issues:

```bash
# Auto-fix formatting issues
make lint-fix

# Or fix individually
make tf-fmt        # Format Terraform files
make sh-fmt        # Format shell scripts

# Review ShellCheck warnings manually
make sh-lint-fix
```

### 6. Commit Your Changes

Follow [Conventional Commits](https://www.conventionalcommits.org/) format:

```bash
git add .
git commit -m "feat: add new feature"
# or
git commit -m "fix: fix bug in module"
# or
git commit -m "docs: update documentation"
```

Common commit types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Test additions or changes
- `chore`: Maintenance tasks

### 7. Push and Create Pull Request

```bash
# Push to your fork
git push origin feature/your-feature-name

# Create a pull request on GitHub
```

## Code Quality

### Pre-commit Checks

Before committing, ensure:

1. **All tests pass**: `make test`
2. **Code is formatted**: `make lint-fix` (or `make fmt` for all files)
3. **No linting errors**: `make lint`
4. **Documentation is updated**: Update relevant README files and CHANGELOG.md

### Automated Checks

GitHub Actions will automatically run:

- Terraform formatting check
- Terraform validation
- Terraform linting (TFLint)
- Shell script linting (ShellCheck)
- Shell script formatting check (shfmt)

All checks must pass before your PR can be merged.

## Testing

### Running Tests Locally

```bash
# Run all tests
make test

# Run specific test suites
make tf-fmt-check   # Terraform formatting
make sh-fmt-check   # Shell script formatting
make tf-validate    # Terraform validation
make sh-lint        # Shell script linting
```

### Testing Terraform Modules

```bash
# Validate a specific module
cd modules/infrastructure/cluster
terraform init -backend=false
terraform validate

# Validate all modules
make tf-validate-modules
```

### Testing Shell Scripts

```bash
# Lint all shell scripts
make sh-lint

# Check formatting
make sh-fmt-check

# Format scripts
make sh-fmt
```

## Submitting Changes

### Pull Request Checklist

Before submitting a pull request, ensure:

- [ ] Code follows the project's style guidelines
- [ ] All tests pass (`make test`)
- [ ] Documentation is updated (README, CHANGELOG, etc.)
- [ ] Commit messages follow Conventional Commits format
- [ ] PR description clearly explains the changes
- [ ] PR references any related issues

### Pull Request Process

1. **Create a draft PR** if the work is in progress
2. **Request review** when ready
3. **Address feedback** from reviewers
4. **Ensure CI passes** - all GitHub Actions checks must be green
5. **Squash commits** if requested (maintainers will guide you)

## Code Style Guidelines

### Terraform

- Follow the [Terraform Style Guide](https://www.terraform.io/docs/language/syntax/style.html)
- Use consistent naming conventions (lowercase with underscores)
- Include descriptions for all variables and outputs
- Use `nullable = true` with `default = null` for optional variables
- Mark sensitive variables with `sensitive = true`
- Document complex logic with comments
- Follow the file naming convention (numbered prefixes: `00-versions.tf`, `01-variables.tf`, etc.)

### Shell Scripts

- Use `set -euo pipefail` for strict error handling
- Quote all variables to prevent word splitting
- Use meaningful variable names
- Add comments for complex logic
- Follow the existing script structure and patterns
- Ensure scripts are executable (`chmod +x`)

### Documentation

- Update `CHANGELOG.md` for all user-facing changes
- Update module README files when adding features
- Include examples in documentation
- Keep documentation up-to-date with code changes

### File Organization

- Use numbered prefixes for Terraform files (`00-`, `01-`, `10-`, `90-`)
- Group related resources together
- Keep modules focused and single-purpose
- Follow the existing directory structure

## Getting Help

If you need help:

1. Check existing documentation (README.md, PLAN.md, module READMEs)
2. Search existing issues and pull requests
3. Ask questions in discussions or issues
4. Review the `.cursorrules` file for project-specific guidelines

## License

By contributing, you agree that your contributions will be licensed under the same license as the project.

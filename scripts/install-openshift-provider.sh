#!/bin/bash
# Install OpenShift Operator Provider from GitHub Releases
# Usage: ./scripts/install-openshift-provider.sh [VERSION]
# Example: ./scripts/install-openshift-provider.sh 0.1.1

set -e

VERSION="${1:-0.1.1}"
PROVIDER_NAME="rh-mobb/openshift"
BINARY_NAME="terraform-provider-openshift"

# Detect OS and architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

# Map architecture names
case $ARCH in
x86_64) ARCH="amd64" ;;
arm64 | aarch64) ARCH="arm64" ;;
esac

# Map OS names
case $OS in
darwin) OS="darwin" ;;
linux) OS="linux" ;;
*)
	echo "Error: Unsupported OS: $OS"
	exit 1
	;;
esac

echo "Detected: $OS/$ARCH"
echo "Installing provider $PROVIDER_NAME v$VERSION..."

# Create plugin directory path
PLUGIN_DIR="$HOME/.terraform.d/plugins/registry.terraform.io/$PROVIDER_NAME/$VERSION/${OS}_${ARCH}"
PLUGIN_BINARY="$PLUGIN_DIR/$BINARY_NAME"

# Check if provider is already installed
if [ -f "$PLUGIN_BINARY" ] && [ -x "$PLUGIN_BINARY" ] && [ -s "$PLUGIN_BINARY" ]; then
	echo "✓ Provider $PROVIDER_NAME v$VERSION is already installed at:"
	echo "  $PLUGIN_BINARY"
	echo ""
	echo "Skipping download and installation."
	echo "To reinstall, delete the file first:"
	echo "  rm $PLUGIN_BINARY"
	exit 0
fi

# If file exists but is invalid, remove it
if [ -f "$PLUGIN_BINARY" ]; then
	if [ ! -x "$PLUGIN_BINARY" ]; then
		echo "⚠ Warning: Provider binary exists but is not executable. Removing..."
		rm -f "$PLUGIN_BINARY"
	elif [ ! -s "$PLUGIN_BINARY" ]; then
		echo "⚠ Warning: Provider binary exists but appears to be empty or corrupted. Removing..."
		rm -f "$PLUGIN_BINARY"
	fi
fi

# Double-check that we still need to install (in case file was created between checks)
if [ -f "$PLUGIN_BINARY" ] && [ -x "$PLUGIN_BINARY" ] && [ -s "$PLUGIN_BINARY" ]; then
	echo "✓ Provider $PROVIDER_NAME v$VERSION is already installed at:"
	echo "  $PLUGIN_BINARY"
	echo ""
	echo "Skipping download and installation."
	exit 0
fi

# Create plugin directory (only if we need to install)
mkdir -p "$PLUGIN_DIR"

# Try multiple filename patterns (different release tools use different conventions)
# Note: Some releases have .zip, others are direct binaries
DOWNLOAD_PATTERNS=(
	"terraform-provider-openshift_v${VERSION}_${OS}_${ARCH}" # Direct binary (no .zip) - most common
	"terraform-provider-openshift_v${VERSION}_${OS}_${ARCH}.zip"
	"terraform-provider-openshift_${VERSION}_${OS}_${ARCH}.zip"
	"terraform-provider-openshift-${VERSION}-${OS}-${ARCH}.zip"
	"terraform-provider-openshift-${VERSION}_${OS}_${ARCH}.zip"
	"terraform-provider-openshift_${OS}_${ARCH}.zip"
)

BASE_URL="https://github.com/rh-mobb/terraform-openshift-provider/releases/download/v${VERSION}"

# Download and extract
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
cd "$TMP_DIR"

DOWNLOADED=false
DOWNLOADED_FILE=""
IS_ZIP=false
for PATTERN in "${DOWNLOAD_PATTERNS[@]}"; do
	DOWNLOAD_URL="${BASE_URL}/${PATTERN}"
	echo "Trying: $DOWNLOAD_URL"

	# Determine if this pattern is a zip file
	case "$PATTERN" in
	*.zip)
		IS_ZIP=true
		OUTPUT_FILE="provider.zip"
		;;
	*)
		IS_ZIP=false
		OUTPUT_FILE="provider.binary"
		;;
	esac

	# Try to download with curl
	if command -v curl &>/dev/null; then
		HTTP_CODE=$(curl -L -f -s -o /dev/null -w "%{http_code}" "$DOWNLOAD_URL" 2>/dev/null || echo "000")
		if [ "$HTTP_CODE" = "200" ]; then
			if curl -L -f -s -o "$OUTPUT_FILE" "$DOWNLOAD_URL" 2>/dev/null; then
				if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
					DOWNLOADED=true
					DOWNLOADED_FILE="$PATTERN"
					break
				fi
			fi
		fi
	# Try to download with wget
	elif command -v wget &>/dev/null; then
		if wget -q --spider "$DOWNLOAD_URL" 2>/dev/null; then
			if wget -q -O "$OUTPUT_FILE" "$DOWNLOAD_URL" 2>/dev/null; then
				if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
					DOWNLOADED=true
					DOWNLOADED_FILE="$PATTERN"
					break
				fi
			fi
		fi
	fi
done

if [ "$DOWNLOADED" = false ]; then
	echo "Error: Failed to download provider with any known filename pattern."
	echo ""
	echo "Tried patterns:"
	for PATTERN in "${DOWNLOAD_PATTERNS[@]}"; do
		echo "  - ${BASE_URL}/${PATTERN}"
	done
	echo ""
	echo "Checking available assets..."
	if command -v curl &>/dev/null; then
		ASSETS=$(curl -s "https://api.github.com/repos/rh-mobb/terraform-openshift-provider/releases/tags/v${VERSION}" | grep -o '"name": "[^"]*"' | sed 's/"name": "//;s/"$//' | grep -E "${OS}|${ARCH}" || echo "Could not fetch asset list")
		if [ -n "$ASSETS" ]; then
			echo "Available assets for ${OS}/${ARCH}:"
			echo "$ASSETS" | head -5
		fi
	fi
	echo ""
	echo "Please check available assets at:"
	echo "https://github.com/rh-mobb/terraform-openshift-provider/releases/tag/v${VERSION}"
	echo ""
	echo "To install manually:"
	echo "1. Download the appropriate file for ${OS}/${ARCH}"
	echo "2. If it's a zip, extract it: unzip <downloaded-file>.zip"
	echo "3. Copy the binary: cp terraform-provider-openshift* $PLUGIN_DIR/$BINARY_NAME"
	echo "4. Make executable: chmod +x $PLUGIN_DIR/$BINARY_NAME"
	exit 1
fi

echo "✓ Successfully downloaded provider (${DOWNLOADED_FILE})"

# Check if it's a zip file or direct binary
if [ "$IS_ZIP" = true ] && [ -f "provider.zip" ]; then
	# Check if it's actually a zip file
	if file provider.zip | grep -q "Zip archive"; then
		# Extract zip
		if command -v unzip &>/dev/null; then
			unzip -q provider.zip
		elif command -v tar &>/dev/null; then
			tar -xzf provider.zip 2>/dev/null || tar -xzf provider.zip
		else
			echo "Error: unzip or tar required to extract zip file"
			exit 1
		fi

		# Find the binary (it might be in a subdirectory)
		BINARY=$(find . -name "$BINARY_NAME" -o -name "$BINARY_NAME.exe" | head -1)

		if [ -z "$BINARY" ]; then
			echo "Error: Binary '$BINARY_NAME' not found in archive"
			echo "Contents of archive:"
			ls -la
			exit 1
		fi
	else
		# File has .zip extension but isn't actually a zip - treat as binary
		mv provider.zip "$BINARY_NAME"
		BINARY="$BINARY_NAME"
	fi
elif [ -f "provider.binary" ]; then
	# It's a direct binary (no zip extension)
	mv provider.binary "$BINARY_NAME"
	BINARY="$BINARY_NAME"
else
	echo "Error: Downloaded file not found"
	exit 1
fi

# Copy to plugin directory
cp "$BINARY" "$PLUGIN_DIR/$BINARY_NAME"
chmod +x "$PLUGIN_DIR/$BINARY_NAME"

# Verify installation succeeded
if [ ! -f "$PLUGIN_BINARY" ]; then
	echo "Error: Failed to install provider binary to $PLUGIN_BINARY"
	exit 1
fi

if [ ! -x "$PLUGIN_BINARY" ]; then
	echo "Error: Installed binary is not executable: $PLUGIN_BINARY"
	exit 1
fi

if [ ! -s "$PLUGIN_BINARY" ]; then
	echo "Error: Installed binary is empty: $PLUGIN_BINARY"
	exit 1
fi

echo "✓ Provider installed to: $PLUGIN_DIR"
echo "✓ Binary: $PLUGIN_DIR/$BINARY_NAME"
echo ""
echo "Next steps:"
echo "1. Update your Terraform configuration to use version $VERSION:"
echo "   openshift = {"
echo "     source  = \"registry.terraform.io/rh-mobb/openshift\""
echo "     version = \"$VERSION\""
echo "   }"
echo "2. Run 'terraform init' in your Terraform configuration directory."

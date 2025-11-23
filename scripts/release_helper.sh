#!/bin/bash

# DinoX Release Helper Script
# Usage: ./scripts/release_helper.sh <version>
# Example: ./scripts/release_helper.sh 0.6.3

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 0.6.3"
    exit 1
fi

VERSION="$1"
DATE=$(date +%Y-%m-%d)
READABLE_DATE=$(date "+%B %d, %Y")

echo "Preparing release v$VERSION ($DATE)..."

# 1. Update CHANGELOG.md
# Replaces "## [Unreleased]" with "## [Unreleased]\n\n## [VERSION] - DATE"
sed -i "s/## \[Unreleased\]/## [Unreleased]\n\n## [$VERSION] - $DATE/" CHANGELOG.md

# Update the links at the bottom of CHANGELOG.md
# This is a bit complex with sed, so we'll append the new link and update the Unreleased link
# Assuming the last line is the previous version link
PREV_VERSION=$(grep -oP "\[\d+\.\d+\.\d+\]:.*tag/v\K.*" CHANGELOG.md | head -1)
if [ ! -z "$PREV_VERSION" ]; then
    # Update Unreleased link to compare VERSION...HEAD
    sed -i "s/\[Unreleased\]:.*compare\/v.*HEAD/[Unreleased]: https:\/\/github.com\/rallep71\/dinox\/compare\/v$VERSION...HEAD/" CHANGELOG.md
    # Add new version link
    echo "[$VERSION]: https://github.com/rallep71/dinox/releases/tag/v$VERSION" >> CHANGELOG.md
fi

echo "Updated CHANGELOG.md"

# 2. Update DEVELOPMENT_PLAN.md
sed -i "s/> \*\*Version\*\*: .*/> **Version**: $VERSION/" DEVELOPMENT_PLAN.md
sed -i "s/> \*\*Last Updated\*\*: .*/> **Last Updated**: $READABLE_DATE/" DEVELOPMENT_PLAN.md
echo "Updated DEVELOPMENT_PLAN.md"

# 3. Update AppData
# Insert new release tag after <releases>
# We use a temporary file to construct the XML block
TMP_XML=$(mktemp)
cat <<EOF > "$TMP_XML"
    <release date="$DATE" version="$VERSION">
      <description>
        <p>See CHANGELOG.md for details.</p>
      </description>
    </release>
EOF

# Insert content of TMP_XML after <releases>
sed -i "/<releases>/r $TMP_XML" main/data/im.github.rallep71.DinoX.appdata.xml
rm "$TMP_XML"
echo "Updated AppData"

echo "------------------------------------------------"
echo "Release v$VERSION prepared successfully!"
echo "Please review the changes:"
echo "  - CHANGELOG.md"
echo "  - DEVELOPMENT_PLAN.md"
echo "  - main/data/im.github.rallep71.DinoX.appdata.xml"
echo ""
echo "Next steps:"
echo "1. git add ."
echo "2. git commit -m \"Release v$VERSION\""
echo "3. git tag v$VERSION"
echo "4. git push origin master --tags"
echo "------------------------------------------------"

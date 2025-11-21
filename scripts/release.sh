#!/bin/bash
# Release script for DinoX

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get version from argument
if [ -z "$1" ]; then
    echo -e "${RED}ERROR: No version specified${NC}"
    echo "Usage: $0 <version>"
    echo "Example: $0 0.6.0"
    exit 1
fi
VERSION="$1"

# Validate version format
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}ERROR: Invalid version format: $VERSION${NC}"
    echo "Version must be in format: X.Y.Z (e.g., 0.6.0)"
    exit 1
fi

TAG="v$VERSION"

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}DinoX Release Script${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo -e "Version: ${YELLOW}$VERSION${NC}"
echo -e "Tag:     ${YELLOW}$TAG${NC}"
echo ""

# Check if we're on master
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "master" ]; then
    echo -e "${YELLOW}WARNING: Not on master branch (currently on: $CURRENT_BRANCH)${NC}"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check for uncommitted changes
if ! git diff-index --quiet HEAD --; then
    echo -e "${RED}ERROR: You have uncommitted changes${NC}"
    echo "Please commit or stash your changes first"
    git status --short
    exit 1
fi

# Check if tag already exists
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo -e "${RED}ERROR: Tag $TAG already exists${NC}"
    echo "Use 'git tag -d $TAG' to delete it first if needed"
    exit 1
fi

# Update CHANGELOG.md date if [Unreleased] exists
if grep -q "## \[Unreleased\]" CHANGELOG.md; then
    TODAY=$(date +%Y-%m-%d)
    sed -i "s/## \[Unreleased\]/## [Unreleased]\n\n## [$VERSION] - $TODAY/" CHANGELOG.md
    echo -e "${GREEN}✓${NC} Updated CHANGELOG.md"
else
    echo -e "${YELLOW}⚠${NC} No [Unreleased] section in CHANGELOG.md"
fi

# Commit changelog update
git add CHANGELOG.md
git commit -m "chore: Release version $VERSION

Release: DinoX v$VERSION

See CHANGELOG.md for full details."
echo -e "${GREEN}✓${NC} Committed version bump"

# Create annotated tag
git tag -a "$TAG" -m "Release DinoX v$VERSION

See CHANGELOG.md for details."
echo -e "${GREEN}✓${NC} Created tag $TAG"

# Show what will be pushed
echo ""
echo -e "${YELLOW}Ready to push:${NC}"
echo "  - Commit: $(git rev-parse --short HEAD)"
echo "  - Tag: $TAG"
echo ""
echo -e "${YELLOW}This will:${NC}"
echo "  1. Push the commit to GitHub"
echo "  2. Push the tag to GitHub"
echo "  3. Trigger the release workflow"
echo "  4. Build Flatpak packages (x86_64, aarch64)"
echo "  5. Create GitHub release with assets"
echo ""

read -p "Push to GitHub and create release? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Push commit
    git push origin "$CURRENT_BRANCH"
    echo -e "${GREEN}✓${NC} Pushed commit"
    
    # Push tag
    git push origin "$TAG"
    echo -e "${GREEN}✓${NC} Pushed tag"
    
    echo ""
    echo -e "${GREEN}======================================${NC}"
    echo -e "${GREEN}Release initiated successfully!${NC}"
    echo -e "${GREEN}======================================${NC}"
    echo ""
    echo -e "GitHub Actions will now:"
    echo -e "  1. Build source tarball"
    echo -e "  2. Build Flatpak packages"
    echo -e "  3. Create release with assets"
    echo ""
    echo -e "Track progress at:"
    echo -e "  ${YELLOW}https://github.com/rallep71/dinox/actions${NC}"
    echo ""
    echo -e "Release will be available at:"
    echo -e "  ${YELLOW}https://github.com/rallep71/dinox/releases/tag/$TAG${NC}"
else
    echo -e "${YELLOW}Aborted.${NC}"
    echo ""
    echo "To undo the local changes:"
    echo "  git reset --hard HEAD~1"
    echo "  git tag -d $TAG"
    exit 1
fi

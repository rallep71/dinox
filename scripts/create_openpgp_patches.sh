#!/bin/bash
# Script to create diffs between xmppwin and original dino
# Run this from the xmppwin directory

DINO_PATH="${1:-../dino}"
OUTPUT_DIR="patches"

mkdir -p "$OUTPUT_DIR"

echo "Creating patches for OpenPGP porting..."
echo "Dino path: $DINO_PATH"
echo "Output: $OUTPUT_DIR/"
echo ""

# Changed files
echo "=== Changed Files ==="

files_to_diff=(
    "plugins/openpgp/src/stream_module.vala"
    "plugins/openpgp/src/manager.vala"
    "plugins/openpgp/src/plugin.vala"
    "plugins/openpgp/src/encryption_preferences_entry.vala"
    "plugins/openpgp/src/encryption_list_entry.vala"
    "plugins/openpgp/src/contact_details_provider.vala"
    "libdino/src/service/presence_manager.vala"
    "plugins/openpgp/meson.build"
    "xmpp-vala/meson.build"
)

for file in "${files_to_diff[@]}"; do
    if [[ -f "$DINO_PATH/$file" ]] && [[ -f "$file" ]]; then
        patch_name=$(echo "$file" | tr '/' '_').patch
        diff -u "$DINO_PATH/$file" "$file" > "$OUTPUT_DIR/$patch_name"
        lines=$(wc -l < "$OUTPUT_DIR/$patch_name")
        if [[ $lines -gt 0 ]]; then
            echo "  ✓ $file ($lines lines changed)"
        else
            rm "$OUTPUT_DIR/$patch_name"
            echo "  = $file (no changes)"
        fi
    else
        echo "  ✗ $file (file missing in one location)"
    fi
done

echo ""
echo "=== New Files (copy to dino) ==="

new_files=(
    "xmpp-vala/src/module/xep/0373_openpgp.vala"
    "xmpp-vala/src/module/xep/0374_openpgp_content.vala"
    "plugins/openpgp/src/xep0373_key_manager.vala"
    "plugins/openpgp/src/key_management_dialog.vala"
)

for file in "${new_files[@]}"; do
    if [[ -f "$file" ]]; then
        if [[ ! -f "$DINO_PATH/$file" ]]; then
            echo "  + $file (NEW - copy to dino)"
            cp "$file" "$OUTPUT_DIR/$(basename $file)"
        else
            echo "  = $file (already exists in dino)"
        fi
    else
        echo "  ✗ $file (not found)"
    fi
done

echo ""
echo "=== Windows-Only Files (DO NOT copy) ==="
windows_only=(
    "plugins/openpgp/src/gpg_cli_helper.vala"
)

for file in "${windows_only[@]}"; do
    if [[ -f "$file" ]]; then
        echo "  ⚠ $file (Windows-only, keep separate)"
    fi
done

echo ""
echo "=== Summary ==="
echo "Patches created in: $OUTPUT_DIR/"
echo ""
echo "To apply patches to dino:"
echo "  cd $DINO_PATH"
echo "  patch -p0 < ../xmppwin/$OUTPUT_DIR/plugins_openpgp_src_stream_module.vala.patch"
echo ""
echo "To copy new files:"
echo "  cp $OUTPUT_DIR/0373_openpgp.vala $DINO_PATH/xmpp-vala/src/module/xep/"
echo "  cp $OUTPUT_DIR/0374_openpgp_content.vala $DINO_PATH/xmpp-vala/src/module/xep/"
echo "  cp $OUTPUT_DIR/xep0373_key_manager.vala $DINO_PATH/plugins/openpgp/src/"

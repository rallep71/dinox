# DinoX: Security & UI/UX Consistency Plan

This document outlines the strategy to address two critical areas: ensuring codebase integrity (Unicode Security) and unifying the User Interface (UI/UX consistency) to meet modern GNOME/Libadwaita standards.

## Part 1: Codebase Integrity & Security (Unicode)

### Problem Analysis
Hidden Unicode characters (Zero-width spaces, Bidi-overrides, etc.) can be used for "Trojan Source" attacks or simply cause inexplicable compiler bugs. An initial scan identified **12** potential instances in the codebase.

### Action Items

1.  **Immediate Sanitization** (✅ Verified & Safe)
    *   **Action**: Reviewed the identified locations from the scan.
    *   **Results**:
        *   `main/src/ui/util/helper.vala`: Clean. No raw Non-Breaking Spaces found.
        *   `xmpp-vala/tests/jid.vala`: Uses escaped `\u200F` (RLM) to test that the JID parser *correctly rejects* invalid Bidi characters. **Safe / Intentional**.
        *   `scripts/translate_all.py`: Contains ZWNJ/ZWJ characters in Persian ("آدرس پیام‌رسان") and Sinhala strings. These are linguistically required for correct display. **Safe / Intentional**.

2.  **Continuous Integration (CI) Gate**
    *   **Action**: Integrate `scripts/scan_unicode.py` into the CI pipeline.
    *   **Goal**: Prevent any Pull Request from merging if it introduces unsuspecting dangerous characters.

## Part 1.5: Deep Code Audit (Security & Stability)

### Phase 1: OMEMO Hardening & Style (✅ Completed)
*   **Status**: Done.
*   **Action**: Hardened the OMEMO module against crashes and weak random number generation.
*   **Details**:
    *   `plugins/omemo/src/protocol/stream_module.vala`: Fixed unsafe `assert`s, replaced `Random.int_range` with PRNG.
    *   `plugins/omemo/src/file_transfer/file_decryptor.vala`: Removed crash-inducing `assert(false)` on missing metadata.
    *   **Linting**: All modified OMEMO files (`simple_pks/spks`, `store`, `bundle`, `plugin`) are now compliant with `io.elementary.vala-lint`.

### Phase 2: General App Stability (Assert Elimination) (✅ Completed)
*   **Goal**: Replace hard crashes (`assert()`, `assert_not_reached()`) with proper error handling across the entire application.
*   **Target Files**:
    1.  **Plugins**:
        *   [x] `plugins/http-files/src/file_provider.vala` (Replaced `assert(false)` with `IOError.INVALID_ARGUMENT`)
        *   [x] `plugins/ice/src/transport_parameters.vala` (Replaced `assert_not_reached` with graceful fallback/warning)
    2.  **XMPP Core (Jingle/ByteStreams)**:
        *   [x] `xmpp-vala/src/module/xep/0047_in_band_bytestreams.vala` (State assertions replaced with warnings/IOErrors)
        *   [x] `xmpp-vala/src/module/xep/0261_jingle_in_band_bytestreams.vala` (Handled multi-component warning)
        *   [x] `xmpp-vala/src/module/xep/0260_jingle_socks5_bytestreams.vala` (Handled enums and component count)
        *   [x] `xmpp-vala/src/module/xep/0166_jingle/*` (Session, Component handling hardened against enum changes/state issues)
    3.  **App Core / UI**:
        *   [x] `main/src/ui/global_search.vala` (Replaced crash on regex error with warning/fallback)
        *   [x] `libdino/src/service/conversation_manager.vala` (Recover gracefully if account is missing in conversation map)
        *   [x] `main/src/windows/preferences_window/*` (Removed crash on unknown UI states)

### Phase 3: Global Linting (📅 Deferred)
*   **Goal**: Apply strict code style (spacing, naming conventions) to the entire legacy codebase.
*   **Status**: Deferred to end of project.

## Part 2: UI/UX Consistency (Libadwaita)

While DinoX has successfully migrated core windows to GTK4 and Libadwaita (`Adw.Dialog`, `Adw.Window`), visual inconsistencies ("Inkontinenz") likely stem from:
*   Legacy styling (custom CSS margins/padding) instead of Libadwaita style classes.
*   Mixing of legacy icons (full color) and modern symbolic icons.
*   Inconsistent "Empty States" or placeholder views.

### Action Items

#### 1. Standardization of Dialogs & Views
*   **Audit**: Review all custom `.ui` files.
*   **Goal**: Ensure every transient window uses `Adw.Dialog` (or `Adw.Window` for standalone).
*   **Status**: *PASSED* (Initial grep shows widespread adoption of `Adw.Dialog`).

#### 2. Spacing & Margins (The "Feeling" of the App)
*   **Problem**: Legacy GTK3 code often uses hardcoded pixel values (e.g., `margin="10"`).
*   **Solution**: Replace hardcoded margins with Adwaita style classes where possible.
    *   Use `spacing-12` or `padding-18` classes if available in our CSS reset.
    *   Use `Adw.Clamp` to restrict content width for better readability on large screens.

#### 3. Iconography
*   **Problem**: Inconsistent mixing of colored and symbolic icons.
*   **Solution**: Enforce **Symbolic Icons** (`-symbolic`) for all UI elements (buttons, menus, lists).
    *   Colored icons (Avatars, Stickes) must be reserved for user-generated content only.

#### 4. Navigation & Lists
*   **Goal**: Migrate all list views to `Adw.PreferencesGroup` and `Adw.ActionRow` where applicable.
*   **Benefit**: This provides the standard "rounded group" look of modern GNOME apps automatically.
*   **Target**: Check `Settings` pages and `Contact Details`.

#### 5. Empty States
*   **Goal**: Use `Adw.StatusPage` for all empty states (e.g., "No conversation selected", "No results found").
*   **Current State**: Sometimes custom `Gtk.Box` with labels are used.

## Implementation Timeline

*   **Phase 1 (Immediate)**: Run manual cleanup of `scan_unicode.py` results.
*   **Phase 2 (Next Release)**: Audit `main/src/ui/` for hardcoded margins and replace with standard Adwaita spacing.
*   **Phase 3 (Ongoing)**: Refactor functional settings lists to `Adw.ActionRow`.

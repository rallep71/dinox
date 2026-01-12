# DinoX: Security & UI/UX Consistency Plan

This document outlines the strategy to address two critical areas: ensuring codebase integrity (Unicode Security) and unifying the User Interface (UI/UX consistency) to meet modern GNOME/Libadwaita standards.

## Part 1: Codebase Integrity & Security (Unicode)

### Problem Analysis
Hidden Unicode characters (Zero-width spaces, Bidi-overrides, etc.) can be used for "Trojan Source" attacks or simply cause inexplicable compiler bugs. An initial scan identified **12** potential instances in the codebase.

### Action Items

1.  **Immediate Sanitization**
    *   **Action**: Review the 12 identified locations from the scan.
    *   **Context**:
        *   `main/src/ui/util/helper.vala`: Contains Non-Breaking Spaces (NBSP). *Verdict: Verify if intentional for UI formatting.*
        *   `xmpp-vala/tests/jid.vala`: Contains RTL marks. *Verdict: Likely intentional for testing XMPP JID handling of RTL languages, but must be verified.*
        *   `scripts/translate_all.py`: Contains ZWJ/ZWNJ. *Verdict: Likely required for automated translation of certain scripts (e.g., Arabic/Persian).*

2.  **Continuous Integration (CI) Gate**
    *   **Action**: Integrate `scripts/scan_unicode.py` into the CI pipeline.
    *   **Goal**: Prevent any Pull Request from merging if it introduces unsuspecting dangerous characters.

## Part 2: UI/UX Consistency (GTK4 & Libadwaita)

### Problem Analysis
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

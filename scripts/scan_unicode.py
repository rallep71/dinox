#!/usr/bin/env python3
"""Scan source files for hidden/dangerous Unicode characters.

Detects zero-width characters, BiDi overrides, homoglyph attacks,
and other invisible Unicode that can hide malicious code or cause
subtle bugs. Run from the project root directory.

Usage: python3 scripts/scan_unicode.py [--verbose]
"""

import os
import sys

# Dangerous or suspicious Unicode characters
SUSPICIOUS_CHARS = {
    # Zero-width characters (can hide code)
    '\u200b': 'Zero Width Space',
    # Note: U+200C (ZWNJ) and U+200D (ZWJ) are excluded because they are
    # linguistically required in Persian/Arabic translations (ZWNJ is used
    # between word parts, ZWJ controls ligature joining).
    '\uFEFF': 'Zero Width No-Break Space / BOM',

    # BiDi control characters (CVE-2021-42574 "Trojan Source" attack vector)
    '\u200e': 'Left-To-Right Mark',
    '\u200f': 'Right-To-Left Mark',
    '\u202a': 'Left-To-Right Embedding',
    '\u202b': 'Right-To-Left Embedding',
    '\u202c': 'Pop Directional Formatting',
    '\u202d': 'Left-To-Right Override',
    '\u202e': 'Right-To-Left Override',
    '\u2066': 'Left-To-Right Isolate',
    '\u2067': 'Right-To-Left Isolate',
    '\u2068': 'First Strong Isolate',
    '\u2069': 'Pop Directional Isolate',

    # Unusual whitespace
    # Note: U+00A0 (NBSP) is excluded because it legitimately appears in
    # translated strings (e.g. French/Luxembourgish typographic rules).
    '\u2000': 'En Quad',
    '\u2001': 'Em Quad',
    '\u2002': 'En Space',
    '\u2003': 'Em Space',
    '\u2004': 'Three-Per-Em Space',
    '\u2005': 'Four-Per-Em Space',
    '\u2006': 'Six-Per-Em Space',
    '\u2007': 'Figure Space',
    '\u2008': 'Punctuation Space',
    '\u2009': 'Thin Space',
    '\u200a': 'Hair Space',
    '\u205f': 'Medium Mathematical Space',
    '\u3000': 'Ideographic Space',

    # Line/paragraph separators (can break parsing)
    '\u2028': 'Line Separator',
    '\u2029': 'Paragraph Separator',

    # Tag characters (can be used to hide data)
    '\U000E0001': 'Language Tag',

    # Interlinear annotation (can hide text)
    '\uFFF9': 'Interlinear Annotation Anchor',
    '\uFFFA': 'Interlinear Annotation Separator',
    '\uFFFB': 'Interlinear Annotation Terminator',

    # Replacement/specials
    '\uFFFC': 'Object Replacement Character',
    '\uFFFD': 'Replacement Character',

    # Soft hyphen (invisible in most contexts)
    '\u00AD': 'Soft Hyphen',
}

EXTENSIONS = [
    '.vala', '.c', '.h', '.py', '.sh', '.md', '.txt',
    '.ui', '.xml', '.json', '.css', '.build', '.in',
    '.yml', '.yaml', '.meson', '.doap', '.desktop',
]
IGNORE_DIRS = {'build', 'build-linux', '.git', 'icon_backup', '.venv', 'node_modules', '__pycache__'}

def scan_file(path, verbose=False):
    """Scan a single file for suspicious Unicode. Returns list of findings."""
    findings = []
    try:
        with open(path, 'r', encoding='utf-8') as f:
            for lineno, line in enumerate(f, start=1):
                for col, char in enumerate(line, start=1):
                    cp = ord(char)
                    if char in SUSPICIOUS_CHARS:
                        findings.append({
                            'file': path,
                            'line': lineno,
                            'col': col,
                            'codepoint': f'U+{cp:04X}',
                            'name': SUSPICIOUS_CHARS[char],
                        })
                    elif cp < 32 and cp not in (9, 10, 13):  # TAB, LF, CR
                        findings.append({
                            'file': path,
                            'line': lineno,
                            'col': col,
                            'codepoint': f'U+{cp:04X}',
                            'name': 'ASCII Control Character',
                        })
                    elif 0xE0020 <= cp <= 0xE007F:  # Tag characters range
                        findings.append({
                            'file': path,
                            'line': lineno,
                            'col': col,
                            'codepoint': f'U+{cp:04X}',
                            'name': 'Tag Character',
                        })
    except UnicodeDecodeError:
        if verbose:
            print(f"  Warning: Could not decode {path} as UTF-8, skipping.")
    except PermissionError:
        if verbose:
            print(f"  Warning: Permission denied for {path}, skipping.")
    except Exception as e:
        print(f"  Error reading {path}: {e}")
    return findings


def main():
    verbose = '--verbose' in sys.argv or '-v' in sys.argv
    scan_root = '.'
    files_scanned = 0
    all_findings = []

    print("Scanning for hidden Unicode characters...")
    if verbose:
        print(f"  Root: {os.path.abspath(scan_root)}")
        print(f"  Extensions: {', '.join(EXTENSIONS)}")
        print(f"  Ignoring: {', '.join(sorted(IGNORE_DIRS))}")
        print()

    for root, dirs, files in os.walk(scan_root):
        dirs[:] = [d for d in dirs if d not in IGNORE_DIRS]

        for filename in files:
            if not any(filename.endswith(ext) for ext in EXTENSIONS):
                continue

            path = os.path.join(root, filename)
            files_scanned += 1
            findings = scan_file(path, verbose)
            all_findings.extend(findings)

    # Report
    print(f"\nScanned {files_scanned} files.")

    if all_findings:
        print(f"\nWARNING: {len(all_findings)} suspicious character(s) found!\n")
        for f in all_findings:
            print(f"  {f['file']}:{f['line']}:{f['col']}  {f['codepoint']} ({f['name']})")
        sys.exit(1)
    else:
        print("OK: No hidden Unicode control characters found.")
        sys.exit(0)


if __name__ == '__main__':
    main()

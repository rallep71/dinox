import os
import re

# Definiere gefährliche oder unerwünschte Unicode-Bereiche
suspicious_chars = {
    '\u200b': 'Zero Width Space',
    '\u200c': 'Zero Width Non-Joiner',
    '\u200d': 'Zero Width Joiner',
    '\u200e': 'Left-To-Right Mark',
    '\u200f': 'Right-To-Left Mark',
    '\uFEFF': 'Zero Width No-Break Space / BOM',
    '\u202a': 'Left-To-Right Embedding',
    '\u202b': 'Right-To-Left Embedding',
    '\u202d': 'Left-To-Right Override',
    '\u202e': 'Right-To-Left Override',
    '\u2066': 'Left-To-Right Isolate',
    '\u2067': 'Right-To-Left Isolate',
    '\u2068': 'First Strong Isolate',
    '\u2028': 'Line Separator',
    '\u2029': 'Paragraph Separator',
    '\u00A0': 'Non-Breaking Space (NBSP)' # Kann in Code tödlich sein
}

extensions = ['.vala', '.c', '.h', '.py', '.sh', '.md', '.txt', '.ui', '.xml', '.json', '.css', '.build', '.in', '.yml', '.yaml']
ignore_dirs = ['build', '.git', 'icon_backup', '.venv']

found_issues = []

print("Starte Scan nach versteckten Unicode-Zeichen...")

for root, dirs, files in os.walk('.'):
    # Filter ignored dirs
    dirs[:] = [d for d in dirs if d not in ignore_dirs]
    
    for file in files:
        if not any(file.endswith(ext) for ext in extensions):
            continue
            
        path = os.path.join(root, file)
        try:
            with open(path, 'r', encoding='utf-8') as f:
                lines = f.readlines()
                for i, line in enumerate(lines):
                    for char in line:
                        if char in suspicious_chars:
                            found_issues.append(f"{path}:{i+1} : Gefunden '{suspicious_chars[char]}' (U+{ord(char):04X})")
                        elif ord(char) < 32 and ord(char) not in [9, 10, 13]: # 9=TAB, 10=LF, 13=CR
                             found_issues.append(f"{path}:{i+1} : Gefunden 'ASCII Control Char' (U+{ord(char):04X})")
        except UnicodeDecodeError:
            print(f"Warnung: Konnte {path} nicht als UTF-8 lesen.")
        except Exception as e:
            print(f"Fehler bei {path}: {e}")

if found_issues:
    print(f"\nACHTUNG: {len(found_issues)} verdächtige Stellen gefunden!")
    for issue in found_issues:
        print(issue)
else:
    print("\nPerfekt: Keine versteckten Unicode-Steuerzeichen gefunden.")

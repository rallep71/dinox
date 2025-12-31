import os
import subprocess
import sys

directories = [
    "main/po",
    "plugins/omemo/po",
    "plugins/openpgp/po"
]

def check_po_file(filepath):
    try:
        # Run msgfmt --statistics
        # Output is usually on stderr
        result = subprocess.run(
            ["msgfmt", "--statistics", filepath],
            capture_output=True,
            text=True
        )
        output = result.stderr.strip()
        
        # Parse output
        # Example: "54 übersetzte Meldungen, 2 ungenaue Übersetzungen."
        # Example: "6 übersetzte Meldungen, 2 ungenaue Übersetzungen, 48 unübersetzte Meldungen."
        
        translated = 0
        fuzzy = 0
        untranslated = 0
        
        parts = output.split(", ")
        for part in parts:
            if "übersetzte Meldungen" in part and "un" not in part: # "54 übersetzte Meldungen"
                translated = int(part.split()[0])
            elif "ungenaue" in part:
                fuzzy = int(part.split()[0])
            elif "unübersetzt" in part:
                untranslated = int(part.split()[0])
                
        return translated, fuzzy, untranslated, output
    except Exception as e:
        return 0, 0, 0, str(e)

def main():
    print(f"{'File':<40} | {'Trans':<5} | {'Fuzzy':<5} | {'Untrans':<7} | {'Status'}")
    print("-" * 80)
    
    total_untranslated = 0
    files_with_issues = []

    for d in directories:
        if not os.path.exists(d):
            continue
            
        print(f"--- {d} ---")
        files = sorted([f for f in os.listdir(d) if f.endswith(".po")])
        
        for f in files:
            filepath = os.path.join(d, f)
            t, fz, u, raw = check_po_file(filepath)
            
            status = "OK"
            if u > 0:
                status = "MISSING"
                total_untranslated += u
                files_with_issues.append(filepath)
            elif fz > 0:
                status = "FUZZY"
            
            # Only print if not 100% clean or if it's interesting
            if u > 0 or fz > 0:
                print(f"{f:<40} | {t:<5} | {fz:<5} | {u:<7} | {status}")

    print("-" * 80)
    if total_untranslated == 0:
        print("All files are 100% translated (ignoring fuzzy).")
    else:
        print(f"Found {total_untranslated} untranslated strings in {len(files_with_issues)} files.")
        for f in files_with_issues:
            print(f"  - {f}")

if __name__ == "__main__":
    main()

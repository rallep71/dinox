import os
import re

# Path to PO files
PO_DIR = '/media/linux/SSD128/xmpp/main/po'

# The specific keys we are interested in
TARGET_KEYS = [
    "Public Access",
    "Allow anyone to see your profile",
    "Share with Contacts",
    "Allow contacts to see your profile"
]

def parse_po_file(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    results = {}
    
    # Pre-process file into blocks for easier parsing? 
    # Or just scan. Scanning is fine.
    
    for key in TARGET_KEYS:
        key_found = False
        translation = None
        is_fuzzy = False
        
        # We need to find 'msgid "KEY"'
        # But it might be wrapped if long? Assuming simple one-liners for these short keys.
        target_msgid = f'msgid "{key}"'
        
        for i, line in enumerate(lines):
            if line.strip() == target_msgid:
                key_found = True
                
                # Check previous lines for fuzzy
                # Look backwards from i-1
                j = i - 1
                while j >= 0:
                    prev_line = lines[j].strip()
                    if not prev_line.startswith("#"):
                        break
                    if "fuzzy" in prev_line:
                        is_fuzzy = True
                    j -= 1
                
                # Get msgstr
                # Usually the next line
                if i + 1 < len(lines):
                    next_line = lines[i+1].strip()
                    if next_line.startswith('msgstr "'):
                        # Extract content between quotes
                        # Handle simple case: msgstr "Value"
                        # If it spans multiple lines, this simple parser fails, but our keys are short.
                        # The script I wrote earlier writes them as single lines.
                        translation = next_line[8:-1] # remove msgstr " and last "
                
                break
        
        if key_found:
            status = "OK"
            if is_fuzzy:
                status = "FUZZY"
            elif not translation: # Empty string or None
                status = "EMPTY"
            elif translation == key:
                 status = "IDENTICAL"
            
            results[key] = {
                "status": status,
                "translation": translation
            }
        else:
            results[key] = {
                "status": "MISSING",
                "translation": None
            }
            
    return results

def analyze():
    if not os.path.exists(PO_DIR):
        print(f"Directory {PO_DIR} not found.")
        return

    files = sorted([f for f in os.listdir(PO_DIR) if f.endswith('.po')])
    
    print(f"{'Language':<10} | {'Status':<10} | {'Details'}")
    print("-" * 80)
    
    fully_translated_count = 0
    
    for filename in files:
        lang_code = filename[:-3]
        file_path = os.path.join(PO_DIR, filename)
        
        analysis = parse_po_file(file_path)
        
        # Determine overall status for this language
        statuses = [data['status'] for data in analysis.values()]
        
        if all(s == "OK" for s in statuses):
            overall_status = "COMPLETE"
            fully_translated_count += 1
            details = "All 4 strings translated."
        elif all(s == "MISSING" for s in statuses):
            overall_status = "MISSING"
            details = "Strings not found in file."
        else:
            overall_status = "PARTIAL"
            # Count issues
            fuzzy = statuses.count("FUZZY")
            empty = statuses.count("EMPTY")
            missing = statuses.count("MISSING")
            identical = statuses.count("IDENTICAL")
            details = []
            if fuzzy: details.append(f"{fuzzy} fuzzy")
            if empty: details.append(f"{empty} empty")
            if missing: details.append(f"{missing} missing")
            if identical: details.append(f"{identical} identical")
            details = ", ".join(details)

        print(f"{lang_code:<10} | {overall_status:<10} | {details}")

    print("-" * 80)
    print(f"Total Languages: {len(files)}")
    print(f"Fully Translated: {fully_translated_count}")

if __name__ == "__main__":
    analyze()

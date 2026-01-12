import os
import re

root_dir = 'libdino/src'

# Regex to match module_manager.get_module(account, Some.IDENTITY)
# Matches: module_manager.get_module(account, MucManager.IDENTITY)
# Group 1: arguments before IDENTITY (e.g. "account, ")
# Group 2: MucManager
pattern = re.compile(r'\.get_module\s*\((.*),\s*([\w\.]+)\.IDENTITY\s*\)')

def replace_in_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Replacement function to use the captured group
    def replacer(match):
        args_before = match.group(1)
        module_type = match.group(2)
        # return .get_module<MucManager>(account, MucManager.IDENTITY)
        return f'.get_module<{module_type}>({args_before}, {module_type}.IDENTITY)'

    new_content, count = pattern.subn(replacer, content)

    if count > 0:
        print(f"Updating {filepath}: {count} replacements")
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)

for subdir, dirs, files in os.walk(root_dir):
    for file in files:
        if file.endswith('.vala'):
            replace_in_file(os.path.join(subdir, file))

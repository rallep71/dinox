#!/usr/bin/env python3
"""
Strip UI classes (Gtk/Adw) and register_plugin from omemo-internal.vapi
to create a bot-features-compatible vapi for OMEMO types.
"""
import sys

def strip_vapi(input_path):
    with open(input_path) as f:
        lines = f.readlines()

    # Classes to remove (inherit from Gtk/Adw types)
    remove_parents = {'Gtk.Box', 'Gtk.Window', 'Adw.PreferencesGroup'}
    
    output = []
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        # Remove register_plugin and its preceding CCode attribute
        if 'register_plugin' in line and 'public static GLib.Type' in line:
            # Also remove preceding [CCode] line if present
            if output and output[-1].strip().startswith('[CCode'):
                output.pop()
            i += 1
            continue

        # Check if this line starts a class that inherits from a UI type
        is_ui_class = False
        if 'public class ' in stripped or 'internal class ' in stripped:
            for parent in remove_parents:
                if ': ' + parent in stripped:
                    is_ui_class = True
                    break

        if is_ui_class:
            # Remove any preceding annotation lines ([CCode], [GtkTemplate])
            while output and output[-1].strip().startswith('['):
                output.pop()
            # Skip the entire class body by counting braces
            depth = 0
            while i < len(lines):
                for ch in lines[i]:
                    if ch == '{':
                        depth += 1
                    elif ch == '}':
                        depth -= 1
                i += 1
                if depth == 0:
                    break
            continue

        output.append(line)
        i += 1

    sys.stdout.write(''.join(output))

if __name__ == '__main__':
    strip_vapi(sys.argv[1])

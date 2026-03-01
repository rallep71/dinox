#!/usr/bin/env python3
"""
Dead Code Detector for Vala projects (optimized).
Finds public/internal methods with 0 external references.
Uses word-level indexing for O(1) lookups instead of regex scanning.
"""
import os, re, sys
from collections import defaultdict

SKIP_DIRS = {'build', '.venv', '.git', '.flatpak-builder', 'node_modules'}
METHOD_RE = re.compile(
    r'^\s*(?:public|internal)\s+(?:async\s+)?(?:static\s+)?(?:override\s+)?'
    r'(?:virtual\s+)?(?:abstract\s+)?(?:new\s+)?(?:unowned\s+)?'
    r'(?:[\w.<>,?\[\]\s]+?)\s+(\w+)\s*\(', re.MULTILINE)
SIGNAL_RE = re.compile(r'^\s*(?:public|internal)\s+signal\s+\w+\s+(\w+)\s*\(', re.MULTILINE)
SKIP = {'constructed','dispose','finalize','destroy','get_type','class_init','instance_init',
    'activate','startup','shutdown','open','main','run','quit','close','get','set','notify',
    'connect','disconnect','map','unmap','realize','unrealize','measure','size_allocate',
    'snapshot','css_changed','root','unroot','to_string','hash','equal','compare',
    'serialize','deserialize','register_plugin','get_info','get_id','populate','present',
    'show','hide','clicked','changed','toggled','pressed','released','activated','selected',
    'bind','unbind','setup','teardown','create_widget'}
MIN_LEN = 5
WORD_RE = re.compile(r'\b[a-zA-Z_]\w*\b')

def find_vala(root):
    files = []
    for dp, dn, fn in os.walk(root):
        dn[:] = [d for d in dn if d not in SKIP_DIRS]
        files.extend(os.path.join(dp, f) for f in fn if f.endswith('.vala'))
    return files

def is_test(fp):
    return any('test' in p for p in fp.lower().split(os.sep))

def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    print(f"Scanning {root}...\n")
    all_files = find_vala(root)
    src_files = [f for f in all_files if not is_test(f)]
    print(f"Source: {len(src_files)}, Test: {len(all_files)-len(src_files)}")

    fc = {}
    for f in all_files:
        try: fc[f] = open(f, encoding='utf-8', errors='replace').read()
        except: pass
    for dp, dn, fn in os.walk(root):
        dn[:] = [d for d in dn if d not in SKIP_DIRS]
        for f in fn:
            if f.endswith('.vapi'):
                fp = os.path.join(dp, f)
                try: fc[fp] = open(fp, encoding='utf-8', errors='replace').read()
                except: pass

    print("Building word index...")
    fwc = {}
    gwc = defaultdict(int)
    for fp, content in fc.items():
        wc = defaultdict(int)
        for w in WORD_RE.findall(content):
            wc[w] += 1; gwc[w] += 1
        fwc[fp] = wc
    print(f"Indexed {len(gwc)} unique words across {len(fc)} files")

    dead = []; total = 0
    for filepath in src_files:
        content = fc.get(filepath, '')
        if not content: continue
        decls = []
        for m in METHOD_RE.finditer(content):
            n = m.group(1); l = content[:m.start()].count('\n')+1
            if n not in SKIP and len(n) >= MIN_LEN: decls.append((n, l, 'method'))
        for m in SIGNAL_RE.finditer(content):
            n = m.group(1); l = content[:m.start()].count('\n')+1
            if n not in SKIP and len(n) >= MIN_LEN: decls.append((n, l, 'signal'))
        total += len(decls)
        lwc = fwc.get(filepath, {})
        for name, line, kind in decls:
            ext = gwc.get(name, 0) - lwc.get(name, 0)
            if ext == 0:
                dead.append((os.path.relpath(filepath, root), line, name, kind, lwc.get(name,0)))

    print(f"\nDeclarations scanned: {total}")
    print(f"Potentially dead (0 external refs): {len(dead)}\n")

    by_file = defaultdict(list)
    for rp, l, n, k, lr in dead: by_file[rp].append((l, n, k, lr))
    print("="*80)
    print("POTENTIALLY DEAD PUBLIC/INTERNAL DECLARATIONS")
    print("="*80 + "\n")
    for fp in sorted(by_file):
        print(f"  {fp}")
        for l, n, k, lr in sorted(by_file[fp]):
            print(f"    L{l:4d}: [{k:6s}] {n} ({lr} local)")
        print()

    print("="*80)
    print("SUMMARY BY DIRECTORY")
    print("="*80)
    dc = defaultdict(int)
    for rp, *_ in dead:
        p = rp.split(os.sep); dc[os.sep.join(p[:2]) if len(p)>=2 else p[0]] += 1
    for d in sorted(dc, key=lambda x: -dc[x]):
        print(f"  {dc[d]:3d}  {d}")
    print(f"\nTotal: {len(dead)} potentially dead declarations")
    print("Note: Some may be API surface, D-Bus exports, or signal handlers.\n")

if __name__ == '__main__':
    main()

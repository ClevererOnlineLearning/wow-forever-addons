"""Flags Lua string literals with a backslash that is not a valid escape (Windows paths).
Usage: python tests/bscheck.py [folder]   (default: the add-on folder). Prints 'bad: N'."""
import os, re, sys
root = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BS = chr(92)
bad = 0
for d, _, files in os.walk(root):
    for f in files:
        if not f.endswith(".lua"):
            continue
        p = os.path.join(d, f)
        for i, line in enumerate(open(p, encoding="utf-8", errors="replace"), 1):
            for m in re.finditer(r'"([^"]*)"', line):
                s = m.group(1)
                j = 0
                while j < len(s):
                    if s[j] == BS:
                        nxt = s[j + 1] if j + 1 < len(s) else ""
                        if nxt == BS:
                            j += 2
                            continue
                        if (nxt.isalpha() and nxt not in "abfnrtv") or (nxt in "abfnrtv" and "Interface" in s):
                            print(os.path.relpath(p, root), i, line.strip()[:100])
                            bad += 1
                            break
                    j += 1
print("bad:", bad)
sys.exit(1 if bad else 0)

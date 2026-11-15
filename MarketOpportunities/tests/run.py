"""Offline test runner for Market Opportunities (pytest is not installed on this PC).

Usage:  python MarketOpportunities/tests/run.py [name-filter]

Finds lupa through the MO_LUPA environment variable, else %USERPROFILE%\\.mo-dev\\lupa_pkg.
Every tests/test_*.py module is imported and each test_* function in it is run.
"""
import importlib.util
import os
import sys
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)  # the add-on folder

LUPA = os.environ.get("MO_LUPA") or os.path.join(os.path.expanduser("~"), ".mo-dev", "lupa_pkg")
sys.path.insert(0, LUPA)
from lupa import lua51  # noqa: E402


class Env:
    """A fresh Lua state with WoW stubs and one shared add-on namespace table."""

    def __init__(self, stubs=True):
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        self.ns = self.lua.eval("{}")
        self.g = self.lua.globals()
        if stubs:
            self.run_file(os.path.join(HERE, "stubs.lua"))

    def run_file(self, path):
        with open(path, encoding="utf-8") as f:
            src = f.read()
        chunk = self.lua.execute  # noqa: F841 (kept for readability)
        fn = self.lua.eval("function(src, name) return assert(loadstring(src, name)) end")(src, "@" + os.path.basename(path))
        return fn("MarketOpportunities", self.ns)

    def load(self, *paths):
        """Runs add-on files (paths relative to the add-on folder) into the shared ns."""
        for p in paths:
            self.run_file(os.path.join(ROOT, *p.split("/")))
        return self.ns

    def eval(self, code):
        return self.lua.eval(code)

    def execute(self, code):
        return self.lua.execute(code)

    def table(self, py):
        """Converts nested Python dicts/lists into Lua tables (lists become 1-based arrays)."""
        if isinstance(py, dict):
            t = self.lua.table()
            for k, v in py.items():
                t[k] = self.table(v)
            return t
        if isinstance(py, (list, tuple)):
            t = self.lua.table()
            for i, v in enumerate(py, 1):
                t[i] = self.table(v)
            return t
        return py


def lua_list(t):
    """Lua array -> Python list."""
    if t is None:
        return []
    out = []
    i = 1
    while t[i] is not None:
        out.append(t[i])
        i += 1
    return out


def main():
    filt = sys.argv[1] if len(sys.argv) > 1 else ""
    sys.path.insert(0, HERE)
    passed = failed = 0
    for fn in sorted(os.listdir(HERE)):
        if not (fn.startswith("test_") and fn.endswith(".py")):
            continue
        spec = importlib.util.spec_from_file_location(fn[:-3], os.path.join(HERE, fn))
        mod = importlib.util.module_from_spec(spec)
        try:
            spec.loader.exec_module(mod)
        except Exception:
            print("ERROR loading", fn)
            traceback.print_exc()
            failed += 1
            continue
        for name in sorted(dir(mod)):
            if not name.startswith("test_") or filt not in name and filt not in fn:
                continue
            f = getattr(mod, name)
            if not callable(f):
                continue
            try:
                f()
                passed += 1
                print("PASS", fn, name)
            except Exception as e:
                failed += 1
                print("FAIL", fn, name, "-", type(e).__name__, str(e).splitlines()[0] if str(e) else "")
                if os.environ.get("MO_TRACE"):
                    traceback.print_exc()
    print(f"{passed} passed, {failed} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

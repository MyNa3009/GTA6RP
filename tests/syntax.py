import sys, glob, lupa
L = lupa.LuaRuntime()
bad = 0
for root in sys.argv[1:]:
    for f in sorted(glob.glob(root + '/**/*.lua', recursive=True)):
        src = open(f, encoding='utf-8').read()
        r = L.eval('function(s, n) local f, e = load(s, n) return e end')(src, f)
        if r: bad += 1; print(r)
print('Syntax-Fehler:', bad)

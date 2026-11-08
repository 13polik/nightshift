"""Applies mobile texture import settings to every PNG under assets/ (VRAM compression,
mipmaps, normal-map flag, size limits). Run after Godot has created the .import files."""
import glob, os, re

def setk(s, k, v):
    if re.search(r'^' + re.escape(k) + '=', s, re.M):
        return re.sub(r'^' + re.escape(k) + '=.*$', f'{k}={v}', s, flags=re.M)
    return s.replace('[params]\n', f'[params]\n\n{k}={v}\n', 1)

n = 0
for f in glob.glob('assets/**/*.png.import', recursive=True):
    p = f.replace(os.sep, '/')
    s = open(f, encoding='utf-8').read()
    small = '/effects/' in p or '/decals/' in p
    s = setk(s, 'compress/mode', '2')
    s = setk(s, 'mipmaps/generate', 'true')
    s = setk(s, 'process/size_limit', '256' if small else '1024')
    s = setk(s, 'detect_3d/compress_to', '0')
    if p.endswith('_normal.png.import'):
        s = setk(s, 'compress/normal_map', '1')
    open(f, 'w', encoding='utf-8').write(s)
    n += 1
print('patched', n)

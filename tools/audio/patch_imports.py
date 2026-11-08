"""Applies mobile audio import settings to assets/audio: QOA compression, loop flags."""
import glob, os, re

LOOP = ["amb_vent", "amb_hum", "amb_drone", "music_tension", "music_pulse", "music_chase", "generator_loop",
        "elevator", "alarm", "interact_loop", "hunter_breath", "hunter_presence", "heartbeat"]


def setk(s, k, v):
    if re.search(r'^' + re.escape(k) + '=', s, re.M):
        return re.sub(r'^' + re.escape(k) + '=.*$', f'{k}={v}', s, flags=re.M)
    return s.replace('[params]\n', f'[params]\n\n{k}={v}\n', 1)


n = 0
for f in glob.glob('assets/audio/**/*.wav.import', recursive=True):
    s = open(f, encoding='utf-8').read()
    name = os.path.basename(f).replace('.wav.import', '')
    s = setk(s, 'compress/mode', '2')
    s = setk(s, 'edit/loop_mode', '2' if name in LOOP else '1')
    s = setk(s, 'edit/loop_begin', '0')
    s = setk(s, 'edit/loop_end', '-1')
    open(f, 'w', encoding='utf-8').write(s)
    n += 1
print('patched', n)

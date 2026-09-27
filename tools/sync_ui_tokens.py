#!/usr/bin/env python3
"""Keep editor-visible theme palettes synchronized with BunkerDesign.gd.
Run with --check in CI. Deliberately excludes needs/status/quality thresholds.
"""
from pathlib import Path
import re
import sys
ROOT = Path(__file__).resolve().parents[1]
values = dict(re.findall(r'const (\w+): Color = Color\("([0-9a-f]+)"\)', (ROOT / 'scripts/ui/common/BunkerDesign.gd').read_text()))
def color(key):
    h = values[key]
    rgba = [int(h[i:i+2], 16) / 255 for i in range(0, len(h), 2)]
    if len(rgba) == 3:
        rgba.append(1)
    return 'Color(' + ', '.join(f'{v:.6f}' for v in rgba) + ')'
maps = {
 'assets/ui/themes/BunkerRedesignTheme.tres': {'Bunker/colors/' + k: v for k,v in dict(background='BG', text='IVORY', secondary='MUTED', blue='BLUE', brass='BRASS', focus='IVORY', success='GREEN', warning='WARNING', critical='RED', inactive='INACTIVE').items()},
 'assets/fonts/BunkerTheme.tres': {'UI/colors/' + k: v for k,v in dict(bg='BG',border='BRASS',header='IVORY',text='IVORY',dim='MUTED',ok='GREEN',warn='WARNING',crit='RED').items()},
}
dirty=[]
for rel, mapping in maps.items():
    path=ROOT/rel
    before=path.read_text()
    after=before
    for key,value in mapping.items():
        after, count=re.subn(r'^'+re.escape(key)+r' = Color\([^\n]+\)', key+' = '+color(value), after, flags=re.M)
        if count != 1:
            raise SystemExit(f'Expected one theme token: {key}')
    if before!=after:
        dirty.append(rel)
        if '--check' not in sys.argv:
            path.write_text(after)
if '--check' in sys.argv and dirty:
    raise SystemExit('Run tools/sync_ui_tokens.py: '+', '.join(dirty))
print('UI theme tokens synchronized')

#!/usr/bin/env python3
"""Merge only pilot coverage into an existing canonical snapshot; retain other releases."""
import argparse,json
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--input',required=True);p.add_argument('--output',required=True);a=p.parse_args()
r=json.loads(Path(a.input).read_text());e='spec/library-corpus-pilot.md'
for c in r['cells']:
 if c['language']=='cu' and ((c['book']=='octoechos' and c.get('alias')=='octoechos-cs-gr') or c['book'] in ['akathist-book','menaion']):
  if e not in c['evidence']:c['evidence'].append(e)
  c['updated_at']='2026-11-17'
  if c['book']=='akathist-book':
   c['stages'][4]='partial';c['stages'][5]='partial';c['quality']['label']='В корпусном пилоте подключён акафист Николаю: 25 строф, без молитв; Unicode 17, без новой копии текста. Полнота Акафистника, сплошная выверка и межъязыковая сверка не подтверждены.'
if not any(b['id']=='margarit' for b in r['books']):r['books'].append({'id':'margarit','label':'Маргарит'})
if not any(c['book']=='margarit' and c['language']=='cu' for c in r['cells']):r['cells'].append({'book':'margarit','language':'cu','status':'in_progress','stages':['done','done','done','pending','partial','partial','pending'],'quality':{'percent':None,'label':'Корпусный пилот: только первая беседа «О непостижимем» из существующей библиотеки; исходные титла и PUA сохранены. Полный сборник, отдельная атрибуция главы, переводчик и сплошная выверка не подтверждены.'},'tags':['Пилот: одна глава'],'evidence':[e],'updated_at':'2026-11-17','edition':'Маргарит · первая беседа о непостижимем'})
r['updated_at']='2026-11-17';Path(a.output).write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n')

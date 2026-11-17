#!/usr/bin/env python3
"""Scoped API/HTML acceptance; no browser or visual testing, no APK publication."""
import argparse,hashlib,json,time,urllib.request,urllib.parse,urllib.error,concurrent.futures
p=argparse.ArgumentParser();p.add_argument('--base',required=True);p.add_argument('--report',required=True);p.add_argument('--internal-quotas',action='store_true');a=p.parse_args()
base=a.base.rstrip('/');checks=[];prefix='/api/v2/study/reader/v1/'
source_ids=['src_4b1c450f72434c3ca14b313e12193a8d','src_940753e0284c461e84296829a3e6f1e6','src_9d0454d1a69b45939d7ebce42dd717ad','src_3d81e2bf35684343ad079ff6ed83ec8b','src_9c3e68a5ac2645478e5d8a2fd0e8c4ba']
def fetch(path,params=None,body=None,method=None,headers=None,pace=True):
 if pace:time.sleep(.15)
 if params:path+='?'+urllib.parse.urlencode(params)
 h={'User-Agent':'cs-app-M202-acceptance/1','Accept':'application/json',**(headers or {})}
 if body is not None:h['Content-Type']='application/json'
 req=urllib.request.Request(base+path,data=None if body is None else json.dumps(body,ensure_ascii=False).encode(),headers=h,method=method)
 try:response=urllib.request.urlopen(req,timeout=90)
 except urllib.error.HTTPError as e:response=e
 data=response.read();info=dict(status=response.status,headers={k.lower():v for k,v in response.headers.items()},bytes=len(data))
 try:info['body']=json.loads(data)
 except (ValueError,UnicodeError):info['text']=data.decode('utf-8','replace')
 return info
def get(action,**params):
 r=fetch(prefix+action,params);assert r['status']==200,(action,r['status'],r.get('body'));return r
caps=get('index/capabilities');c=caps['body'];assert c['contract']=='cs-index/1';c=c['data'];assert c['available'] and c['publicRead'];assert c['indexRevision']=='ix1_d40064e4ed4fe8a67e41351e3ef8a2a3c2eeb3409e1b5dd455e2a68e33bc48a5';assert c['coverage']['placements']==67 and c['coverage']['navigationMaterials']==5
P='cs-pilot-source-r2';D=c['dictionaryVersion'];pilot='cs-mvp-pilot-01';assert {x['id'] for x in c['profiles']}=={P,'cs-pilot-unicode-r2'};checks.append('anonymous public capabilities, exact I/C/D/r2 profiles and five-source scope')
reader=get('capabilities')['body']['data'];assert all(x['versions']['unicode']=='17.0' for x in reader['profileSets'])
catalog=get('catalog',pilotId=pilot)['body']['data'];assert {x['sourceId'] for x in catalog['items']}==set(source_ids);checks.append('catalog reuses all five real source IDs')
query=dict(pilotId=pilot,profileSetId=P,mode='word',q='Христос',limit=50)
r=get('index/search',**query);data=r['body']['data'];assert r['headers']['cache-control']=='no-store' and r['bytes']<=1048576;hits=data['hits'];assert len(hits)==14 and len({h['hitId'] for h in hits})==14
irmos=[h for h in hits if any(x['address']['sourceId']==source_ids[3] for x in h['navigationAliases'])];assert len(irmos)==3
phrase=get('index/search',**dict(query,mode='phrase',q='Христос раждается'))['body']['data']['hits'];assert len(phrase)==1 and len(phrase[0]['navigationAliases'])==1
accepted=get('index/occurrences',pilotId=pilot,profileSetId=P,lexemeId='68399a217310e32be5d7e0fe',dictionaryVersion=D)['body']['data']['hits'];assert len(accepted)==3 and {h['hitId'] for h in accepted}=={h['hitId'] for h in irmos};assert all(h['matchKind']=='lexeme_verified' for h in accepted)
faith=get('index/occurrences',pilotId=pilot,profileSetId=P,lexemeId='68399a217310e32be5d77634',dictionaryVersion=D)['body']['data']['hits'];assert len(faith)==1;checks.append('14 surface Christos hits / 3 accepted shared-irmos hits / 1 accepted faith link, no P01/P04 doubling')
for h in irmos:
 assert h['snippet']['rawWindow'][1]-h['snippet']['rawWindow'][0]<=512
 request=dict(contract='cs-reader/1',address=h['address'],profileSetId=P,window=dict(bodyId=h['bodyId'],rawRange=h['snippet']['rawWindow']))
 packet=fetch(prefix+'read',body=request);assert packet['status']==200;assert set(h['tokenIds'])<={t['tokenId'] for p in packet['body']['data']['projections'] for t in p['tokens']}
checks.append('pinned address/window/token round trip; unchanged accepted hit IDs')
for sid,field,state in [(source_ids[2],'translator','unknown'),(source_ids[3],'originalPartOf','unknown')]:
 passport=get('passport/'+sid)['body']['data'];assert passport['fields'][field]['state']==state
checks.append('Margarit translator and irmos native canon remain unknown')
for extra,status in [({'profileSetId':'cs-pilot-letterfold-r2'},422),({'profileSetId':'cs-pilot-source-r1'},422),({'cursor':'!!!','indexRevision':c['indexRevision']},400),({'indexRevision':'ix1_'+'f'*64},409)]:
 bad=fetch(prefix+'index/search',dict(query,**extra));assert bad['status']==status,(extra,bad['status'])
bad=fetch(prefix+'index/occurrences',dict(pilotId=pilot,profileSetId=P,lexemeId='68399a217310e32be5d7e0fe',dictionaryVersion='0'*64));assert bad['status']==409
checks.append('explicit 400/409/422 for malformed cursors, wrong I/D and unsupported profiles')
for item in catalog['items']:
 path=urllib.parse.urlsplit(item['canonicalUrl']).path
 html=fetch(path);assert html['status']==200,(path,html['status']);assert 'noindex' in html['headers'].get('x-robots-tag','');assert '<h1>' in html.get('text','')
chapter=fetch('/sources/id/'+source_ids[2],{'view':'normalized'});assert chapter['status']==200
experiments=fetch('/opyty/cs-reader');assert experiments['status']==200 and all(sid in experiments.get('text','') for sid in source_ids)
checks.append('all five existing portal source URLs and normalized Margarit return noindex HTML; pilot remains in experiments')
legacy=fetch(prefix+'resolve',body=dict(contract='cs-reader/1',legacyTarget=dict(kind='chant',id='132')));assert legacy['status']==200 and legacy['body']['data']['resolvedAddress']['sourceId']==source_ids[3]
for id in ['132','77050']:assert fetch('/api/v2/chants/'+id)['status']==200
checks.append('legacy linked-irmos/troparion addresses stay available')
for schema in [1,2]:
 dictionary=fetch('/api/v2/cs/search',dict(schema=schema,q='воздушный',direction='cu-ru'));assert dictionary['status']==200 and dictionary['body'].get('version')==D,(schema,dictionary['status'],dictionary.get('body'))
checks.append('dictionary schema1/schema2 remain compatible with pinned D')
quotas=None
if a.internal_quotas:
 ip={'x-real-ip':'203.0.113.71'}
 for _ in range(35):assert fetch(prefix+'index/search',method='OPTIONS',headers=ip,pace=False)['status']==204
 responses=[fetch(prefix+'index/search',dict(pilotId=pilot,profileSetId=P,mode='word',q=''),headers=dict(ip,Origin='https://www.typikon.info'),pace=False) for _ in range(31)]
 assert [r['status'] for r in responses]==[400]*30+[429];assert int(responses[-1]['headers']['retry-after'])>0
 quotas={'optionsUnmetered':35,'searchSubset':30,'nextStatus':429,'siteOriginDoesNotBypass':True}
 checks.append('shared-IP search quota, Retry-After, OPTIONS exemption, no Origin privilege')
report={'format':'m2-02-u17-scoped-smoke/1','base':base,'passed':True,'indexRevision':c['indexRevision'],'corpusRelease':c['corpusRelease'],'dictionaryVersion':D,'profiles':[P,'cs-pilot-unicode-r2'],'checks':checks,'acceptedChristosHitIds':[h['hitId'] for h in accepted],'acceptedFaithHitIds':[h['hitId'] for h in faith],'sourceIds':source_ids,'applicationQuotaProbe':quotas,'visualTestingPerformed':False,'apkPublished':False}
open(a.report,'w').write(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'passed':True,'checks':len(checks),'base':base,'indexRevision':c['indexRevision']}))

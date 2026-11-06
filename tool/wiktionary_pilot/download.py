"""Download a resumable, identifiable Kaikki snapshot without expanding it on disk."""
import argparse, hashlib, json, os, time, urllib.request
from pathlib import Path
UA='TypikonCSDictionaryPilot/0.1 (https://www.typikon.info/contact)'
def download(url, destination):
    path=Path(destination);path.parent.mkdir(parents=True,exist_ok=True)
    partial=path.with_suffix(path.suffix+'.part')
    metadata=path.with_suffix(path.suffix+'.http.json')
    with urllib.request.urlopen(urllib.request.Request(url,method='HEAD',headers={'User-Agent':UA}),timeout=60) as response:
        remote={k:response.headers.get(k) for k in ['Content-Length','Last-Modified','ETag']}
    if path.exists() and metadata.exists():
        previous=json.loads(metadata.read_text())
        if previous.get('remote')==remote and previous.get('bytes')==path.stat().st_size:
            print(json.dumps({'cached':str(path),'bytes':path.stat().st_size}),flush=True);return
        raise RuntimeError('Completed destination belongs to a different snapshot: '+str(path))
    prior=metadata.with_suffix('.partial.json')
    if partial.exists() and prior.exists() and json.loads(prior.read_text())!=remote:
        raise RuntimeError('Remote snapshot changed; preserve old partial and choose another destination')
    prior.write_text(json.dumps(remote))
    started=time.monotonic()
    for attempt in range(6):
        offset=partial.stat().st_size if partial.exists() else 0
        headers={'User-Agent':UA}
        if offset: headers['Range']=f'bytes={offset}-'
        if remote['Last-Modified']:headers['If-Unmodified-Since']=remote['Last-Modified']
        try:
            with urllib.request.urlopen(urllib.request.Request(url,headers=headers),timeout=120) as response:
                if offset and response.status!=206:raise RuntimeError('Server did not honor resume')
                with partial.open('ab' if offset else 'wb') as output:
                    last=time.monotonic()
                    while chunk:=response.read(1024*1024):
                        output.write(chunk)
                        if time.monotonic()-last>25:
                            print(json.dumps({'file':path.name,'downloadedMiB':round(output.tell()/2**20),'seconds':round(time.monotonic()-started)}),flush=True);last=time.monotonic()
            break
        except (OSError,TimeoutError) as error:
            if attempt==5:raise
            print(type(error).__name__+'; resuming',flush=True);time.sleep(min(2**attempt,20))
    expected=int(remote['Content-Length']) if remote['Content-Length'] else None
    if expected is not None and partial.stat().st_size!=expected:raise RuntimeError('Incomplete download')
    digest=hashlib.sha256()
    with partial.open('rb') as file:
        while chunk:=file.read(8*1024*1024):digest.update(chunk)
    partial.rename(path)
    record={'url':url,'retrievedAtUtc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'remote':remote,'bytes':path.stat().st_size,'sha256':digest.hexdigest(),'compression':'gzip' if url.endswith('.gz') else 'none','rawIndex':'download-index.html'}
    metadata.write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n');prior.unlink(missing_ok=True)
    print(json.dumps(record),flush=True)
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('url');parser.add_argument('destination');args=parser.parse_args();download(args.url,args.destination)

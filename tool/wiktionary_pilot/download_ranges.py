"""Bounded (max four requests) resumable range download of a large immutable snapshot."""
import argparse, concurrent.futures, hashlib, json, os, threading, time, urllib.request
from pathlib import Path
from download import UA

def download_ranges(url,destination,workers=4):
    path=Path(destination);path.parent.mkdir(parents=True,exist_ok=True)
    partial=Path(str(path)+'.part');state_path=Path(str(path)+'.ranges.json');metadata=Path(str(path)+'.http.json')
    with urllib.request.urlopen(urllib.request.Request(url,method='HEAD',headers={'User-Agent':UA}),timeout=60) as r:
        remote={k:r.headers.get(k) for k in ['Content-Length','Last-Modified','ETag']}
    size=int(remote['Content-Length']);workers=max(1,min(4,workers));lock=threading.Lock()
    if path.exists():
        old=json.loads(metadata.read_text())
        if old['remote']!=remote or path.stat().st_size!=size:raise RuntimeError('Different completed snapshot')
        print('Already downloaded',path,flush=True);return
    if state_path.exists():
        state=json.loads(state_path.read_text())
        if state['remote']!=remote or not partial.exists() or partial.stat().st_size!=size:raise RuntimeError('Partial snapshot mismatch')
    else:
        if partial.exists():raise RuntimeError('Unidentified partial file')
        state={'remote':remote,'ranges':[]}
        for i in range(workers):
            start=size*i//workers;end=size*(i+1)//workers-1
            state['ranges'].append({'start':start,'end':end,'next':start})
        with partial.open('wb') as f:f.truncate(size)
    def persist():
        tmp=Path(str(state_path)+'.tmp');tmp.write_text(json.dumps(state));tmp.replace(state_path)
    persist();fd=os.open(partial,os.O_RDWR);started=time.monotonic()
    def worker(segment):
      for attempt in range(8):
        start=segment['next'];end=segment['end']
        if start>end:return
        headers={'User-Agent':UA,'Range':f'bytes={start}-{end}','If-Unmodified-Since':remote['Last-Modified']}
        try:
          with urllib.request.urlopen(urllib.request.Request(url,headers=headers),timeout=120) as response:
            if response.status!=206 or response.headers.get('Content-Range')!=f'bytes {start}-{end}/{size}':raise RuntimeError('Invalid range response')
            checkpoint=start
            while segment['next']<=end:
              chunk=response.read(min(1024*1024,end-segment['next']+1))
              if not chunk:raise OSError('Truncated range')
              offset=segment['next'];written=0
              while written<len(chunk):written+=os.pwrite(fd,chunk[written:],offset+written)
              with lock:
                segment['next']+=len(chunk)
                if segment['next']-checkpoint>=4*1024*1024:persist();checkpoint=segment['next']
          with lock:persist()
          return
        except (OSError,TimeoutError) as e:
          with lock:persist()
          if attempt==7:raise
          print(type(e).__name__+'; retrying range',segment['start'],flush=True);time.sleep(min(2**attempt,20))
      raise RuntimeError('Range retries exhausted')
    try:
      with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        futures=[executor.submit(worker,r) for r in state['ranges']]
        while not all(f.done() for f in futures):
          concurrent.futures.wait(futures,timeout=25)
          with lock:done=sum(r['next']-r['start'] for r in state['ranges'])
          print(json.dumps({'downloadedMiB':round(done/2**20),'totalMiB':round(size/2**20),'seconds':round(time.monotonic()-started)}),flush=True)
        for future in futures:future.result()
      os.fsync(fd)
    finally:os.close(fd)
    sha=hashlib.sha256()
    with partial.open('rb') as f:
      while chunk:=f.read(8*1024*1024):sha.update(chunk)
    partial.replace(path)
    result={'url':url,'retrievedAtUtc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'remote':remote,'bytes':size,'sha256':sha.hexdigest(),'compression':'gzip','rangeWorkers':workers}
    metadata.write_text(json.dumps(result,indent=2)+'\n');state_path.unlink()
    print(json.dumps(result),flush=True)
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('url');parser.add_argument('destination');args=parser.parse_args();download_ranges(args.url,args.destination)

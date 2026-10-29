"""Download an official large SDK artifact with resumable range parts."""
import argparse
import concurrent.futures
from pathlib import Path
import time
import httpx

parser=argparse.ArgumentParser();parser.add_argument('url');parser.add_argument('output');args=parser.parse_args()
output=Path(args.output);parts=output.with_name(output.name+'.parts');parts.mkdir(parents=True,exist_ok=True)
with httpx.Client(follow_redirects=True,timeout=30) as client:
    response=client.head(args.url,headers={'Accept-Encoding':'identity'});response.raise_for_status();total=int(response.headers.get('x-identity-content-length',response.headers.get('x-goog-stored-content-length',response.headers['content-length'])))
chunk=4*1024*1024

def fetch(index):
    start=index*chunk;end=min(total-1,start+chunk-1);part=parts/str(index)
    if part.exists() and part.stat().st_size==end-start+1:return index
    for attempt in range(5):
        try:
            with httpx.Client(follow_redirects=True,timeout=180) as client:
                r=client.get(args.url,headers={'Range':f'bytes={start}-{end}','Accept-Encoding':'identity'})
                if r.status_code!=206 or len(r.content)!=end-start+1:raise RuntimeError('Invalid range response')
                part.write_bytes(r.content);return index
        except Exception:
            if attempt==4:raise
            time.sleep(1)

count=(total+chunk-1)//chunk
with concurrent.futures.ThreadPoolExecutor(max_workers=12) as executor:
    for n,_ in enumerate(executor.map(fetch,range(count)),1):
        if n%5==0 or n==count:print(f'Completed {n}/{count} parts',flush=True)
with output.open('wb') as destination:
    for i in range(count):destination.write((parts/str(i)).read_bytes())
print(f'Artifact ready: {output} ({total} bytes)')

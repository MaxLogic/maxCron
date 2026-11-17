"""Executable footer oracle. Run python -I; see tests/data/footer-reference.md.
Calendar arithmetic classifies the supported domain and named divergence variants.
Expected offsets always come from pinned tzcode through both entry paths.
Linux glibc supplies a second reference via both POSIX and identical TZif bytes.
"""
import argparse, calendar, hashlib, io, json, os, platform, random, struct, sys, time, zlib
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

SEED=20261117
REVIEW_SEED=2718281828
EPOCH=datetime(1899,12,30)
DAY_MS=86400000
MS=timedelta(milliseconds=1)

def clock(n):
    sign='-' if n<0 else ''
    n=abs(n)
    return f'{sign}{n//3600}:{n//60%60:02}:{n%60:02}'

def tzif(footer,std):
    # A real sentinel before the supported horizon makes glibc apply the footer
    # after its historical cutoff. With zero transitions it can ignore DST.
    header=b'TZif3'+bytes(15)+struct.pack('>6I',0,0,0,1,1,4)
    block=struct.pack('>iBB',std,0,0)+b'STD\0'
    return header+struct.pack('>i',-2147483648)+b'\0'+block+header+struct.pack('>q',-11676096000)+b'\0'+block+b'\n'+footer.encode('ascii')+b'\n'

def cases():
    # Preserve all previous Footer00..31 rule inputs.
    rows=[(0,3600,'J1/-1','J365/25'),(0,3600,'0/-167:59:59','365/167:59:59'),
        (0,3600,'M1.1.0/-26','M12.5.0/50'),(-18000,-14400,'0/0','J365/25'),
        (-10800,-14400,'0/0','J365/23'),(0,-3600,'J1/-1','J365/23'),
        (36000,39600,'M10.1.0/2','M4.1.0/3'),(0,-3600,'M3.5.0/-2','M10.5.0/25'),
        (19800,21600,'J60/-25:30:01','J300/49:10:03'),(-10800,-7200,'59/-2','300/26'),
        (86399,82799,'J1/0','J365/24'),(-86399,-82799,'0/0','365/24'),
        (0,3600,'J365/25','J1/-1'),(0,3600,'J1/0','J1/1'),(0,-3600,'J1/0','J1/-1'),
        (0,3600,'M2.5.0/167:59:59','M3.1.0/-167:59:59'),
        (0,3600,'J60/0','J61/0'),(0,3600,'59/0','60/0')]
    rng=random.Random(SEED)
    dates=['J1','J60','J365','0','59','365','M1.1.0','M3.5.0','M10.5.0','M12.5.6']
    times=['-167:59:59','-25','-1','0','2','25','167:59:59']
    for _ in range(14):
        std=rng.choice([-43200,-12600,0,20700,50400])
        dst=std+rng.choice([-7200,-3600,1800,3600,7200])
        rows.append((std,dst,rng.choice(dates)+'/'+rng.choice(times),rng.choice(dates)+'/'+rng.choice(times)))
    # The reviewer's complete 112-case exploration with the same seed/bounds.
    rows += [(0,3600,'J1/-1','J365/25'),(-10800,-14400,'0/0','J365/23'),
        (-18000,-14400,'0/0','J365/25'),(0,3600,'M3.2.0/2','M11.1.0/2'),
        (39600,36000,'M10.1.0/2','M4.1.0/3'),(0,-3600,'J1/0','J1/-1'),
        (0,3600,'J1/0','J1/1'),(0,3600,'J60/0','J60/0'),
        (0,3600,'M2.5.0/167:59:59','M3.1.0/-167:59:59'),
        (0,3600,'M1.1.0/-26','M12.5.0/50'),
        (0,3600,'M12.5.0/167:59:59','M1.1.0/-167:59:59'),
        (0,3600,'J365/167:59:59','J1/-167:59:59')]
    rng=random.Random(REVIEW_SEED)
    dates=['J1','J60','J100','J200','J365','0','59','60','100','364','365',
           'M1.1.0','M2.5.0','M3.1.0','M3.5.6','M10.5.0','M12.5.6']
    times=['-167:59:59','-97','-24:01','-1','0','0:00:01','2','23','24','25:01','167:59:59']
    for _ in range(100):
        std=rng.choice([-86399,-43200,-20700,0,19800,50400,86399])
        dst=std+rng.choice([-7200,-3600,0,1800,3600,7200])
        if abs(dst)>=86400: dst=std
        rows.append((std,dst,rng.choice(dates)+'/'+rng.choice(times),rng.choice(dates)+'/'+rng.choice(times)))
    result=[]
    for i,(std,dst,start,end) in enumerate(rows):
        result.append(dict(name=f'Synthetic/Footer{i:03}' if i>=32 else f'Synthetic/Footer{i:02}',
            footer=f'STD{clock(-std)}DST{clock(-dst)},{start},{end}',std=std,dst=dst,start=start,end=end))
    # Exact spellings of all eight horizon cases, including the minimal case.
    for label,footer,std,dst in [
        ('cross','STD0DST-1,J1/-1,J365/25',0,3600),
        ('erased','STD0DST-1,J365/25,J1/-1',0,3600),
        ('all-positive','EST5EDT,0/0,J365/25',-18000,-14400),
        ('all-negative','XXX3EDT4,0/0,J365/23',-10800,-14400),
        ('southern','STD-10DST-11,M10.1.0/2,M4.1.0/3',36000,39600),
        ('negative','STD0DST1,M3.5.0/-2,M10.5.0/25',0,-3600),
        ('julian','STD0DST-1,J60/0,J300/0',0,3600),
        ('ordinal','STD0DST-1,59/0,300/26',0,3600)]:
        start,end=footer.split(',')[1:]
        result.append(dict(name='Synthetic/Horizon-'+label,footer=footer,std=std,dst=dst,start=start,end=end))
    return result

# Decision 7: local-year domain; pinned tzcode is the executable oracle.
import collections, re, subprocess, tempfile

SWEEP_SEED=31415926
CYCLE_SECONDS=146097*86400
UNIX_MS=2209161600000

def jan1(year):
    cycles,rem=divmod(year-2000,400)
    return ((datetime(2000+rem,1,1)-EPOCH).days+cycles*146097)*DAY_MS

def rule_seconds(year,rule,python_day=False):
    date,_,text=rule.partition('/')
    value=text or '2'
    sign=-1 if value.startswith('-') else 1
    seconds=sign*sum(int(p)*w for p,w in zip(value.lstrip('+-').split(':'),(3600,60,1)))
    mapped=2000+(year-2000)%400
    if date.startswith('M'):
        month,week,weekday=map(int,date[1:].split('.'))
        first=datetime(mapped,month,1)
        day=1+(weekday-(first.weekday()+1)%7)%7+(week-1)*7
        day=min(day,day-7) if day>calendar.monthrange(mapped,month)[1] else day
        index=(datetime(mapped,month,day)-datetime(mapped,1,1)).days
    elif date.startswith('J'):
        n=int(date[1:]);index=n-1
        if calendar.isleap(mapped) and (n>=59 if python_day else n>=60):index+=1
    else:
        index=int(date)-(1 if python_day else 0)
    return index*86400+seconds

def domain(case):
    if case.get('start') is None:return 'fixed'
    regular=True;all_year=True;failure=None
    for year in range(2000,2400):
        s=rule_seconds(year,case['start']);e=rule_seconds(year,case['end'])
        length=(366 if calendar.isleap(year) else 365)*86400
        start=s-case['std'];end=e-case['dst']
        if start<end:
            part=end-start
            across=length+rule_seconds(year+1,case['start'])-case['std']-end
        else:
            part=start-end
            across=length+rule_seconds(year+1,case['end'])-case['dst']-start
        okay=(2*86400<=s<=length-2*86400 and 2*86400<=e<=length-2*86400
              and part>=28*86400 and across>=28*86400)
        if not okay and failure is None:failure=dict(year=year,start_local=s,end_local=e,year_seconds=length,part_seconds=part,across_seconds=across)
        regular=regular and okay
        all_year=all_year and s==0 and e==length+case['dst']-case['std']
    case['first_invalid_year']=failure
    return 'all-year' if all_year else 'regular' if regular else 'rejected'

def expanded_cases():
    rows=cases()
    named=[('Horizon-forward-spill','STD0DST-1,J300/0,J365/48',0,3600),
        ('Horizon-spill','STD3:30:00DST5:30:00,0/-25,0/-1',-12600,-19800),
        ('Horizon-all-east','<+12>-12<+13>,0/0,J365/25',43200,46800),
        ('Horizon-equal','STD0DST-1,J1/0,J1/1',0,3600),
        ('Horizon-mixed','STD0DST-1,M3.2.0/0,J70/0',0,3600),
        ('AllYear','EST5EDT,0/0,J365/25',-18000,-14400),
        ('Real-Nuuk','<-02>2<-01>,M3.5.0/-1,M10.5.0/0',-7200,-3600),
        ('Real-Troll','<+00>0<+02>-2,M3.5.0/1,M10.5.0/3',0,7200),
        ('Real-LordHowe','<+1030>-10:30<+11>-11,M10.1.0/2,M4.1.0/2',37800,39600),
        ('OrdinaryOrdinal','STD0DST-1,59/0,300/0',0,3600)]
    for name,footer,std,dst in named:
        start,end=footer.split(',')[1:]
        rows.append(dict(name='Synthetic/'+name,footer=footer,std=std,dst=dst,start=start,end=end))
    # Decision 7: seconds on both sides of each exact inclusive limit.
    # DST and standard lengths are UTC elapsed durations; year bounds are local.
    for label,start,end in [
        ('DstBelow','J60/0','J88/0:59:59'),
        ('DstAt','J60/0','J88/1'),
        ('DstAbove','J60/0','J88/1:00:01'),
        ('StdBelow','J88/-1:00:01','J60/0'),
        ('StdAt','J88/-1','J60/0'),
        ('StdAbove','J88/-0:59:59','J60/0'),
        ('YearStartBelow','J2/23:59:59','J200/0'),
        ('YearStartAt','J3/0','J200/0'),
        ('YearStartAbove','J3/0:00:01','J200/0'),
        ('YearEndBelow','J200/0','J364/0:00:01'),
        ('YearEndAt','J200/0','J364/0'),
        ('YearEndAbove','J200/0','J363/23:59:59'),
        ('CrossStdBelow','J26/22:59:59','J364/0'),
        ('CrossStdAt','J26/23','J364/0'),
        ('CrossStdAbove','J26/23:00:01','J364/0'),
        ('CrossDstBelow','J363/23:00:01','J26/24'),
        ('CrossDstAt','J363/23','J26/24'),
        ('CrossDstAbove','J363/22:59:59','J26/24')]:
        rows.append(dict(name='Synthetic/Boundary-'+label,footer=f'STD0DST-1,{start},{end}',
                         std=0,dst=3600,start=start,end=end,boundary=True))
    rows.append(dict(name='Synthetic/FixedSeconds',footer='STD-5:45:13',std=20713,dst=20713,start=None,end=None))
    # Section 6.4.4 explicitly keeps the two 26-hour cases model-only (OUT).
    for sign in (-1,1):
        rows.append(dict(name='Synthetic/Fixed26'+('East' if sign>0 else 'West'),
                         footer='STD'+clock(-sign*93600),std=sign*93600,dst=sign*93600,
                         start=None,end=None,model_only=True))
    rng=random.Random(SWEEP_SEED)
    edges=[-604799,-349200,-90000,-86460,-3600,0,1,7200,82800,86400,90000,90060,172800,604799]
    def date_rule():
        kind=rng.choice('MJN')
        if kind=='M':return f'M{rng.randint(1,12)}.{rng.randint(1,5)}.{rng.randint(0,6)}'
        if kind=='J':return 'J'+str(rng.choice([1,59,60,365,rng.randint(1,365)]))
        return str(rng.choice([0,58,59,60,364,365,rng.randint(0,365)]))
    for i in range(300):
        std=rng.choice([-86400,-43200,-1,0,1,19800,86400,rng.randint(-86400,86400)])
        dst=max(-86400,min(86400,std+rng.choice(list(range(-7200,7201,1800))+[-1,1])))
        start=date_rule()+'/'+clock(rng.choice(edges) if rng.random()<0.4 else rng.randint(-604799,604799))
        end=date_rule()+'/'+clock(rng.choice(edges) if rng.random()<0.4 else rng.randint(-604799,604799))
        if i%31==0:end=start
        rows.append(dict(name=f'Synthetic/Sweep{i:03}',footer=f'STD{clock(-std)}DST{clock(-dst)},{start},{end}',
                         std=std,dst=dst,start=start,end=end,sweep=True))
    return rows

def query_tzcode(probe,tz,points):
    command=[str(probe),tz]
    begin=time.monotonic()
    p=subprocess.run(command,input=''.join(str((v-UNIX_MS)//1000)+'\n' for v in points),
                     text=True,capture_output=True)
    assert p.returncode==0,dict(command=command,exit=p.returncode,stderr=p.stderr)
    values=[int(line.split()[1])*1000 for line in p.stdout.splitlines()]
    assert len(values)==len(points)
    return values,dict(command=command,native_exit=p.returncode,probes=len(points),duration_seconds=time.monotonic()-begin,
                       first_isdst=int(p.stdout.splitlines()[0].split()[2]) if points else None,
                       stdout_sha256=hashlib.sha256(p.stdout.encode()).hexdigest())

def tzif(footer,std,offset=None,daylight=False):
    # The last transition must agree with the direct POSIX reference exactly.
    offset=std if offset is None else offset
    names=re.findall(r'(?:^|(?<=[0-9]))(<[^>]+>|[A-Za-z]{3,})',footer.split(',')[0])
    abbreviation=(names[min(int(daylight),len(names)-1)].strip('<>') if names else ('DST' if daylight else 'STD')).encode()+b'\0'
    header=b'TZif3'+bytes(15)+struct.pack('>6I',0,0,0,1,1,len(abbreviation))
    block=struct.pack('>iBB',offset,int(daylight),0)+abbreviation
    return header+struct.pack('>i',-2147483648)+b'\0'+block+header+struct.pack('>q',-11676096000)+b'\0'+block+b'\n'+footer.encode()+b'\n'

def points_for(case,first,last):
    points={jan1(first),jan1(last+1)-1}
    for y in range(first,last+1):
        base=jan1(y)
        points.add(base);points.add(base+181*DAY_MS)
        if case.get('start') is not None:
            for nominal in (y-1,y,y+1):
                for rule,offset in [(case['start'],case['std']),(case['end'],case['dst'])]:
                    for py in (False,True):
                        t=jan1(nominal)+1000*(rule_seconds(nominal,rule,py)-offset)
                        points.update((t-1,t,t+1))
    lo,hi=jan1(first),jan1(last+1)
    return sorted(p for p in points if lo<=p<hi)

def variant(case,utc_ms,python_day=False):
    year=(EPOCH+timedelta(milliseconds=utc_ms)).year
    s=jan1(year)+1000*(rule_seconds(year,case['start'],python_day)-case['std'])
    e=jan1(year)+1000*(rule_seconds(year,case['end'],python_day)-case['dst'])
    daylight=s<=utc_ms<e if s<e else not(e<=utc_ms<s)
    return 1000*(case['dst'] if daylight else case['std'])

def frame_new_year(case,utc_ms):
    """Decision 6's two bounds, with the actual governing local-year event."""
    if case.get('start') is None:return None
    # An all-year footer has no governing offset-changing transition.
    if (case.get('domain') or domain(case))!='regular':return None
    year=(EPOCH+timedelta(milliseconds=utc_ms)).year
    bound=1000*max(abs(case['std']),abs(case['dst']))
    distance=min(abs(utc_ms-jan1(year)),abs(utc_ms-jan1(year+1)))
    if distance>bound:return None
    events=[]
    for nominal in (year-1,year,year+1):
        for rule,offset in ((case['start'],case['std']),(case['end'],case['dst'])):
            at=jan1(nominal)+1000*(rule_seconds(nominal,rule)-offset)
            if at<=utc_ms:events.append((at,nominal))
    at,nominal=max(events)
    if nominal==year:return None
    return dict(utc_year=year,governing_local_year=nominal,governing_utc_ms=at,
                new_year_distance_ms=distance,largest_absolute_offset_ms=bound)

def python_divergence(case,utc_ms,expected,actual):
    if case.get('start') is None or actual==expected:return None
    frame=variant(case,utc_ms,False)
    mapped=variant(case,utc_ms,True)
    # A day-mapping class must actually change the result at this instant.
    # Otherwise the same-year predicate alone could hide a different defect.
    if actual==mapped and mapped!=frame:
        if frame==expected:return 'P-DAY'
        if frame_new_year(case,utc_ms):return 'P-DAY+FRAME-NY'
    if actual==frame and frame_new_year(case,utc_ms):return 'FRAME-NY'
    return None

def glibc_divergence(case,utc_ms,expected,actual):
    if case.get('start') is None or actual==expected:return None
    if actual!=variant(case,utc_ms):return None
    if (case.get('domain') or domain(case))=='all-year':return 'FRAME'
    return 'FRAME-NY' if frame_new_year(case,utc_ms) else None

def generate(output,first,last,probe,quick=False):
    assert platform.libc_ver()[0]=='glibc','Qualification requires native Linux/glibc'
    output.mkdir(parents=True,exist_ok=True)
    rows=expanded_cases();records=[];table=[];properties=[]
    by_reference=collections.defaultdict(collections.Counter);examples=collections.defaultdict(list)
    class DivergenceLog:
        def __init__(self):
            self.count=0;self.compressor=zlib.compressobj(9)
            self.file=(output/'footer-divergence.jsonl.z').open('wb');self.closed=False
        def append(self,record):
            cls=record['named_class'];ref=record['reference']
            by_reference[cls][ref]+=1
            if len(examples[cls+'|'+ref])<3:examples[cls+'|'+ref].append(record)
            self.file.write(self.compressor.compress((json.dumps(record,separators=(',',':'))+'\n').encode()))
            self.count+=1
        def __len__(self):return self.count
        def finish(self):
            if not self.closed:
                self.file.write(self.compressor.flush());self.file.close();self.closed=True
    divergences=DivergenceLog();unexplained=[];counts=collections.Counter()
    meta=dict(seeds=[SEED,REVIEW_SEED,SWEEP_SEED],cycle=[2000,2399],python=sys.version,libc=platform.libc_ver(),
              tzcode_probe=str(probe),probe_sha256=hashlib.sha256(probe.read_bytes()).hexdigest(),cases=records,
              accepted=0,rejected=0,probes=0,unexplained=0,allowed_divergences=0,
              authority='tzcode2025b direct POSIX and identical TZif must agree; decision 7; corroborators informational')
    def flush():
        meta['unexplained']=len(unexplained);meta['allowed_divergences']=len(divergences);meta['classes']=dict(counts)
        meta['classes_by_reference']={k:dict(v) for k,v in by_reference.items()};meta['class_examples']=dict(examples)
        (output/'footer-reference.json').write_text(json.dumps(meta,indent=2)+'\n')
        (output/'footer-unexplained.json').write_text(json.dumps(unexplained,indent=2)+'\n')
        divergences.finish()
    for case in rows:
        label=domain(case);case['domain']=label
        accepted=label!='rejected'
        meta['accepted' if accepted else 'rejected']+=1
        name=case['name'];path=output/'tzif'/name;path.parent.mkdir(parents=True,exist_ok=True)
        if accepted and not case.get('model_only'):
            sentinel,receipt=query_tzcode(probe,case['footer'],[jan1(1600)])
            offset=sentinel[0]//1000
            assert offset in (case['std'],case['dst'])
            data=tzif(case['footer'],case['std'],offset,receipt['first_isdst']!=0)
            case['sentinel']=dict(offset_seconds=offset,daylight=receipt['first_isdst'],reference=receipt)
        else:data=tzif(case['footer'],case['std'])
        path.write_bytes(data)
        properties.append((name,accepted))
        records.append(dict(**case,sha256=hashlib.sha256(data).hexdigest(),ranges=[]))
        if not accepted:continue
        if case.get('model_only'):
            divergences.append(dict(name=name,reference='tzcode/Python',expected=None,actual=None,
                                    named_class='OUT',reason='26-hour offset model-only case per section 6.4.4'))
            counts['OUT']+=1
            continue
        zone=ZoneInfo.from_file(io.BytesIO(data))
        ranges=[(first,last)] if not case.get('sweep') or quick else [(1800,2300),(9600,9999)]
        for low,high in ranges:
            points=points_for(case,low,high)
            expected,direct=query_tzcode(probe,case['footer'],points)
            file,file_receipt=query_tzcode(probe,':'+str(path.resolve()),points)
            refs={}
            for ref,tz in [('glibc-posix',case['footer']),('glibc-tzif',':'+str(path.resolve()))]:
                os.environ['TZ']=tz;time.tzset()
                refs[ref]=[time.localtime((p-UNIX_MS)//1000).tm_gmtoff*1000 for p in points]
            changes=[];previous=None
            for i,(utc,want) in enumerate(zip(points,expected)):
                meta['probes']+=1
                if want!=file[i]:unexplained.append(dict(name=name,footer=case['footer'],utc_ms=utc,reference='tzcode-tzif',expected=want,actual=file[i]))
                if previous is not None and want!=previous:
                    # Probe sets contain t-1,t,t+1 for every possible rule event.
                    assert points[i]-points[i-1]<=1,(name,utc,'missing exact transition probe')
                    changes.append((utc,want))
                previous=want
                try:
                    instant=EPOCH+timedelta(milliseconds=utc)
                    got=(zone.fromutc(instant.replace(tzinfo=zone)).replace(tzinfo=None)-instant)//MS
                    if got!=want:
                        cls=python_divergence(case,utc,want,got) or 'OTHER'
                        rec=dict(name=name,footer=case['footer'],utc_ms=utc,reference='Python',expected=want,actual=got,named_class=cls)
                        if cls and 'FRAME-NY' in cls:rec['frame_new_year']=frame_new_year(case,utc)
                        divergences.append(rec)
                        if cls:counts[cls]+=1
                except (OverflowError,ValueError):
                    rec=dict(name=name,utc_ms=utc,reference='Python',expected=want,actual=None,named_class='OUT')
                    divergences.append(rec);counts['OUT']+=1
                for ref,values in refs.items():
                    got=values[i]
                    if got==want:continue
                    cls=glibc_divergence(case,utc,want,got)
                    if cls is None and utc<UNIX_MS:
                        os.environ['TZ']=case['footer'] if ref=='glibc-posix' else ':'+str(path.resolve());time.tzset()
                        projected=time.localtime((utc-UNIX_MS)//1000+CYCLE_SECONDS).tm_gmtoff*1000
                        if projected==want:cls='G-HIST'
                    cls=cls or 'OTHER'
                    rec=dict(name=name,footer=case['footer'],utc_ms=utc,reference=ref,expected=want,actual=got,named_class=cls)
                    if cls and 'FRAME-NY' in cls:rec['frame_new_year']=frame_new_year(case,utc)
                    divergences.append(rec)
                    if cls:counts[cls]+=1
                if unexplained:
                    flush()
                    print(json.dumps(dict(state='REFERENCE_STOP',first=unexplained[0],output=str(output))),flush=True)
                    raise SystemExit(42)
            table.append((name,low,high,expected[0],changes))
            records[-1]['ranges'].append(dict(first=low,last=high,probes=len(points),changes=len(changes),direct=direct,tzif=file_receipt))
        print(json.dumps(dict(case=name,domain=label,probes=meta['probes'],divergences=len(divergences))),flush=True)
    packed=bytearray(b'FTR3'+struct.pack('<I',len(table)))
    for name,low,high,initial,changes in table:
        n=name.encode();packed.extend(struct.pack('<I',len(n))+n+struct.pack('<iiiI',low,high,initial,len(changes)))
        for utc,offset in changes:packed.extend(struct.pack('<qi',utc,offset))
    payload=zlib.compress(packed,9);(output/'footer-model.bin.z').write_bytes(payload)
    meta['table_sha256']=hashlib.sha256(payload).hexdigest();meta['records']=len(table)
    packed=bytearray(b'FDV1'+struct.pack('<I',len(properties)))
    for name,accepted in properties:
        n=name.encode();packed.extend(struct.pack('<I',len(n))+n+struct.pack('<B',accepted))
    (output/'footer-domain.bin.z').write_bytes(zlib.compress(packed,9))
    (output/'footer-cases.txt').write_text(''.join('F|'+c['name']+'|'+c['footer']+'\n' for c in rows))
    flush();print(json.dumps({k:v for k,v in meta.items() if k!='cases'}),flush=True)

if __name__=='__main__':
    assert sys.flags.isolated,'Run with python -I'
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--tzcode-probe',type=Path,required=True)
    parser.add_argument('--first-year',type=int,default=1800)
    parser.add_argument('--last-year',type=int,default=9999)
    parser.add_argument('--quick',action='store_true')
    args=parser.parse_args()
    generate(args.output,args.first_year,args.last_year,args.tzcode_probe,args.quick)

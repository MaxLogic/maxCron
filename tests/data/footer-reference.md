# POSIX footer executable references

Run the generator with isolated native Linux Python, glibc and the retained
pinned tzcode2025b probe:

```text
python3 -I tests/data/generate-footer-reference.py --output <owned-native-root> --tzcode-probe <pinned-native-probe>
```

Coordinator decision 7 defines the supported domain and reference policy.
The generator preserves the original 152 inputs, adds RFC, real-world signed,
Troll, Lord Howe, fixed-second-offset and historical rejection cases, and adds
300 deterministic sweep rules (seed 31415926). M/J/zero-based ordinal dates,
both orientations, signed/extended times, negative DST, minute/second offsets
and equal/inverting rules are represented. Seeds 20261117 and 2718281828 retain
the historical inputs. The two 26-hour fixed-offset cases are domain-only OUT
cases as specified in section 6.4.4; they have no fabricated reference offsets.

Domain classification uses datetime/calendar independently of the Pascal
implementation. Every year 2000..2399 must place both rule-local transitions
at least 2 local days from either boundary of its nominal calendar year. Both
DST and standard parts must last at least 28 elapsed UTC days, including the
part crossing into the following year. Exact limits are inclusive. Eighteen
additional named boundary fixtures cover both sides and equality at these
limits, in northern and southern orientations. Footer23 and Footer051 (REF-04)
are explicit rejection regressions. The RFC form
starting January 1 00:00 and ending at year-end 24:00 plus the DST delta is
accepted as daylight time throughout; no-DST footers are accepted too.
Every generated input, accepted or rejected, is retained as a TZif fixture.
Accepted fixtures have a direct-tzcode-consistent 1600 sentinel, including
offset, DST flag and footer abbreviation. Synthetic/AllYear is the only
pre-existing hand-made fixture regenerated; CrossYear remains unchanged.

Expected offsets come exclusively from tzcode, queried on both the direct
POSIX string and identical TZif bytes. Those paths must agree at every probe.
Python ZoneInfo.from_file/fromutc and glibc POSIX/TZif are corroborators.
No accepted input or probe is omitted because a corroborator disagrees.
Each disagreement is classified and retained in
footer-divergence.jsonl.z. P-DAY executes the recorded CPython day mapping,
including ordinal n -> n-1 and its known J59 leap-year boundary. FRAME is
restricted to glibc on the all-year form. FRAME-NY is allowed for Python and
glibc only when the probe is within the largest absolute zone offset of a
UTC New Year, the governing transition's local year differs from the probe's
UTC year, and the actual offset equals the executable own-UTC-year variant.
Each FRAME-NY row retains the distance, bound and governing transition/year.
P-DAY+FRAME-NY requires both executable changes to contribute to the result;
P-DAY cannot hide a pure year-frame difference. Class totals count every
listed discrepancy, with the two glibc entry paths recorded separately.
G-HIST requires a direct glibc query 146097 days later to agree
with the primary reference. OUT records an unrepresentable local civil date
or the two explicitly model-only cases. OTHER records corroborator differences
that match no historical executable class. All corroborator disagreements are
informational under decision 7. Counts per class and reference, plus up to three
examples per class/reference, are retained in footer-reference.json. Only a
primary tzcode entry-path disagreement stops generation and preserves
footer-unexplained.json; product differential and all 487 real-zone checks
remain mandatory zero-failure gates.

Original/named rules cover actual years 1800..9999; sweep rules cover
1800..2300 and 9600..9999. Expected values are never extrapolated from a cycle.
Probe locations include both correctly mapped and CPython-mapped transition
dates at -1/0/+1 ms, year boundaries, July samples and range endpoints. The
Gregorian cycle is used only for domain classification and the named
historical corroborator check. Consecutive primary-reference outputs determine
all exact changes; each change is bracketed by adjacent millisecond probes.

footer-model.bin.z contains zlib-compressed little-endian FTR3: magic,
UInt32 record count; each record has UInt32 ASCII name length/name,
Int32 first/last years, Int32 initial offset milliseconds, UInt32 change count,
then packed (Int64 UTC milliseconds, Int32 offset-after) changes. UTC uses
1899-12-30. A SHA-256 and per-record executable receipts are in
footer-reference.json. FooterDifferential walks the entire step function,
including equal-offset raw partitions, and verifies every actual change's
raw boundary on both sides. GetPeriod's bounded equal-offset merge is not
assumed to make every period globally maximal.

footer-domain.bin.z is FDV1: magic, UInt32 count; each record contains
UInt32 ASCII name length/name and one byte (1 accepted, 0 rejected).
FooterDomainProperty loads every fixture and compares the result, including
the required rejection error. Dedicated rejection cases additionally assert
the setter's exact exception class/message and previous-zone retention.
footer-cases.txt lists all rule inputs. footer-reference.json records runtime,
seeds, domain counts, reference commands/exits/durations, class totals and
zero-primary-disagreement verdict. The qualified run is native Linux; a Windows-only
generator run cannot substitute for it.

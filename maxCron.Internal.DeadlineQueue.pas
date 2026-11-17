unit maxCron.Internal.DeadlineQueue;
{$I maxCron.inc}

interface

uses
  {$IFDEF FPC}
  Generics.Collections, SyncObjs
  {$ELSE}
  System.Generics.Collections, System.SyncObjs
  {$ENDIF};

type
  /// Indexed min-heap. Its lock is a leaf: no caller lock is acquired inside it.
  TCronDeadlineQueue = class
  private
    type
      TEntry = record
        WakeUs, EventId: Int64;
      end;
  private
    fLock: TCriticalSection;
    fHeap: TList<TEntry>;
    fIndices: TDictionary<Int64, Integer>;
    function Less(const aLeft, aRight: Integer): Boolean;
    procedure Swap(const aLeft, aRight: Integer);
    function SiftUp(const aIndex: Integer): Integer;
    procedure SiftDown(const aIndex: Integer);
    procedure RemoveAt(const aIndex: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    function Upsert(const aEventId, aWakeUs: Int64): Boolean;
    function Remove(const aEventId: Int64): Boolean;
    function TryPeek(out aWakeUs: Int64): Boolean;
    procedure PopDue(const aNowUs: Int64; const aIds: TList<Int64>);
    function Count: Integer;
  end;

implementation

constructor TCronDeadlineQueue.Create;
begin
  inherited;
  fLock := TCriticalSection.Create;
  fHeap := TList<TEntry>.Create;
  fIndices := TDictionary<Int64, Integer>.Create;
end;

destructor TCronDeadlineQueue.Destroy;
begin
  fIndices.Free;
  fHeap.Free;
  fLock.Free;
  inherited;
end;

function TCronDeadlineQueue.Less(const aLeft, aRight: Integer): Boolean;
var
  lLeft, lRight: TEntry;
begin
  lLeft := fHeap[aLeft]; lRight := fHeap[aRight];
  Result := (lLeft.WakeUs < lRight.WakeUs) or
    ((lLeft.WakeUs = lRight.WakeUs) and (lLeft.EventId < lRight.EventId));
end;

procedure TCronDeadlineQueue.Swap(const aLeft, aRight: Integer);
var
  lTemp: TEntry;
begin
  lTemp := fHeap[aLeft]; fHeap[aLeft] := fHeap[aRight]; fHeap[aRight] := lTemp;
  fIndices[fHeap[aLeft].EventId] := aLeft;
  fIndices[fHeap[aRight].EventId] := aRight;
end;

function TCronDeadlineQueue.SiftUp(const aIndex: Integer): Integer;
var
  lParent: Integer;
begin
  Result := aIndex;
  while Result > 0 do
  begin
    lParent := (Result - 1) div 2;
    if not Less(Result, lParent) then Break;
    Swap(Result, lParent); Result := lParent;
  end;
end;

procedure TCronDeadlineQueue.SiftDown(const aIndex: Integer);
var
  lIndex, lChild: Integer;
begin
  lIndex := aIndex;
  while lIndex < fHeap.Count div 2 do
  begin
    lChild := lIndex * 2 + 1;
    if (lChild + 1 < fHeap.Count) and Less(lChild + 1, lChild) then Inc(lChild);
    if not Less(lChild, lIndex) then Break;
    Swap(lIndex, lChild); lIndex := lChild;
  end;
end;

procedure TCronDeadlineQueue.RemoveAt(const aIndex: Integer);
var
  lLast: Integer;
begin
  lLast := fHeap.Count - 1;
  fIndices.Remove(fHeap[aIndex].EventId);
  if aIndex <> lLast then
  begin
    fHeap[aIndex] := fHeap[lLast];
    fIndices[fHeap[aIndex].EventId] := aIndex;
  end;
  fHeap.Delete(lLast);
  if aIndex < fHeap.Count then SiftDown(SiftUp(aIndex));
end;

function TCronDeadlineQueue.Upsert(const aEventId, aWakeUs: Int64): Boolean;
var
  lOldTop, lEntry: TEntry;
  lIndex: Integer;
  lHadTop: Boolean;
begin
  fLock.Acquire;
  try
    lHadTop := fHeap.Count > 0;
    lOldTop := Default(TEntry);
    if lHadTop then lOldTop := fHeap[0];
    lEntry.EventId := aEventId; lEntry.WakeUs := aWakeUs;
    if fIndices.TryGetValue(aEventId, lIndex) then
      fHeap[lIndex] := lEntry
    else begin
      lIndex := fHeap.Add(lEntry); fIndices.Add(aEventId, lIndex);
    end;
    SiftDown(SiftUp(lIndex));
    Result := (not lHadTop) or (lOldTop.EventId <> fHeap[0].EventId) or
      (lOldTop.WakeUs <> fHeap[0].WakeUs);
  finally
    fLock.Release;
  end;
end;

function TCronDeadlineQueue.Remove(const aEventId: Int64): Boolean;
var
  lIndex: Integer;
begin
  fLock.Acquire;
  try
    Result := False;
    if fIndices.TryGetValue(aEventId, lIndex) then
    begin
      Result := lIndex = 0; RemoveAt(lIndex);
    end;
  finally
    fLock.Release;
  end;
end;

function TCronDeadlineQueue.TryPeek(out aWakeUs: Int64): Boolean;
begin
  fLock.Acquire;
  try
    aWakeUs := 0;
    Result := fHeap.Count > 0;
    if Result then aWakeUs := fHeap[0].WakeUs;
  finally
    fLock.Release;
  end;
end;

procedure TCronDeadlineQueue.PopDue(const aNowUs: Int64; const aIds: TList<Int64>);
begin
  aIds.Clear;
  fLock.Acquire;
  try
    while (fHeap.Count > 0) and (fHeap[0].WakeUs <= aNowUs) do
    begin
      aIds.Add(fHeap[0].EventId); RemoveAt(0);
    end;
  finally
    fLock.Release;
  end;
end;

function TCronDeadlineQueue.Count: Integer;
begin
  fLock.Acquire;
  try
    Result := fHeap.Count;
  finally
    fLock.Release;
  end;
end;

end.

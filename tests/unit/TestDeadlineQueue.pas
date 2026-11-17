unit TestDeadlineQueue;
{$I maxCron.inc}
interface
uses
  {$IFDEF FPC}
  Generics.Collections, SysUtils,
  DUnitX.TestFramework,
  maxCron.Internal.DeadlineQueue
  {$ELSE} System.Generics.Collections, System.SysUtils, DUnitX.TestFramework,
  maxCron.Internal.DeadlineQueue
  {$ENDIF};
type
  [TestFixture]
  TTestDeadlineQueue = class
  public
    [Test] procedure GeneratedOperations;
  end;
implementation
procedure TTestDeadlineQueue.GeneratedOperations;
var
  lQueue: TCronDeadlineQueue;
  lPopped: TList<Int64>;
  lWake: array[1..128] of Int64;
  lPresent: array[1..128] of Boolean;
  lSeed: UInt64;
  lTop,lNewTop,lId,lOp,lBest,lCount,i,j: Integer;
  lAt,lPeek: Int64;
  lChanged,lExpected: Boolean;
begin
  lQueue := TCronDeadlineQueue.Create;
  lPopped := TList<Int64>.Create;
  try
    for i := 1 to 128 do
    begin
      lPresent[i] := False; lWake[i] := 0;
    end;
    lSeed := 20261115;
    for i := 1 to 20000 do
    begin
      lTop := 0;
      for j := 1 to 128 do
        if lPresent[j] then
          if (lTop=0) or (lWake[j]<lWake[lTop]) then lTop := j;
      lSeed := (lSeed*1664525+1013904223) and $FFFFFFFF;
      lId := Integer(lSeed mod 128)+1;
      lOp := Integer((lSeed shr 12) mod 4);
      lAt := Int64((lSeed shr 8) mod 1000)+1;
      case lOp of
        0,1:
          begin
            lExpected := (lTop=0) or (lAt<lWake[lTop]) or
              ((lAt=lWake[lTop]) and (lId<lTop)) or ((lId=lTop) and (lAt<>lWake[lTop]));
            lChanged := lQueue.Upsert(lId,lAt);
            Assert.AreEqual(lExpected,lChanged,'upsert '+IntToStr(i));
            lWake[lId] := lAt; lPresent[lId] := True;
          end;
        2:
          begin
            Assert.AreEqual((lTop=lId),lQueue.Remove(lId),'remove '+IntToStr(i));
            lPresent[lId] := False;
          end;
        3:
          begin
            lPopped.Add(-1);
            lQueue.PopDue(lAt,lPopped);
            j := 0;
            repeat
              lBest := 0;
              for lId := 1 to 128 do
                if lPresent[lId] and (lWake[lId]<=lAt) then
                  if (lBest=0) or (lWake[lId]<lWake[lBest]) then lBest := lId;
              if lBest<>0 then
              begin
                Assert.IsTrue(j<lPopped.Count,'missing pop');
                Assert.AreEqual<Int64>(Int64(lBest),lPopped[j],'pop order '+IntToStr(i));
                Inc(j); lPresent[lBest] := False;
              end;
            until lBest=0;
            Assert.AreEqual<Integer>(j,Integer(lPopped.Count),'pop count');
          end;
      end;
      lNewTop := 0; lCount := 0;
      for j := 1 to 128 do
        if lPresent[j] then
        begin
          Inc(lCount);
          if (lNewTop=0) or (lWake[j]<lWake[lNewTop]) then lNewTop := j;
        end;
      Assert.AreEqual(lCount,lQueue.Count,'count '+IntToStr(i));
      Assert.AreEqual(lNewTop<>0,lQueue.TryPeek(lPeek),'peek '+IntToStr(i));
      if lNewTop<>0 then Assert.AreEqual<Int64>(lWake[lNewTop],lPeek,'peek value');
    end;
  finally
    lPopped.Free; lQueue.Free;
  end;
end;
end.

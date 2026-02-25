unit TestRetryBackoff;

interface

uses
  System.Diagnostics, System.SysUtils,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestRetryBackoff = class
  public
    [Test]
    procedure DeadLetter_Fires_AfterRetryExhaustion;

    [Test]
    procedure SuccessWithinRetryBudget_DoesNotDeadLetter;
  end;

implementation

procedure TTestRetryBackoff.DeadLetter_Fires_AfterRetryExhaustion;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lInvokeCount: Integer;
  lDeadLetterCount: Integer;
  lDeadLetterAttempts: Integer;
  lStopwatch: TStopwatch;
begin
  lInvokeCount := 0;
  lDeadLetterCount := 0;
  lDeadLetterAttempts := 0;

  lCron := TmaxCron.Create(ctPortable);
  try
    lEvent := lCron.Add('RetryDeadLetter');
    lEvent.EventPlan := '* * * * * * * 0';
    lEvent.InvokeMode := imMainThread;
    lEvent.RetryMaxAttempts := 2;
    lEvent.RetryInitialDelayMs := 10;
    lEvent.RetryBackoffMultiplier := 2.0;
    lEvent.RetryMaxDelayMs := 20;
    lEvent.OnScheduleProc :=
      procedure(aSender: IMaxCronEvent)
      begin
        Inc(lInvokeCount);
        raise Exception.Create('planned callback failure');
      end;
    lEvent.OnDeadLetterProc :=
      procedure(aSender: IMaxCronEvent; const aErrorText: string; const aAttemptCount: Integer)
      begin
        Inc(lDeadLetterCount);
        lDeadLetterAttempts := aAttemptCount;
      end;
    lEvent.Run;

    lStopwatch := TStopwatch.StartNew;
    lCron.TickAt(lEvent.NextSchedule);

    Assert.AreEqual(3, lInvokeCount, 'Expected initial call + two retries');
    Assert.AreEqual(1, lDeadLetterCount, 'Dead-letter callback should fire exactly once');
    Assert.AreEqual(3, lDeadLetterAttempts, 'Dead-letter callback should report total attempts');
    Assert.IsTrue(lStopwatch.ElapsedMilliseconds >= 25,
      'Expected backoff delays to contribute measurable elapsed time');
  finally
    lCron.Free;
  end;
end;

procedure TTestRetryBackoff.SuccessWithinRetryBudget_DoesNotDeadLetter;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lInvokeCount: Integer;
  lDeadLetterCount: Integer;
  lSucceeded: Boolean;
begin
  lInvokeCount := 0;
  lDeadLetterCount := 0;
  lSucceeded := False;

  lCron := TmaxCron.Create(ctPortable);
  try
    lEvent := lCron.Add('RetrySuccess');
    lEvent.EventPlan := '* * * * * * * 0';
    lEvent.InvokeMode := imMainThread;
    lEvent.RetryMaxAttempts := 3;
    lEvent.RetryInitialDelayMs := 1;
    lEvent.RetryBackoffMultiplier := 1.5;
    lEvent.RetryMaxDelayMs := 5;
    lEvent.OnScheduleProc :=
      procedure(aSender: IMaxCronEvent)
      begin
        Inc(lInvokeCount);
        if lInvokeCount < 3 then
          raise Exception.Create('transient callback failure');
        lSucceeded := True;
      end;
    lEvent.OnDeadLetterProc :=
      procedure(aSender: IMaxCronEvent; const aErrorText: string; const aAttemptCount: Integer)
      begin
        Inc(lDeadLetterCount);
      end;
    lEvent.Run;

    lCron.TickAt(lEvent.NextSchedule);

    Assert.IsTrue(lSucceeded, 'Expected callback to succeed within retry budget');
    Assert.AreEqual(3, lInvokeCount, 'Expected two failures followed by one success');
    Assert.AreEqual(0, lDeadLetterCount, 'Dead-letter callback should not fire on successful retry');
  finally
    lCron.Free;
  end;
end;

end.

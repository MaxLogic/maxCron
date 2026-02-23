Unit CronDemoMainForm;

Interface

Uses
  maxCron,
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.Buttons,
  Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Menus;

Type
  TForm2 = Class(TForm)
    popSamples: TPopupMenu;
    PageControl1: TPageControl;
    tsIntervals: TTabSheet;
    pnlIntervalTest: TGroupBox;
    btnCalculate: TBitBtn;
    memCalculatedIntervals: TMemo;
    pnlCronString: TGroupBox;
    labSample: TStaticText;
    edCronString: TEdit;
    StaticText1: TStaticText;
    btnReset: TBitBtn;
    StaticText2: TStaticText;
    edMinute: TEdit;
    StaticText3: TStaticText;
    edHour: TEdit;
    StaticText4: TStaticText;
    edDayOfMonth: TEdit;
    StaticText5: TStaticText;
    edMonthOfYear: TEdit;
    StaticText6: TStaticText;
    edDayOfTheWeek: TEdit;
    StaticText7: TStaticText;
    edYear: TEdit;
    StaticText9: TStaticText;
    edExecutionLimit: TEdit;
    StaticText11: TStaticText;
    edSecond: TEdit;
    StaticText10: TStaticText;
    btnSamples: TButton;
    stDialect: TStaticText;
    cbDialect: TComboBox;
    stDayMatchMode: TStaticText;
    cbDayMatchMode: TComboBox;
    stInvokeMode: TStaticText;
    cbInvokeMode: TComboBox;
    stOverlapMode: TStaticText;
    cbOverlapMode: TComboBox;
    stMisfirePolicy: TStaticText;
    cbMisfirePolicy: TComboBox;
    tsEventLog: TTabSheet;
    memLog: TMemo;
    StaticText12: TStaticText;
    Panel1: TPanel;
    StaticText8: TStaticText;
    dtDate: TDateTimePicker;
    dtTime: TDateTimePicker;
    StaticText13: TStaticText;
    Procedure FormCreate(Sender: TObject);
    Procedure btnResetClick(Sender: TObject);
    Procedure edCronStringChange(Sender: TObject);
    Procedure edExecutionLimitChange(Sender: TObject);
    Procedure btnCalculateClick(Sender: TObject);
    Procedure FormDestroy(Sender: TObject);
    Procedure btnSamplesClick(Sender: TObject);
    Procedure cbDialectChange(Sender: TObject);
    Procedure cbDayMatchModeChange(Sender: TObject);
    Procedure cbInvokeModeChange(Sender: TObject);
    Procedure cbOverlapModeChange(Sender: TObject);
    Procedure cbMisfirePolicyChange(Sender: TObject);
  Private
    ChronScheduler: TmaxCron;
    FDynamicEvent: IMaxCronEvent;
    fSamples: TStringList;
    Procedure OnScheduleTrigger(Sender: IMaxCronEvent);
    Procedure log(Const msg: String);
    Function showDate(Const aDateTime: TDateTime): String;
    Procedure prepareSamples;
    Function GetSampleCronString(Const sample: String): String;
    Function GetSampleCaption(Const sample: String): String;
    Function GetSelectedDialect: TmaxCronDialect;
    Function GetSelectedDayMatchMode: TmaxCronDayMatchMode;
    Function GetSelectedInvokeMode: TmaxCronInvokeMode;
    Function GetSelectedOverlapMode: TmaxCronOverlapMode;
    Function GetSelectedMisfirePolicy: TmaxCronMisfirePolicy;
    Function NormalizeCronField(const aValue, aDefault: string): string;
    Procedure ApplyCronString;
    Procedure ApplyDynamicEventFromUi(const aLogSuccess: Boolean);
    Procedure RebuildCronString;
    Procedure UpdateDialectUi;
    Procedure SelectSample(Sender: TObject); Overload;
    Procedure SelectSample(index: Integer); Overload;
    Procedure calculateIntervalls;
  Public

  End;

Var
  Form2: TForm2;

Implementation

{$R *.dfm}


Procedure TForm2.FormCreate(Sender: TObject);
Var
  lNewSchedule: IMaxCronEvent;
  lStartDate, lStopDate: TDateTime;
  lPlan: TPlan;
Begin
  PageControl1.activepageIndex := 0;

  dtDate.date := now();
  dtTime.time := time();
  prepareSamples;

  cbDialect.Items.Clear;
  cbDialect.Items.Add('MaxCron (minute-first, 5-8 fields)');
  cbDialect.Items.Add('Standard (minute-first, 5 fields)');
  cbDialect.Items.Add('Quartz (seconds-first, 6/7 fields)');
  cbDialect.ItemIndex := 0;

  cbDayMatchMode.Items.Clear;
  cbDayMatchMode.Items.Add('And (legacy)');
  cbDayMatchMode.Items.Add('Or (crontab)');
  cbDayMatchMode.ItemIndex := 0;

  cbInvokeMode.Items.Clear;
  cbInvokeMode.Items.Add('Default (scheduler)');
  cbInvokeMode.Items.Add('Main thread');
  cbInvokeMode.Items.Add('TTask');
  cbInvokeMode.Items.Add('Thread');
  cbInvokeMode.Items.Add('MaxAsync');
  cbInvokeMode.ItemIndex := 0;

  cbOverlapMode.Items.Clear;
  cbOverlapMode.Items.Add('Allow overlap');
  cbOverlapMode.Items.Add('Skip if running');
  cbOverlapMode.Items.Add('Serialize');
  cbOverlapMode.Items.Add('Serialize (coalesce)');
  cbOverlapMode.ItemIndex := 0;

  cbMisfirePolicy.Items.Clear;
  cbMisfirePolicy.Items.Add('Default (scheduler)');
  cbMisfirePolicy.Items.Add('Skip');
  cbMisfirePolicy.Items.Add('Fire once now');
  cbMisfirePolicy.Items.Add('Catch up all (bounded)');
  cbMisfirePolicy.ItemIndex := 0;

  UpdateDialectUi;

  log('now is ' + showDate(now));

  // create a new TmaxCron  that will hold all the events
  ChronScheduler := TmaxCron.Create;

  lNewSchedule := ChronScheduler.Add('Event1', '1 * * * * *', OnScheduleTrigger).Run;
  log(lNewSchedule.name + ' next scheduled date is ' + showDate(lNewSchedule.NextSchedule));

  // you can use anonymous methods as well
  lNewSchedule := ChronScheduler.Add('Event2Worker');
  lNewSchedule.EventPlan := '*/2 * * * * *';
  lNewSchedule.OnScheduleproc := Procedure(aEvent: IMaxCronEvent)
    Begin
      OnScheduleTrigger(aEvent);
    End;
  lNewSchedule.Run;
  log(lNewSchedule.name + ' next scheduled date is ' + showDate(lNewSchedule.NextSchedule));

  // using a shorter adding syntax
  lNewSchedule := ChronScheduler.Add('Event4', '1 * * * * *',
    Procedure(aEvent: IMaxCronEvent)
    Begin
      OnScheduleTrigger(aEvent);
    End).Run;
  log(lNewSchedule.name + ' next scheduled date is ' + showDate(lNewSchedule.NextSchedule));

  // using the TPlan helper
  // The TPlan is a small record that allows you to specify the parts in a more friendly way and then convert them to a cron string
  lPlan := Default (TPlan); // it is a record, so initialize it properly
  // you can use the reset method to reset all the values to their defaults like this:
  lPlan.reset;
  // you can access any of the fields just like that:
  lPlan.Second := '30';
  // now create a new event using our new plan
  lNewSchedule := ChronScheduler.Add('EventFromTPlan', lPlan.text, OnScheduleTrigger).Run;
  log(lNewSchedule.name + ' next scheduled date is ' + showDate(lNewSchedule.NextSchedule));

  // start stop dynamic event
  FDynamicEvent := ChronScheduler.Add('DynamicSchedule');
  lPlan.reset;
  lPlan.Second := '15';
  FDynamicEvent.EventPlan := lPlan.text;
  FDynamicEvent.OnScheduleEvent := OnScheduleTrigger;
  FDynamicEvent.Run;
  log(FDynamicEvent.name + ' next scheduled date is ' + showDate(FDynamicEvent.NextSchedule));

  // now ad a event with a valid range

  // start time is in 50 seconds
  lStartDate := now() + 1 / 24 / 60 / 60 * 50;
  // and stop 5 minutes afterwards
  lStopDate := lStartDate + 1 / 24 / 60 * 5;
  log('Ranged Event start date: ' + showDate(lStartDate));
  log('Ranged Event stop date: ' + showDate(lStopDate));
  lNewSchedule := ChronScheduler.Add('RangedSchedule');
  lNewSchedule.EventPlan := '0 0 */2 * 1,5,10 7 *';
  lNewSchedule.OnScheduleEvent := OnScheduleTrigger;
  lNewSchedule.ValidFrom := lStartDate;
  lNewSchedule.ValidTo := lStopDate;
  lNewSchedule.Run;
  log(lNewSchedule.name + ' next scheduled date is ' + showDate(lNewSchedule.NextSchedule));

End;

Procedure TForm2.OnScheduleTrigger(Sender: IMaxCronEvent);
Begin
  log(Format('Event "%s"  was trigered at : %s, next scheduled date is %s',
    [Sender.name,
    showDate(now),
    showDate(Sender.NextSchedule)]));
End;

Procedure TForm2.log(Const msg: String);
Begin
  memLog.lines.Add(msg);
  // scroll to bottom to move the new added line into view.
  memLog.Perform(WM_VSCROLL, SB_BOTTOM, 0);
End;

Function TForm2.showDate(Const aDateTime: TDateTime): String;
Begin
  result := formatDateTime(
    'yyyy"-"mm"-"dd" "hh":"nn":"ss"."zzz', aDateTime);
End;

Procedure TForm2.btnResetClick(Sender: TObject);
Begin
  edCronString.setFocus;
  Case GetSelectedDialect Of
    cdStandard:
      edCronString.text := '* * * * *';
    cdQuartzSecondsFirst:
      edCronString.text := '0 * * * * *';
  Else
    edCronString.text := '* * * * * * * *';
  End;
  ApplyDynamicEventFromUi(True);
End;

Procedure TForm2.edCronStringChange(Sender: TObject);
Var
  lPlan: TPlan;
Begin
  If edCronString.focused Then
  Begin
    lPlan := Default(TPlan);
    lPlan.Dialect := GetSelectedDialect;
    try
      lPlan.Text := edCronString.Text;
    except
      on E: Exception do
      begin
        labSample.Caption := '(' + E.Message + ')';
        Exit;
      end;
    end;

    edMinute.text := lPlan.minute;
    edHour.text := lPlan.hour;
    edDayOfMonth.text := lPlan.DayOfTheMonth;
    edMonthOfYear.text := lPlan.Month;
    edDayOfTheWeek.text := lPlan.DayOfTheWeek;
    edYear.text := lPlan.Year;
    edSecond.text := lPlan.Second;
    edExecutionLimit.text := lPlan.ExecutionLimit;
    labSample.Caption := '';
    ApplyDynamicEventFromUi(False);
  End;
End;

Procedure TForm2.edExecutionLimitChange(Sender: TObject);
Var
  lEdit: TEdit;
Begin
  lEdit := Sender As TEdit;
  If lEdit.focused Then
  Begin
    RebuildCronString;
    ApplyDynamicEventFromUi(False);
    labSample.Caption := '';
  End;
End;

Procedure TForm2.btnCalculateClick(Sender: TObject);
Begin
  calculateIntervalls;
  ApplyDynamicEventFromUi(True);
End;

Procedure TForm2.calculateIntervalls;
Var
  dt: TDateTime;
  lSchedule: TCronSchedulePlan;
  x: Integer;
Begin
  lSchedule := TCronSchedulePlan.Create;
  memCalculatedIntervals.lines.beginUpdate;
  Try
    memCalculatedIntervals.lines.clear;
    dt := trunc(dtDate.DateTime) + frac(dtTime.DateTime);

    lSchedule.Dialect := GetSelectedDialect;
    lSchedule.DayMatchMode := GetSelectedDayMatchMode;
    try
      lSchedule.Parse(edCronString.text);
    except
      on E: Exception do
      begin
        memCalculatedIntervals.lines.Add('Error: ' + E.Message);
        Exit;
      end;
    end;

    For x := 0 To 99 Do
    Begin
      If Not lSchedule.FindNextScheduleDate(dt, dt) Then
        break;

      memCalculatedIntervals.lines.Add(
        formatDateTime('ddd', dt) + #9 +
        showDate(dt));
    End;
  Finally
    memCalculatedIntervals.lines.endUpdate;
    lSchedule.free;
  End;

End;

Procedure TForm2.prepareSamples;
Var
  mi: TMenuItem;
  x: Integer;
  s: String;
Begin
  // first prepare the list
  // I;ve made it as a simple stringList, in a readable format, we will get rd of the extra spaces later on.
  fSamples := TStringList.Create;
  With fSamples Do
  Begin
      Add('59 23 31 12 5 *                       |One minute  before the end of year if the last day of the year is Friday');
    Add('59 23 31 DEC Fri *                    |Same as above (different notation)');
    Add('45 17 7 6 * *                         |Every  year, on June 7th at 17:45');
    Add('45 17 7 6 * 2001,2002                 |Once a   year, on June 7th at 17:45, if the year is 2001 or  2002');
    Add('0,15,30,45 0,6,12,18 1,15,31 * 1-5 *  |At 00:00, 00:15, 00:30, 00:45, 06:00, 06:15, 06:30, 06:45, 12:00, 12:15, 12:30, 12:45, 18:00, 18:15, 18:30, 18:45, on 1st, 15th or  31st of each  month, but not on weekends');
    Add('*/15 */6 1,15,31 * 1-5 *              |Same as above (different notation)');
    Add('0 12 * * 1-5 *                        |At midday on weekdays');
    Add('0 12 * * Mon-Fri *                    |Same as above (different notation)');
    Add('* * * 1,3,5,7,9,11 * *                |Each minute in January,  March,  May, July, September, and November');
    Add('1,2,3,5,20-25,30-35,59 23 31 12 * *   |On the  last day of year, at 23:01, 23:02, 23:03, 23:05, 23:20, 23:21, 23:22, 23:23, 23:24, 23:25, 23:30, 23:31, 23:32, 23:33, 23:34, 23:35, 23:59');
    Add('0 9 1-7 * 1 *                         |First Monday of each month, at 9 a.m.');
    Add('0 0 1 * * *                           |At midnight, on the first day of each month');
    Add('* 0-11 * * *                          |Each minute before midday');
    Add('* * * 1,2,3 * *                       |Each minute in January, February or March');
    Add('* * * Jan,Feb,Mar * *                 |Same as above (different notation)');
    Add('0 0 * * * *                           |Daily at midnight');
    Add('0 0 * * 3 *                           |Each Wednesday at midnight');
    Add('0 0 * * * * *                         |Daily at midnight every second. That is 60 executions');
    Add('0 0 * * * * 15,30                     |Daily 15 and 30 second after midnight');
    Add('0 0 * * * * * 3                       |Daily at midnight every second. But limited to 3 executions');
    Add('M:0 0 LW * *                          |Last weekday of month (set start after last weekday to test rollover)');
    Add('M:0 0 15W * *                         |Nearest weekday to 15th (set start after that day to test rollover)');
    Add('M:0 0 * * 5L                          |Last Friday of month (set start after that day to test rollover)');
    Add('M:0 0 * * 2#3                         |3rd Tuesday of month (set start after that day to test rollover)');
    Add('Q:0 15 10 ? * 2#3                      |Quartz: 3rd Tuesday at 10:15:00 (seconds-first)');
    Add('S:*/15 9-17 * * Mon-Fri               |Standard: every 15 minutes on weekdays');
    Add('@hourly                               |Macro: hourly');
    Add('@daily                                |Macro: daily at midnight');
    Add('@monthly                               |Macro: monthly at midnight');
    Add('M:@reboot                             |Macro: reboot (maxCron only)');
    Add('0 0 LW * * # last weekday               |Trailing comment example');
  End;

  // now build the popup menu
  For x := 0 To fSamples.count - 1 Do
  Begin
      mi := TMenuItem.Create(popSamples);
    mi.Caption := GetSampleCaption(fSamples[x]);
    mi.onClick := SelectSample;
    mi.tag := x;
    popSamples.items.Add(mi);
    mi.VISIBLE := TRUE;
  End;
End;

Procedure TForm2.FormDestroy(Sender: TObject);
Begin
  fSamples.free;
End;

Function TForm2.GetSampleCronString(Const sample: String): String;
Var
  lRaw: String;
  lPrefix: String;
Begin
  lRaw := trim(copy(sample, 1, pos('|', sample) - 1));
  if Length(lRaw) >= 2 then
  begin
    lPrefix := Copy(lRaw, 1, 2);
    if (lPrefix = 'M:') or (lPrefix = 'S:') or (lPrefix = 'Q:') then
      lRaw := Trim(Copy(lRaw, 3, MaxInt));
  end;
  result := lRaw;
End;

Function TForm2.GetSampleCaption(Const sample: String): String;
Begin
  result := trim(copy(sample, pos('|', sample) + 1, length(sample)));
End;

Procedure TForm2.SelectSample(Sender: TObject);
Var
  mi: TMenuItem;
Begin
  mi := Sender As TMenuItem;
  SelectSample(mi.tag);
End;

Procedure TForm2.SelectSample(index: Integer);
Var
  s: String;
  lRaw: String;
Begin
  edCronString.setFocus;
  lRaw := trim(copy(fSamples[Index], 1, pos('|', fSamples[Index]) - 1));
  if lRaw.StartsWith('Q:') then
    cbDialect.ItemIndex := 2
  else if lRaw.StartsWith('S:') then
    cbDialect.ItemIndex := 1
  else
    cbDialect.ItemIndex := 0;

  UpdateDialectUi;
  edCronString.text := GetSampleCronString(fSamples[Index]);
  ApplyCronString;
  s := GetSampleCaption(fSamples[Index]);
  labSample.Caption := '(' + s + ')';

  calculateIntervalls;
  ApplyDynamicEventFromUi(True);

  // now inject the samle info as the first line in the memo.
  memCalculatedIntervals.lines.insert(0, s + sLineBreak);
End;

Procedure TForm2.btnSamplesClick(Sender: TObject);
Var
  p: Tpoint;
Begin
  p := point(0, btnSamples.height);
  p := btnSamples.ClientToScreen(p);
  popSamples.Popup(p.x, p.y);
End;

Procedure TForm2.cbDialectChange(Sender: TObject);
Begin
  UpdateDialectUi;
  ApplyCronString;
  ApplyDynamicEventFromUi(True);
  labSample.Caption := '';
End;

Procedure TForm2.cbDayMatchModeChange(Sender: TObject);
Begin
  ApplyDynamicEventFromUi(True);
  labSample.Caption := '';
End;

Procedure TForm2.cbInvokeModeChange(Sender: TObject);
Begin
  ApplyDynamicEventFromUi(True);
  labSample.Caption := '';
End;

Procedure TForm2.cbOverlapModeChange(Sender: TObject);
Begin
  ApplyDynamicEventFromUi(True);
  labSample.Caption := '';
End;

Procedure TForm2.cbMisfirePolicyChange(Sender: TObject);
Begin
  ApplyDynamicEventFromUi(True);
  labSample.Caption := '';
End;

Function TForm2.GetSelectedDialect: TmaxCronDialect;
Begin
  Case cbDialect.ItemIndex Of
    1: Result := cdStandard;
    2: Result := cdQuartzSecondsFirst;
  Else
    Result := cdMaxCron;
  End;
End;

Function TForm2.GetSelectedDayMatchMode: TmaxCronDayMatchMode;
Begin
  If cbDayMatchMode.ItemIndex = 1 Then
    Result := dmOr
  Else
    Result := dmAnd;
End;

Function TForm2.GetSelectedInvokeMode: TmaxCronInvokeMode;
Begin
  Case cbInvokeMode.ItemIndex Of
    1: Result := TmaxCronInvokeMode.imMainThread;
    2: Result := TmaxCronInvokeMode.imTTask;
    3: Result := TmaxCronInvokeMode.imThread;
    4: Result := TmaxCronInvokeMode.imMaxAsync;
  Else
    Result := TmaxCronInvokeMode.imDefault;
  End;
End;

Function TForm2.GetSelectedOverlapMode: TmaxCronOverlapMode;
Begin
  Case cbOverlapMode.ItemIndex Of
    1: Result := TmaxCronOverlapMode.omSkipIfRunning;
    2: Result := TmaxCronOverlapMode.omSerialize;
    3: Result := TmaxCronOverlapMode.omSerializeCoalesce;
  Else
    Result := TmaxCronOverlapMode.omAllowOverlap;
  End;
End;

Function TForm2.GetSelectedMisfirePolicy: TmaxCronMisfirePolicy;
Begin
  Case cbMisfirePolicy.ItemIndex Of
    1: Result := TmaxCronMisfirePolicy.mpSkip;
    2: Result := TmaxCronMisfirePolicy.mpFireOnceNow;
    3: Result := TmaxCronMisfirePolicy.mpCatchUpAll;
  Else
    Result := TmaxCronMisfirePolicy.mpDefault;
  End;
End;

Function TForm2.NormalizeCronField(const aValue, aDefault: string): string;
Var
  lValue: String;
Begin
  lValue := Trim(aValue);
  If lValue = '' Then
    lValue := aDefault;
  Result := lValue;
End;

Procedure TForm2.ApplyCronString;
Var
  lPlan: TPlan;
Begin
  lPlan := Default(TPlan);
  lPlan.Dialect := GetSelectedDialect;
  try
    lPlan.Text := edCronString.Text;
  except
    on E: Exception do
    begin
      labSample.Caption := '(' + E.Message + ')';
      Exit;
    end;
  end;

  edMinute.text := lPlan.minute;
  edHour.text := lPlan.hour;
  edDayOfMonth.text := lPlan.DayOfTheMonth;
  edMonthOfYear.text := lPlan.Month;
  edDayOfTheWeek.text := lPlan.DayOfTheWeek;
  edYear.text := lPlan.Year;
  edSecond.text := lPlan.Second;
  edExecutionLimit.text := lPlan.ExecutionLimit;
End;

Procedure TForm2.ApplyDynamicEventFromUi(const aLogSuccess: Boolean);
Var
  lPlanText: String;
Begin
  if FDynamicEvent = nil then
    Exit;

  lPlanText := Trim(edCronString.Text);
  if lPlanText = '' then
    Exit;

  try
    FDynamicEvent.Dialect := GetSelectedDialect;
    FDynamicEvent.DayMatchMode := GetSelectedDayMatchMode;
    FDynamicEvent.InvokeMode := GetSelectedInvokeMode;
    FDynamicEvent.OverlapMode := GetSelectedOverlapMode;
    FDynamicEvent.MisfirePolicy := GetSelectedMisfirePolicy;
    FDynamicEvent.EventPlan := lPlanText;
    if not FDynamicEvent.Enabled then
      FDynamicEvent.Run;
    if aLogSuccess then
      log(FDynamicEvent.name + ' next scheduled date is ' + showDate(FDynamicEvent.NextSchedule));
  except
    on E: Exception do
    begin
      if aLogSuccess then
        log('DynamicSchedule error: ' + E.Message);
    end;
  end;
End;

Procedure TForm2.RebuildCronString;
Var
  lDialect: TmaxCronDialect;
  lMinute, lHour, lDom, lMonth, lDow, lYear, lSecond, lExec: String;
  lYearRaw: String;
Begin
  lDialect := GetSelectedDialect;
  lMinute := NormalizeCronField(edMinute.Text, '*');
  lHour := NormalizeCronField(edHour.Text, '*');
  lDom := NormalizeCronField(edDayOfMonth.Text, '*');
  lMonth := NormalizeCronField(edMonthOfYear.Text, '*');
  lDow := NormalizeCronField(edDayOfTheWeek.Text, '*');
  lYear := NormalizeCronField(edYear.Text, '*');
  lSecond := NormalizeCronField(edSecond.Text, '0');
  lExec := NormalizeCronField(edExecutionLimit.Text, '0');

  Case lDialect Of
    cdStandard:
      edCronString.Text := Format('%s %s %s %s %s', [lMinute, lHour, lDom, lMonth, lDow]);
    cdQuartzSecondsFirst:
      begin
        lYearRaw := Trim(edYear.Text);
        if (lYearRaw = '') or (lYearRaw = '*') then
          edCronString.Text := Format('%s %s %s %s %s %s', [lSecond, lMinute, lHour, lDom, lMonth, lDow])
        else
          edCronString.Text := Format('%s %s %s %s %s %s %s', [lSecond, lMinute, lHour, lDom, lMonth, lDow, lYear]);
      end;
  else
    edCronString.Text := Format('%s %s %s %s %s %s %s %s',
      [lMinute, lHour, lDom, lMonth, lDow, lYear, lSecond, lExec]);
  End;
End;

Procedure TForm2.UpdateDialectUi;
Var
  lDialect: TmaxCronDialect;
Begin
  lDialect := GetSelectedDialect;
  edSecond.Enabled := lDialect <> cdStandard;
  edYear.Enabled := lDialect <> cdStandard;
  edExecutionLimit.Enabled := lDialect = cdMaxCron;
End;

End.

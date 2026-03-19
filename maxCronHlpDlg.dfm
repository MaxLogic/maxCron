object ChronHelpDlg: TChronHelpDlg
  Left = 0
  Top = 0
  Caption = 'Chron Help'
  ClientHeight = 307
  ClientWidth = 643
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 96
  TextHeight = 13
  object btnOpenInBrowser: TButton
    Left = 0
    Top = 281
    Width = 643
    Height = 26
    Align = alBottom
    Caption = 'Open in Browser'
    TabOrder = 0
    OnClick = btnOpenInBrowserClick
  end
  object edHTML: TMemo
    Left = 0
    Top = 0
    Width = 643
    Height = 281
    Align = alClient
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 1
    Lines.Strings = (
      '<html><head>'
      '<title>maxCron format help</title>'
      '<meta http-equiv="Content-Type" content="text/html; charset=windows-1252">'
      '<style>'
      'body { font-family: Arial, Helvetica, sans-serif; font-size: 10pt; }'
      'p, li { font-family: Arial, Helvetica, sans-serif; font-size: 10pt; }'
      'pre { font-size: 10pt; color: #333333; background-color: #F5F5F5; padding: 5px; border: 1px solid #CCCCCC; }'
      '</style>'
      '</head>'
      '<body bgcolor="#FFFFFF" text="#000000">'
      '<p align="center"><b><font size="5">maxCron Format</font></b></p>'
      '<p>maxCron supports three dialects:</p>'
      '<ul>'
      '<li><b>Standard</b>: <code>&lt;Minute&gt; &lt;Hour&gt; &lt;DayOfMonth&gt; &lt;Month&gt; &lt;DayOfWeek&gt;</code></li>'
      '<li><b>maxCron</b> (default, minute-first): <code>&lt;Minute&gt; &lt;Hour&gt; &lt;DayOfMonth&gt; &lt;Month&gt; &lt;DayOfWeek&gt; [Year] [Second] [ExecutionLimit]</code></li>'
      '<li><b>Quartz seconds-first</b>: <code>&lt;Second&gt; &lt;Minute&gt; &lt;Hour&gt; &lt;DayOfMonth&gt; &lt;Month&gt; &lt;DayOfWeek&gt; [Year]</code></li>'
      '</ul>'
      '<p>Important: Quartz expressions are seconds-first. Use the Quartz dialect for expressions that use <code>?</code>, <code>W</code>, <code>LW</code>, <code>nL</code>, or <code>n#k</code>.</p>'
      '<pre><b>maxCron full form</b>'
      '&lt;Minute&gt; &lt;Hour&gt; &lt;DayOfMonth&gt; &lt;Month&gt; &lt;DayOfWeek&gt; &lt;Year&gt; &lt;Second&gt; &lt;ExecutionLimit&gt;'
      ''
      'Example: * * * * * * * 0'
      '| | | | | | | +-- ExecutionLimit: range 0 - 4294967295, default 0 = unlimited'
      '| | | | | | +---- Second: range 0 - 59, default 0 when omitted'
      '| | | | | +------ Year: range 1900 - 3000'
      '| | | | +-------- Day of Week: standard/maxCron use 0 or 7 = Sunday, 1..6 = Monday..Saturday'
      '| | | +---------- Month: range 1 - 12'
      '| | +------------ Day of Month: range 1 - 31'
      '| +-------------- Hour: range 0 - 23'
      '+---------------- Minute: range 0 - 59</pre>'
      '<p>Lists, ranges, steps, month/day names, trailing <code># comments</code>, and cron macros are supported.</p>'
      '<p>Macros include <code>@yearly</code>, <code>@monthly</code>, <code>@weekly</code>, <code>@daily</code>, <code>@hourly</code>, and <code>@reboot</code> (<code>@reboot</code> is maxCron-only).</p>'
      '<p>Examples:</p>'
      '<pre>*/5 * * * *'
      'Every 5 minutes (default maxCron dialect, 5-field form)'
      ''
      '* * * * * * */2 0'
      'Every 2 seconds in explicit 8-field maxCron form'
      ''
      '0 15 10 ? * 2#3'
      'Quartz seconds-first: third Tuesday of each month at 10:15:00'
      ''
      '@reboot'
      'Run once on the next scheduler tick (maxCron dialect only)</pre>'
      '<p>When in doubt, use 5 fields for minute-level schedules or the full 8-field maxCron form when seconds or ExecutionLimit matter.</p>'
      '</body></html>')
    TabOrder = 1
    Visible = False
  end
end

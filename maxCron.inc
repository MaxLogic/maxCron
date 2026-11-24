{$IFDEF FPC}
  {$IF FPC_FULLVERSION < 30301}{$ERROR maxCron requires FPC 3.3.1 or later}{$IFEND}
  {$IF not ((defined(MSWINDOWS) and defined(CPUX86_64)) or (defined(LINUX) and (defined(CPUX86_64) or defined(CPUAARCH64))))}{$ERROR maxCron on FPC supports Windows x64 and Linux x86_64/aarch64 only}{$IFEND}
  {$MODE DELPHIUNICODE}
  // Delphi evaluates real constants at Double precision on Windows x64.
  {$MINFPCONSTPREC 64}
  {$MODESWITCH ANONYMOUSFUNCTIONS}
  {$MODESWITCH FUNCTIONREFERENCES}
{$ELSE}
  {$IF CompilerVersion <= 29.0}
    {$DEFINE ForceQueueNotAvailable}
  {$IFEND}
{$ENDIF}
{$SCOPEDENUMS OFF}

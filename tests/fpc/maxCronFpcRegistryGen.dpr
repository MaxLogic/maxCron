program maxCronFpcRegistryGen;
{$I maxCron.inc}

uses
  Classes, StrUtils, SysUtils;

const
  cUnits: array[0..19] of string = ('TestCronInstant', 'TestCronParsing', 'TestCronInvalidCorpus',
    'TestCronUtilsCorpus', 'TestCronFuzzOracle', 'TestCronQuery', 'TestIntervalPlan', 'TestDeadlineQueue',
    'TestTimeZoneRules', 'TestTimeZoneTzif', 'TestCronTextParity', 'TestFpcShims', 'TestScheduleNext',
    'TestHashJitter', 'TestCalendarTimeZone', 'TestNamedTimeZones', 'TestTimeBoundaries', 'TestMisfireOnTime',
    'TestCronPhaseDifferential', 'TestLocalZoneOs');

var
  gDeclarations, gBodies, gRegistrations: TStringList;
  gCount, gFixtures: Integer;
  gFile: string;
  gLine: Integer;

procedure Reject(const aReason: string);
begin
  raise Exception.Create(gFile + ':' + IntToStr(gLine + 1) + ': ' + aReason);
end;

function Quoted(const s: string): string;
begin
  Result := QuotedStr(s);
end;

function ReadLiteral(const s: string; var aPos: Integer): string;
begin
  Result := '';
  while (aPos <= Length(s)) and (s[aPos] = ' ') do Inc(aPos);
  if (aPos > Length(s)) or (s[aPos] <> '''') then Reject('Expected Pascal string literal');
  Inc(aPos);
  while aPos <= Length(s) do
  begin
    if s[aPos] = '''' then
    begin
      Inc(aPos);
      if (aPos <= Length(s)) and (s[aPos] = '''') then
        Result := Result + ''''
      else Exit;
    end else
      Result := Result + s[aPos];
    Inc(aPos);
  end;
  Reject('Unterminated string literal');
end;

procedure Emit(const aUnit, aClass, aMethod, aCase, aArgs: string);
var
  lWrapper, lFixture, lName: string;
begin
  Inc(gCount);
  lWrapper := 'GeneratedTest' + IntToStr(gCount);
  lFixture := 'gGeneratedFixture' + IntToStr(gFixtures);
  lName := aUnit + '.' + aClass + '.' + aMethod;
  if aCase <> '' then lName := lName + '.' + aCase;
  gBodies.Add('procedure ' + lWrapper + ';');
  gBodies.Add('begin');
  gBodies.Add('  ' + lFixture + '.' + aMethod + aArgs + ';');
  gBodies.Add('end;');
  gRegistrations.Add('  RegisterTest(' + Quoted(lName) + ', ' + Quoted(aUnit + '.' + aClass) + ', @' + lWrapper + ');');
end;

function Arguments(const aParams, aValues: string): string;
var
  lGroups, lValues: TArray<string>;
  lGroup, lType, lValue: string;
  i, j, k, lColon, lNameCount, lNumber: Integer;
begin
  Result := '(';
  // DUnitX TestCaseAttribute uses StrUtils.SplitString with no trimming by default.
  lValues := aValues.Split([',']);
  lGroups := aParams.Split([';']);
  k := 0;
  for lGroup in lGroups do
  begin
    lColon := Pos(':', lGroup);
    if lColon = 0 then Reject('Unparsable parameter declaration');
    lNameCount := Length(Trim(StringReplace(Copy(lGroup, 1, lColon - 1), 'const ', '', [])).Split([',']));
    lType := LowerCase(Trim(Copy(lGroup, lColon + 1, MaxInt)));
    if (lType <> 'string') and (lType <> 'integer') then Reject('Unsupported parameter type ' + lType);
    for j := 1 to lNameCount do
    begin
      if k >= Length(lValues) then Reject('Too few TestCase values');
      lValue := lValues[k];
      if k > 0 then Result := Result + ', ';
      if lType = 'string' then Result := Result + Quoted(lValue)
      else begin
        if lValue = '' then Reject('Empty Integer case value');
        for i := 1 to Length(lValue) do
          if not CharInSet(lValue[i], ['0'..'9', '+', '-']) then Reject('Nondecimal Integer case value');
        if not TryStrToInt(lValue, lNumber) then Reject('Invalid Integer case value');
        Result := Result + IntToStr(lNumber);
      end;
      Inc(k);
    end;
  end;
  if k <> Length(lValues) then Reject('Too many TestCase values');
  Result := Result + ')';
end;

type
  TConditional = record
    ParentActive, Condition, ElseSeen: Boolean;
  end;

// Only the fixed FPC gate environment is supported. Unknown conditions fail
// closed rather than guessing whether an attributed declaration is active.
function GateDefined(const aSymbol: string): Boolean;
begin
  if SameText(aSymbol, 'FPC') or SameText(aSymbol, 'MAXCRON_TESTS') or
    SameText(aSymbol, 'MSWINDOWS') or SameText(aSymbol, 'WIN64') or
    SameText(aSymbol, 'CPUX86_64') then Exit(True);
  if SameText(aSymbol, 'WIN32') then Exit(False);
  Reject('Unsupported conditional symbol ' + aSymbol);
  Result := False;
end;

procedure ActiveInterface(aLines: TStringList);
var
  lStack: array of TConditional;
  lActive, lString: Boolean;
  lComment: Integer;
  s, lOutput, lDirective, lCommand, lArgument: string;
  i, j, lDepth, lSpace: Integer;
begin
  lStack := nil;
  lActive := True;
  lComment := 0;
  for gLine := 0 to aLines.Count - 1 do
  begin
    s := aLines[gLine];
    lOutput := '';
    lString := False;
    i := 1;
    while i <= Length(s) do
    begin
      if lComment <> 0 then
      begin
        if (lComment = 1) and (s[i] = '}') then lComment := 0
        else if (lComment = 2) and (Copy(s, i, 2) = '*)') then
        begin
          lComment := 0;
          Inc(i);
        end;
        Inc(i);
        Continue;
      end;
      if s[i] = '''' then
      begin
        lString := not lString;
        if lActive then lOutput := lOutput + s[i];
        Inc(i);
        Continue;
      end;
      if not lString then
      begin
        if Copy(s, i, 2) = '//' then Break;
        if Copy(s, i, 2) = '{$' then
        begin
          j := i + 2;
          while (j <= Length(s)) and (s[j] <> '}') do Inc(j);
          if j > Length(s) then Reject('Unterminated compiler directive');
          lDirective := UpperCase(Trim(Copy(s, i + 2, j - i - 2)));
          lSpace := Pos(' ', lDirective);
          lCommand := lDirective;
          lArgument := '';
          if lSpace > 0 then
          begin
            lCommand := Copy(lDirective, 1, lSpace - 1);
            lArgument := Trim(Copy(lDirective, lSpace + 1, MaxInt));
          end;
          lDepth := Length(lStack);
          if (lCommand = 'IFDEF') or (lCommand = 'IFNDEF') then
          begin
            SetLength(lStack, lDepth + 1);
            lStack[lDepth].ParentActive := lActive;
            lStack[lDepth].Condition := GateDefined(lArgument);
            if lCommand = 'IFNDEF' then lStack[lDepth].Condition := not lStack[lDepth].Condition;
            lStack[lDepth].ElseSeen := False;
            lActive := lActive and lStack[lDepth].Condition;
          end else if lCommand = 'ELSE' then
          begin
            if (lDepth = 0) or (lArgument <> '') then Reject('Unmatched ELSE');
            if lStack[lDepth - 1].ElseSeen then Reject('Duplicate ELSE');
            lStack[lDepth - 1].ElseSeen := True;
            lActive := lStack[lDepth - 1].ParentActive and not lStack[lDepth - 1].Condition;
          end else if (lCommand = 'ENDIF') or (lCommand = 'IFEND') then
          begin
            if (lDepth = 0) or (lArgument <> '') then Reject('Unmatched ENDIF');
            lActive := lStack[lDepth - 1].ParentActive;
            SetLength(lStack, lDepth - 1);
          end else if StartsText('IF', lCommand) or (lCommand = 'ELSEIF') or
            (lCommand = 'DEFINE') or (lCommand = 'UNDEF') then
            Reject('Unsupported conditional directive ' + lDirective)
          else if ((lCommand = 'I') or (lCommand = 'INCLUDE')) and
            (lArgument <> 'MAXCRON.INC') then Reject('Unsupported declaration include ' + lArgument);
          i := j + 1;
          lOutput := lOutput + ' ';
          Continue;
        end;
        if Copy(s, i, 3) = '(*$' then Reject('Unsupported directive comment syntax');
        if (s[i] = '{') or (Copy(s, i, 2) = '(*') then
        begin
          if s[i] = '{' then lComment := 1
          else begin
            lComment := 2;
            Inc(i);
          end;
          lOutput := lOutput + ' ';
          Inc(i);
          Continue;
        end;
      end;
      if lActive then lOutput := lOutput + s[i];
      Inc(i);
    end;
    if lString then Reject('Unterminated string literal');
    aLines[gLine] := Trim(lOutput);
    if SameText(aLines[gLine], 'implementation') then
    begin
      if Length(lStack) <> 0 then Reject('Conditional crosses implementation boundary');
      Exit;
    end;
  end;
  Reject('Missing implementation boundary');
end;

function Identifier(const s: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  if (s = '') or not CharInSet(s[1], ['A'..'Z', 'a'..'z', '_']) then Exit;
  for i := 2 to Length(s) do
    if not CharInSet(s[i], ['A'..'Z', 'a'..'z', '_', '0'..'9']) then Exit;
  Result := True;
end;

function AttributeEnd(const s: string): Integer;
var
  i: Integer;
  lQuoted: Boolean;
begin
  lQuoted := False;
  for i := 2 to Length(s) do
  begin
    if s[i] = '''' then lQuoted := not lQuoted;
    if (s[i] = ']') and not lQuoted then Exit(i);
  end;
  Result := 0;
end;

function AttributeTokens(const s: string): string;
var
  i: Integer;
  lQuoted, lGap: Boolean;
  c, p: Char;
begin
  Result := '';
  lQuoted := False;
  lGap := False;
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if not lQuoted and CharInSet(c, [#9, #10, #13, ' ']) then
    begin
      lGap := True;
      Continue;
    end;
    if lGap and (Result <> '') then
    begin
      p := Result[Length(Result)];
      // Whitespace separates identifier tokens; it must not turn an invalid
      // "Test Fixture" into TestFixture, or merge separate string literals.
      if (CharInSet(p, ['A'..'Z', 'a'..'z', '_', '0'..'9']) and
        CharInSet(c, ['A'..'Z', 'a'..'z', '_', '0'..'9'])) or ((p = '''') and (c = '''')) then
        Result := Result + ' ';
    end;
    lGap := False;
    Result := Result + c;
    if c = '''' then lQuoted := not lQuoted;
  end;
end;

procedure TokenizeAttributes(aLines: TStringList);
var
  i, j, lEnd: Integer;
  s, lTokens: string;
begin
  i := 0;
  while i < aLines.Count do
  begin
    s := Trim(aLines[i]);
    if SameText(s, 'implementation') then Exit;
    if StartsText('[', s) then
    begin
      gLine := i;
      lTokens := '';
      j := i;
      while StartsText('[', s) do
      begin
        lEnd := AttributeEnd(s);
        while lEnd = 0 do
        begin
          Inc(j);
          if (j >= aLines.Count) or SameText(Trim(aLines[j]), 'implementation') then
            Reject('Unterminated attribute');
          s := s + ' ' + Trim(aLines[j]);
          aLines[j] := '';
          lEnd := AttributeEnd(s);
        end;
        lTokens := lTokens + AttributeTokens(Copy(s, 1, lEnd));
        s := Trim(Copy(s, lEnd + 1, MaxInt));
      end;
      aLines[i] := lTokens + ' ' + s;
      i := j;
    end;
    Inc(i);
  end;
end;

function UnconsumedAttribute(const s: string): Boolean;
var
  i: Integer;
  lQuoted: Boolean;
begin
  Result := False;
  lQuoted := False;
  for i := 1 to Length(s) do
  begin
    if s[i] = '''' then lQuoted := not lQuoted;
    if (s[i] = '[') and not lQuoted then Exit(True);
  end;
end;

procedure ScanUnit(const aRoot, aUnit: string);
var
  lLines, lCases, lNames: TStringList;
  s, lClass, lMethod, lParams, lCase, lValues, lDecl: string;
  lFixturePending, lTestPending, lFoundFixture: Boolean;
  i, j, lEnd, lPos, lStartCount, lUnitCount: Integer;
begin
  gFile := IncludeTrailingPathDelimiter(aRoot) + 'tests\unit\' + aUnit + '.pas';
  if aUnit = 'TestFpcShims' then
    gFile := IncludeTrailingPathDelimiter(aRoot) + 'tests\fpc\' + aUnit + '.pas';
  lLines := TStringList.Create;
  lCases := TStringList.Create;
  lNames := TStringList.Create;
  try
    lLines.LoadFromFile(gFile, TEncoding.UTF8);
    ActiveInterface(lLines);
    TokenizeAttributes(lLines);
    lClass := '';
    lFoundFixture := False;
    lFixturePending := False;
    lTestPending := False;
    lStartCount := 0;
    lUnitCount := gCount;
    gLine := 0;
    while gLine < lLines.Count do
    begin
      s := Trim(lLines[gLine]);
      if SameText(s, 'implementation') then Break;
      if s = '' then
      begin
        Inc(gLine);
        Continue;
      end;
      if StartsText('[TestFixture]', s) then
      begin
        if lFixturePending or (lClass <> '') then Reject('Nested/dangling fixture attribute');
        lFixturePending := True;
        s := Trim(Copy(s, Length('[TestFixture]') + 1, MaxInt));
      end;
      if lFixturePending and (s <> '') then
      begin
        lPos := Pos('=', s);
        if (lPos = 0) or not SameText(Trim(Copy(s, lPos + 1, MaxInt)), 'class') then
          Reject('Unsupported fixture declaration');
        lClass := Trim(Copy(s, 1, Pos('=', s) - 1));
        if not Identifier(lClass) then Reject('Invalid fixture identifier');
        Inc(gFixtures);
        lFoundFixture := True;
        lFixturePending := False;
        lStartCount := gCount;
        gDeclarations.Add('  gGeneratedFixture' + IntToStr(gFixtures) + ': ' + aUnit + '.' + lClass + ';');
        gRegistrations.Add('  gGeneratedFixture' + IntToStr(gFixtures) + ' := ' + aUnit + '.' + lClass + '.Create;');
        gRegistrations.Add('  RegisterFixture(gGeneratedFixture' + IntToStr(gFixtures) + ');');
      end else if lClass <> '' then
      begin
        while (Length(s) > 0) and (s[1] = '[') do
        begin
          lEnd := AttributeEnd(s);
          if lEnd = 0 then Reject('Unterminated attribute');
          lDecl := Copy(s, 1, lEnd);
          if SameText(lDecl, '[Test]') then lTestPending := True
          else if StartsText('[TestCase(', lDecl) then
          begin
            lPos := Length('[TestCase(') + 1;
            lCase := ReadLiteral(lDecl, lPos);
            while (lPos <= Length(lDecl)) and (lDecl[lPos] = ' ') do Inc(lPos);
            if (lPos > Length(lDecl)) or (lDecl[lPos] <> ',') then Reject('Expected case separator');
            Inc(lPos);
            lValues := ReadLiteral(lDecl, lPos);
            if Trim(Copy(lDecl, lPos, MaxInt)) <> ')]' then Reject('Unsupported TestCase arguments');
            lCases.Add(lValues);
            lNames.Add(lCase);
          end else Reject('Unsupported attribute ' + lDecl);
          s := Trim(Copy(s, lEnd + 1, MaxInt));
        end;
        if (s <> '') and (lTestPending or (lCases.Count > 0)) and not StartsText('procedure ', s) then
          Reject('Unsupported test declaration');
        if StartsText('procedure ', s) and (lTestPending or (lCases.Count > 0)) then
        begin
          while (s <> '') and (s[Length(s)] <> ';') do
          begin
            Inc(gLine);
            if gLine >= lLines.Count then Reject('Unterminated method');
            s := s + ' ' + Trim(lLines[gLine]);
          end;
          lDecl := Trim(Copy(s, Length('procedure ') + 1, MaxInt));
          i := Pos('(', lDecl);
          lParams := '';
          if i = 0 then lMethod := Trim(Copy(lDecl, 1, Pos(';', lDecl) - 1))
          else begin
            lMethod := Trim(Copy(lDecl, 1, i - 1));
            j := Pos(')', lDecl);
            if j = 0 then Reject('Unterminated parameters');
            lParams := Copy(lDecl, i + 1, j - i - 1);
            if Trim(Copy(lDecl, j + 1, MaxInt)) <> ';' then Reject('Unsupported method suffix');
          end;
          if not Identifier(lMethod) then Reject('Unsupported test method identifier');
          if (i = 0) and (Trim(Copy(lDecl, Pos(';', lDecl), MaxInt)) <> ';') then
            Reject('Unsupported method suffix');
          if lCases.Count = 0 then
          begin
            if lParams <> '' then Reject('Parameterized test has no cases');
            Emit(aUnit, lClass, lMethod, '', '');
          end else
            for i := 0 to lCases.Count - 1 do
              Emit(aUnit, lClass, lMethod, lNames[i], Arguments(lParams, lCases[i]));
          lTestPending := False;
          lCases.Clear;
          lNames.Clear;
        end else if s = 'end;' then
        begin
          if lTestPending or (lCases.Count > 0) then Reject('Dangling test attribute');
          if gCount = lStartCount then Reject('Fixture has no tests');
          lClass := '';
        end;
      end;
      if UnconsumedAttribute(s) then Reject('Unconsumed attribute construct');
      Inc(gLine);
    end;
    if not lFoundFixture or (gCount = lUnitCount) then Reject('Listed unit has no fixture/tests');
    if lFixturePending or lTestPending or (lCases.Count > 0) or (lClass <> '') then
      Reject('Unparsed fixture/test declaration');
  finally
    lNames.Free;
    lCases.Free;
    lLines.Free;
  end;
end;

procedure Generate;
var
  s: string;
  lOutput: TStringList;
begin
  if ParamCount <> 2 then raise Exception.Create('Usage: maxCronFpcRegistryGen <repo> <output.inc>');
  gDeclarations := TStringList.Create;
  gBodies := TStringList.Create;
  gRegistrations := TStringList.Create;
  lOutput := TStringList.Create;
  try
    for s in cUnits do ScanUnit(ParamStr(1), s);
    lOutput.Add('// Generated from fixture declarations. Do not edit.');
    lOutput.Add('const cGeneratedTestCount = ' + IntToStr(gCount) + ';');
    lOutput.Add('var');
    lOutput.AddStrings(gDeclarations);
    lOutput.AddStrings(gBodies);
    lOutput.Add('procedure RegisterGeneratedTests;');
    lOutput.Add('begin');
    lOutput.AddStrings(gRegistrations);
    lOutput.Add('end;');
    lOutput.SaveToFile(ParamStr(2), TEncoding.UTF8);
    WriteLn('Generated ', gCount, ' tests in ', gFixtures, ' fixtures');
  finally
    lOutput.Free;
    gRegistrations.Free;
    gBodies.Free;
    gDeclarations.Free;
  end;
end;

begin
  try
    Generate;
  except
    on E: Exception do
    begin
      WriteLn(string(E.Message));
      ExitCode := 3;
    end;
  end;
end.

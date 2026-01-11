unit maxCronHlpDlg;

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.ShellAPI, System.SysUtils, System.Variants, System.Classes,
  System.IOUtils,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls;

type
  TChronHelpDlg = class(TForm)
    edHTML: TMemo;
    btnOpenInBrowser: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnOpenInBrowserClick(Sender: TObject);
  private
    fHTMLFileName: string;
    procedure OpenInBrowser;
  public
    { Public declarations }
  end;

Procedure ShowmaxChronHelp;

implementation

uses
  System.SysUtils;

{$R *.dfm}


procedure TChronHelpDlg.FormCreate(Sender: TObject);
begin
  fHTMLFileName := TPath.Combine(TPath.GetTempPath, Self.ClassName + IntToStr(GetTickCount) + '.html');
  edHTML.Lines.SaveToFile(fHTMLFileName);
  edHTML.ReadOnly := True;
  OpenInBrowser;
end;

procedure TChronHelpDlg.FormDestroy(Sender: TObject);
begin
  if fileExists(fHTMLFileName) then
    deleteFile(fHTMLFileName);
end;

procedure TChronHelpDlg.btnOpenInBrowserClick(Sender: TObject);
begin
  OpenInBrowser;
end;

procedure TChronHelpDlg.OpenInBrowser;
var
  lResult: HINST;
begin
  if fHTMLFileName = '' then
    Exit;
  lResult := ShellExecute(Handle, 'open', PChar(fHTMLFileName), nil, nil, SW_SHOWNORMAL);
  if lResult <= 32 then
    raise Exception.CreateFmt('Failed to open browser for "%s" (ShellExecute code %d).', [fHTMLFileName, NativeInt(lResult)]);
end;

Procedure ShowmaxChronHelp;
begin
  with TChronHelpDlg.Create(nil) do
  begin
    showmodal;
    Free;
  end;
end;

end.

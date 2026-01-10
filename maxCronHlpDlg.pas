unit maxCronHlpDlg;

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.ShellAPI, System.SysUtils, System.Variants, System.Classes,
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
  jclSysInfo;

{$R *.dfm}


procedure TChronHelpDlg.FormCreate(Sender: TObject);
begin
  fHTMLFileName := jclSysInfo.GetWindowsTempFolder + self.ClassName + IntToStr(GetTickCount) + '.html';
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
begin
  if fHTMLFileName = '' then
    Exit;
  ShellExecute(Handle, 'open', PChar(fHTMLFileName), nil, nil, SW_SHOWNORMAL);
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

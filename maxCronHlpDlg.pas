unit maxCronHlpDlg;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.OleCtrls, SHDocVw, Vcl.StdCtrls;

type
  TChronHelpDlg = class(TForm)
    WebBrowser1: TWebBrowser;
    edHTML: TMemo;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    fHTMLFileName: string;
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
  edHTML.Lines.SaveToFile(fHTMLFileName);;
  WebBrowser1.Align := alClient;
  WebBrowser1.Navigate(fHTMLFileName);
end;

procedure TChronHelpDlg.FormDestroy(Sender: TObject);
begin
  if fileExists(fHTMLFileName) then
    deleteFile(fHTMLFileName);
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

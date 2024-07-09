unit Main;

{$I lape.inc}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs,
  StdCtrls, ExtCtrls, SynEdit, SynGutter, SynHighlighterPas,
  lptypes, lpvartypes;

type
  TForm1 = class(TForm)
    btnRun: TButton;
    btnDisassemble: TButton;
    ButtonBench: TButton;
    e: TSynEdit;
    m: TMemo;
    pnlTop: TPanel;
    Splitter1: TSplitter;
    PasSyn: TSynFreePascalSyn;

    procedure btnDisassembleClick(Sender: TObject);
    procedure btnRunClick(Sender: TObject);
    procedure ButtonBenchClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  private
    procedure WriteHint(Sender: TLapeCompilerBase; Msg: lpString);
  end;

var
  Form1: TForm1;

implementation

uses
  {$IFDEF WINDOWS}
  Windows,
  {$ENDIF}
  lpparser, lpcompiler, lputils, lpeval, lpinterpreter, lpdisassembler, lpmessages, lpffi, ffi;

{$R *.lfm}

function HighResolutionTime: Double;
{$IFDEF WINDOWS}
var
  Frequency: Int64 = 0;
  Count: Int64 = 0;
begin
  QueryPerformanceFrequency(Frequency);
  QueryPerformanceCounter(Count);

  Result := Count / Frequency * 1000;
end;
{$ELSE}
begin
  Result := GetTickCount64();
end;
{$ENDIF}

procedure MyWrite(const Params: PParamArray); {$IFDEF Lape_CDECL}cdecl;{$ENDIF}
begin
  with TForm1(Params^[0]) do
    m.Text := m.Text + {$IF DEFINED(Lape_Unicode)}UTF8Encode(PlpString(Params^[1])^){$ELSE}PlpString(Params^[1])^{$IFEND};
  Write(PlpString(Params^[1])^);
end;

procedure MyWriteLn(const Params: PParamArray); {$IFDEF Lape_CDECL}cdecl;{$ENDIF}
begin
  with TForm1(Params^[0]) do
    m.Text := m.Text + LineEnding;
  WriteLn();
end;

procedure Compile(Run, Disassemble: Boolean);
var
  t: Double;
  Parser: TLapeTokenizerBase;
  Compiler: TLapeCompiler;
begin
  Parser := nil;
  Compiler := nil;
  with Form1 do
  try
    Parser := TLapeTokenizerString.Create({$IF DEFINED(Lape_Unicode)}UTF8Decode(e.Lines.Text){$ELSE}e.Lines.Text{$IFEND});
    Compiler := TLapeCompiler.Create(Parser);
    Compiler.OnHint := @WriteHint;

    InitializeFFI(Compiler);
    InitializePascalScriptBasics(Compiler, [psiTypeAlias]);

    Compiler.addGlobalMethod('procedure _Write(s: string); override;', @MyWrite, Form1);
    Compiler.addGlobalMethod('procedure _WriteLn; override;', @MyWriteLn, Form1);

    try
      t := HighResolutionTime();
      if Compiler.Compile() then
        m.Lines.Add('Compiling Time: ' + IntToStr(Round(HighResolutionTime() - t)) + 'ms.')
      else
        m.Lines.Add('Error!');
    except
      on E: Exception do
      begin
        m.Lines.Add('Compilation error: "' + E.Message + '"');
        Exit;
      end;
    end;

    try
      if Disassemble then
        DisassembleCode(Compiler.Emitter.Code, [Compiler.ManagedDeclarations.GetByClass(TLapeGlobalVar, bTrue), Compiler.GlobalDeclarations.GetByClass(TLapeGlobalVar, bTrue)]);

      if Run then
      begin
        t := HighResolutionTime();

        with TLapeCodeRunner.Create(Compiler.Emitter) do
        try
          Run();
        finally
          Free();
        end;

        m.Lines.Add('Running Time: ' + IntToStr(Round(HighResolutionTime - t)) + 'ms.');
      end;
    except
      on E: lpException do
      begin
        m.Lines.Add(E.Message);
        if (E.StackTrace <> '') then
          m.Lines.Add(E.StackTrace);
      end;
      on E: Exception do
        m.Lines.Add(E.Message);
    end;
  finally
    if (Compiler <> nil) then
      Compiler.Free()
    else if (Parser <> nil) then
      Parser.Free();
  end;
end;

procedure TForm1.btnRunClick(Sender: TObject);
begin
  Compile(True, False);
end;

procedure TForm1.ButtonBenchClick(Sender: TObject);
begin
  e.Text := ReadFileToString('tests/bench.inc');
  e.Update();

  Compile(True, False);
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  if Screen.Fonts.IndexOf('Cascadia Mono SemiLight') > -1 then
  begin
    e.Font.Name := 'Cascadia Mono SemiLight';
    e.Font.Size := 11;
  end;

  e.Gutter.LineNumberPart().MarkupInfo.Background := clNone;
  e.Gutter.SeparatorPart().MarkupInfo.Background := clNone;
  e.Gutter.ChangesPart().Free();
  e.Gutter.CodeFoldPart().Free();
  e.Gutter.RightOffset := Scale96ToScreen(5);
end;

procedure TForm1.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_R) and (Shift = [ssAlt]) then
  begin
    Key := 0;

    btnRun.Click();
  end;
end;

procedure TForm1.WriteHint(Sender: TLapeCompilerBase; Msg: lpString);
begin
  m.Lines.Add(Msg);
end;

procedure TForm1.btnDisassembleClick(Sender: TObject);
begin
  Compile(True, True);
end;

{$IF DEFINED(MSWINDOWS) AND DECLARED(LoadFFI)}
initialization
  if (not FFILoaded()) then
    LoadFFI(
    {$IFDEF Win32}
    'extensions\ffi\bin\win32'
    {$ELSE}
    'extensions\ffi\bin\win64'
    {$ENDIF}
    );
{$ENDIF}
end.


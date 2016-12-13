unit Unit1;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls;


const
  MAX_BUF = 512;
  verSocks4 = 4;
  verSocks5 = 5;
  cmdConnect = 1;
  cmdBind = 2;

  verReply = 0;
  resGranted = 90;
  resRejectedFailed = 91;
  resRejectedIdentD = 92;
  resRejectedIdentDUserIDMismatch = 93;


type
  TForm1 = class(TForm)
    Label1: TLabel;
    Label2: TLabel;
    procedure FormCreate(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

  TBuffer = array [0..MAX_BUF - 1] of Char;
  PProxyParts = ^TProxyParts;
  TProxyParts = record
    Client: Integer;
    Target: Integer;
    Handle: Cardinal;
  end;

  IPAddress = record
    A: Byte;
    B: Byte;
    C: Byte;
    D: Byte;
  end;

  SocksPacket = record
    VersionNumber: Byte;
    Command: Byte;
    DestinationPortH: Byte;
    DestinationPortL: Byte;
    DestinationIP: IPAddress;
  end;

  SocksData = record
    VersionNumber: Integer;
    Command: Integer;
    DestinationPort: Integer;
    DestinationIP: String;
    UserID: String;
  end;

var
  Form1: TForm1;

implementation

uses  TcpSocket;

{$R *.dfm}

function TargetThreadProc(ProxyPtr: PProxyParts): Integer;
var
  Buf: TBuffer;
  R: Integer;
begin
  while True do
  begin
    R := ReceiveBuffer(ProxyPtr^.Target, Buf, SizeOf(Buf));
    if R = 0 then
      Break;
    R := SendBuffer(ProxyPtr^.Client, Buf, R);
    if R = 0 then
      Break;
  end;
  Disconnect(ProxyPtr^.Target);
  Disconnect(ProxyPtr^.Client);
  CloseHandle(ProxyPtr^.Handle);
  Dispose(ProxyPtr);
  Result := 0;
  EndThread(Result);
end;

procedure OnClientConnect(Client: Integer; Port: Integer; IP: string);
var
  Buf: TBuffer;
  ID: Cardinal;
  Target, R: Integer;
  ProxyPtr: PProxyParts;
  Packet: SocksPacket;
  Data: SocksData;
begin
// Receive the first identifier packet for socks
  ReceiveBuffer(Client, Packet, SizeOf(SocksPacket));
// Receive a user id if supplied
  Data.UserID := ReceiveLine(Client);
  Data.VersionNumber := Packet.VersionNumber;
  Data.Command := Packet.Command;
  Data.DestinationPort := (Packet.DestinationPortH * $100) + Packet.DestinationPortL;
  Data.DestinationIP := IntToStr(Packet.DestinationIP.A) + '.' + IntToStr(Packet.DestinationIP.B) + '.' + IntToStr(Packet.DestinationIP.C) + '.' + IntToStr(Packet.DestinationIP.D);

// Is it socks 4?
  if Data.VersionNumber = verSocks4 then
   begin
// Has CONNECT been requested?
    if Data.Command = cmdConnect then
     begin
      Packet.VersionNumber := verReply;
      Packet.Command := resGranted;
// Send back granted reply
      SendBuffer(Client, Packet, SizeOf(Packet));
      Target := Connect(Data.DestinationIP, Data.DestinationPort);
      if Target = 0 then Exit;
      New(ProxyPtr);
      ProxyPtr^.Client := Client;
      ProxyPtr^.Target := Target;
// Create a new thread based on a procedure to relay one direction
      ProxyPtr^.Handle := BeginThread(nil, 0, @TargetThreadProc, ProxyPtr, 0, ID);
// Use the current thread to relay the other direction
      while True do
       begin
        R := ReceiveBuffer(Client, Buf, SizeOf(Buf));
        if R = 0 then Break;
        R := SendBuffer(Target, Buf, R);
        if R = 0 then Break;
       end;
      Disconnect(Target);
      Disconnect(Client);
     end
    else
     begin
// Bad request packet received so tell the whore
      Packet.VersionNumber := verReply;
      Packet.Command := resRejectedFailed;
      SendBuffer(Client, Packet, SizeOf(Packet));
     end;
   end
  else
   begin
//Shit connection altogether, dump the bitch
    Disconnect(Client);
   end;
end;


procedure TForm1.FormCreate(Sender: TObject);
begin
  CreateServer(9000, OnClientConnect, False);
end;

end.

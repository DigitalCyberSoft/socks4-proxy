unit TcpSocket;

interface

uses
  Windows, WinSock;

{$H+}

type
  TAcceptProc = procedure(Client: Integer; Port: Integer; IP: string);

function CreateServer(Port: Integer; AcceptProc: TAcceptProc;
  Blocking: Boolean = True): Integer;
function Connect(HostName: string; Port: Integer): Integer;
function Connected(Socket: Integer): Boolean;
function Readable(Socket: Integer): Boolean;
function LookupHostAddr(const Host: string): string;
function SendBuffer(Socket: Integer; var Buf; Len: Cardinal): Integer;
function SendLn(Socket: Integer; S: string): Integer;
function Send(Socket: Integer; S: string): Integer;
function PeekBuffer(Socket: TSocket; var Buf; BufSize: Integer): Integer;
function ReceiveBuffer(Socket: Integer; var Buf; BufSize: Integer): Integer;
function Receiveln(Socket: Integer; EOL: string = #13#10): string;
function ReceiveLine(Socket: TSocket): string;
procedure Disconnect(Socket: Integer);
function IntToStr(N: Integer): string;
function StrToInt(S: string): Integer;

implementation

function NewTcpSocket: TSocket;
begin
  Result := Socket(PF_INET, SOCK_STREAM, IPPROTO_IP);
end;

function IntToStr(N: Integer): string;
begin
  Str(N, Result);
end;

function LookupHostAddr(const Host: string): string;
var
  h: PHostEnt;
begin
  Result := '';
  if Host <> '' then
  begin
    if Host[1] in ['0'..'9'] then
    begin
      if inet_addr(pchar(Host)) <> INADDR_NONE then
        Result := Host;
    end
    else
    begin
      h := gethostbyname(pchar(Host));
      if h <> nil then
        with h^ do
        Result := IntToStr(ord(h_addr^[0])) + '.' + IntToStr(ord(h_addr^[1])) + '.' +
            IntToStr(ord(h_addr^[2])) + '.' + IntToStr(ord(h_addr^[3]));
    end;
  end
  else Result := '0.0.0.0';
end;

function StrToInt(S: string): Integer;
var
  E: Integer;
begin
  Val(S, Result, E);
end;
       
function LookupPort(const sn: string; pn: pchar = nil): Word;
var
  se: PServent;
begin
  Result := 0;
  if sn <> '' then
  begin
    se := GetServbyName(pchar(sn), pn);
    if se <> nil then
      Result := ntohs(se^.s_port)
    else
      Result := StrToInt(sn);
  end;
end;  

function GetSocketAddr(H: string; P: Cardinal): TSockAddr;
begin
  Result.sin_family := AF_INET;
  Result.sin_addr.s_addr := inet_addr(pchar(LookupHostAddr(h)));
  Result.sin_port := htons(LookupPort(IntTostr(p)));
end;

function Connect(HostName: string; Port: Integer): TSocket;
var
  Addr: TSockAddr;
begin
  Result := NewTcpSocket;
  if Result = INVALID_SOCKET then
  begin
    Result := 0;
    Exit;
  end;
  Addr := GetSocketAddr(HostName, Port);
  if WinSock.Connect(Result, Addr, SizeOf(Addr)) = INVALID_SOCKET then
  begin
    CloseSocket(Result);
    Result := 0;
  end;
end;

function Connected(Socket: TSocket): Boolean;
var
  tmp: Char;
begin
  Result := (PeekBuffer(Socket, tmp, 1) > 0) and (WSAGetLastError = 0);
  if not Result then
    WSASetLastError(0);
end;

function Readable(Socket: Integer): Boolean;
var
  ReadFds: TFDset;
  ReadFdsptr: PFDset;
  tv: TimeVal;
  Timeptr: PTimeVal;
begin
  tv.tv_sec := 0;
  tv.tv_usec := 0;
  Timeptr := @tv;
  FD_ZERO(ReadFds);                  
  FD_SET(Socket, ReadFds);
  ReadFdsptr := @ReadFds;
  Result := (select(0, ReadFdsptr, nil, nil, Timeptr) > 0);
end;

procedure Disconnect(Socket: TSocket);
begin
  ShutDown(Socket, SD_BOTH);
  CloseSocket(Socket);
end;

function SendBuffer(Socket: TSocket; var Buf; Len: Cardinal): Integer;
begin
  if (Len = 0) or (PChar(Buf) = nil) then
    Result := 0
  else
    begin
      Result := WinSock.Send(Socket, Buf, Len, 0);
      if Result = SOCKET_ERROR then
        Result := 0;
    end;
end;

function SendLn(Socket: TSocket; S: string): Integer;
begin
  S := S + #13#10;
  Result := SendBuffer(Socket, PChar(S)^, Length(S));
end;

function Send(Socket: TSocket; S: string): Integer;
begin
  Result := SendBuffer(Socket, PChar(S)^, Length(S));
end;

function ReceiveBuffer(Socket: TSocket ;var Buf; BufSize: Integer): Integer;
begin
  Result := Recv(Socket, Buf, BufSize, 0);
  if Result = SOCKET_ERROR then
    Result := 0;
end;

function PeekBuffer(Socket: TSocket; var Buf; BufSize: Integer): Integer;
begin
  Result := Recv(Socket, buf, bufsize, MSG_PEEK);
  if Result = SOCKET_ERROR then
    Result := 0;
end;

function StrPos(const Str1, Str2: PChar): PChar; assembler;
asm
        PUSH    EDI
        PUSH    ESI
        PUSH    EBX
        OR      EAX,EAX
        JE      @@2
        OR      EDX,EDX
        JE      @@2
        MOV     EBX,EAX
        MOV     EDI,EDX
        XOR     AL,AL
        MOV     ECX,0FFFFFFFFH
        REPNE   SCASB
        NOT     ECX
        DEC     ECX
        JE      @@2
        MOV     ESI,ECX
        MOV     EDI,EBX
        MOV     ECX,0FFFFFFFFH
        REPNE   SCASB
        NOT     ECX
        SUB     ECX,ESI
        JBE     @@2
        MOV     EDI,EBX
        LEA     EBX,[ESI-1]
@@1:    MOV     ESI,EDX
        LODSB
        REPNE   SCASB
        JNE     @@2
        MOV     EAX,ECX
        PUSH    EDI
        MOV     ECX,EBX
        REPE    CMPSB
        POP     EDI
        MOV     ECX,EAX
        JNE     @@1
        LEA     EAX,[EDI-1]
        JMP     @@3
@@2:    XOR     EAX,EAX
@@3:    POP     EBX
        POP     ESI
        POP     EDI
end;

function ReceiveLine(Socket: TSocket): string;
var
  len, nullindex: Integer;
  buf: array[0..511] of char;
  function GetNullIndex(): Integer;
  begin
    for Result := 0 to Len - 1 do
    begin
      if buf[Result] = #0 then
        Exit;
    end;
    Result := -1;
  end;
begin
  Result := '';
  nullindex := -1;
  repeat
    len := PeekBuffer(Socket, buf, sizeof(buf) - 1);
    if len > 0 then
    begin
      nullindex := GetNullIndex();
      ReceiveBuffer(Socket, buf, nullindex + 1);
      Result := Result + buf;
    end;
  until (len < 1) or (nullindex >= 0);
end;

function Receiveln(Socket: TSocket; EOL: string): string;
var
  len: Integer;
  buf: array[0..511] of char;
  eolptr: pchar;
  i: integer;
begin
  Result := '';
  eolptr := nil;
  repeat
    len := PeekBuffer(Socket, buf, sizeof(buf) - 1);
    if len > 0 then
    begin
      buf[len] := #0;
      eolptr := strpos(buf, pchar(EOL));
      if eolptr <> nil then
        len := eolptr - buf + length(EOL);
      ReceiveBuffer(Socket, buf, len);
      if eolptr <> nil then
        len := len - length(EOL);
      buf[len] := #0;
      Result := Result + buf;
    end;
  until (len < 1) or (eolptr <> nil);
end;

type
  PData = ^TData;
  TData = record
    Client: TSocket;
    Port: Integer;
    IP: string;
    Proc: TAcceptProc;
    ThreadHandle: Cardinal;
  end;

  PAccept = ^TAccept;
  TAccept = record
    Srv: Integer;
    Port: Integer;
    AcceptProc: TAcceptProc;
    ThreadHandle: Cardinal;
  end;

function TcpClientThread(DataPtr: PData): Integer;
begin
  Result := 0;
  with DataPtr^ do
  try
    Proc(Client, Port, IP);
  finally
    CloseHandle(ThreadHandle);
    Disconnect(Client);
    Dispose(DataPtr);
  end;
  EndThread(Result);
end;

procedure doAccept(Srv: TSocket; P: Integer; AcceptProc: TAcceptProc);
var
  Cli, Len: Integer;
  ID: Cardinal;
  addr: TSockAddr;
  DataPtr: PData;
begin
  Len := SizeOf(addr);
  repeat
    Cli := WinSock.accept(Srv, @addr, @Len);
    if Cli = SOCKET_ERROR then
      Break;
    New(DataPtr);
    with DataPtr^ do
    begin
      Client := Cli;
      Port := P;
      IP := inet_ntoa(addr.sin_addr);
      Proc := AcceptProc;
      ThreadHandle := BeginThread(nil, 0, @TcpClientThread, DataPtr, 0, ID);
    end;
  until False;
  Disconnect(Srv);
end;

function TcpServerThread(AcceptPtr: PAccept): Integer;
begin
  Result := 0;
  with AcceptPtr^ do
  try
    if Assigned(AcceptPtr) and Assigned(AcceptProc) and (Srv <> 0) then
      doAccept(Srv, Port, AcceptProc);
  finally
    CloseHandle(ThreadHandle);
    Dispose(AcceptPtr);
    EndThread(Result);
  end;
end;

procedure Accept(Server: TSocket; P: Integer; Proc: TAcceptProc; Blocking: Boolean);
var
  AcceptData: PAccept;
  ID: Cardinal;
begin
  if Blocking then
  begin
    doAccept(Server, P, Proc);
  end
  else
  begin
    New(AcceptData);
    with AcceptData^ do
    begin
      Srv := Server;
      Port := P;
      AcceptProc := Proc;
      ThreadHandle := BeginThread(nil, 0, @TcpServerThread, AcceptData, 0, ID);
    end;
  end;
end;

function Listen(Port: Integer): Integer;
var
  addr: TSockAddr;
begin
  Result := NewTcpSocket;
  if Result = INVALID_SOCKET then
  begin 
    Result := 0;
    Exit;
  end;
  Addr := GetSocketAddr('', Port);
  if WinSock.bind(Result, addr, sizeof(addr)) <> 0 then
  begin
    CloseSocket(Result);
    Result := 0;
    Exit;
  end;
  if WinSock.listen(Result, SOMAXCONN) = SOCKET_ERROR then
  begin
    CloseSocket(Result);
    Result := 0;
  end;
end;

function CreateServer(Port: Integer; AcceptProc: TAcceptProc; Blocking: Boolean): Integer;
begin
  Result := Listen(Port);
  Accept(Result, Port, AcceptProc, Blocking);
end;

var
  WSAData: TWSAData;

initialization
  WSAStartup($0101, WSAData); // Winsock version 1.1

finalization
  WSACleanup;

end.

function [ passfail ] = test_tcp_server
% Function to test tcp_server.

args = { 'debug', 1 };

n_tests  = 7;
passfail = zeros(1,n_tests);
for i=1:n_tests
  fprintf( '\nITEST = %i\n\n', i )

  try
    feval( ['test',num2str(i)], args{:} );
    passfail(i) = 1;
  catch
    lasterr
    % stop
  end
end


beep();
if( ~all(passfail) )
  pause(0.3)
  beep();
  pause(0.3)
  beep();
end


%------------------------------------------------------------------------------%

% Test 1. Initialize and close.
function test1( varargin )
tcp   = tcp_server( 'initialize', varargin{:} );

tcp   = tcp_server( 'close' );
assert( tcp==0 )

tcp   = tcp_server();
assert( isempty(tcp) )


% Test 2. Initialize, re-initalize, and close.
function test2( varargin )
tcp   = tcp_server( 'initialize', varargin{:} );
tcp   = tcp_server();
port0 = tcp.port;

tcp   = tcp_server( 'initialize', varargin{:} );
tcp   = tcp_server();
port1 = tcp.port;

tcp   = tcp_server( 'close' );
assert( tcp==0 & port0==port1 )

tcp   = tcp_server();
assert( isempty(tcp) )


% Test 3. Initialize, (clear), re-initalize, and close.
function test3( varargin )
tcp   = tcp_server( 'initialize', varargin{:} );
tcp   = tcp_server();
port0 = tcp.port;
s     = tcp.server_socket;

munlock tcp_server
clear tcp_server
tcp   = tcp_server( 'initialize', varargin{:} );
tcp   = tcp_server();
port1 = tcp.port;

tcp   = tcp_server( 'close' );
assert( tcp==0 & port0<port1 )

tcp   = tcp_server();
assert( isempty(tcp) )
s.close();


% Test 4. Initialize, accept connection, and close.
function test4( varargin )
tcp = tcp_server( 'initialize', varargin{:} );
tcp = tcp_server();
s   = tcp.server_socket;
c   = javaObject( 'java.net.Socket', s.getInetAddress(), s.getLocalPort() );

tcp = tcp_server( 'accept' );
c.close();

tcp = tcp_server();
assert( isfield(tcp,'socket') )

tcp = tcp_server( 'close' );
assert( tcp==0 )


% Test 5. Initialize, accept connection, receive message, and close.
function test5( varargin )
tcp = tcp_server( 'initialize', varargin{:} );
tcp = tcp_server();
s = tcp.server_socket;
c = javaObject( 'java.net.Socket', s.getInetAddress(), s.getLocalPort() );

tcp = tcp_server( 'accept' );

msg = int8('socket-test-message');
c.getOutputStream().write( msg, 0, length(msg) );
c.getOutputStream().flush();
data = tcp_server( 'receive' );
c.close();

assert( isequal(msg,data) )
tcp = tcp_server( 'close' );
assert( tcp==0 )


% Test 6. Initialize, accept connection, send message, and close.
function test6( varargin )
tcp = tcp_server( 'initialize', varargin{:} );
tcp = tcp_server();
s = tcp.server_socket;
c = javaObject( 'java.net.Socket', s.getInetAddress(), s.getLocalPort() );

tcp = tcp_server( 'accept' );

msg = int8('socket-test-message');
tcp = tcp_server( 'send', msg );
inputStream = c.getInputStream();
n = inputStream.available();
for i=1:n
  data(i) = inputStream.read();
end
c.close();

assert( isequal(msg,data) )
tcp = tcp_server( 'close' );
assert( tcp==0 )


% Test 7. Accept timeout.
function test7( varargin )

tcp = tcp_server( 'initialize', varargin{:}, 'timeout', 500 );

tcp = tcp_server( 'accept' );
assert( tcp==-1 )

tcp = tcp_server();
s   = tcp.server_socket;
c   = javaObject( 'java.net.Socket', s.getInetAddress(), s.getLocalPort() );

tcp = tcp_server( 'accept' );
c.close();
assert( tcp==0 )

tcp = tcp_server( 'close' );
assert( tcp==0 )


%------------------------------------------------------------------------------%
function [ stat ] = l_browser( addr )

try
  if( ~exist( 'OCTAVE_VERSION', 'builtin' ) )
    stat = web( addr, '-browser' );
  else
    if( ispc )
      stat = dos( ['cmd.exe /c rundll32  url.dll,FileProtocolHandler "',addr,'"'] );
    elseif( isunix )
      try
        status = unix( ['xdg-open ',addr] );
      catch
        status = unix( ['gnome-open ',addr] );
      end
    elseif( ismac )
      unix( ['open ',addr] );
    end
  end
catch
  stat = -1;
end
if( stat~=0 )
  warning(['Failed to automatically open browser, please manually open:',char(10),char(10),addr,char(10)])
end

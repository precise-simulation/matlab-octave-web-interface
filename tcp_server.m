function [ out ] = tcp_server( action, varargin )
%TCP_SERVER TCP Server control function.
%
%   [ OUT ] = TCP_SERVER( ACTION, ARG ) Sets up and controls
%   a TCP server in Matlab and Octave. ACTION specifies one
%   of INITIALIZE, ACCEPT, RECEIVE, SEND, or CLOSE operations.
%   The optional output OUT argument is indicates success 0,
%   failure -1, or the read DATA for the RECEIVE action. The
%   TCP data struct is returned when TCP_SERVER is called
%   without any input arguments.
%
%   The INITIALIZE action accepts the following ARG
%   property/value pairs.
%
%       Property    Value/{Default}           Description
%       -----------------------------------------------------------------------------------
%       port         scalar (2)/{[4000 inf]}  Port or range to establish server connection.
%       timeout      scalar/{1000}            Accept/read socket [ms] timeout limit.
%       fid          scalar/{1}               Output log file identifstat.
%       debug        scalar/{0}               Debug message level (0/1/2).
%
%  The SEND action accepts the DATA to send as second
%  input argument.

% Copyright 2013-2017 Precise Simulation, Ltd.
mlock
if( ~(nargin || nargout) ),help tcp_server, return, end

if( nargout && ~nargin )
  out = tcp_get_set();
  return
end


if( ischar(action) )
  action = find(strncmpi( action, ...
             {'initialize','accept','receive','send','close','read','write'}, 4 ));
end

out = -1;
switch( action )

  case 1       % Initialize.

    out = tcp_initialize( varargin{:} );

  case 2       % Accept.
    out = tcp_accept();

  case {3,6}   % Receive/read.
    out = tcp_receive();

  case {4,7}   % Send/write.
    out = tcp_send( varargin{:} );

  case 5       % Close.
    out = tcp_close();

  otherwise
    error( 'Unknown TCP action/operation.' )
end


if( ~nargout )
  clear out;
end


%------------------------------------------------------------------------------%
function [ stat ] = tcp_initialize( varargin )
% Initialize and open TCP socket.

try
  tmp = javaObject('java.lang.String');
  assert( isa(tmp,'java.lang.String') )
catch
  error( 'tcp_server:initialize', ...
         'Java not found. Please install and enable Java. ' )
end

% Set up initial TCP parameters.
tcp = tcp_configure( varargin{:} );


% Attempt to open socket.
stat = -1;
while( tcp.port(1)<=tcp.port(2) )

  try
    server_socket = javaObject( 'java.net.ServerSocket', tcp.port(1) );
    stat = 0;
    break;
  catch
    % Try another port in valid range.
    tcp.port(1) = tcp.port(1) + 1;
  end

end
if( stat~=0 )
  error( 'tcp_server:initialize', ...
         sprintf('Failed to open server on port %i.', tcp.port(1) ) )
  % Possible reasons: "port is still open by Octave/Matlab for
  % instance due to an previous crash", "Blocked by Firewall
  % application", "Port open in another Application", "No rights to
  % open the port"
end
assert( ~server_socket.isClosed() )


% Sucessfully opened socket and established connection.
server_socket.setSoTimeout( tcp.timeout );
tcp.port = tcp.port(1);
tcp.server_socket = server_socket;

if( tcp.debug )
  fprintf( tcp.fid, 'Server sucessfully openened on port %i.\n', tcp.port );
end

tcp_get_set( tcp );


%------------------------------------------------------------------------------%
function [ tcp ] = tcp_configure( varargin )
% Setup and parse input parameters.

NRANGE = 20;


% Try to close socket if it exists and is open on port.
tcp = tcp_get_set();
if( ~isempty(tcp) && isfield(tcp,'server_socket') && ...
    isa(tcp.server_socket,'java.net.ServerSocket') && ...
    tcp.server_socket.getLocalPort()==tcp.port(1) && ...
    ~tcp.server_socket.isClosed() )
  tcp.server_socket.close();
end
tcp = [];


% Default parameters.
tcp.port    = [4000 inf];
tcp.timeout = 1000;
tcp.fid     = 1;
tcp.debug   = 0;


% Parse configuration.
config = varargin;
if( ~isempty(config) )
  if( iscell(config) )
    config = cell2struct( config(2:2:end), config(1:2:end-1), 2 );
  end
  for s_field=fieldnames(config)'
    tcp.(s_field{1}) = config.(s_field{1});
  end
end
if( ~length(tcp.port~=2) )
  tcp.port = tcp.port([1 1]);
end


%------------------------------------------------------------------------------%
function [ stat ] = tcp_accept()
% Callback function to accept socket connection.

tcp = tcp_get_set();
stat = -1;
if( tcp.debug>1 )
  fprintf( tcp.fid, 'Running tcp_accept callback.\n' );
end

try
  socket = tcp.server_socket.accept();

  if( isempty(socket) || ~isa(socket,'java.net.Socket') )
    return
  end
catch
  return
end
stat = 0;


% Store accepted socket data.
tcp.socket       = socket;
tcp.remoteHost   = char(socket.getInetAddress());
tcp.outputStream = socket.getOutputStream();
tcp.inputStream  = socket.getInputStream();
tcp_get_set( tcp );


if( tcp.debug )
  fprintf( tcp.fid, 'Connection established on socket.\n' );
end


%------------------------------------------------------------------------------%
function [ data ] = tcp_receive()
% Receive/read message.

tcp = tcp_get_set();
NDATA0  = 10000;           % Initial data array size.
T_MIN   = 0.01;            % Minimum time to receive any data [s].
T_MAX   = 5.0;             % Maximum time to wait for and receive data [s].

data = zeros( 1, NDATA0, 'int8' );
n_data_bytes  = 0;         % Total number of received data bytes.
n_data_length = NDATA0;    % Current total length of data array.
t_start = tic();
while( true )

  % Check number of bytes in partial stream and exit if done.
  n_partial_bytes = tcp.inputStream.available();
  t = toc( t_start );
  if( n_partial_bytes<=0 && ...
      ( (n_data_bytes>0 && t>T_MIN) || (t>T_MAX) ) )
    break;
  end

  % Increase data array length if required.
  if( n_data_bytes+n_partial_bytes>n_data_length )
    data = [ data zeros( 1, NDATA0, 'int8' ) ];
    n_data_length = n_data_bytes + NDATA0;
  end

  % Recieve partial data stream.
  try
    data_i = toByteArray( org.apache.commons.io.IOUtils, tcp.inputStream, n_partial_bytes );
    data(n_data_bytes+1:n_data_bytes+length(data_i)) = data_i;
  catch
    for i=1:n_partial_bytes
      data(n_data_bytes+i) = tcp.inputStream.read();
    end
  end

  n_data_bytes = n_data_bytes + n_partial_bytes;

end
if( n_data_bytes<=0 || n_partial_bytes<0 )
  error( 'Could not recieve data.' )
end
data = data(1:n_data_bytes);


if( tcp.debug )
  fprintf( tcp.fid, 'Data sucessfully received.\n' );
  if( tcp.debug>1 )
    fprintf( tcp.fid, '\n%s\n', char(data) );
  end
end


tcp.data = data;
tcp_get_set( tcp );


%------------------------------------------------------------------------------%
function [ stat ] = tcp_send( varargin )
% Send/write message.

stat = 0;
if( isnumeric(varargin{1}) )
  data = varargin{1};
elseif( any(strcmpi(varargin,'data')) )
  data = varargin{find(strcmpi(varargin,'data'),1,'first')+1};
else
  error( 'Error in input data.' );
end
if( ischar(data) )
  data = int8(data);
end
if( ~isa(varargin{1},'int8') )
  error( 'Input data must be of type int8.' );
end

tcp = tcp_get_set();
tcp.outputStream.write( data, 0, length(data) );
tcp.outputStream.flush();


%------------------------------------------------------------------------------%
function [ stat ] = tcp_close()
% Disconnect and close TCP server.

stat = 0;
tcp = tcp_get_set();
tcp.server_socket.close();
assert( tcp.server_socket.isClosed() )

if( tcp.debug )
  fprintf( tcp.fid, 'Server on port %i sucessfully closed.\n', tcp.port );
end

if( isfield(tcp,'shandle') )
  delete( tcp.shandle )
end
tcp = [];
tcp_get_set( tcp );


%------------------------------------------------------------------------------%
function [ tcp ] = tcp_get_set( tcp )
% Persistently get and set TCP data struct.

persistent stored_tcp

if( nargin )    % Set.
  stored_tcp = tcp;
end

if( nargout )   % Get.
  tcp = stored_tcp;
end





%%-----------------------------------------------------------------------------%
%% TESTS
%%-----------------------------------------------------------------------------%

%!shared args
%! args = { 'debug', 0 };

%!test % Test 1. Initialize and close.
%!
%! tcp   = tcp_server( 'initialize', args{:} );
%!
%! tcp   = tcp_server( 'close' );
%! assert( tcp==0 )
%!
%! tcp   = tcp_server();
%! assert( isempty(tcp) )

%!test % Test 2. Initialize, re-initalize, and close.
%!
%! tcp   = tcp_server( 'initialize', args{:} );
%! tcp   = tcp_server();
%! port0 = tcp.port;
%!
%! tcp   = tcp_server( 'initialize', args{:} );
%! tcp   = tcp_server();
%! port1 = tcp.port;
%!
%! tcp   = tcp_server( 'close' );
%! assert( tcp==0 & port0==port1 )
%!
%! tcp   = tcp_server();
%! assert( isempty(tcp) )

%!test % Test 3. Initialize, (clear), re-initalize, and close.
%!
%! tcp   = tcp_server( 'initialize', args{:} );
%! tcp   = tcp_server();
%! port0 = tcp.port;
%! s     = tcp.server_socket;
%!
%! clear tcp_server
%! tcp   = tcp_server( 'initialize', args{:} );
%! tcp   = tcp_server();
%! port1 = tcp.port;
%!
%! tcp   = tcp_server( 'close' );
%! assert( tcp==0 & port0<port1 )
%!
%! tcp   = tcp_server();
%! assert( isempty(tcp) )
%! s.close();

%!test % Test 4. Initialize, accept connection, and close.
%!
%! tcp = tcp_server( 'initialize', args{:} );
%! tcp = tcp_server();
%! s   = tcp.server_socket;
%! c   = javaObject( 'java.net.Socket', s.getInetAddress(), s.getLocalPort() );
%!
%! tcp = tcp_server( 'accept' );
%! c.close();
%!
%! tcp = tcp_server();
%! assert( isfield(tcp,'socket') )
%!
%! tcp = tcp_server( 'close' );
%! assert( tcp==0 )

%!test % Test 5. Initialize, accept connection, receive message, and close.
%!
%! tcp = tcp_server( 'initialize', args{:} );
%! tcp = tcp_server();
%! s = tcp.server_socket;
%! c = javaObject( 'java.net.Socket', s.getInetAddress(), s.getLocalPort() );
%!
%! tcp = tcp_server( 'accept' );
%!
%! msg = int8('socket-test-message');
%! c.getOutputStream().write( msg, 0, length(msg) );
%! c.getOutputStream().flush();
%! data = tcp_server( 'receive' );
%! c.close();
%!
%! assert( isequal(msg,data) )
%! tcp = tcp_server( 'close' );
%! assert( tcp==0 )

%!test % Test 6. Initialize, accept connection, send message, and close.
%!
%! tcp = tcp_server( 'initialize', args{:} );
%! tcp = tcp_server();
%! s = tcp.server_socket;
%! c = javaObject( 'java.net.Socket', s.getInetAddress(), s.getLocalPort() );
%!
%! tcp = tcp_server( 'accept' );
%!
%! msg = int8('socket-test-message');
%! tcp = tcp_server( 'send', msg );
%! inputStream = c.getInputStream();
%! n = inputStream.available();
%! for i=1:n
%!   data(i) = inputStream.read();
%! end
%! c.close();
%!
%! assert( isequal(msg,data) )
%! tcp = tcp_server( 'close' );
%! assert( tcp==0 )

%!test % Test 7. Accept timeout.
%!
%! tcp = tcp_server( 'initialize', args{:}, 'timeout', 500 );
%!
%! tcp = tcp_server( 'accept' );
%! assert( tcp==-1 )
%!
%! tcp = tcp_server();
%! s   = tcp.server_socket;
%! c   = javaObject( 'java.net.Socket', s.getInetAddress(), s.getLocalPort() );
%!
%! tcp = tcp_server( 'accept' );
%! c.close();
%! assert( tcp==0 )
%!
%! tcp = tcp_server( 'close' );
%! assert( tcp==0 )

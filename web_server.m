function [ out ] = web_server( action, varargin )
%WEB_SERVER Matlab/Octave web server.
%
%   [ OUT ] = WEB_SERVER( ACTION, ARG ) Sets up and controls
%   a web server in Matlab and Octave. ACTION specifies either
%   START or STOP.
%
%   The START action accepts the following ARG property/value pairs.
%
%       Property    Value/{Default}           Description
%       -----------------------------------------------------------------------------------
%       timeout      scalar/{500}             Accept/read socket [ms] timeout limit.
%       default_file string/{index.html}      Default root html file
%       www_folder   string/{www}             Webpage folder
%       plotly       bool/{true}              Use plotly for plot rendering.
%       fid          scalar/{1}               Output log file identifier.
%       logfile      string/{tempfile}        Log file {[tempdir,eval_in_base_diary.log]}
%       debug        scalar/{0}               Debug message level (0/1/2).

% Copyright 2013-2017 Precise Simulation, Ltd.
if( ~(nargin || nargout) ),help web_server, return, end

if( ischar(action) )
  action = find(strncmpi( action, ...
                          {'start','stop'}, 4 ));
end

out = -1;
switch( action )

  case 1       % Start.

    cfg = web_configure( varargin{:} );

    out = tcp_server( 'init', 'timeout', cfg.timeout );

    if( out~=0 )
      error( 'Could not start web server.' )
    end

    h_timer = timerfun( { @main_loop, cfg }, cfg.timeout/1000 );
    if( isempty(h_timer) )
      error( 'Could not start web server.' )
    end

    tcp = tcp_server();
    fprintf( 1, '\nWeb server started on http://127.0.0.1:%i\n\n', tcp.port );
    l_browser( ['http://127.0.0.1:',num2str(tcp.port)] );

  case 2       % Stop.
    out = tcp_server( 'close' );

    h_timer = timerfun();
    if( isempty(h_timer) && out==0 )
      fprintf( 1, '\nWeb server stopped.\n\n' );
    else
      error( 'Could not stop web server.' )
    end

  otherwise
    error( 'Unknown web server action/operation.' )
end


if( ~nargout )
  clear out;
end


%------------------------------------------------------------------------------%
function main_loop( h_timer, tmp, cfg )


ier = tcp_server( 'accept' );
if( ier==-1 )
  return
end


data = tcp_server( 'receive' );
if( isempty(data) )
  return
end
if( cfg.debug>1 )
  char( data )
end


% Convert the header text to a struct.
request = parse_request( data );


% The filename asked by the browser
if( isfield(request,'Get') )
  filename = request.Get.Filename;
elseif( isfield(request,'Post') )
  filename = request.Post.Filename;
else
  warning( 'Unknown Type of Request' );
  return
end


% Use default_file for root.
if( strcmp(filename,'/') )
  filename = cfg.default_file;
end
fullfilename = fullfile( cfg.www_folder, filename );
[pathstr,name,ext] = fileparts( fullfilename );


% Check if file asked by the browser can be opened.
html  = '';
found = exist( fullfilename )==2;
if( ~found )
  fullfilename = fullfile( cfg.www_folder, '404.html' );
  if( ~(exist( fullfilename )==2) )
    html = '<html><body>404 File not found.</body></html>';
  end
end


% Based on the extension asked, read a local file and
% parse it, or execute matlab code, which generates the file.
if( isempty(html) )
  fid  = fopen( fullfilename, 'r' );
  html = fread( fid, inf, 'int8' )';
  fclose( fid );
end
if( strcmp(ext,'.m') )
  addpath( pathstr );
  try
    html = feval( name, request, cfg );
  catch ME
    html = [ '<html><body><font color="#FF0000">Error in file : ', name, ...
            '.m</font><br><br><font color="#990000"> The file returned the following error: <br>', ...
            ME.message, '</font></body></html>' ];
  end
  rmpath( pathstr );
end
response = get_response( html, found, ext );


% Send response and html to client.
tcp_server( 'write', int8(response) );
tcp_server( 'write', int8(html) );


%------------------------------------------------------------------------------%
function [ header ] = parse_request( requestdata )

request_text  = char( requestdata );
request_lines = regexp( request_text, '[\n|\r|\r\n]+', 'split' );
request_words = regexp( request_lines, '\s+', 'split' );

for i=1:length( request_lines )
  line = request_lines{i};
  if( isempty(line) ), break; end

  type = request_words{i}{1};
  switch(lower(type))
    case 'get'
      header.Get.Filename = request_words{i}{2};
      header.Get.Protocol = request_words{i}{3};
    case 'post'
      header.Post.Filename = request_words{i}{2};
      header.Post.Protocol = request_words{i}{3};
    case 'host:'
      header.Host = strtrim(line(7:end));
    case 'user-agent:'
      header.UserAgent = strtrim(line(13:end));
    case 'accept:'
      header.Accept = strtrim(line(9:end));
    case 'accept-language:'
      header.AcceptLanguage = strtrim(line(18:end));
    case 'accept-encoding:'
      header.AcceptEncoding = strtrim(line(18:end));
    case 'accept-charset:'
      header.AcceptCharset = strtrim(line(17:end));
    case 'keep-alive:'
      header.KeepAlive = strtrim(line(13:end));
    case 'connection:'
      header.Connection = strtrim(line(13:end));
    case 'content-length:'
      header.ContentLength = strtrim(line(17:end));
    case 'content-type:'
      switch( strtrim(request_words{i}{2}) )
        case {'application/x-www-form-urlencoded','application/x-www-form-urlencoded;'}
          header.ContentType.Type     = 'application/x-www-form-urlencoded';
          header.ContentType.Boundary = '&';
        case {'multipart/form-data','multipart/form-data;'}
          header.ContentType.Type = 'multipart/form-data';
          header.ContentType.Boundary = request_words{i}{3}(10:end);
        otherwise
          warning( 'Unhandled reqest content type.' )
      end
    otherwise
      % warning( [ 'Unhandled reqest: ',type] )
  end
end

header.Content = struct;

if( isfield(header,'ContentLength') )
  cl   = str2double(header.ContentLength);
  str  = request_text(end-cl+1:end);
  data = requestdata(end-cl+1:end);
  if( ~isfield(header,'ContentType') )
    header.ContentType.Type     = '';
    header.ContentType.Boundary = '&';
  end

  switch(header.ContentType.Type )
    case {'application/x-www-form-urlencoded',''}
      words = regexp( strtrim(str), '&', 'split' );
      for i=1:length(words)
        words2 = regexp( words{i}, '=', 'split' );
        header.Content.(words2{1}) = words2{2};
      end
    case 'multipart/form-data'
      pos = strfind( str, header.ContentType.Boundary );
      while( (pos(1)>1)&&(str(pos(1)-1)=='-') )
        header.ContentType.Boundary = [ '-' header.ContentType.Boundary];
        pos = strfind(str,header.ContentType.Boundary);
      end

      for i=1:(length(pos)-1)
        pstart = pos(i)+length(header.ContentType.Boundary);
        pend = pos(i+1)-3; % Remove "13 10" End-line characters.
        subrequestdata = data(pstart:pend);
        subdata = multipart2struct( subrequestdata, config );
        header.Content.(subdata.Name).Filename    = subdata.Filename;
        header.Content.(subdata.Name).ContentType = subdata.ContentType;
        header.Content.(subdata.Name).ContentData = subdata.ContentData;
      end
    otherwise
      disp( 'Unknown request handling.' )
  end
end


%------------------------------------------------------------------------------%
function [ response ] = get_response( html, found, ext )

header = header_commons( found );

switch( ext )
  case {'.html','.htm','.css','.js','.m'}

    header.XPoweredBY = [ 'Matlab', version ];
    header.SetCookie = 'SESSID=5322082bf473207961031e3df1f45a22; path=/';
    header.Expires = 'Thu, 19 Nov 1980 08:00:00 GMT';
    header.CacheControl = 'no-store, no-cache, must-revalidate, post-check=0, pre-check=0';
    header.Pragma = 'no-cache';
    header.Connection = 'close';
    header.ContentLength = num2str(length(html));
    header.ContentType = 'text/html; charset=UTF-8';
    if( strcmp(ext,'.css') )
      header.ContentType = 'text/css; charset=UTF-8';
    end
    if( strcmp(ext,'.js') )
      header.ContentType = 'text/js; charset=UTF-8';
    end

  otherwise

    header.LastModified = 'Last-Modified: Thu, 21 Jun 2007 14:56:37 GMT';
    header.AcceptRanges = 'Accept-Ranges: bytes';
    header.ContentLength = num2str(length(html));
    header.ETag = '"948921-15ae-c0dbf340"';
    %header.KeepAlive = 'Keep-Alive: timeout=15, max=100';
    header.ContentType = 'application/octet-stream';

end
if( any(strcmp(ext,{'.jpg','.png','.gif','.ico'})) )
  header.ContentType = 'image/png';
end

response = header2text( header );


%------------------------------------------------------------------------------%
function [ header ] = header_commons( found )

if( found )
  header.HTTP = '200 OK';
else
  header.HTTP = '404 Not Found';
end

header.Date = datestr(now,'ddd, dd mmm yyyy HH:MM:SS');

if( exist( 'OCTAVE_VERSION', 'builtin' ) )
  header.Server = 'Octave Web Server';
else
  header.Server = 'Matlab Web Server';
end


%------------------------------------------------------------------------------%
function [ text ] = header2text( header )

text = '';
fn   = fieldnames(header);
for i=1:length(fn)
  name = fn{i};
  data = header.(name);

  switch name
    case 'HTTP'
      data = [ 'HTTP/1.0 ', data ];
    case 'Date'
      data = [ 'Date: ', data ];
    case 'Server'
      data = [ 'Server: ', data ];
    case 'XPoweredBY'
      data = [ 'X-Powered-By: ', data ];
    case 'SetCookie'
      data = [ 'Set-Cookie: ', data ];
    case 'Expires'
      data = [ 'Expires: ', data ];
    case 'CacheControl'
      data = [ 'Cache-Control: ', data ];
    case 'Pragma'
      data = [ 'Pragma: ', data ];
    case 'XPingback'
      data = [ 'X-Pingback: ', data ];
    case 'Connection'
      data = [ 'Connection: ', data ];
    case 'ContentLength'
      data = [ 'Content-Length: '  data];
    case 'ContentType'
      data = [ 'Content-Type: ', data ];
    case 'LastModified'
      data = [ 'Last-Modified: ', data ];
    case 'AcceptRanges';
      data = [ 'Accept-Ranges: ', data ];
    case 'ETag';
      data = [ 'ETag: ', data ];
    case'KeepAlive';
      data = [ 'Keep-Alive: ', data ];
    otherwise
      warning( 'Wrong header fieldname.' );
      continue;
  end
  text=[ text, data, '\n' ];
end
text = [ text, '\n' ];
text = sprintf( text );


%------------------------------------------------------------------------------%
function [ subdata ] = multipart2struct( subrequestdata, config )

request_lines = regexp( char(subrequestdata), '\n+', 'split' );
request_words = regexp( request_lines, '\s+', 'split' );

i = 1;
subdata = struct;
subdata.Name = '';
subdata.Filename = '';
subdata.ContentType = '';
subdata.ContentData = '';
while( true )
  i = i+1;
  if((i>length(request_lines))||(uint8(request_lines{i}(1)==13))), break; end
  line = request_lines{i};
  type = request_words{i}{1};
  switch( type )
    case 'Content-Disposition:'
      for j=3:length(request_words{i})
        line_words = regexp( request_words{i}{j}, '"', 'split' );
        switch( line_words{1} )
          case 'name='
            subdata.Name = line_words{2};
          case 'filename='
            subdata.Filename = line_words{2};
        end
      end
    case 'Content-Type:'
      subdata.ContentType = strtrim(line(15:end));
  end
end
w  =find(subrequestdata==10);
switch( subdata.ContentType )
  case ''
    subdata.ContentData = char(subrequestdata(w(i)+1:end));
  otherwise
    subdata.ContentData = subrequestdata(w(i)+1:end);
    [pathstr,name,ext]  = fileparts(subdata.Filename);
    filename = [ '/', char(round(rand(1,32)*9)+48) ];
    fullfilename = [ tempdir, filename, ext ];
    fid = fopen(fullfilename,'w');
    fwrite(fid,subdata.ContentData,'int8');
    fclose(fid);
    subdata.Filename = fullfilename;
end


%------------------------------------------------------------------------------%
function [ cfg ] = web_configure( varargin )
% Setup and parse input parameters.

% Default parameters.
cfg.timeout      = 500;
cfg.default_file = 'index.html';
cfg.www_folder   = 'www';
cfg.logfile      = fullfile( tempdir, ['eval_in_base_diary_',l_get_uid(10),'.log'] );
cfg.plotly       = true;
cfg.debug        = 0;
cfg.octave       = exist( 'OCTAVE_VERSION', 'builtin' );
if( exist(cfg.logfile)==2 )
  try
    delete( logfile );
  catch
  end
end

% Parse configuration.
config = varargin;
if( ~isempty(config) )
  if( iscell(config) )
    config = cell2struct( config(2:2:end), config(1:2:end-1), 2 );
  end
  fields = fieldnames(config);
  for i=1:length(fields)
    cfg.(fields{i}) = config.(fields{i});
  end
end
if( exist(cfg.logfile)==2 )
  try
    delete( cfg.logfile );
  catch
  end
end

try
  if( cfg.plotly )
    addpath( genpath('lib/plotly') );
  end
catch
  cfg.plotly = false;
end


%-------------------------------------------------------------------------%
function [ s_uid, uid ] = l_get_uid( n )
% Unique (random) user id.

uid = zeros(1,n);
ix  = (uid>=48&uid<=57) | (uid>=65&uid<=90) | (uid>=97&uid<=122);
while( ~all(ix) )
  ix = (uid>=48&uid<=57) | (uid>=65&uid<=90) | (uid>=97&uid<=122);
  uid(~ix) = randi( 122, 1, sum(~ix) );
end
s_uid = char(uid);


%------------------------------------------------------------------------------%
function [ stat ] = l_browser( addr )
% Open web address in default web browser.

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


%------------------------------------------------------------------------------%
function [ h_out ] = timerfun( cbf, delay )
%TIMERFUN Create single timer function.
%
%   [ H ] = TIMERFUN( CBF, DELAY ) Creates a single timer function
%   with persistent handle H. If a timer function is not already
%   present a new object is created with the callback CBF which is
%   called every DELAY seconds (CBF can be a cell array of a function
%   handle and following input arguments). A call with an existing
%   timer object stops and deletes it.
%
%   See also TIMER.

persistent h
is_debug = false;


if( nargin<2 )
  delay = 3;
end
if( nargin && ~iscell(cbf) )
  cbf = { cbf };
end
if( isempty(h) )
  action = 'start';
else
  action = 'stop';
end


switch( lower(action) )

  case 'start'
    if( is_debug )
      fprintf( 'Starting timer function %s with delay %g s. \n', func2str(cbf{1}), delay )
    end
    if( ~isempty(h) )
      warning('timerfun: closing existing timer function.')
      try
        delete( h )
      catch
      end
    end
    h = add_timer( delay, cbf );

  case 'stop'
    if( is_debug )
      fprintf( 'Stopping timer function.\n\n' )
    end
    if( exist( 'OCTAVE_VERSION', 'builtin' ) )
      remove_input_event_hook( h );
    else
      stop( h )
      delete( h )
    end
    h = [];

end


if( nargout )
  h_out = h;
end


%-------------------------------------------------------------------------%
function [ h ] = add_timer( delay, cbf )

if( exist( 'OCTAVE_VERSION', 'builtin' ) )

  h = add_input_event_hook( @cbf_timer, { cbf delay } );

else

  h = timer( 'TimerFcn', cbf, 'ExecutionMode', 'fixedSpacing', ...
             'Period', delay );
  start( h );

end

%-------------------------------------------------------------------------%
function cbf_timer( data )

persistent last_time
if( isempty(last_time) )
  last_time = 0;
end

cbf   = data{1};
delay = data{2};

current_time = clock();
current_time = sum(current_time(4:6).*[60*60 60 1]);
if( (current_time-last_time)>=delay )

  args = cbf(2:end);
  cbf  = cbf{1};
  cbf( [], [], args{:} )

  fflush( stdout );
  last_time = current_time;
end

function [ html ] = eval_web_command( headers, config )
%EVAL_WEB_COMMAND Evaluate and parse web command.

% Copyright 2013-2017 Precise Simulation, Ltd.

I_METHOD = 1;
N_MAX_LINES = 2000;

s_ans = '';
try
  if( isfield(headers.Content,'cmd') )
    s_cmd = headers.Content.cmd;
    if( ischar(s_cmd) && ~isempty(s_cmd) )
      s_cmd = char( javaMethod('decode','java.net.URLDecoder',s_cmd,'UTF-8') );
      if( isfield(config,'debug') && config.debug>1 )
        disp( ['Cmd to eval: ',s_cmd] )
      end
      l_assert_safe( s_cmd );

      if( I_METHOD==1 )

        if( isfield(config,'logfile') )
          logfile = config.logfile;
        else
          logfile = fullfile( tempdir, 'eval_in_base_diary.log' );
        end
        fid = fopen( logfile, 'a' );
        fprintf( fid, '>> %s\n', s_cmd );
        if( config.octave )
          fprintf( fid, '\n' );
        end
        fclose(fid);
        diary( logfile );

        evalin( 'base', s_cmd );
        drawnow;
        if( config.octave )
          disp('')
        end

        diary( 'off' );
        fid   = fopen( logfile, 'r' );
        data  = fread( fid, inf, 'int8' )';
        fclose(fid);

        if( ~any(data(end)==[10 13]) )
          data = [ data int8([10 13]) ];
        end
        ie_lines = data==13;
        if( ~any(ie_lines) )
          ie_lines = data==10;
        end
        n_lines = sum(ie_lines);
        if( n_lines>N_MAX_LINES )
          ie_lines = find(ie_lines);
          data = data(ie_lines(n_lines-N_MAX_LINES)+1:end);
          fid  = fopen( logfile, 'w' );
          fprintf( fid, '%s', char(data) );
          fclose(fid);
        end

        s_ans = char( data );

      else

        s_ans = evalc( ['evalin(''base'',''',s_cmd,''')'] );

      end

    end
  end
catch err

  s_ans = ['  <font style="color:red">Error: Failed to parse or evaluate command "',s_cmd,'".</font>'];

end

html = '<html><head><style> * { font-family: "Courier New", Courier, monospace; font-size: 14; }</style></head><body>';
html = [ html, '<pre><code>', char(10), s_ans, char(10), '</code></pre>' ];
html = [ html '<script>document.body.scrollTop = document.body.scrollHeight;</script>' ];
s_add = '';
hf = findall(0,'type','figure');
hf(strcmp(get(hf,'visible'),'off')) = [];
if( ~isempty(hf) && config.plotly )

  for i=1:length(hf)
    if( exist( 'OCTAVE_VERSION', 'builtin' ) || verLessThan('matlab','8.4.0') )
      s_fignum = num2str(hf(i));
    else
      s_fignum = num2str(get(hf(i),'Number'));
    end

    out = fig2plotly( hf(i), 'offline', true, 'open', false, 'filename', ['plotly_figure_',s_fignum] );

    stat = movefile( out.url, fullfile(config.www_folder,['plotly_figure_',s_fignum,'.html']) );

    if( stat~=0 )
      s_add = [s_add,'<script>', ...
               ['  var url = "plotly_figure_',s_fignum,'.html";'], ...
               ['  window.open(url, "Figure ',s_fignum,'", "width=640,height=480", statusbar=0, menubar=0, toolbar=0);'], ...
               '</script>'];
    else
      s_ans = [char([10 13]),'<font style="color:red">Error: Could not find or move "',['plotly_figure_',s_fignum,'.html'],'" file.</font>',char([10 13])];
    end
  end

end
html = [ html, s_add ];
html = [ html, '</body></html>'];

%------------------------------------------------------------------------------%
function l_assert_safe( s_cmd )

c_forbid = {'eval','system','delete','copyfile','movefile','mkdir','rmdir'};

ix = [];
for i=1:length(c_forbid)
  if( any(strfind( s_cmd, c_forbid{i} )) )
    error( 'Forbidden string found in command.' )
  end
end

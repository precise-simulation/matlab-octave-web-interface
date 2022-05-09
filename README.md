A Web Browser Interface and Server for Matlab and Octave
========================================================


About
-----

A simple experimental web browser interface for Matlab and Octave.
Running the <code>web_server('start')</code> command starts a local
_TCP_ and _web_ server and opens a connected web browser window which
accepts Matlab and Octave commands as input. Plots are translated via
the Plotly Javascript library into Html graphs.

![Matlab Octave Web Browser and Server Interface](https://raw.githubusercontent.com/precise-simulation/matlab-octave-web-interface/master/matlab-octave-web-browser-and-server-interface.jpg)


Installation
------------

Download the _webserver_ archive and extract the contents in a
convenient folder.


Requirements
------------

1. A modern [web browser](https://www.mozilla.org/en-US/firefox)
with Javascript enabled and flexbox CSS support.

2. [Matlab](https://www.mathworks.com/matlab) or
[Octave](https://www.gnu.org/software/octave) installed.

3. [Java](http://www.oracle.com/technetwork/java/javase/downloads)
   installed and support enabled with Matlab and Octave.


Usage
-----

Simply change to the extracted folder or add it to the Matlab/Octave
paths and run the command

    web_server( 'start' )

to start the web server and open the mirrored Matlab/Octave session in
the default web browser. To stop the sever run the command

    web_server( 'stop' )

To see the available options enter

    help web_server
    help tcp_server


Known Issues
------------

1. The Plotly library needs further improvements to fully support
   Octave (currently only line plots are supported). The main issue is
   that a lot of struct calls in the Plotly conversion function are
   accessed as _s.Color_ or _s.XLabel_ where in Octave the fields are
   all in lower case, that is _s.color_ and _s.xlabel_.


Credits
-------

[1] [Matlab Webserver by Dirk-Jan Kroon](https://www.mathworks.com/matlabcentral/fileexchange/29027-web-server)

[2] [Plotly Javascript library](https://plot.ly/javascript)


Software License
----------------

[GNU Affero General Public License AGPL](https://www.gnu.org/licenses/agpl-3.0.txt)

   audtool(1) — audacious — Debian testing — Debian Manpages @font-face { font-family: 'Inconsolata'; src: local('Inconsolata'), url(/Inconsolata.woff2) format('woff2'), url(/Inconsolata.woff) format('woff'); font-display: swap; } @font-face { font-family: 'Roboto'; font-style: normal; font-weight: 400; src: local('Roboto'), local('Roboto Regular'), local('Roboto-Regular'), url(/Roboto-Regular.woff2) format('woff2'), url(/Roboto-Regular.woff) format('woff'); font-display: swap; } body { color: #000; background-color: white; background-image: linear-gradient(to bottom, #d7d9e2, #fff 70px); background-position: 0 0; background-repeat: repeat-x; font-family: sans-serif; font-size: 100%; line-height: 1.2; letter-spacing: 0.15px; margin: 0; padding: 0; } body > div#header { padding: 0 10px 0 52px; } #logo { position: absolute; top: 0; left: 0; border-left: 1px solid transparent; border-right: 1px solid transparent; border-bottom: 1px solid transparent; width: 50px; height: 5.07em; min-height: 65px; } #logo a { display: block; height: 100%; } #logo img { margin-top: 5px; position: absolute; bottom: 0.3em; overflow: auto; border: 0; } p.section { margin: 0; padding: 0 5px 0 5px; font-size: 13px; line-height: 16px; color: white; letter-spacing: 0.08em; position: absolute; top: 0px; left: 52px; background-color: #c70036; } p.section a { color: white; text-decoration: none; } .hidecss { display: none; } #searchbox { text-align:left; line-height: 1; margin: 0 10px 0 0.5em; padding: 1px 0 1px 0; position: absolute; top: 0; right: 0; font-size: .75em; } #navbar { border-bottom: 1px solid #c70036; } #navbar ul { margin: 0; padding: 0; overflow: hidden; } #navbar li { list-style: none; float: left; } #navbar a { display: block; padding: 1.75em .5em .25em .5em; color: #0035c7; text-decoration: none; border-left: 1px solid transparent; border-right: 1px solid transparent; } #navbar a:hover , #navbar a:visited:hover { background-color: #f5f6f7; border-left: 1px solid #d2d3d7; border-right: 1px solid #d2d3d7; text-decoration: underline; } a:link { color: #0035c7; } a:visited { color: #54638c; } #breadcrumbs { line-height: 2; min-height: 20px; margin: 0; padding: 0; font-size: 0.75em; background-color: #f5f6f7; border-bottom: 1px solid #d2d3d7; } #breadcrumbs:before { margin-left: 0.5em; margin-right: 0.5em; } #content { margin: 0 10px 0 52px; display: flex; flex-direction: row; word-wrap: break-word; } .paneljump { background-color: #d70751; padding: 0.5em; border-radius: 3px; margin-right: .5em; display: none; } .paneljump a, .paneljump a:visited, .paneljump a:hover, .paneljump a:focus { color: white; } @media all and (max-width: 800px) { #content { flex-direction: column; margin: 0.5em; } .paneljump { display: block; } } .panels { display: block; order: 2; } .maincontent { width: 100%; max-width: 80ch; order: 1; } .mandoc { font-family: monospace; font-size: 1.04rem; } .mandoc pre { white-space: pre-wrap; } body > div#footer { border: 1px solid #dfdfe0; border-left: 0; border-right: 0; background-color: #f5f6f7; padding: 1em; margin: 1em 10px 0 52px; font-size: 0.75em; line-height: 1.5em; } hr { border-top: 1px solid #d2d3d7; border-bottom: 1px solid white; border-left: 0; border-right: 0; margin: 1.4375em 0 1.5em 0; height: 0; background-color: #bbb; } #content p { padding-left: 1em; } a, a:hover, a:focus, a:visited { color: #0530D7; text-decoration: none; } .panel { padding: 15px; margin-bottom: 20px; background-color: #ffffff; border: 1px solid #dddddd; border-radius: 4px; -webkit-box-shadow: 0 1px 1px rgba(0, 0, 0, 0.05); box-shadow: 0 1px 1px rgba(0, 0, 0, 0.05); } .panel-heading, .panel details { margin: -15px -15px 0px; background-color: #d70751; border-bottom: 1px solid #dddddd; border-top-right-radius: 3px; border-top-left-radius: 3px; } .panel-heading, .panel summary { padding: 5px 5px; font-size: 17.5px; font-weight: 500; color: #ffffff; outline-style: none; } .panel summary { padding-left: 7px; } summary, details { display: block; } .panel details ul { margin: 0; } .panel-footer { padding: 5px 5px; margin: 15px -15px -15px; background-color: #f5f5f5; border-top: 1px solid #dddddd; border-bottom-right-radius: 3px; border-bottom-left-radius: 3px; } .panel-info { border-color: #bce8f1; } .panel-info .panel-heading { color: #3a87ad; background-color: #d9edf7; border-color: #bce8f1; } .list-group { padding-left: 0; margin-bottom: 20px; background-color: #ffffff; } .list-group-item { position: relative; display: block; padding: 5px 5px 5px 5px; margin-bottom: -1px; border: 1px solid #dddddd; } .list-group-item > .list-item-key { min-width: 27%; display: inline-block; } .list-group-item > .list-item-key.versions-repository { min-width: 40%; } .list-group-item > .list-item-key.versioned-links-version { min-width: 40% } .versioned-links-icon { margin-right: 2px; } .versioned-links-icon a { color: black; } .versioned-links-icon a:hover { color: blue; } .versioned-links-icon-inactive { opacity: 0.5; } .list-group-item:first-child { border-top-right-radius: 4px; border-top-left-radius: 4px; } .list-group-item:last-child { margin-bottom: 0; border-bottom-right-radius: 4px; border-bottom-left-radius: 4px; } .list-group-item-heading { margin-top: 0; margin-bottom: 5px; } .list-group-item-text { margin-bottom: 0; line-height: 1.3; } .list-group-item:hover { background-color: #f5f5f5; } .list-group-item.active a { z-index: 2; } .list-group-item.active { background-color: #efefef; } .list-group-flush { margin: 15px -15px -15px; } .panel .list-group-flush { margin-top: -1px; } .list-group-flush .list-group-item { border-width: 1px 0; } .list-group-flush .list-group-item:first-child { border-top-right-radius: 0; border-top-left-radius: 0; } .list-group-flush .list-group-item:last-child { border-bottom: 0; } .panel { float: right; clear: right; min-width: 200px; } .toc { width: 200px; } .toc li { font-size: 98%; letter-spacing: 0.02em; display: flex; } .otherversions { width: 200px; } .otherversions li, .otherlangs li { display: flex; } .otherversions a, .otherlangs a { flex-shrink: 0; } .pkgversion, .pkgname, .toc a { text-overflow: ellipsis; overflow: hidden; white-space: nowrap; } .pkgversion, .pkgname { margin-left: auto; padding-left: 1em; } .mandoc { overflow: hidden; margin-top: .5em; margin-right: 45px; } table.head, table.foot { width: 100%; } .head-vol { text-align: center; } .head-rtitle { text-align: right; } .spacer, .Pp { min-height: 1em; } pre { margin-left: 2em; } .anchor { margin-left: .25em; visibility: hidden; } h1:hover .anchor, h2:hover .anchor, h3:hover .anchor, h4:hover .anchor, h5:hover .anchor, h6:hover .anchor { visibility: visible; } h1, h2, h3, h4, h5, h6 { letter-spacing: .07em; margin-top: 1.5em; margin-bottom: .35em; } h1 { font-size: 150%; } h2 { font-size: 125%; } @media print { #header, #footer, .panel, .anchor, .paneljump { display: none; } #content { margin: 0; } .mandoc { margin: 0; } } .Bd { } .Bd-indent { margin-left: 3.8em; } .Bl-bullet { list-style-type: disc; padding-left: 1em; } .Bl-bullet > li { } .Bl-dash { list-style-type: none; padding-left: 0em; } .Bl-dash > li:before { content: "\\2014 "; } .Bl-item { list-style-type: none; padding-left: 0em; } .Bl-item > li { } .Bl-compact > li { margin-top: 0em; } .Bl-enum { padding-left: 2em; } .Bl-enum > li { } .Bl-compact > li { margin-top: 0em; } .Bl-diag { } .Bl-diag > dt { font-style: normal; font-weight: bold; } .Bl-diag > dd { margin-left: 0em; } .Bl-hang { } .Bl-hang > dt { } .Bl-hang > dd { margin-left: 5.5em; } .Bl-inset { } .Bl-inset > dt { } .Bl-inset > dd { margin-left: 0em; } .Bl-ohang { } .Bl-ohang > dt { } .Bl-ohang > dd { margin-left: 0em; } .Bl-tag { margin-left: 5.5em; } .Bl-tag > dt { float: left; margin-top: 0em; margin-left: -5.5em; padding-right: 1.2em; vertical-align: top; } .Bl-tag > dd { clear: both; width: 100%; margin-top: 0em; margin-left: 0em; vertical-align: top; overflow: auto; } .Bl-compact > dt { margin-top: 0em; } .Bl-column { } .Bl-column > tbody > tr { } .Bl-column > tbody > tr > td { margin-top: 1em; } .Bl-compact > tbody > tr > td { margin-top: 0em; } .Rs { font-style: normal; font-weight: normal; } .RsA { } .RsB { font-style: italic; font-weight: normal; } .RsC { } .RsD { } .RsI { font-style: italic; font-weight: normal; } .RsJ { font-style: italic; font-weight: normal; } .RsN { } .RsO { } .RsP { } .RsQ { } .RsR { } .RsT { text-decoration: underline; } .RsU { } .RsV { } .eqn { } .tbl { } .HP { margin-left: 3.8em; text-indent: -3.8em; } table.Nm { } code.Nm { font-style: normal; font-weight: bold; font-family: inherit; } .Fl { font-style: normal; font-weight: bold; font-family: inherit; } .Cm { font-style: normal; font-weight: bold; font-family: inherit; } .Ar { font-style: italic; font-weight: normal; } .Op { display: inline; } .Ic { font-style: normal; font-weight: bold; font-family: inherit; } .Ev { font-style: normal; font-weight: normal; font-family: monospace; } .Pa { font-style: italic; font-weight: normal; } .Lb { } code.In { font-style: normal; font-weight: bold; font-family: inherit; } a.In { } .Fd { font-style: normal; font-weight: bold; font-family: inherit; } .Ft { font-style: italic; font-weight: normal; } .Fn { font-style: normal; font-weight: bold; font-family: inherit; } .Fa { font-style: italic; font-weight: normal; } .Vt { font-style: italic; font-weight: normal; } .Va { font-style: italic; font-weight: normal; } .Dv { font-style: normal; font-weight: normal; font-family: monospace; } .Er { font-style: normal; font-weight: normal; font-family: monospace; } .An { } .Lk { } .Mt { } .Cd { font-style: normal; font-weight: bold; font-family: inherit; } .Ad { font-style: italic; font-weight: normal; } .Ms { font-style: normal; font-weight: bold; } .St { } .Ux { } .Bf { display: inline; } .No { font-style: normal; font-weight: normal; } .Em { font-style: italic; font-weight: normal; } .Sy { font-style: normal; font-weight: bold; } .Li { font-style: normal; font-weight: normal; font-family: monospace; } body { font-family: 'Roboto', sans-serif; } .mandoc, .mandoc pre, .mandoc code, p.section { font-family: 'Inconsolata', monospace; } 

[![Debian](audtool_files/openlogo-50.svg)](https://www.debian.org/ "Debian Home")

[MANPAGES](https://manpages.debian.org/)

     

[Skip Quicknav](#content)

*   [Index](https://manpages.debian.org/)
*   [About Manpages](https://manpages.debian.org/about.html)
*   [FAQ](https://manpages.debian.org/faq.html)
*   [Service Information](https://wiki.debian.org/manpages.debian.org)

  / [testing](https://manpages.debian.org/contents-testing.html) / [audacious](https://manpages.debian.org/testing/audacious/index.html) / audtool(1)

links

*   [language-indep link](https://manpages.debian.org/testing/audacious/audtool.1)
*   [package tracker](https://tracker.debian.org/pkg/audacious)
*   [raw man page](https://manpages.debian.org/testing/audacious/audtool.1.en.gz)

table of contents

*   [NAME](#NAME "NAME")
*   [SYNOPSIS](#SYNOPSIS "SYNOPSIS")
*   [DESCRIPTION](#DESCRIPTION "DESCRIPTION")
*   [COMMANDS](#COMMANDS "COMMANDS")
*   [BUGS](#BUGS "BUGS")
*   [AUTHORS](#AUTHORS "AUTHORS")
*   [SEE ALSO](#SEE_ALSO "SEE ALSO")
*   [WEBSITE](#WEBSITE "WEBSITE")

other versions

*   [trixie](https://manpages.debian.org/trixie/audacious/audtool.1.en.html) 4.4.2-1
*   [testing](https://manpages.debian.org/testing/audacious/audtool.1.en.html) 4.5.1-1
*   [unstable](https://manpages.debian.org/unstable/audacious/audtool.1.en.html) 4.5.1-1

[Scroll to navigation](#panels)

AUDTOOL(1)

General Commands Manual

AUDTOOL(1)

NAME[¶](#NAME)
==============

**audtool** - a small tool to control Audacious from the command line.

SYNOPSIS[¶](#SYNOPSIS)
======================

**audtool** \[_instance_\] _command_ \[_parameter_ ...\] ...

DESCRIPTION[¶](#DESCRIPTION)
============================

**audtool** sends commands to a running instance of Audacious.

It can send many common commands, such as to skip to the next song in the playlist, and can also print status information, such as the title of the current song.

_instance_ may be given as **\-1**, **\-2**, etc. (up to **\-9**) to specify which instance of Audacious to control when multiple instances have been started.

COMMANDS[¶](#COMMANDS)
======================

Current song information:[¶](#Current_song_information:)
--------------------------------------------------------

[**\--current-song**](#current-song)

Print the formatted title of the current song. Depending on Audacious settings, this may include information such as the artist and album name. To print only the song title, use **\--current-song-tuple-data title** instead.

[**\--current-song-filename**](#current-song-filename)

Print the file name (full path or URI) of the current song.

[**\--current-song-length**](#current-song-length)

Print the length of the current song in M:SS format.

[**\--current-song-length-seconds**](#current-song-length-seconds)

Print the length of the current song in seconds.

[**\--current-song-length-frames**](#current-song-length-frames)

Print the length of the current song in milliseconds.

[**\--current-song-output-length**](#current-song-output-length)

Print the playback time counter in M:SS format.

[**\--current-song-output-length-seconds**](#current-song-output-length-seconds)

Print the playback time counter in seconds.

[**\--current-song-output-length-frames**](#current-song-output-length-frames)

Print the playback time counter in milliseconds.

[**\--current-song-bitrate**](#current-song-bitrate)

Print the streaming bitrate in bits per second.

[**\--current-song-bitrate-kbps**](#current-song-bitrate-kbps)

Print the streaming bitrate in kilobits per second (1 kilobit = 1000 bits).

[**\--current-song-frequency**](#current-song-frequency)

Print the sampling rate in hertz.

[**\--current-song-frequency-khz**](#current-song-frequency-khz)

Print the sampling rate in kilohertz.

[**\--current-song-channels**](#current-song-channels)

Print the number of audio channels.

[**\--current-song-tuple-data _field_**](#current-song-tuple-data)

Print the value of a named field (**artist**, **year**, **genre**, etc.) for the current song. If the field name is omitted, a list of allowed fields will be printed.

[**\--current-song-info**](#current-song-info)

Print the streaming bitrate, sampling rate, and number of audio channels.

Playback commands:[¶](#Playback_commands:)
------------------------------------------

[**\--playback-play**](#playback-play)

Start playback. If paused, playback will resume from the same point. If already active and not paused, it will restart from the beginning of the song.

[**\--playback-pause**](#playback-pause)

Pause playback, or resume if already paused.

[**\--playback-playpause**](#playback-playpause)

Equivalent to **\--playback-pause** if playback is active, otherwise **\--playback-play**.

[**\--playback-stop**](#playback-stop)

Stop playback.

[**\--playback-playing**](#playback-playing)

Return an exit code of 0 (true) if playback is active.

[**\--playback-paused**](#playback-paused)

Return an exit code of 0 (true) if playback is paused.

[**\--playback-stopped**](#playback-stopped)

Return an exit code of 0 (true) if playback is not active.

[**\--playback-status**](#playback-status)

Print the playback status (\`\`playing'', \`\`paused'', or \`\`stopped'').

[**\--playback-seek _time_**](#playback-seek)

Seek to the given time in seconds, relative to the beginning of the song.

[**\--playback-seek-relative _time_**](#playback-seek-relative)

Seek to the given time in seconds, relative to the current time counter.

[**\--playback-record**](#playback-record)

Toggle recording of the output stream (using FileWriter).

[**\--playback-recording**](#playback-recording)

Return an exit code of 0 (true) if stream recording is enabled.

Playlist selection:[¶](#Playlist_selection:)
--------------------------------------------

[**\--select-displayed**](#select-displayed)

Specifies that any subsequent playlist commands should apply to the playlist currently displayed by Audacious, regardless of which playlist is playing. This setting takes effect until it is overridden by **\--select-playing** or Audacious is restarted.

The following commands are also affected:

\--current-song  
\--current-song-filename  
\--current-song-length\[-seconds,-frames\]  
\--current-song-tuple-data

[**\--select-playing**](#select-playing)

Specifies that when playback is active, any subsequent playlist commands should apply to the playlist currently playing. When playback is stopped, the behavior is the same as **\--select-displayed**. This setting is the default.

Playlist commands:[¶](#Playlist_commands:)
------------------------------------------

[**\--playlist-advance**](#playlist-advance)

Skip to the next song in the playlist.

[**\--playlist-reverse**](#playlist-reverse)

Skip to the previous song in the playlist.

[**\--playlist-addurl _path_**](#playlist-addurl)

Add a song to end of the playlist. Either a URI or a local file path (absolute or relative) may be given.

[**\--playlist-insurl _path_ _position_**](#playlist-insurl)

Insert a song at the given position (one-based) in the playlist.

[**\--playlist-addurl-to-new-playlist _path_**](#playlist-addurl-to-new-playlist)

Add a song to the \`\`Now Playing'' playlist, creating the playlist if necessary, and begin to play the song. Depending on Audacious settings, the playlist may first be cleared.

[**\--playlist-delete _position_**](#playlist-delete)

Remove the song at the given position from the playlist.

[**\--playlist-length**](#playlist-length)

Print the number of songs in the playlist.

[**\--playlist-song _position_**](#playlist-song)

Print the formatted title of a song in the playlist.

[**\--playlist-song-filename _position_**](#playlist-song-filename)

Print the file name (full path or URI) of a song in the playlist.

[**\--playlist-song-length _position_**](#playlist-song-length)

Print the length of a song in the playlist in M:SS format.

[**\--playlist-song-length-seconds _position_**](#playlist-song-length-seconds)

Print the length of a song in the playlist in seconds.

[**\--playlist-song-length-frames _position_**](#playlist-song-length-frames)

Print the length of a song in the playlist in milliseconds.

[**\--playlist-tuple-data _field_ _position_**](#playlist-tuple-data)

Print the value of a named field for a song in the playlist.

[**\--playlist-display**](#playlist-display)

Print the titles of all the songs in the playlist.

[**\--playlist-position**](#playlist-position)

Print the position of the current song in the playlist.

[**\--playlist-jump _position_**](#playlist-jump)

Skip to the song at the given position in the playlist.

[**\--playlist-clear**](#playlist-clear)

Clear the playlist.

[**\--playlist-auto-advance-status**](#playlist-auto-advance-status)

Print the status of playlist auto-advance (\`\`on'' or \`\`off'').

[**\--playlist-auto-advance-toggle**](#playlist-auto-advance-toggle)

Toggle playlist auto-advance.

[**\--playlist-repeat-status**](#playlist-repeat-status)

Print the status of playlist repeat (\`\`on'' or \`\`off'').

[**\--playlist-repeat-toggle**](#playlist-repeat-toggle)

Toggle playlist repeat.

[**\--playlist-shuffle-status**](#playlist-shuffle-status)

Print the status of playlist shuffle (\`\`on'' or \`\`off'').

[**\--playlist-shuffle-toggle**](#playlist-shuffle-toggle)

Toggle playlist shuffle.

[**\--playlist-stop-after-status**](#playlist-stop-after-status)

Print the \`\`stop after current song'' option (\`\`on'' or \`\`off'').

[**\--playlist-stop-after-toggle**](#playlist-stop-after-toggle)

Toggle the \`\`stop after current song'' option.

More playlist commands:[¶](#More_playlist_commands:)
----------------------------------------------------

[**\--number-of-playlists**](#number-of-playlists)

Print the number of open playlists.

[**\--current-playlist**](#current-playlist)

Print the number of the current playlist, where "current" is interpreted according to **\--select-displayed** or **\--select-playing**.

[**\--play-current-playlist**](#play-current-playlist)

Start playback in the current playlist, resuming from the last point played if possible. When **\--select-displayed** is in effect, this command can be used to switch playback to the displayed playlist.

[**\--set-current-playlist _playlist_**](#set-current-playlist)

Display the given playlist. When **\--select-playing** is in effect and a different playlist is playing, this command will also switch playback to the given playlist. The **\--select-displayed** option disables this behavior.

[**\--current-playlist-name**](#current-playlist-name)

Print the title of the current playlist.

[**\--set-current-playlist-name _title_**](#set-current-playlist-name)

Set the title of the current playlist.

[**\--new-playlist**](#new-playlist)

Insert a new playlist after the current one and switch to it as if **\--set-current-playlist** were used.

[**\--delete-current-playlist**](#delete-current-playlist)

Remove the current playlist.

Playlist queue commands:[¶](#Playlist_queue_commands:)
------------------------------------------------------

[**\--playqueue-add _position_**](#playqueue-add)

Add the song at the given playlist position to the queue.

[**\--playqueue-remove _position_**](#playqueue-remove)

Remove the song at the given playlist position from the queue.

[**\--playqueue-is-queued _position_**](#playqueue-is-queued)

Return an exit code of 0 (true) if the song at the given playlist position is in the queue.

[**\--playqueue-get-queue-position _position_**](#playqueue-get-queue-position)

Print the queue position of the song at the given playlist position.

[**\--playqueue-get-list-position _position_**](#playqueue-get-list-position)

Print the playlist position of the song at the given queue position.

[**\--playqueue-length**](#playqueue-length)

Print the number of songs in the queue.

[**\--playqueue-display**](#playqueue-display)

Print the titles of all the songs in the queue.

[**\--playqueue-clear**](#playqueue-clear)

Clear the queue.

Volume control and equalizer:[¶](#Volume_control_and_equalizer:)
----------------------------------------------------------------

[**\--get-volume**](#get-volume)

Print the current volume level in percent.

[**\--set-volume _level_**](#set-volume)

Set the current volume level in percent.

[**\--equalizer-activate \[on|off\]**](#equalizer-activate)

Activate or deactivate the equalizer.

[**\--equalizer-get**](#equalizer-get)

Print the equalizer settings (preamp and gain for all bands) in decibels.

[**\--equalizer-set _preamp_ _band0_ _band1_ _band2_ _band3_ _band4_ _band5_ _band6_ _band7_ _band8_ _band9_**](#equalizer-set)

Set the equalizer settings (preamp and gain for all bands) in decibels.

[**\--equalizer-get-preamp**](#equalizer-get-preamp)

Print the equalizer pre-amplification in decibels.

[**\--equalizer-set-preamp _preamp_**](#equalizer-set-preamp)

Set the equalizer pre-amplification in decibels.

[**\--equalizer-get-band _band_**](#equalizer-get-band)

Print the gain of the given equalizer band (0-9) in decibels.

[**\--equalizer-set-band _band_ _gain_**](#equalizer-set-band)

Set the gain of the given equalizer band (0-9) in decibels.

Miscellaneous:[¶](#Miscellaneous:)
----------------------------------

[**\--mainwin-show \[on|off\]**](#mainwin-show)

Show or hide the Audacious window.

[**\--filebrowser-show \[on|off\]**](#filebrowser-show)

Show or hide the Add Files window.

[**\--jumptofile-show \[on|off\]**](#jumptofile-show)

Show or hide the Jump to Song window.

[**\--preferences-show \[on|off\]**](#preferences-show)

Show or hide the Settings window.

[**\--about-show \[on|off\]**](#about-show)

Show or hide the About window.

[**\--version**](#version)

Print version information.

[**\--plugin-is-enabled _plugin_**](#plugin-is-enabled)

Return an exit code of 0 (true) if the given plugin is enabled. The plugin is specified using its installed filename minus the folder path and suffix: for example, **crossfade** for _lib/x86\_64-linux-gnu/audacious/Effect/crossfade.so_.

[**\--plugin-enable _plugin_ \[on|off\]**](#plugin-enable)

Enable or disable the given plugin. Note that interface and output plugins cannot be disabled directly since one of each must always be active. Enabling an interface or output plugin will automatically disable the previous plugin.

[**\--config-get \[_section_:\]_name_**](#config-get)

Print the value of a configuration setting. Any use of this command is entirely unsupported. How to find the _section_ and _name_ of a given setting is left as an exercise for the reader.

[**\--config-set \[_section_:\]_name_ _value_**](#config-set)

Change the value of a configuration setting. This command is unsupported and dangerous. It might have unexpected side effects (such as crashing Audacious), or it might have no effect at all. Use it at your own risk!

[**\--shutdown**](#shutdown)

Shut down Audacious.

[**\--help**](#help)

Print a brief summary of audtool commands.

Commands may be prefixed with \`--' (GNU-style long options) or not, your choice.

BUGS[¶](#BUGS)
==============

There are no known bugs in audtool at this time; if you find any please report them at _[https://github.com/audacious-media-player/audacious/issues](https://github.com/audacious-media-player/audacious/issues)_.

AUTHORS[¶](#AUTHORS)
====================

**audtool** was written by George Averill <nhjm@nhjm.net> and Ariadne Conill <ariadne@dereferenced.org>.

This manual page was written by Adam Cecile <gandalf@le-vert.net> and Kiyoshi Aman <kiyoshi@atheme.org>. Some additional tweaks were done by Ariadne Conill <ariadne@dereferenced.org> and Tony Vroon <chainsaw@gentoo.org>. The manual page was updated for Audacious 3.7 and later by John Lindgren <john@jlindgren.net>.

This work is licensed under a Creative Commons Attribution 3.0 Unported License <[https://creativecommons.org/licenses/by/3.0/](https://creativecommons.org/licenses/by/3.0/)\>.

SEE ALSO[¶](#SEE_ALSO)
======================

[audacious(1)](https://manpages.debian.org/testing/audacious/audacious.1.en.html)

WEBSITE[¶](#WEBSITE)
====================

_[https://audacious-media-player.org](https://audacious-media-player.org/)_

September 2017

Version 4.5.1

Source file:

audtool.1.en.gz (from [audacious 4.5.1-1](http://snapshot.debian.org/package/audacious/4.5.1-1/))

Source last updated:

2025-10-05T10:17:49Z

Converted to HTML:

2025-12-30T10:44:19Z

* * *

debiman HEAD, see [github.com/Debian/debiman](https://github.com/Debian/debiman/). Found a problem? See the [FAQ](https://manpages.debian.org/faq.html).

"{\\"@context\\":\\"http://schema.org\\",\\"@type\\":\\"BreadcrumbList\\",\\"itemListElement\\":\[{\\"@type\\":\\"ListItem\\",\\"position\\":1,\\"item\\":{\\"@type\\":\\"Thing\\",\\"@id\\":\\"/contents-testing.html\\",\\"name\\":\\"testing\\"}},{\\"@type\\":\\"ListItem\\",\\"position\\":2,\\"item\\":{\\"@type\\":\\"Thing\\",\\"@id\\":\\"/testing/audacious/index.html\\",\\"name\\":\\"audacious\\"}},{\\"@type\\":\\"ListItem\\",\\"position\\":3,\\"item\\":{\\"@type\\":\\"Thing\\",\\"@id\\":\\"\\",\\"name\\":\\"audtool(1)\\"}}\]}"
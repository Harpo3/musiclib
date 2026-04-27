##   audtool(1) — audacious 

     
[Skip Quicknav](#content)

*   [Index](https://manpages.debian.org/)
*   [About Manpages](https://manpages.debian.org/about.html)
*   [FAQ](https://manpages.debian.org/faq.html)
*   [Service Information](https://wiki.debian.org/manpages.debian.org)

  / [testing](https://manpages.debian.org/contents-testing.html) / [audacious](https://manpages.debian.org/testing/audacious/index.html) / audtool(1)

link

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

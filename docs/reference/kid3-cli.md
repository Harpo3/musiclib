## kid3-cli 

[SYNOPSIS](#SYNOPSIS)
=====================

**kid3-cli**  
\[**\--portable**\]  
\[**\--dbus**\]  
\[  
| **\-h**  
| **\--help** \]  
\[**\-c COMMAND1**\]  
\[**\-c COMMAND2**...\]  
\[_FILE_...\]


kid3-cli
--------

**\--dbus**

Activate the D-Bus interface.

**\-c**

Execute a command. Multiple **\-c** options are possible, they are executed in sequence. See the section about kid3-cli for a description of the available commands.

**\-h**|**\--help**

Show help about options and commands.



[KID3-CLI](#KID3-CLI)
=====================

[Commands](#Commands)
---------------------

**kid3-cli** offers a command-line-interface for Kid3. If a folder path is used, the folder is opened. If one or more file paths are given, the common folder is opened and the files are selected. Subsequent commands will then work on these files. **Commands are specified using **\-c** options.** If multiple commands are passed, they are executed in the given order. If files are modified by the commands, they will be saved at the end. 

### Command-line vs. Interactive Mode

If no command options are passed, **kid3-cli** starts in interactive mode. Commands can be entered and will operate on the current selection. The following sections list all available commands.

**Help**  

**help**  
\[_COMMAND-NAME_\]

Displays help about the parameters of _COMMAND-NAME_ or about all commands if no command name is given.

**Timeout**  

**timeout**  
\[  
| default  
| off  
| _TIME_ \]

Overwrite the default command timeout. The CLI commands abort after a command specific timeout is expired. This timeout is 10 seconds for **ls** and **albumart**, 60 seconds for **autoimport** and **filter**, and 3 seconds for all other commands. If a huge number of files has to be processed, these timeouts may be too restrictive, thus the timeout for all commands can be set to _TIME_ ms, switched off altogether or be left at the default values.

**Quit application**  

**exit**  
\[force\]

Exit application. If there are modified unsaved files, the _force_ parameter is required.

**Change folder**  

**cd**  
\[_FOLDER_\]

If no _FOLDER_ is given, change to the home folder. If a folder is given, change into the folder. If one or more file paths are given, change to their common folder and select the files.

**Print the filename of the current folder**  

**pwd**

Print the filename of the current working folder.

**Folder list**  

**ls**

List the contents of the current folder. This corresponds to the file list in the Kid3 GUI. Five characters before the file names show the state of the file.

•> File is selected.

•\* File is modified.

•1 File has a tag 1, otherwise '-' is displayed.

•2 File has a tag 2, otherwise '-' is displayed.

•3 File has a tag 3, otherwise '-' is displayed.

kid3-cli> **ls**
  1-- 01 Intro.mp3
> 12- 02 We Only Got This One.mp3
 \*1-- 03 Outro.mp3

In this example, all files have a tag 1, the second file also has a tag 2 and it is selected. The third file is modified.

**Save the changed files**  

**save**

**Select file**  

**select**  
\[  
| all  
| none  
| first  
| previous  
| next  
| _FILE_... \]

To select all files, enter **select all**, to deselect all files, enter **select none**. To traverse the files in the current folder start with **select first**, then go forward using **select next** or backward using **select previous**. Specific files can be added to the current selection by giving their file names. Wildcards are possible, so **select \*.mp3** will select all MP3 files in the current folder.

kid3-cli> **select first**
kid3-cli> **ls**
> 1-- 01 Intro.mp3
  12- 02 We Only Got This One.mp3
 \*1-- 03 Outro.mp3
kid3-cli> **select next**
kid3-cli> **ls**
  1-- 01 Intro.mp3
> 12- 02 We Only Got This One.mp3
 \*1-- 03 Outro.mp3
kid3-cli> **select \*.mp3**
kid3-cli> **ls**
> 1-- 01 Intro.mp3
> 12- 02 We Only Got This One.mp3
>\*1-- 03 Outro.mp3

**Select tag**  

**tag**  
\[_TAG-NUMBERS_\]

Many commands have an optional _TAG-NUMBERS_ parameter, which specifies whether the command operates on tag 1, 2, or 3. If this parameter is omitted, the default tag numbers are used, which can be set by this command. At startup, it is set to 12 which means that information is read from tag 2 if available, else from tag 1; modifications are done on tag 2. The _TAG-NUMBERS_ can be set to **1**, **2**, or **3** to operate only on the corresponding tag. If the parameter is omitted, the current setting is displayed.

**Get tag frame**  

**get**  
\[  
| all  
| _FRAME-NAME_ \]  
\[_TAG-NUMBERS_\]

This command can be used to read the value of a specific tag frame or get information about all tag frames (if the argument is omitted or **all** is used). Modified frames are marked with a '\*'.

kid3-cli> **get**
File: MPEG 1 Layer 3 192 kbps 44100 Hz Joint Stereo
  Name: 01 Intro.mp3
Tag 1: ID3v1.1
  Title         Intro
  Artist        One Hit Wonder
  Album         Let's Tag
  Date          2013
  Track Number  1
  Genre         Pop
kid3-cli> **get title**
Intro

To save the contents of a picture frame to a file, use

**get picture:'/path/to/folder.jpg'**

To save synchronized lyrics to an LRC file, use

**get SYLT:'/path/to/lyrics.lrc'**

It is possible to get only a specific field from a frame, for example **get POPM.Email** for the Email field of a Popularimeter frame. If a file has multiple frames of the same kind, the different frames can be indexed with brackets, for example the first performer from a Vorbis comment can be retrieved using **get performer\[0\]**, the second using **get performer\[1\]**.

The pseudo field name "selected" can be used to check if a frame is selected, for example **get artist.selected** will return 1 if the artist frame is selected, else 0.

The pseudo frame name "ratingstars" can be used to get the value of the "rating" frame as the format specific value corresponding to the number of stars (0 to 5). When using "rating", the internal value is returned.

**Set tag frame**  

**set**  
{_FRAME-NAME_}  
{_FRAME-VALUE_}  
\[_TAG-NUMBERS_\]

This command sets the value of a specific tag frame. If _FRAME-VALUE_ is empty, the frame is deleted.

kid3-cli> **set remixer 'O.H. Wonder'**

To set the contents of a picture frame from a file, use

**set picture:'/path/to/folder.jpg' 'Picture Description'**

To set synchronized lyrics from an LRC file, use

**set SYLT:'/path/to/lyrics.lrc' 'Lyrics Description'**

To set a specific field of a frame, the field name can be given after a dot, e.g. to set the Counter field of a Popularimeter frame, use

**set POPM.Counter 5**

An application for field specifications is the case where you want a custom TXXX frame with "rating" description instead of a standard Popularimeter frame (this seems to be used by some plugins). You can create such a TXXX rating frame with **kid3-cli**, however, you have to first create a TXXX frame with description "rating" and then set the value of this frame to the rating value.

kid3-cli> **set rating ""**
kid3-cli> **set TXXX.Description rating**
kid3-cli> **set rating 5**

The first command will delete an existing POPM frame, because if such a frame exists, **set rating 5** would set the POPM frame and not the TXXX frame. Another possibility would be to use **set TXXX.Text 5**, but this would only work if there is no other TXXX frame present.

To set multiple frames of the same kind, an index can be given in brackets, e.g. to set multiple performers in a Vorbis comment, use

kid3-cli> **set performer\[0\] 'Liza don Getti (soprano)'**
kid3-cli> **set performer\[1\] 'Joe Barr (piano)'**

To select certain frames before a copy, paste or remove action, the pseudo field name "selected" can be used. Normally, all frames are selected, to deselect all, use **set '\*.selected' 0**, then for example **set artist.selected 1** to select the artist frame.

The pseudo frame name "ratingstars" can be used to set the value of the "rating" frame to the format specific value corresponding to the number of stars (0 to 5). The frame name "rating" can be used to set the internal value.

Setting "ratingstars" on multiple files having different tag formats will not work because the frame with the value mapped from the star count is created for the first file and then used for all files. So instead of **kid3-cli -c "set ratingstars 2" \*** you should rather use **for f in \*; do kid3-cli -c "set ratingstars 2" "$f"; done**.

**Revert**  

**revert**

Revert all modifications in the selected files (or all files if no files are selected).

**Import from file**  

**import**  
{_FILE_}  
{_FORMAT-NAME_}  
\[_TAG-NUMBERS_\]

Tags are imported from the file _FILE_ in the format with the name _FORMAT-NAME_ (e.g. **"CSV unquoted"**, see Import).

If **tags** is given for _FILE_, tags are imported from other tags. Instead of _FORMAT-NAME_ parameters _SOURCE_ and _EXTRACTION_ are required, see Import from Tags. To apply the import from tags on the selected files, use **tagsel** instead of **tags**. This function also supports output of the extracted value by using an _EXTRACTION_ with the value **%{\_\_return}(.+)**.

**Automatic import**  

**autoimport**  
\[_PROFILE-NAME_\]  
\[_TAG-NUMBERS_\]

Batch import using profile _PROFILE-NAME_ (see Automatic Import, **"All"** is used if omitted).

**Download album cover artwork**  

**albumart**  
{_URL_}  
\[all\]

Set the album artwork by downloading a picture from _URL_. The rules defined in the Browse Cover Art dialog are used to transform general URLs (e.g. from Amazon) to a picture URL. To set the album cover from a local picture file, use the set command.

kid3-cli> **albumart**
**http://www.amazon.com/Versus-World-Amon-Amarth/dp/B000078DOC**

**Export to file**  

**export**  
{_FILE_}  
{_FORMAT-NAME_}  
\[_TAG-NUMBERS_\]

Tags are exported to file _FILE_ in the format with the name _FORMAT-NAME_ (e.g. **"CSV unquoted"**, see Export).

**Create playlist**  

**playlist**

Create playlist in the format set in the configuration, see Create Playlist.

**Apply filename format**  

**filenameformat**

Apply file name format set in the configuration, see Apply Filename Format.

**Apply tag format**  

**tagformat**

Apply tag name format set in the configuration, see Apply Tag Format.

**Apply text encoding**  

**textencoding**

Apply text encoding set in the configuration, see Apply Text Encoding.

**Rename folder**  

**renamedir**  
\[_FORMAT_\]  
\[  
| create  
| rename  
| dryrun \]  
\[_TAG-NUMBERS_\]

Rename or create folders from the values in the tags according to a given _FORMAT_ (e.g. **%{artist} - %{album}**, see Rename Folder), if no format is given, the format defined in the Rename folder dialog is used. The default mode is **rename**; to create folders, **create** must be given explicitly. The rename actions will be performed immediately, to just see what would be done, use the **dryrun** option.

**Number tracks**  

**numbertracks**  
\[_TRACK-NUMBER_\]  
\[_TAG-NUMBERS_\]

Number the selected tracks starting with _TRACK-NUMBER_ (1 if omitted).

**Filter**  

**filter**  
\[  
| _FILTER-NAME_  
| _FILTER-FORMAT_ \]

Filter the files so that only the files matching the _FILTER-FORMAT_ are visible. The name of a predefined filter expression (e.g. **"Filename Tag Mismatch"**) can be used instead of a filter expression, see Filter.

kid3-cli> **filter '%{title} contains "tro"'**
Started
  /home/urs/One Hit Wonder - Let's Tag
+ 01 Intro.mp3
- 02 We Only Got This One.mp3
+ 03 Outro.mp3
Finished
kid3-cli> **ls**
  1-- 01 Intro.mp3
  1-- 03 Outro.mp3
kid3-cli> **filter All**
Started
  /home/urs/One Hit Wonder - Let's Tag
+ 01 Intro.mp3
+ 02 We Only Got This One.mp3
+ 03 Outro.mp3
Finished
kid3-cli> **ls**
  1-- 01 Intro.mp3
  12- 02 We Only Got This One.mp3
  1-- 03 Outro.mp3

**Convert ID3v2.3 to ID3v2.4**  

**to24**

**Convert ID3v2.4 to ID3v2.3**  

**to23**

**Filename from tag**  

**fromtag**  
\[_FORMAT_\]  
\[_TAG-NUMBERS_\]

Set the file names of the selected files from values in the tags, for example **fromtag '%{track} - %{title}' 1**. If no format is specified, the format set in the GUI is used.

**Tag from filename**  

**totag**  
\[_FORMAT_\]  
\[_TAG-NUMBERS_\]

Set the tag frames from the file names, for example **totag '%{albumartist} - %{album}/%{track} %{title}' 2**. If no format is specified, the format set in the GUI is used. If the format of the filename does not match this pattern, a few other commonly used formats are tried.

**Tag to other tag**  

**syncto**  
{_TAG-NUMBER_}

Copy the tag frames from one tag to the other tag, e.g. to set the ID3v2 tag from the ID3v1 tag, use **syncto 2**.

**Copy**  

**copy**  
\[_TAG-NUMBER_\]

Copy the tag frames of the selected file to the internal copy buffer. They can then be set on another file using the **paste** command.

To copy only a subset of the frames, use the "selected" pseudo field with the **set** command. For example, to copy only the disc number and copyright frames, use

**set '\*.selected' 0**
**set discnumber.selected 1**
**set copyright.selected 1**
**copy**

**Paste**  

**paste**  
\[_TAG-NUMBER_\]

Set tag frames from the contents of the **copy** buffer in the selected files.

**Remove**  

**remove**  
\[_TAG-NUMBER_\]

Remove a tag.

It is possible to remove only a subset of the frames by selecting them as described in the **copy** command.

**Configure Kid3**  

**config**  
\[_OPTION_\]  
\[_VALUE_\]

Query or set a configuration option.

The _OPTION_ consists of a group name and a property name separated by a dot. When no _OPTION_ is given, all available groups are displayed. If only a group name is given, all available properties of the group are displayed. For a given group and property, the currently configured value is displayed. To change the setting, the new value can be passed as a second argument.

If the value of a setting is a list, all list elements have to be given as arguments. This means that to append an element to an existing list of elements, all existing elements have to be passed followed by the new element. In such a situation, it is easier to use the JSON mode, where the current list can be copied with the new element appended.

**Execute program or QML script**  

**execute**  
\[@qml\]  
{_FILE_}  
\[_ARGS_\]

Execute a QML script or an executable.

Without **@qml** a program is executed with arguments. When **@qml** is given as the first argument, the following arguments are the QML script and its arguments. For example, the tags of a folder can be exported to the file export.csv with the following command.

**kid3-cli -c "execute @qml**
**/usr/share/kid3/qml/script/ExportCsv.qml export.csv"**
**/path/to/folder/**

Here **export.csv** is the argument for the ExportCsv.qml script, whereas **/path/to/folder/** is the _FILE_ argument for **kid3-cli**.

[Examples](#Examples)
---------------------

Set title containing an apostrophe. Commands passed to **kid3-cli** with _\-c_ have to be in quotes if they do not only consist of a single word. If such a command itself has an argument containing spaces, that argument has to be quoted too. In UNIX® shells single or double quotes can be used, but on the Windows Command Prompt, it is important that the outer quoting is done using double quotes and inside these quotes, single quotes are used. If the text inside the single quotes contains a single quote, it has to be escaped using a backslash character, as shown in the following example:

**kid3-cli -c "set title 'I\\'ll be there for you'" /path/to/folder**

Set album cover in all files of a folder using the batch import function:

**kid3-cli -c "autoimport 'Cover Art'" /path/to/folder**

Remove comment frames and apply the tag format in both tags of all MP3 files of a folder:

**kid3-cli -c "set comment '' 1" -c "set comment '' 2" \\**
**\-c "tagformat 1" -c "tagformat 2" /path/to/folder/\*.mp3**

Automatically import tag 2, synchronize to tag 1, set file names from tag 2 and finally create a playlist:

**kid3-cli -c autoimport -c "syncto 1" -c fromtag -c playlist \\**
  **/path/to/folder/\*.mp3**

For all files with an ID3v2.4.0 tag, convert to ID3v2.3.0 and remove the arranger frame:

**kid3-cli -c "filter 'ID3v2.4.0 Tag'" -c "select all" -c to23 \\**
  **-c "set arranger ''" /path/to/folder**

This Python script uses **kid3-cli** to generate iTunes Sound Check iTunNORM frames from replay gain information.

#!/usr/bin/env python3
# Generate iTunes Sound Check from ReplayGain.
import os, sys, subprocess
def rg2sc(dirpath):
  for root, dirs, files in os.walk(dirpath):
    for name in files:
      if name.endswith(('.mp3', '.m4a', '.aiff', '.aif')):
        fn = os.path.join(root, name)
        rg = subprocess.check\_output(\[
          'kid3-cli', '-c', 'get "replaygain\_track\_gain"',
           fn\]).strip()
        if rg.endswith(b' dB'):
          rg = rg\[:-3\]
        try:
          rg = float(rg)
        except ValueError:
          print('Value %s of %s in not a float' % (rg, fn))
          continue
        sc = (' ' + ('%08X' % int((10 \*\* (-rg / 10)) \* 1000) )) \* 10
        subprocess.call(\[
          'kid3-cli', '-c', 'set iTunNORM "%s"' % sc, fn\])
if \_\_name\_\_ == '\_\_main\_\_':
  rg2sc(sys.argv\[1\])

[JSON Format](#JSON_Format)
---------------------------

In order to make it easier to parse results from **kid3-cli**, it is possible to get the output in JSON format. When the request is in JSON format, the response will also be JSON. A compact format of the request will also give a compact representation of the response. If the request contains an "id" field, it is assumed to be a JSON-RPC request and the response will contain a "jsonrpc" field and the "id" of the request. The request format uses the same commands as the standard CLI, the "method" field contains the command and the parameters (if any) are given in the "params" list. The response contains a "result" object, which can also be null if the corresponding **kid3-cli** command does not return a result. In case of an error, an "error" object is returned with "code" and "message" fields as used in JSON-RPC.

kid3-cli> **{"method":"set","params":\["artist","An Artist"\]}**
{"result":null}
kid3-cli> **{"method":"get","params":\["artist",2\]}**
{"result":"An Artist"}
kid3-cli> **{"method": "get", "params": \["artist"\]}**
{
    "result": "An Artist"
}
kid3-cli> **{"jsonrpc":"2.0","id":"123","method":"get","params":\["artist"\]}**
{"id":"123","jsonrpc":"2.0","result":"An Artist"}


[Configuration](#Configuration)
-------------------------------

With KDE, the settings are stored in .config/kid3rc, the application state in .local/share/kid3/kid3staterc. As a Qt(TM) application, this file is in .config/Kid3/Kid3.conf. On Windows®, the configuration is stored in the registry. on macOS® in a plist file.

The environment variable _KID3\_CONFIG\_FILE_ can be used to set the path of the configuration file.

[D-BUS INTERFACE](#D-BUS_INTERFACE)
===================================

D-Bus Examples
--------------

On Linux® a D-Bus-interface can be used to control Kid3 by scripts. Scripts can be written in any language with D-Bus-bindings (e.g. in Python) and can be added to the User Actions to extend the functionality of Kid3.

The artist in tag 2 of the current file can be set to the value "One Hit Wonder" with the following code:

Shell

dbus-send --dest=org.kde.kid3 --print-reply=literal \\
/Kid3 org.kde.Kid3.setFrame int32:2 string:'Artist' \\
string:'One Hit Wonder'

or easier with Qt(TM)'s **qdbus** (**qdbusviewer** can be used to explore the interface in a GUI):

qdbus org.kde.kid3 /Kid3 setFrame 2 Artist \\
'One Hit Wonder'

Python

import dbus
kid3 = dbus.SessionBus().get\_object(
  'org.kde.kid3', '/Kid3')
kid3.setFrame(2, 'Artist', 'One Hit Wonder')

Perl

use Net::DBus;
$kid3 = Net::DBus->session->get\_service(
  "org.kde.kid3")->get\_object(
  "/Kid3", "org.kde.Kid3");
$kid3->setFrame(2, "Artist", "One Hit Wonder");

D-Bus API
---------

The D-Bus API is specified in org.kde.Kid3.xml. The Kid3 interface has the following methods:

**Open file or folder**  

**boolean openDirectory(string** _path_**);**

  
.PP _path_

  
path to file or folder

  
.RE

Returns true if OK.

**Unload the tags of all files which are not modified or selected**  

**unloadAllTags(void);**

**Save all modified files**  

**boolean save(void);**

Returns true if OK.

**Get a detailed error message provided by some methods**  

**string getErrorMessage(void);**

Returns detailed error message.

**Revert changes in the selected files**  

**revert(void);**

**Start an automatic batch import**  

**boolean batchImport(int32** _tagMask_**, string** _profileName_**);**

  
.PP _tagMask_

  
tag mask (bit 0 for tag 1, bit 1 for tag 2)

  
.RE  
.PP _profileName_

  
name of batch import profile to use

  
.RE

**Import tags from a file**  

**boolean importFromFile(int32** _tagMask_**, string** _path_**, int32** _fmtIdx_**);**

  
.PP _tagMask_

  
tag bit (1 for tag 1, 2 for tag 2)

  
.RE  
.PP _path_

  
path of file

  
.RE  
.PP _fmtIdx_

  
index of format

  
.RE

Returns true if OK.

**Import tags from other tags**  

**importFromTags(int32** _tagMask_**, string** _source_**, string** _extraction_**);**

  
.PP _tagMask_

  
tag bit (1 for tag 1, 2 for tag 2)

  
.RE  
.PP _source_

  
format to get source text from tags

  
.RE  
.PP _extraction_

  
regular expression with frame names and captures to extract from source text

  
.RE

**Import tags from other tags on selected files**  

**array importFromTagsToSelection(int32** _tagMask_**, string** _source_**, string** _extraction_**);**

  
.PP _tagMask_

  
tag bit (1 for tag 1, 2 for tag 2)

  
.RE  
.PP _source_

  
format to get source text from tags

  
.RE  
.PP _extraction_

  
regular expression with frame names and captures to extract from source text

  
.RE

  
.PP _returnValues_

  
extracted value for "%{\_\_return}(.+)"

  
.RE

**Download album cover art**  

**downloadAlbumArt(string** _url_**, boolean** _allFilesInDir_**);**

  
.PP _url_

  
URL of picture file or album art resource

  
.RE  
.PP _allFilesInDir_

  
true to add the image to all files in the folder

  
.RE

**Export tags to a file**  

**boolean exportToFile(int32** _tagMask_**, string** _path_**, int32** _fmtIdx_**);**

  
.PP _tagMask_

  
tag bit (1 for tag 1, 2 for tag 2)

  
.RE  
.PP _path_

  
path of file

  
.RE  
.PP _fmtIdx_

  
index of format

  
.RE

Returns true if OK.

**Create a playlist**  

**boolean createPlaylist(void);**

Returns true if OK.

**Get items of a playlist**  

**array getPlaylistItems(string** _path_**);**

  
.PP _path_

  
path to playlist file

  
.RE

Returns list of absolute paths to playlist items.

**Set items of a playlist**  

**boolean setPlaylistItems(string** _path_**, array** _items_**);**

  
.PP _path_

  
path to playlist file

  
.RE  
.PP _items_

  
list of absolute paths to playlist items

  
.RE

Returns true if OK, false if not all items were found and added or saving failed.

**Quit the application**  

**quit(void);**

**Select all files**  

**selectAll(void);**

**Deselect all files**  

**deselectAll(void);**

**Set the first file as the current file**  

**boolean firstFile(void);**

Returns true if there is a first file.

**Set the previous file as the current file**  

**boolean previousFile(void);**

Returns true if there is a previous file.

**Set the next file as the current file**  

**boolean nextFile(void);**

Returns true if there is a next file.

**Select the first file**  

**boolean selectFirstFile(void);**

Returns true if there is a first file.

**Select the previous file**  

**boolean selectPreviousFile(void);**

Returns true if there is a previous file.

**Select the next file**  

**boolean selectNextFile(void);**

Returns true if there is a next file.

**Select the current file**  

**boolean selectCurrentFile(void);**

Returns true if there is a current file.

**Expand or collapse the current file item if it is a folder**  

**boolean expandDirectory(void);**

A file list item is a folder if getFileName() returns a name with '/' as the last character.

Returns true if current file item is a folder.

**Apply the file name format**  

**applyFilenameFormat(void);**

**Apply the tag format**  

**applyTagFormat(void);**

**Apply text encoding**  

**applyTextEncoding(void);**

**Set the folder name from the tags**  

**boolean setDirNameFromTag(int32** _tagMask_**, string** _format_**, boolean** _create_**);**

  
.PP _tagMask_

  
tag mask (bit 0 for tag 1, bit 1 for tag 2)

  
.RE  
.PP _format_

  
folder name format

  
.RE  
.PP _create_

  
true to create, false to rename

  
.RE

Returns true if OK, else the error message is available using getErrorMessage().

**Set subsequent track numbers in the selected files**  

**numberTracks(int32** _tagMask_**, int32** _firstTrackNr_**);**

  
.PP _tagMask_

  
tag mask (bit 0 for tag 1, bit 1 for tag 2)

  
.RE  
.PP _firstTrackNr_

  
number to use for first file

  
.RE

**Filter the files**  

**filter(string** _expression_**);**

  
.PP _expression_

  
filter expression

  
.RE

**Convert ID3v2.3 tags to ID3v2.4**  

**convertToId3v24(void);**

**Convert ID3v2.4 tags to ID3v2.3**  

**convertToId3v23(void);**

Returns true if OK.

**Get path of folder**  

**string getDirectoryName(void);**

Returns absolute path of folder.

**Get name of current file**  

**string getFileName(void);**

Returns true absolute file name, ends with "/" if it is a folder.

**Set name of selected file**  

**setFileName(string** _name_**);**

  
.PP _name_

  
file name

  
.RE

The file will be renamed when the folder is saved.

**Set format to use when setting the filename from the tags**  

**setFileNameFormat(string** _format_**);**

  
.PP _format_

  
file name format

  
.RE

**Set the file names of the selected files from the tags**  

**setFileNameFromTag(int32** _tagMask_**);**

  
.PP _tagMask_

  
tag bit (1 for tag 1, 2 for tag 2)

  
.RE

**Get value of frame**  

**string getFrame(int32** _tagMask_**, string** _name_**);**

  
.PP _tagMask_

  
tag bit (1 for tag 1, 2 for tag 2)

  
.RE  
.PP _name_

  
name of frame (e.g. "artist")

  
.RE

To get binary data like a picture, the name of a file to write can be added after the _name_, e.g. "Picture:/path/to/file". In the same way, synchronized lyrics can be exported, e.g. "SYLT:/path/to/file".

Returns value of frame.

**Set value of frame**  

**boolean setFrame(int32** _tagMask_**, string** _name_**, string** _value_**);**

  
.PP _tagMask_

  
tag bit (1 for tag 1, 2 for tag 2)

  
.RE  
.PP _name_

  
name of frame (e.g. "artist")

  
.RE  
.PP _value_

  
value of frame

  
.RE

For tag 2 (_tagMask_ 2), if no frame with _name_ exists, a new frame is added, if _value_ is empty, the frame is deleted. To add binary data like a picture, a file can be added after the _name_, e.g. "Picture:/path/to/file". "SYLT:/path/to/file" can be used to import synchronized lyrics.

Returns true if OK.

**Get all frames of a tag**  

**array of string getTag(int32** _tagMask_**);**

  
.PP _tagMask_

  
tag bit (1 for tag 1, 2 for tag 2)

  
.RE

Returns list with alternating frame names and values.

**Get technical information about file**  

**array of string getInformation(void);**

Properties are Format, Bitrate, Samplerate, Channels, Duration, Channel Mode, VBR, Tag 1, Tag 2. Properties which are not available are omitted.

Returns list with alternating property names and values.

**Set tag from file name**  

**setTagFromFileName(int32** _tagMask_**);**

  
.PP _tagMask_

  
tag bit (1 for tag 1, 2 for tag 2)

  
.RE

**Set tag from other tag**  

**setTagFromOtherTag(int32** _tagMask_**);**

  
.PP _tagMask_

  
tag bit (1 for tag 1, 2 for tag 2)

  
.RE

**Copy tag**  

**copyTag(int32** _tagMask_**);**

  
.PP _tagMask_

  
tag bit (1 for tag 1, 2 for tag 2)

  
.RE

**Paste tag**  

**pasteTag(int32** _tagMask_**);**

  
.PP _tagMask_

  
tag bit (1 for tag 1, 2 for tag 2)

  
.RE

**Remove tag**  

**removeTag(int32** _tagMask_**);**

  
.PP _tagMask_

  
tag bit (1 for tag 1, 2 for tag 2)

  
.RE

**Reparse the configuration**  

**reparseConfiguration(void);**

Automated configuration changes are possible by modifying the configuration file and then reparsing the configuration.

**Plays the selected files**  

**playAudio(void);**

[QML INTERFACE](#QML_INTERFACE)
===============================

[QML Examples](#QML_Examples)
-----------------------------

QML scripts can be invoked via the context menu of the file list and can be set in the tab User Actions of the settings dialog. The scripts which are set there can be used as examples to program custom scripts. QML uses JavaScript, here is the obligatory "Hello World":

import Kid3 1.0
Kid3Script {
  onRun: {
    console.log("Hello world, folder is", app.dirName)
    Qt.quit()
  }
}

If this script is saved as /path/to/Example.qml, the user command can be defined as **@qml /path/to/Example.qml** with name **QML Test** and Output checked. It can then be started using the QML Test item in the file list context menu, and the output will be visible in the window.

Unfortunately, starting the QML scripts using the **qml** (e.g. **qml -apptype widget -I /usr/lib/kid3/plugins/imports /path/to/Example.qml**) is broken in recent versions of Qt. But **kid3-cli** offers an alternative way to run a QML script from the command line using its **execute** command.

kid3-cli -c "execute @qml /path/to/Example.qml"

To list the titles in the tags 2 of all files in the current folder, the following script could be used:

import Kid3 1.0
Kid3Script {
  onRun: {
    app.firstFile()
    do {
      if (app.selectionInfo.tag(Frame.Tag\_2).tagFormat) {
        console.log(app.getFrame(tagv2, "title"))
      }
    } while (app.nextFile())
  }
}

If the folder contains many files, such a script might block the user interface for some time. For longer operations, it should therefore have a break from time to time. The alternative implementation below has the work for a single file moved out into a function. This function invokes itself with a timeout of 1 ms at the end, given that more files have to be processed. This will ensure that the GUI remains responsive while the script is running.

import Kid3 1.0
Kid3Script {
  onRun: {
    function doWork() {
      if (app.selectionInfo.tag(Frame.Tag\_2).tagFormat) {
        console.log(app.getFrame(tagv2, "title"))
      }
      if (!app.nextFile()) {
        Qt.quit()
      } else {
        setTimeout(doWork, 1)
      }
    }
    app.firstFile()
    doWork()
  }
}

When using **app.firstFile()** with **app.nextFile()**, all files of the current folder will be processed. If only the selected files shall be affected, use **firstFile()** and **nextFile()** instead, these are convenience functions of the Kid3Script component. The following example is a script which copies only the disc number and copyright frames of the selected file.

import Kid3 1.1
Kid3Script {
  onRun: {
    function doWork() {
      if (app.selectionInfo.tag(Frame.Tag\_2).tagFormat) {
        app.setFrame(tagv2, "\*.selected", false)
        app.setFrame(tagv2, "discnumber.selected", true)
        app.setFrame(tagv2, "copyright.selected", true)
        app.copyTags(tagv2)
      }
      if (!nextFile()) {
        Qt.quit()
      } else {
        setTimeout(doWork, 1)
      }
    }
    firstFile()
    doWork()
  }
}

More example scripts come with Kid3 and are already registered as user commands.

•ReplayGain to SoundCheck (ReplayGain2SoundCheck.qml): Create iTunNORM SoundCheck information from replay gain frames.

•Resize Album Art (ResizeAlbumArt.qml): Resize embedded cover art images which are larger than 500x500 pixels.

•Extract Album Art (ExtractAlbumArt.qml): Extract all embedded cover art pictures avoiding duplicates.

•Embed Album Art (EmbedAlbumArt.qml): Embed cover art found in image files into audio files in the same folder.

•Embed Lyrics (EmbedLyrics.qml): Fetch unsynchronized lyrics from web service.

•Text Encoding ID3v1 (ShowTextEncodingV1.qml): Helps to find the encoding of ID3v1 tags by showing the tags of the current file in all available character encodings.

•ID3v1 to ASCII (Tag1ToAscii.qml): Transliterate extended latin characters in the ID3v1 tag to ASCII.

•English Title Case (TitleCase.qml): Formats text in the tags to English title case.

•Rewrite Tags (RewriteTags.qml): Rewrite all tags in the selected files.

•Export CSV (ExportCsv.qml): Export recursively all tags of all files to a CSV file.

•Import CSV (ImportCsv.qml): Import recursively all tags of all files from a CSV file.

•Export JSON (ExportJson.qml): Export recursively all tags of all files to a JSON file.

•Import JSON (ImportJson.qml): Import recursively all tags of all files from a JSON file.

•Export Playlist Folder (ExportPlaylist.qml): Copy all files from a playlist into a folder and rename them according to their position.

•QML Console (QmlConsole.qml): Simple console to play with Kid3's QML API.

[QML API](#QML_API)
-------------------

The API can be easily explored using the QML Console, which is available as an example script with a user interface.

**Kid3Script**  

Kid3Script is a regular QML component located inside the plugin folder. You could use another QML component just as well. Using Kid3Script makes it easy to start the script function using the **onRun** signal handler. Moreover it offers some functions:

onRun: Signal handler which is invoked when the script is started
tagv1, tagv2, tagv2v1: Constants for tag parameters
script: Access to scripting functions
configs: Access to configuration objects
getArguments(): List of script arguments
isStandalone(): true if the script was not started from within Kid3
setTimeout(callback, delay): Starts callback after delay ms
firstFile(): To first selected file
nextFile(): To next selected file

**Scripting Functions**  

As JavaScript and therefore QML too has only a limited set of functions for scripting, the **script** object has some additional methods, for instance:

script.properties(obj): String with Qt properties
script.writeFile(filePath, data): Write data to file, true if OK
script.readFile(filePath): Read data from file
script.removeFile(filePath): Delete file, true if OK
script.fileExists(filePath): true if file exists
script.fileIsWritable(filePath): true if file is writable
script.getFilePermissions(filePath): Get file permission mode bits
script.setFilePermissions(filePath, modeBits): Set file permission mode bits
script.classifyFile(filePath): Get class of file (folder "/", symlink "@", exe "\*",
  file " ")
script.renameFile(oldName, newName): Rename file, true if OK
script.copyFile(source, dest): Copy file, true if OK
script.makeDir(path): Create folder, true if OK
script.removeDir(path): Remove folder, true if OK
script.tempPath(): Path to temporary folder
script.musicPath(): Path to music folder
script.listDir(path, \[nameFilters\], \[classify\]): List folder entries
script.system(program, \[args\], \[msecs\]): Synchronously start a system command,
  \[exit code, standard output, standard error\] if not timeout
script.systemAsync(program, \[args\], \[callback\]): Asynchronously start a system
command, callback will be called with \[exit code, standard output, standard
error\]
script.getEnv(varName): Get value of environment variable
script.setEnv(varName, value): Set value of environment variable
script.getQtVersion(): Qt version string, e.g. "5.4.1"
script.getDataMd5(data): Get hex string of the MD5 hash of data
script.getDataSize(data): Get size of byte array
script.dataToImage(data, \[format\]): Create an image from data bytes
script.dataFromImage(img, \[format\]): Get data bytes from image
script.loadImage(filePath): Load an image from a file
script.saveImage(img, filePath, \[format\]): Save an image to a file, true if OK
script.imageProperties(img): Get properties of an image, map containing
  "width", "height", "depth" and "colorCount", empty if invalid image
script.scaleImage(img, width, \[height\]): Scale an image, returns scaled image

**Application Context**  

Using QML, a large part of the Kid3 functions are accessible. The API is similar to the one used for D-Bus. For details, refer to the respective notes.

app.openDirectory(path): Open folder
app.unloadAllTags(): Unload all tags
app.saveDirectory(): Save folder
app.revertFileModifications(): Revert
app.importTags(tag, path, fmtIdx): Import file
app.importFromTags(tag, source, extraction): Import from tags
app.importFromTagsToSelection(tag, source, extraction): Import from tags of selected files
app.downloadImage(url, allFilesInDir): Download image
app.exportTags(tag, path, fmtIdx): Export file
app.writePlaylist(): Write playlist
app.getPlaylistItems(path): Get items of a playlist
app.setPlaylistItems(path, items): Set items of a playlist
app.selectAllFiles(): Select all
app.deselectAllFiles(): Deselect
app.firstFile(\[select\], \[onlyTaggedFiles\]): To first file
app.nextFile(\[select\], \[onlyTaggedFiles\]): To next file
app.previousFile(\[select\], \[onlyTaggedFiles\]): To previous file
app.selectCurrentFile(\[select\]): Select current file
app.selectFile(path, \[select\]): Select a specific file
app.getSelectedFilePaths(\[onlyTaggedFiles\]): Get paths of selected files
app.requestExpandFileList(): Expand all
app.applyFilenameFormat(): Apply filename format
app.applyTagFormat(): Apply tag format
app.applyTextEncoding(): Apply text encoding
app.numberTracks(nr, total, tag, \[options\]): Number tracks
app.applyFilter(expr): Filter
app.convertToId3v23(): Convert ID3v2.4.0 to ID3v2.3.0
app.convertToId3v24(): Convert ID3v2.3.0 to ID3v2.4.0
app.getFilenameFromTags(tag): Filename from tags
app.getTagsFromFilename(tag): Filename to tags
app.getAllFrames(tag): Get object with all frames
app.getFrame(tag, name): Get frame
app.setFrame(tag, name, value): Set frame
app.getPictureData(): Get data from picture frame
app.setPictureData(data): Set data in picture frame
app.copyToOtherTag(tag): Tags to other tags
app.copyTags(tag): Copy
app.pasteTags(tag): Paste
app.removeTags(tag): Remove
app.playAudio(): Play
app.readConfig(): Read configuration
app.applyChangedConfiguration(): Apply configuration
app.dirName: Folder name
app.selectionInfo.fileName: File name
app.selectionInfo.filePath: Absolute file path
app.selectionInfo.detailInfo: Format details
app.selectionInfo.tag(Frame.Tag\_1).tagFormat: Tag 1 format
app.selectionInfo.tag(Frame.Tag\_2).tagFormat: Tag 2 format
app.selectionInfo.formatString(tag, format): Substitute codes in format string
app.selectFileName(caption, dir, filter, saveFile): Open file dialog to
select a file
app.selectDirName(caption, dir): Open file dialog to select a folder

For asynchronous operations, callbacks can be connected to signals.

function automaticImport(profile) {
  function onAutomaticImportFinished() {
    app.batchImporter.finished.disconnect(onAutomaticImportFinished)
  }
  app.batchImporter.finished.connect(onAutomaticImportFinished)
  app.batchImport(profile, tagv2)
}
function renameDirectory(format) {
  function onRenameActionsScheduled() {
    app.renameActionsScheduled.disconnect(onRenameActionsScheduled)
    app.performRenameActions()
  }
  app.renameActionsScheduled.connect(onRenameActionsScheduled)
  app.renameDirectory(tagv2v1, format, false)
}

**Configuration Objects**  

The different configuration sections are accessible via methods of **configs**. Their properties can be listed in the QML console.

script.properties(configs.networkConfig())

Properties can be set:

configs.networkConfig().useProxy = false

configs.batchImportConfig()
configs.exportConfig()
configs.fileConfig()
configs.filenameFormatConfig()
configs.filterConfig()
configs.findReplaceConfig()
configs.guiConfig()
configs.importConfig()
configs.mainWindowConfig()
configs.networkConfig()
configs.numberTracksConfig()
configs.playlistConfig()
configs.renDirConfig()
configs.tagConfig()
configs.tagFormatConfig()
configs.userActionsConfig()

[AUTHOR](#AUTHOR)
=================

**Urs Fleisch** <ufleisch at users.sourceforge.net>

Software development

[COPYRIGHT](#COPYRIGHT)
=======================

Copyright © 2025 Urs Fleisch  

**FDL**

[NOTES](#NOTES)
===============

1.

gnudb.org

[http://gnudb.org](http://gnudb.org/)

2.

MusicBrainz

[http://musicbrainz.org](http://musicbrainz.org/)

3.

Discogs

[http://discogs.com](http://discogs.com/)

4.

Amazon

[http://www.amazon.com](http://www.amazon.com/)

5.

ID3 specification

[http://id3.org/id3v2.4.0-frames](http://id3.org/id3v2.4.0-frames)

6.

SYLT Editor

[http://www.compuphase.com/software\_sylteditor.htm](http://www.compuphase.com/software_sylteditor.htm)

7.

www.gnudb.org

[http://www.gnudb.org](http://www.gnudb.org/)

8.

gnudb.org

[https://gnudb.org/info.php](https://gnudb.org/info.php)

9.

Discogs

[https://www.discogs.com/](https://www.discogs.com/)

10.

freedb.org

[http://freedb.org](http://freedb.org/)

11.

ID3 tag version 2.3.0

[http://id3.org/id3v2.3.0](http://id3.org/id3v2.3.0)

12.

ID3 tag version 2.4.0 - Main Structure

[http://id3.org/id3v2.4.0-structure](http://id3.org/id3v2.4.0-structure)

13.

LyricWiki

[http://www.lyricwiki.org](http://www.lyricwiki.org/)

14.

Google

[http://www.google.com](http://www.google.com/)

15.

id3lib

[http://id3lib.sourceforge.net](http://id3lib.sourceforge.net/)

16.

libogg

[http://xiph.org/ogg/](http://xiph.org/ogg/)

17.

libvorbis, libvorbisfile

[http://xiph.org/vorbis/](http://xiph.org/vorbis/)

18.

libFLAC++ and libFLAC

[http://flac.sourceforge.net](http://flac.sourceforge.net/)

19.

TagLib

[http://taglib.github.io/](http://taglib.github.io/)

20.

mp4v2

[https://mp4v2.org/](https://mp4v2.org/)

21.

Chromaprint

[http://acoustid.org/chromaprint](http://acoustid.org/chromaprint)

22.

libav

[http://libav.org/](http://libav.org/)

23.

FDL

[http://www.gnu.org/licenses/licenses.html#FDL](http://www.gnu.org/licenses/licenses.html#FDL)

24.

GPL

[http://www.gnu.org/licenses/licenses.html#GPL](http://www.gnu.org/licenses/licenses.html#GPL)

25.

Qt(TM)

[https://www.qt.io](https://www.qt.io/)

26.

KDE

[http://www.kde.org](http://www.kde.org/)

2025-07-24

3.9.7

 

Package information:

Package name:

[extra/kid3-common](https://www.archlinux.org/packages/extra/x86_64/kid3-common/)

Version:

3.9.7-2

Upstream:

[https://kid3.kde.org/](https://kid3.kde.org/)

Licenses:

GPL-2.0-or-later

Manuals:

[/listing/extra/kid3-common/](https://man.archlinux.org/listing/extra/kid3-common/)

Table of contents

*   [NAME](#NAME)
*   [SYNOPSIS](#SYNOPSIS)
*   [OPTIONS](#OPTIONS)
*   [INTRODUCTION](#INTRODUCTION)
*   [USING KID3](#USING_KID3)
*   [COMMAND REFERENCE](#COMMAND_REFERENCE)
*   [KID3-CLI](#KID3-CLI)
*   [CREDITS AND LICENSE](#CREDITS_AND_LICENSE)
*   [INSTALLATION](#INSTALLATION)
*   [D-BUS INTERFACE](#D-BUS_INTERFACE)
*   [QML INTERFACE](#QML_INTERFACE)
*   [AUTHOR](#AUTHOR)
*   [COPYRIGHT](#COPYRIGHT)
*   [NOTES](#NOTES)

In other languages:

*   [ca](https://man.archlinux.org/man/kid3.1.ca)
*   [de](https://man.archlinux.org/man/kid3.1.de)
*   [it](https://man.archlinux.org/man/kid3.1.it)
*   [nl](https://man.archlinux.org/man/kid3.1.nl)
*   [pt](https://man.archlinux.org/man/kid3.1.pt)
*   [ru](https://man.archlinux.org/man/kid3.1.ru)
*   [sv](https://man.archlinux.org/man/kid3.1.sv)
*   [uk](https://man.archlinux.org/man/kid3.1.uk)

Other formats: [txt](https://man.archlinux.org/man/kid3.1.en.txt), [raw](https://man.archlinux.org/man/kid3.1.en.raw)

Powered by [archmanweb](https://gitlab.archlinux.org/archlinux/archmanweb), using [mandoc](https://mandoc.bsd.lv/) for the conversion of manual pages.

The website is available under the terms of the [GPL-3.0](https://www.gnu.org/licenses/gpl-3.0.en.html) license, except for the contents of the manual pages, which have their own license specified in the corresponding Arch Linux package.

' Sometimes you need to write a small script that lets a user select a file
' and do some operation on it, like convert it to another format.
' This script provides a full-blown example for Microsoft Windows.
'
' In order to add this script to Windows Explorer's "Send to" menu, place a shortcut to it
' in the following directory:
'   %APPDATA%\Microsoft\Windows\SendTo
' (or more correctly, to the folder pointed by the registry key
'  HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders\SendTo )
'
' Alternatively, the user can drag a file with the mouse to this .vbs script file
' in order to start the processing.
'
' Copyright (c) 2016 R. Diez - Licensed under the GNU AGPLv3


Option Explicit

' After opening the GetFileDlgEx() dialog box and running a program in a console application,
' message boxes appear underneath existing windows. Adding vbSystemModal seems to fix the problem.
' Flag 8192 (0x00002000L) does not work properly.
' objShell.Popup() has the same problem.
' Another work-around to investigate is running a child process to display a message box.
' Maybe a message box created by a child process does get displayed at the top.
dim extraMsgBoxFlags
extraMsgBoxFlags = 0


' Set here the user language to use. See GetMessage() for a list of language codes available.
const language = "eng"

Function GetMessage ( msgEng, msgDeu, msgSpa )

  Select Case language
    Case "eng"  GetMessage = msgEng
    Case "deu"  GetMessage = msgDeu
    Case "spa"  GetMessage = msgSpa
    Case Else   GetMessage = msgEng
      MsgBox "Invalid language.", vbOkOnly + vbError, "Error"
      WScript.Quit( 0 )
  End Select

End Function


Function Abort ( errorMessage )
  MsgBox errorMessage, vbOkOnly + vbError + extraMsgBoxFlags, GetMessage( "Error", "Fehler", "Error" )
  WScript.Quit( 0 )
End Function


Function GetFileDlgEx ( sIniDir, sFilter, sTitle )
  ' Class ID "3050f4e1-98b5-11cf-bb82-00aa00bdce0b" below belongs to the HtmlDlgHelper class,
  ' which is an internal, undocumented IE class that we actually should not be using here.
  dim oDlg
  set oDlg = objShell.Exec( "mshta.exe ""about:<object id=d classid=clsid:3050f4e1-98b5-11cf-bb82-00aa00bdce0b></object><script>moveTo(0,-9999);eval(new ActiveXObject('Scripting.FileSystemObject').GetStandardStream(0).Read("&Len(sIniDir)+Len(sFilter)+Len(sTitle)+41&"));function window.onload(){var p=/[^\0]*/;new ActiveXObject('Scripting.FileSystemObject').GetStandardStream(1).Write(p.exec(d.object.openfiledlg(iniDir,null,filter,title)));close();}</script><hta:application showintaskbar=no />""")
  oDlg.StdIn.Write "var iniDir='" & sIniDir & "';var filter='" & sFilter & "';var title='" & sTitle & "';"
  GetFileDlgEx = oDlg.StdOut.ReadAll
End Function


Function RunExternalCommand ( cmd, shouldWaitForChildToExit )

  const activateAndDisplayTheWindow = 1

  dim waitFlag
  if shouldWaitForChildToExit then
    waitFlag = true
  else
    waitFlag = false
  end if

  On Error Resume Next

  dim runRet
  runRet = objShell.Run( cmd, activateAndDisplayTheWindow, waitFlag )

  if Err.Number <> 0 then
    Abort GetMessage( "Error running command:", _
                      "Fehler beim Ausführen des Kommandos:", _
                      "Error durante la ejecución del comando:" ) & _
          vbCr & vbCr & cmd & vbCr & vbCr & _
          GetMessage( "The error was", _
                      "Der Fehler war:", _
                      "El error fue: " ) & _
          Err.Description & vbCr & vbCr & _
          GetMessage( "Error position: ", _
                      "Fehlerposition: ", _
                      "Posición del error: " )
  end if

  On Error Goto 0

  ' If shouldWaitForChildToExit is true, then the exit code from objShell.Run() is always 0.
  if shouldWaitForChildToExit and runRet <> 0 Then

    Abort GetMessage( "Error running command:", _
                      "Fehler beim Ausführen des Kommandos:", _
                      "Error durante la ejecución del comando:" ) & _
                      vbCr & vbCr & cmd & vbCr & vbCr & _
                      GetMessage( "Error code: ", _
                                  "Fehlercode: ", _
                                  "Código de error: " ) & _
                      runRet & ", hex " & Hex( runRet )
    WScript.Quit( runRet )
  End If

End Function


' ------ Entry point ------

Dim shouldPromptTheUserForFilename

Dim args
Set args = WScript.Arguments

if args.length = 0 then
  shouldPromptTheUserForFilename = true
elseif args.length = 1 then
  shouldPromptTheUserForFilename = false
else
  Abort GetMessage( "Wrong number of command-line arguments. This script can only process one file at a time.", _
                    "Falsche Anzahl von Befehlszeilenargumenten. Dieses Skript kann nur eine Datei auf einmal verarbeiten.", _
                    "Número incorrecto de argumentos de línea de comandos. Este programa solamente puede procesar un archivo a la vez." )
end if

dim objShell
Set objShell = WScript.CreateObject( "WScript.Shell" )

dim objFSO
set objFSO = CreateObject( "Scripting.FileSystemObject" )

dim srcFilename

if shouldPromptTheUserForFilename then

  dim currentDirectory
  currentDirectory = objFSO.GetAbsolutePathName( "." )

  dim sIniDir
  sIniDir = ""  ' objFSO.BuildPath( currentDirectory, "File.ext" )

  ' Here you can specify your own file type instead of PDF.
  dim sFilter
  sFilter = GetMessage( "PDF files", "PDF Dateien", "Archivos PDF" ) & " (*.pdf)|*.pdf"

  dim sTitle
  sTitle = GetMessage( "Select the file", "Die Datei wählen", "Selecciona el archivo" )

  srcFilename = GetFileDlgEx( Replace( sIniDir, "\","\\" ), sFilter, sTitle )
  extraMsgBoxFlags = vbSystemModal

  if srcFilename = "" then
    ' WScript.echo "Cancelled!"
    WScript.Quit( 0 )
  end if

else

  srcFilename = args( 0 )

end if


' If shouldPromptTheUserForFilename is true, GetFileDlgEx() should have made sure that
' the file already exists, but check it here too just in case.
if not objFSO.FileExists( srcFilename ) Then
  Abort GetMessage( "File does not exist:", _
                    "Die Datei existiert nicht:", _
                    "El archivo no existe:" ) & _
                    vbCr & vbCr & srcFilename
end if

dim objFile
set objFile = objFSO.GetFile( srcFilename )

' Here you can set your own suffix.
dim processedFilenameSuffix
processedFilenameSuffix = GetMessage( "-processed", "-verarbeitet", "-procesado" )

dim destFilename
destFilename = objFSO.BuildPath( objFSO.GetParentFolderName( objFile ), _
                                 objFSO.GetBaseName( objFile ) & processedFilenameSuffix & "." & objFSO.GetExtensionName( objFile ) )

if objFSO.FileExists( destFilename ) then

  dim msgBoxRet
  msgBoxRet = MsgBox( GetMessage( "The following file already exists. Do you wish to overwrite it?", _
                                  "Die folgende Datei existiert bereits. Möchten Sie sie überschreiben?", _
                                  "El siguiente archivo ya existe. ¿Desea sobreescribirlo?" ) & _
                        vbCr & vbCr & destFilename, _
                      vbYesNo + vbQuestion, _
                      GetMessage( "The file already exists", "Die Datei existiert bereits", "El archivo ya existe" ) )

  if msgBoxRet <> vbYes then
    WScript.Quit( 0 )
  end if

  dim objDestFile
  set objDestFile = objFSO.GetFile( destFilename )

  if objDestFile.Attributes and 1 then
    Abort GetMessage( "File is read only:", _
                      "Die Datei ist nur lesbar:", _
                      "El archivo es de sólo lectura:" ) & _
                      vbCr & vbCr & destFilename
  end if

end if


' Here you can use your own command instead of "cmd /c copy":
dim cmd
cmd = "cmd /c copy /y """ & srcFilename & """ """ & destFilename & """"

RunExternalCommand cmd, true


if shouldPromptTheUserForFilename then
  ' We can either display a message box, or open the file explorer with the new file selected.
  if true then
    RunExternalCommand "explorer /select,""" & destFilename & """", false
  else
    MsgBox GetMessage( "The file created is called:", _
                       "Die erstellte Datei heißt:", _
                       "El archivo creado se llama:" ) & _
             vbCr & vbCr & destFilename , _
           vbOkOnly + vbInformation + extraMsgBoxFlags, _
           GetMessage( "File created", "Erstellte Datei", "Archivo creado" )
  end if
end if

WScript.Quit( 0 )

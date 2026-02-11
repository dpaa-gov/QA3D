' QA3D - Silent Launcher (no console window)
' Double-click this file to start QA3D without a console window

Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Get the directory where this script lives
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)

' Run qa3d.bat silently (0 = hidden window, False = don't wait)
WshShell.Run """" & scriptDir & "\qa3d.bat""", 0, False

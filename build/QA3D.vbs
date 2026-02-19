Set fso = CreateObject("Scripting.FileSystemObject")
Set WshShell = CreateObject("WScript.Shell")
appDir = fso.GetParentFolderName(WScript.ScriptFullName)
WshShell.CurrentDirectory = appDir
WshShell.Environment("Process").Item("JULIA_NUM_THREADS") = "auto"
WshShell.Run """" & appDir & "\bin\qa3d.exe""", 0, False

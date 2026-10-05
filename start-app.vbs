Set shell = CreateObject("WScript.Shell")
root = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & root & "\launcher.ps1"""
If WScript.Arguments.Count > 0 Then cmd = cmd & " -NoBrowser"
shell.Run cmd, 0, False

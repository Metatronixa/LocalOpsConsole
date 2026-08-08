' Launch LocalOpsConsole with no console flash (shortcuts / Startup folder).
' Primary documented entry remains start.bat.
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
root = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & root & "\start.ps1"""
sh.Run cmd, 0, False

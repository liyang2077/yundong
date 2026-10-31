Dim fso, sh, root, target, ps1, cmd
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")

root = fso.GetParentFolderName(WScript.ScriptFullName)

If WScript.Arguments.Count > 0 Then
    target = WScript.Arguments(0)
Else
    target = "settings.ps1"
End If

ps1 = root & "\" & target

If Not fso.FileExists(ps1) Then
    MsgBox "Cannot find " & target & " in " & root, 16, "Exercise Reminder"
    WScript.Quit 1
End If

cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """"
sh.Run cmd, 0, False

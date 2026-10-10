using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;

class Launcher
{
    [STAThread]
    static void Main()
    {
        var folder = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
        var script = Path.Combine(folder, "Widget.ps1");
        var start = new ProcessStartInfo("powershell.exe",
            "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + script + "\"");
        start.UseShellExecute = false;
        start.CreateNoWindow = true;
        Process.Start(start);
    }
}

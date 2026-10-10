using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Threading.Tasks;
class NativeHost {
  static int Main() {
    var folder = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
    var node = File.ReadAllText(Path.Combine(folder, "node-path.txt")).Trim();
    var info = new ProcessStartInfo(node, "\"" + Path.Combine(folder, "native-bridge.js") + "\"");
    info.UseShellExecute = false; info.CreateNoWindow = true;
    info.RedirectStandardInput = true; info.RedirectStandardOutput = true; info.RedirectStandardError = true;
    using (var process = Process.Start(info)) {
      var input = Console.OpenStandardInput(); var output = Console.OpenStandardOutput();
      var writer = Task.Run(async () => { await input.CopyToAsync(process.StandardInput.BaseStream); process.StandardInput.Close(); });
      var reader = process.StandardOutput.BaseStream.CopyToAsync(output);
      var errors = process.StandardError.ReadToEndAsync();
      process.WaitForExit(); reader.Wait();
      return process.ExitCode;
    }
  }
}

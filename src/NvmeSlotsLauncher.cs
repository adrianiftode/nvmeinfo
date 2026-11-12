using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;

[assembly: AssemblyTitle("NVMe Slot Info")]
[assembly: AssemblyDescription("Reports NVMe drives and the motherboard PCIe/M.2 slots they are connected to.")]
[assembly: AssemblyProduct("NVMe Slot Info")]
[assembly: AssemblyCompany("NvmeInfo")]
[assembly: AssemblyCopyright("")]
[assembly: AssemblyVersion("1.1.0.0")]
[assembly: AssemblyFileVersion("1.1.0.0")]

internal static class Program
{
    private const string ScriptResourceName = "NvmeSlots.Script.ps1";

    [DllImport("kernel32.dll", SetLastError = false)]
    private static extern uint GetConsoleProcessList(uint[] processList, uint processCount);

    private static int Main(string[] args)
    {
        bool launchedDirectly = IsOnlyProcessOnConsole();
        string scriptPath = null;

        try
        {
            TrySetTitle();
            scriptPath = ExtractScript();
            List<string> scriptArgs = BuildScriptArguments(args);

            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = GetPowerShellPath();
            startInfo.Arguments = BuildPowerShellArguments(scriptPath, scriptArgs);
            startInfo.UseShellExecute = false;
            startInfo.WorkingDirectory = Environment.CurrentDirectory;

            using (Process process = Process.Start(startInfo))
            {
                if (process == null)
                {
                    throw new InvalidOperationException("PowerShell could not be started.");
                }

                process.WaitForExit();
                int exitCode = process.ExitCode;

                if (exitCode != 0 || launchedDirectly)
                {
                    Pause();
                }

                return exitCode;
            }
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("ERROR: " + ex.Message);
            if (launchedDirectly)
            {
                Pause();
            }
            return 1;
        }
        finally
        {
            TryDelete(scriptPath);
        }
    }

    private static string ExtractScript()
    {
        Assembly assembly = Assembly.GetExecutingAssembly();
        using (Stream stream = assembly.GetManifestResourceStream(ScriptResourceName))
        {
            if (stream == null)
            {
                throw new InvalidOperationException("The embedded PowerShell script is missing from this executable.");
            }

            string path = Path.Combine(
                Path.GetTempPath(),
                "NvmeSlots-" + Guid.NewGuid().ToString("N") + ".ps1");

            using (FileStream file = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                stream.CopyTo(file);
            }

            return path;
        }
    }

    private static List<string> BuildScriptArguments(string[] args)
    {
        List<string> list = new List<string>(args);

#if REPORT_MODE
        bool hasHtml = false;
        bool hasOpen = false;
        bool noOpen = false;

        foreach (string arg in args)
        {
            if (EqualsArg(arg, "-Html") || arg.StartsWith("-Html:", StringComparison.OrdinalIgnoreCase))
            {
                hasHtml = true;
            }
            else if (EqualsArg(arg, "-Open"))
            {
                hasOpen = true;
            }
            else if (EqualsArg(arg, "-NoOpen"))
            {
                noOpen = true;
            }
        }

        list.RemoveAll(delegate(string arg) { return EqualsArg(arg, "-NoOpen"); });

        if (!hasHtml)
        {
            list.Insert(0, "-Html");
            list.Insert(1, Path.Combine(Environment.CurrentDirectory, "NvmeSlotReport.html"));
        }

        if (!hasOpen && !noOpen)
        {
            list.Insert(0, "-Open");
        }
#endif

        return list;
    }

    private static bool EqualsArg(string value, string expected)
    {
        return string.Equals(value, expected, StringComparison.OrdinalIgnoreCase);
    }

    private static string GetPowerShellPath()
    {
        string systemDirectory = Environment.GetFolderPath(Environment.SpecialFolder.System);
        if (!string.IsNullOrEmpty(systemDirectory))
        {
            string candidate = Path.Combine(systemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        return "powershell.exe";
    }

    private static string BuildPowerShellArguments(string scriptPath, List<string> scriptArgs)
    {
        StringBuilder builder = new StringBuilder();
        builder.Append("-NoProfile -ExecutionPolicy Bypass -File ");
        builder.Append(Quote(scriptPath));

        foreach (string arg in scriptArgs)
        {
            builder.Append(' ');
            builder.Append(Quote(arg));
        }

        return builder.ToString();
    }

    // Quoting rules used by CommandLineToArgvW and the C runtime.
    private static string Quote(string value)
    {
        if (value == null)
        {
            return "\"\"";
        }

        if (value.Length == 0)
        {
            return "\"\"";
        }

        bool needsQuotes = false;
        foreach (char c in value)
        {
            if (c == ' ' || c == '\t' || c == '\n' || c == '\v' || c == '"')
            {
                needsQuotes = true;
                break;
            }
        }

        if (!needsQuotes)
        {
            return value;
        }

        StringBuilder builder = new StringBuilder();
        builder.Append('"');
        int backslashes = 0;

        foreach (char c in value)
        {
            if (c == '\\')
            {
                backslashes++;
                continue;
            }

            if (c == '"')
            {
                builder.Append('\\', (backslashes * 2) + 1);
                builder.Append('"');
                backslashes = 0;
                continue;
            }

            if (backslashes > 0)
            {
                builder.Append('\\', backslashes);
                backslashes = 0;
            }

            builder.Append(c);
        }

        if (backslashes > 0)
        {
            builder.Append('\\', backslashes * 2);
        }

        builder.Append('"');
        return builder.ToString();
    }

    private static void TrySetTitle()
    {
        try
        {
            Console.Title = "NVMe Slot Report";
        }
        catch
        {
            // A title is optional; some hosts have no console window.
        }
    }

    private static bool IsOnlyProcessOnConsole()
    {
        try
        {
            uint[] processes = new uint[8];
            uint count = GetConsoleProcessList(processes, (uint)processes.Length);
            return count == 1;
        }
        catch
        {
            return false;
        }
    }

    private static void Pause()
    {
        try
        {
            Console.WriteLine();
            Console.Write("Press Enter to exit...");
            Console.ReadLine();
        }
        catch
        {
            // No usable console; nothing to pause.
        }
    }

    private static void TryDelete(string path)
    {
        if (string.IsNullOrEmpty(path))
        {
            return;
        }

        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
            // The temporary file is harmless; deletion is best effort.
        }
    }
}

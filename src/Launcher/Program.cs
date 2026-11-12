using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;

namespace NvmeSlots;

internal static class Program
{
    private const string ScriptResourceName = "NvmeSlots.Script.ps1";

    [DllImport("kernel32.dll", SetLastError = false)]
    private static extern uint GetConsoleProcessList(uint[] processList, uint processCount);

    private static int Main(string[] args)
    {
        bool launchedDirectly = IsOnlyProcessOnConsole();
        string? scriptPath = null;

        try
        {
            TrySetTitle();
            scriptPath = ExtractScript();

            ProcessStartInfo startInfo = new ProcessStartInfo
            {
                FileName = GetPowerShellPath(),
                UseShellExecute = false,
                WorkingDirectory = Environment.CurrentDirectory
            };

            startInfo.ArgumentList.Add("-NoProfile");
            startInfo.ArgumentList.Add("-ExecutionPolicy");
            startInfo.ArgumentList.Add("Bypass");
            startInfo.ArgumentList.Add("-File");
            startInfo.ArgumentList.Add(scriptPath);

            foreach (string argument in BuildScriptArguments(args))
            {
                startInfo.ArgumentList.Add(argument);
            }

            using (Process? process = Process.Start(startInfo))
            {
                if (process is null)
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
        using (Stream? stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(ScriptResourceName))
        {
            if (stream is null)
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

        foreach (string argument in args)
        {
            if (EqualsArg(argument, "-Html") || argument.StartsWith("-Html:", StringComparison.OrdinalIgnoreCase))
            {
                hasHtml = true;
            }
            else if (EqualsArg(argument, "-Open"))
            {
                hasOpen = true;
            }
            else if (EqualsArg(argument, "-NoOpen"))
            {
                noOpen = true;
            }
        }

        list.RemoveAll(argument => EqualsArg(argument, "-NoOpen"));

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
            string candidate = Path.Combine(systemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe");
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        return "powershell.exe";
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

    private static void TryDelete(string? path)
    {
        if (string.IsNullOrEmpty(path))
        {
            return;
        }

        // Antivirus and the indexer can hold a freshly written file briefly, so
        // retry instead of leaving the extracted script behind.
        for (int attempt = 0; attempt < 5; attempt++)
        {
            try
            {
                if (!File.Exists(path))
                {
                    return;
                }

                File.Delete(path);
                return;
            }
            catch (IOException)
            {
                Thread.Sleep(100 * (attempt + 1));
            }
            catch (UnauthorizedAccessException)
            {
                Thread.Sleep(100 * (attempt + 1));
            }
            catch
            {
                // The temporary file is harmless; deletion is best effort.
                return;
            }
        }
    }
}

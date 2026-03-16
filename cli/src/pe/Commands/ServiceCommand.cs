using System.CommandLine;
using System.Diagnostics;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using ParsecEventExecutor.Cli.Hosting;

namespace ParsecEventExecutor.Cli.Commands;

public static class ServiceCommand
{
    private const string ServiceName = "ParsecEventWatcher";
    private const string ServiceDisplayName = "Parsec Event Watcher";
    private const string ServiceDescription = "Monitors Parsec connections and dispatches display configuration recipes.";

    public static Command Create()
    {
        var command = new Command("service", "Manage the Parsec Event Watcher Windows Service");
        command.Subcommands.Add(CreateInstallCommand());
        command.Subcommands.Add(CreateUninstallCommand());
        command.Subcommands.Add(CreateStartCommand());
        command.Subcommands.Add(CreateStopCommand());
        command.Subcommands.Add(CreateStatusCommand());
        command.Subcommands.Add(CreateRunCommand());
        return command;
    }

    private static Command CreateInstallCommand()
    {
        var command = new Command("install", "Register the watcher as a Windows Service");
        command.SetAction(_ => HandleInstall());
        return command;
    }

    private static void HandleInstall()
    {
        var exePath = Process.GetCurrentProcess().MainModule?.FileName
            ?? throw new InvalidOperationException("Cannot determine pe.exe path");

        // Register the service
        var createResult = RunSc($"create {ServiceName} binPath= \"\\\"{exePath}\\\" service run\" start= auto DisplayName= \"{ServiceDisplayName}\"");
        if (createResult != 0)
        {
            Console.Error.WriteLine("Failed to create service. Are you running as Administrator?");
            Environment.ExitCode = 1;
            return;
        }

        // Set description
        RunSc($"description {ServiceName} \"{ServiceDescription}\"");

        // Set recovery: restart after 5 seconds, up to 3 times
        RunSc($"failure {ServiceName} reset= 86400 actions= restart/5000/restart/5000/restart/5000");

        Console.WriteLine($"Service '{ServiceName}' installed successfully.");
        Console.WriteLine($"  Binary: {exePath}");
        Console.WriteLine($"  Start:  pe service start");
    }

    private static Command CreateUninstallCommand()
    {
        var command = new Command("uninstall", "Remove the Windows Service");
        command.SetAction(_ => HandleUninstall());
        return command;
    }

    private static void HandleUninstall()
    {
        RunSc($"stop {ServiceName}");
        var result = RunSc($"delete {ServiceName}");
        if (result != 0)
        {
            Console.Error.WriteLine("Failed to delete service. Are you running as Administrator?");
            Environment.ExitCode = 1;
            return;
        }

        Console.WriteLine($"Service '{ServiceName}' uninstalled.");
    }

    private static Command CreateStartCommand()
    {
        var command = new Command("start", "Start the watcher service");
        command.SetAction(_ =>
        {
            var result = RunSc($"start {ServiceName}");
            if (result == 0)
                Console.WriteLine($"Service '{ServiceName}' started.");
            else
                Environment.ExitCode = 1;
        });
        return command;
    }

    private static Command CreateStopCommand()
    {
        var command = new Command("stop", "Stop the watcher service");
        command.SetAction(_ =>
        {
            var result = RunSc($"stop {ServiceName}");
            if (result == 0)
                Console.WriteLine($"Service '{ServiceName}' stopped.");
            else
                Environment.ExitCode = 1;
        });
        return command;
    }

    private static Command CreateStatusCommand()
    {
        var command = new Command("status", "Query the service status");
        command.SetAction(_ => HandleStatus());
        return command;
    }

    private static void HandleStatus()
    {
        var result = RunSc($"query {ServiceName}");
        if (result != 0)
            Console.WriteLine($"Service '{ServiceName}' is not installed.");
    }

    private static Command CreateRunCommand()
    {
        var configOption = new Option<string?>("--config") { Description = "Path to parsec-watcher.toml" };
        var stateRootOption = new Option<string?>("--state-root") { Description = "Override state root directory" };

        // Hidden command — SCM entry point
        var command = new Command("run", "Run the watcher as a Windows Service (called by SCM)");
        command.Hidden = true;
        command.Options.Add(configOption);
        command.Options.Add(stateRootOption);

        command.SetAction(parseResult =>
        {
            var configPath = parseResult.GetValue(configOption);
            var stateRoot = parseResult.GetValue(stateRootOption);
            HandleRun(configPath, stateRoot);
        });

        return command;
    }

    private static void HandleRun(string? configPath, string? stateRoot)
    {
        var builder = Host.CreateApplicationBuilder();

        builder.Services.AddWindowsService(options =>
        {
            options.ServiceName = ServiceName;
        });

        builder.Services.AddSingleton(new WatcherServiceOptions
        {
            ConfigPath = configPath,
            StateRoot = stateRoot
        });

        builder.Services.AddHostedService<WatcherService>();

        var host = builder.Build();
        host.Run();
    }

    private static int RunSc(string arguments)
    {
        var psi = new ProcessStartInfo("sc.exe", arguments)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        using var proc = Process.Start(psi);
        if (proc is null) return 1;

        var stdout = proc.StandardOutput.ReadToEnd();
        var stderr = proc.StandardError.ReadToEnd();
        proc.WaitForExit();

        if (!string.IsNullOrWhiteSpace(stdout))
            Console.WriteLine(stdout.Trim());
        if (!string.IsNullOrWhiteSpace(stderr))
            Console.Error.WriteLine(stderr.Trim());

        return proc.ExitCode;
    }
}

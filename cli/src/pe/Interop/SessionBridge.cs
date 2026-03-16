using System.Diagnostics;
using Microsoft.Extensions.Logging;

namespace ParsecEventExecutor.Cli.Interop;

/// <summary>
/// Dispatches recipe execution to the interactive user session
/// via Task Scheduler one-shot tasks. This solves the Session 0
/// constraint: the service runs in Session 0 (no desktop), but
/// display APIs require the user's desktop session (Session 1+).
/// </summary>
public sealed class SessionBridge
{
    private readonly ILogger<SessionBridge>? _logger;

    public SessionBridge(ILogger<SessionBridge>? logger = null)
    {
        _logger = logger;
    }

    /// <summary>
    /// Creates a one-shot scheduled task that runs "pe run {recipeName}"
    /// in the interactive user's session, waits for completion, then
    /// deletes the task.
    /// </summary>
    public async Task<int> DispatchToUserSession(string recipeName, string? stateRoot = null, CancellationToken ct = default)
    {
        var exePath = Process.GetCurrentProcess().MainModule?.FileName
            ?? throw new InvalidOperationException("Cannot determine pe.exe path");

        var taskName = $"ParsecEvent_{Guid.NewGuid():N}";
        var arguments = $"run \"{recipeName}\"";
        if (stateRoot is not null)
            arguments += $" --state-root \"{stateRoot}\"";

        _logger?.LogInformation("Creating scheduled task {TaskName} for recipe {Recipe}", taskName, recipeName);

        // Create the one-shot task
        var createArgs = $"/Create /TN \"{taskName}\" /TR \"\\\"{exePath}\\\" {arguments}\" /SC ONCE /ST 00:00 /F /RL HIGHEST /IT";
        var createResult = await RunProcess("schtasks.exe", createArgs, ct);
        if (createResult != 0)
        {
            _logger?.LogError("Failed to create scheduled task (exit code {Code})", createResult);
            return createResult;
        }

        try
        {
            // Run it immediately
            var runArgs = $"/Run /TN \"{taskName}\"";
            var runResult = await RunProcess("schtasks.exe", runArgs, ct);
            if (runResult != 0)
            {
                _logger?.LogError("Failed to run scheduled task (exit code {Code})", runResult);
                return runResult;
            }

            // Poll for completion
            return await WaitForTaskCompletion(taskName, ct);
        }
        finally
        {
            await CleanupTask(taskName, CancellationToken.None);
        }
    }

    private async Task<int> WaitForTaskCompletion(string taskName, CancellationToken ct)
    {
        const int maxWaitMs = 300_000; // 5 minutes
        const int pollIntervalMs = 1_000;
        var elapsed = 0;

        while (elapsed < maxWaitMs && !ct.IsCancellationRequested)
        {
            await Task.Delay(pollIntervalMs, ct);
            elapsed += pollIntervalMs;

            var (exitCode, output) = await RunProcessWithOutput(
                "schtasks.exe", $"/Query /TN \"{taskName}\" /FO CSV /NH", ct);

            if (exitCode != 0)
                continue;

            // CSV output: "taskname","next run time","status","last result"
            if (output.Contains("Ready", StringComparison.OrdinalIgnoreCase))
            {
                _logger?.LogInformation("Scheduled task {TaskName} completed", taskName);
                return 0;
            }
        }

        _logger?.LogWarning("Scheduled task {TaskName} timed out after {Ms}ms", taskName, maxWaitMs);
        return 1;
    }

    private async Task CleanupTask(string taskName, CancellationToken ct)
    {
        await RunProcess("schtasks.exe", $"/Delete /TN \"{taskName}\" /F", ct);
    }

    private static async Task<int> RunProcess(string fileName, string arguments, CancellationToken ct)
    {
        var psi = new ProcessStartInfo(fileName, arguments)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        using var proc = Process.Start(psi)
            ?? throw new InvalidOperationException($"Failed to start {fileName}");

        await proc.WaitForExitAsync(ct);
        return proc.ExitCode;
    }

    private static async Task<(int ExitCode, string Output)> RunProcessWithOutput(
        string fileName, string arguments, CancellationToken ct)
    {
        var psi = new ProcessStartInfo(fileName, arguments)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        using var proc = Process.Start(psi)
            ?? throw new InvalidOperationException($"Failed to start {fileName}");

        var output = await proc.StandardOutput.ReadToEndAsync(ct);
        await proc.WaitForExitAsync(ct);

        return (proc.ExitCode, output);
    }
}

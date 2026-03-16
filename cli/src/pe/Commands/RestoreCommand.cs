using System.CommandLine;
using System.Text.Json;
using ParsecEventExecutor.Cli.Hosting;

namespace ParsecEventExecutor.Cli.Commands;

public static class RestoreCommand
{

    public static Command Create()
    {
        var idOption = new Option<string?>("--id") { Description = "Snapshot name to restore" };
        var jsonOption = new Option<bool>("--json") { Description = "Output raw JSON" };
        var stateRootOption = new Option<string?>("--state-root") { Description = "Override state root directory" };

        var command = new Command("restore", "Restore a display snapshot");
        command.Options.Add(idOption);
        command.Options.Add(jsonOption);
        command.Options.Add(stateRootOption);
        command.Subcommands.Add(CreateListCommand());

        command.SetAction(parseResult =>
        {
            var id = parseResult.GetValue(idOption);
            var json = parseResult.GetValue(jsonOption);
            var stateRoot = parseResult.GetValue(stateRootOption);
            HandleRestore(id, json, stateRoot);
        });

        return command;
    }

    private static Command CreateListCommand()
    {
        var jsonOption = new Option<bool>("--json") { Description = "Output raw JSON" };
        var stateRootOption = new Option<string?>("--state-root") { Description = "Override state root directory" };

        var command = new Command("list", "List available snapshots");
        command.Options.Add(jsonOption);
        command.Options.Add(stateRootOption);

        command.SetAction(parseResult =>
        {
            var json = parseResult.GetValue(jsonOption);
            var stateRoot = parseResult.GetValue(stateRootOption);
            HandleList(json, stateRoot);
        });

        return command;
    }

    private static void HandleList(bool json, string? stateRoot)
    {
        var snapshotDir = GetSnapshotDirectory(stateRoot);

        if (!Directory.Exists(snapshotDir))
        {
            Console.WriteLine("No snapshots found.");
            return;
        }

        var files = Directory.GetFiles(snapshotDir, "*.json")
            .OrderByDescending(File.GetLastWriteTimeUtc)
            .ToList();

        if (files.Count == 0)
        {
            Console.WriteLine("No snapshots found.");
            return;
        }

        if (json)
        {
            var snapshots = files.Select(f => new
            {
                name = Path.GetFileNameWithoutExtension(f),
                path = f,
                modified = File.GetLastWriteTimeUtc(f).ToString("o")
            }).ToList();
            Console.WriteLine(JsonSerializer.Serialize(snapshots, PsObjectHelpers.JsonOptions));
            return;
        }

        Console.WriteLine($"{"Name",-40} {"Modified",-25}");
        Console.WriteLine(new string('-', 65));
        foreach (var file in files)
        {
            var name = Path.GetFileNameWithoutExtension(file);
            var modified = File.GetLastWriteTimeUtc(file).ToString("yyyy-MM-dd HH:mm:ss");
            Console.WriteLine($"  {name,-38} {modified}");
        }
    }

    private static void HandleRestore(string? id, bool json, string? stateRoot)
    {
        using var host = new PowerShellHost();

        // If no ID given, find active_snapshot from executor state
        if (id is null)
        {
            var stateResults = host.GetExecutorState(stateRoot);
            if (stateResults.Count > 0)
            {
                id = stateResults[0].Properties["active_snapshot"]?.Value?.ToString();
            }

            if (string.IsNullOrEmpty(id))
            {
                Console.Error.WriteLine("No active snapshot to restore. Use --id to specify one, or 'pe restore list' to see available snapshots.");
                Environment.ExitCode = 1;
                return;
            }
        }

        Console.WriteLine($"Restoring snapshot: {id}");

        var arguments = new Dictionary<string, object?>
        {
            ["snapshot_name"] = id
        };

        var results = host.InvokeIngredient(
            "display.snapshot",
            operation: "reset",
            arguments: arguments,
            stateRoot: stateRoot);

        if (json)
        {
            var list = results.Select(PsObjectHelpers.ToDictionary).ToList();
            Console.WriteLine(JsonSerializer.Serialize(list, PsObjectHelpers.JsonOptions));
            return;
        }

        Console.WriteLine($"Snapshot '{id}' restored.");
    }

    private static string GetSnapshotDirectory(string? stateRoot)
    {
        var root = stateRoot
            ?? Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "ParsecEventExecutor");
        return Path.Combine(root, "snapshots");
    }
}

using System.Collections;
using System.CommandLine;
using System.Text.Json;
using ParsecEventExecutor.Cli.Hosting;

namespace ParsecEventExecutor.Cli.Commands;

public static class StatusCommand
{
    public static Command Create()
    {
        var jsonOption = new Option<bool>("--json") { Description = "Output raw JSON" };
        var stateRootOption = new Option<string?>("--state-root") { Description = "Override state root directory" };

        var command = new Command("status", "Show executor state and service status");
        command.Options.Add(jsonOption);
        command.Options.Add(stateRootOption);

        command.SetAction(parseResult =>
        {
            var json = parseResult.GetValue(jsonOption);
            var stateRoot = parseResult.GetValue(stateRootOption);
            Handle(json, stateRoot);
        });

        return command;
    }

    private static void Handle(bool json, string? stateRoot)
    {
        using var host = new PowerShellHost();
        var results = host.GetExecutorState(stateRoot);

        if (results.Count == 0)
        {
            Console.WriteLine("No executor state found.");
            return;
        }

        var state = results[0];

        if (json)
        {
            var jsonDict = PsObjectHelpers.ToDictionary(state);
            Console.WriteLine(JsonSerializer.Serialize(jsonDict, PsObjectHelpers.JsonOptions));
            return;
        }

        Console.WriteLine("Parsec Event Executor Status");
        Console.WriteLine(new string('-', 40));

        var entries = PsObjectHelpers.UnwrapToDictionary(state);
        foreach (DictionaryEntry entry in entries)
        {
            var key = entry.Key?.ToString() ?? "";
            var label = key.Replace("_", " ");
            label = string.Join(" ", label.Split(' ').Select(w =>
                w.Length > 0 ? char.ToUpper(w[0]) + w[1..] : w));

            var display = entry.Value?.ToString() ?? "(none)";
            Console.WriteLine($"  {label,-22} {display}");
        }
    }
}

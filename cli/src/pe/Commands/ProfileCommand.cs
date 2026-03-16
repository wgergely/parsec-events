using System.Collections;
using System.CommandLine;
using System.Management.Automation;
using System.Text.Json;
using ParsecEventExecutor.Cli.Hosting;

namespace ParsecEventExecutor.Cli.Commands;

public static class ProfileCommand
{

    public static Command Create()
    {
        var command = new Command("profile", "Manage the default system profile");
        command.Subcommands.Add(CreateSetDefaultCommand());
        command.Subcommands.Add(CreateShowCommand());
        return command;
    }

    private static Command CreateSetDefaultCommand()
    {
        var stateRootOption = new Option<string?>("--state-root") { Description = "Override state root directory" };

        var command = new Command("set-default", "Capture current system state as the default profile");
        command.Options.Add(stateRootOption);

        command.SetAction(parseResult =>
        {
            var stateRoot = parseResult.GetValue(stateRootOption);
            HandleSetDefault(stateRoot);
        });

        return command;
    }

    private static void HandleSetDefault(string? stateRoot)
    {
        using var host = new PowerShellHost();

        Console.WriteLine("Capturing current system state as default profile...");

        var parameters = new Dictionary<string, object?>();
        if (stateRoot is not null) parameters["StateRoot"] = stateRoot;

        var results = host.Invoke("Set-ParsecDefaultProfile", parameters);

        if (results.Count > 0)
        {
            var snapshot = results[0];
            var baseObj = snapshot is PSObject pso ? pso.BaseObject : snapshot;

            if (baseObj is IDictionary dict && dict.Contains("name"))
            {
                Console.WriteLine($"Default profile set: {dict["name"]}");
                Console.WriteLine($"Captured at: {dict["captured_at"]}");
            }
            else
            {
                Console.WriteLine("Default profile set.");
            }
        }
        else
        {
            Console.WriteLine("Default profile set.");
        }
    }

    private static Command CreateShowCommand()
    {
        var jsonOption = new Option<bool>("--json") { Description = "Output raw JSON" };
        var stateRootOption = new Option<string?>("--state-root") { Description = "Override state root directory" };

        var command = new Command("show", "Show the current default profile");
        command.Options.Add(jsonOption);
        command.Options.Add(stateRootOption);

        command.SetAction(parseResult =>
        {
            var json = parseResult.GetValue(jsonOption);
            var stateRoot = parseResult.GetValue(stateRootOption);
            HandleShow(json, stateRoot);
        });

        return command;
    }

    private static void HandleShow(bool json, string? stateRoot)
    {
        using var host = new PowerShellHost();

        var parameters = new Dictionary<string, object?>();
        if (stateRoot is not null) parameters["StateRoot"] = stateRoot;

        var results = host.Invoke("Get-ParsecDefaultProfile", parameters);

        if (results.Count == 0 || results[0] is null)
        {
            Console.WriteLine("No default profile set. Run 'pe profile set-default' to capture one.");
            return;
        }

        var profile = results[0];

        if (json)
        {
            var dict = PsObjectHelpers.ToDictionary(profile);
            Console.WriteLine(JsonSerializer.Serialize(dict, PsObjectHelpers.JsonOptions));
            return;
        }

        var source = PsObjectHelpers.UnwrapToDictionary(profile);
        Console.WriteLine("Default Profile");
        Console.WriteLine(new string('-', 40));
        foreach (DictionaryEntry entry in source)
        {
            var key = entry.Key?.ToString() ?? "";
            var value = entry.Value?.ToString() ?? "(none)";

            // Skip large nested objects in table view
            if (value.StartsWith("System.") || value.StartsWith("@{"))
                continue;

            Console.WriteLine($"  {key,-22} {value}");
        }
    }
}

using System.CommandLine;
using System.Text.Json;
using ParsecEventExecutor.Cli.Hosting;

namespace ParsecEventExecutor.Cli.Commands;

public static class RunCommand
{

    public static Command Create()
    {
        var nameArg = new Argument<string>("name") { Description = "Recipe name to execute" };
        var dryRunOption = new Option<bool>("--dry-run") { Description = "Show execution plan without applying" };
        var jsonOption = new Option<bool>("--json") { Description = "Output raw JSON" };
        var stateRootOption = new Option<string?>("--state-root") { Description = "Override state root directory" };

        var command = new Command("run", "Execute a recipe by name");
        command.Arguments.Add(nameArg);
        command.Options.Add(dryRunOption);
        command.Options.Add(jsonOption);
        command.Options.Add(stateRootOption);

        command.SetAction(parseResult =>
        {
            var name = parseResult.GetValue(nameArg)!;
            var dryRun = parseResult.GetValue(dryRunOption);
            var json = parseResult.GetValue(jsonOption);
            var stateRoot = parseResult.GetValue(stateRootOption);
            Handle(name, dryRun, json, stateRoot);
        });

        return command;
    }

    private static void Handle(string name, bool dryRun, bool json, string? stateRoot)
    {
        using var host = new PowerShellHost();
        var results = host.InvokeRecipe(name, stateRoot, whatIf: dryRun);

        if (json)
        {
            var list = results.Select(PsObjectHelpers.ToDictionary).ToList();
            Console.WriteLine(JsonSerializer.Serialize(list, PsObjectHelpers.JsonOptions));
            return;
        }

        if (dryRun)
        {
            Console.WriteLine($"Dry run: {name}");
            Console.WriteLine(new string('-', 40));
        }

        foreach (var result in results)
        {
            var status = result.Properties["status"]?.Value?.ToString();
            var stepId = result.Properties["step_id"]?.Value?.ToString()
                      ?? result.Properties["id"]?.Value?.ToString();

            if (stepId is not null && status is not null)
            {
                var symbol = status switch
                {
                    "Succeeded" => "+",
                    "Skipped" => "-",
                    "Failed" => "!",
                    _ => "?"
                };
                Console.WriteLine($"  [{symbol}] {stepId}: {status}");
            }
            else
            {
                Console.WriteLine($"  {result}");
            }
        }

        if (results.Count == 0)
        {
            Console.WriteLine("  (no results)");
        }
    }
}

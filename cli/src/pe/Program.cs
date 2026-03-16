using System.CommandLine;
using ParsecEventExecutor.Cli.Commands;

var rootCommand = new RootCommand("Parsec Event Executor — manage display recipes and the watcher service");
rootCommand.Subcommands.Add(StatusCommand.Create());
rootCommand.Subcommands.Add(ProfileCommand.Create());
rootCommand.Subcommands.Add(RecipeCommand.Create());
rootCommand.Subcommands.Add(RunCommand.Create());
rootCommand.Subcommands.Add(RestoreCommand.Create());
rootCommand.Subcommands.Add(ServiceCommand.Create());

return rootCommand.Parse(args).Invoke();

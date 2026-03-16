# Parsec Event Executor — build and test tasks

cli_proj := "cli/src/pe/pe.csproj"
cli_test := "cli/tests/pe.tests/pe.tests.csproj"
cli_sln  := "cli/pe.sln"

# Build the CLI binary
build:
    dotnet build {{cli_proj}}

# Publish self-contained single-file pe.exe
publish:
    dotnet publish {{cli_proj}} -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o publish/

# Run CLI tests
test-cli:
    dotnet test {{cli_test}}

# Run PowerShell Pester tests
test-ps:
    pwsh -NoProfile -Command "Invoke-Pester -Path tests/ -Output Detailed"

# Run all tests
test: test-ps test-cli

# Clean build artifacts
clean:
    dotnet clean {{cli_sln}}

# Lint PowerShell files
lint-ps:
    pwsh -NoProfile -File tools/Invoke-PowerShellLint.ps1

# Format C# files
format-cs:
    dotnet format {{cli_sln}}

# Lint everything
lint: lint-ps format-cs

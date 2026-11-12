#requires -Version 7.0
param(
    [string]$ProjectPath = (Get-Location).Path,
    [string]$ClangPath
)

# xcross 2.0.9 generates Runner.m instead of compiling ios/Runner/AppDelegate.swift.
# Intercept its compiler invocation, rather than racing the generated source with
# a watcher. All generated files and the only source mutation stay under build/.
$ErrorActionPreference = 'Stop'
$project = (Get-Item -LiteralPath (Resolve-Path -LiteralPath $ProjectPath).Path)
if ($project.Attributes -band [IO.FileAttributes]::ReparsePoint) {
    $project = $project.ResolveLinkTarget($true)
}
$projectRoot = $project.FullName
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') -PathType Leaf)) {
    throw 'Expected a Flutter project containing pubspec.yaml'
}
$buildRoot = Join-Path $projectRoot 'build'
$helperRoot = Join-Path $buildRoot 'xcross-notification-runner'
$runnerRoot = Join-Path $buildRoot 'xcross-flutter-runner-bin'
foreach ($directory in @($buildRoot, $helperRoot, $runnerRoot)) {
    if ((Test-Path -LiteralPath $directory) -and
        ((Get-Item -LiteralPath $directory).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Refusing to prepare a runner through linked build directories'
    }
}
$helperPath = Join-Path $helperRoot 'clang.exe'
if (-not $ClangPath) {
    $ClangPath = $env:XCROSS_APPLE_TOOL_CLANG
    if ($ClangPath -and [IO.Path]::GetFullPath($ClangPath) -eq $helperPath) {
        $ClangPath = $env:CHATLOOM_XCROSS_REAL_CLANG
    }
    if (-not $ClangPath) {
        throw 'Pass -ClangPath matching the real compiler selected by xcross (or retain its existing XCROSS_APPLE_TOOL_CLANG override)'
    }
}
$realClang = (Resolve-Path -LiteralPath $ClangPath).Path
if ([IO.Path]::GetExtension($realClang) -ne '.exe' -or $realClang -eq $helperPath) {
    throw 'Expected the real clang.exe, not a shell script or the generated shim'
}
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc -PathType Leaf)) {
    throw 'The .NET Framework C# compiler is required to prepare the clang shim'
}
$runnerSource = Join-Path $runnerRoot 'Runner.m'
$source = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

internal static class ChatLoomClang {
    private static readonly string RealClang = Decode("__CLANG__");
    private static readonly string RunnerSource = Decode("__RUNNER__");
    private const string Marker = "// ChatLoom: restore Flutter notification delegate after plugin registration.";
    private const string Delegate = "[UNUserNotificationCenter currentNotificationCenter].delegate = self;";
    private const string NotificationImport = "#import <UserNotifications/UserNotifications.h>";
    private static string Decode(string value) { return Encoding.UTF8.GetString(Convert.FromBase64String(value)); }
    private static bool SamePath(string value, string expected) {
        if (String.IsNullOrEmpty(value) || value[0] == '-') return false;
        try { return String.Equals(Path.GetFullPath(value), expected, StringComparison.OrdinalIgnoreCase); }
        catch (ArgumentException) { return false; }
        catch (NotSupportedException) { return false; }
    }
    private static void CheckBuildPaths() {
        string runnerDirectory = Path.GetDirectoryName(RunnerSource);
        string buildDirectory = Path.GetDirectoryName(runnerDirectory);
        foreach (string path in new string[] { buildDirectory, runnerDirectory, RunnerSource }) {
            if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidOperationException("Refusing linked generated runner paths");
        }
    }
    private static void PrepareRunner() {
        CheckBuildPaths();
        string source = File.ReadAllText(RunnerSource);
        if (!source.Contains("@interface AppDelegate : FlutterAppDelegate <FlutterImplicitEngineDelegate>") ||
            !source.Contains("- (void)didInitializeImplicitFlutterEngine:(NSObject<FlutterImplicitEngineBridge>*)engineBridge {"))
            throw new InvalidOperationException("Unsupported xcross runner shape; reassess the notification hook");
        Regex registration = new Regex(@"(?m)^([ \t]*)XcrossRegisterGeneratedPlugins\(engineBridge\.pluginRegistry\);[ \t]*\r?$");
        MatchCollection matches = registration.Matches(source);
        if (matches.Count != 1) throw new InvalidOperationException("Expected exactly one generated plugin registration");
        int method = source.IndexOf("- (void)didInitializeImplicitFlutterEngine:", StringComparison.Ordinal);
        int methodEnd = source.IndexOf('}', method);
        if (matches[0].Index < method || matches[0].Index > methodEnd)
            throw new InvalidOperationException("Plugin registration is outside the expected engine method");
        string newline = source.Contains("\r\n") ? "\r\n" : "\n";
        string indent = matches[0].Groups[1].Value;
        string hook = newline + indent + Marker + newline + indent + Delegate;
        if (source.Contains(Marker)) {
            if (Regex.Matches(source, Regex.Escape(Marker)).Count != 1 ||
                !source.Contains(matches[0].Value.TrimEnd('\r') + hook) ||
                Regex.Matches(source, Regex.Escape(Delegate)).Count != 1 ||
                Regex.Matches(source, Regex.Escape(NotificationImport)).Count != 1)
                throw new InvalidOperationException("Unexpected existing ChatLoom notification hook");
            return;
        }
        if (source.Contains(Delegate) || source.Contains(NotificationImport))
            throw new InvalidOperationException("Unexpected existing notification delegate customization");
        const string flutterImport = "#import <Flutter/Flutter.h>";
        if (Regex.Matches(source, Regex.Escape(flutterImport)).Count != 1)
            throw new InvalidOperationException("Expected one Flutter framework import");
        source = registration.Replace(source, delegate(Match match) { return match.Value.TrimEnd('\r') + hook; });
        source = source.Replace(flutterImport, flutterImport + newline + NotificationImport);
        File.WriteAllText(RunnerSource, source, new UTF8Encoding(false));
    }
    // Quote every argument according to the Windows CRT argv rules. In
    // particular, trailing backslashes and backslashes before quotes double.
    private static string Quote(string argument) {
        StringBuilder result = new StringBuilder("\"");
        int slashes = 0;
        foreach (char character in argument) {
            if (character == '\\') { slashes++; continue; }
            if (character == '"') {
                result.Append('\\', slashes * 2 + 1).Append('"');
            } else {
                result.Append('\\', slashes).Append(character);
            }
            slashes = 0;
        }
        return result.Append('\\', slashes * 2).Append('"').ToString();
    }
    private static int Main(string[] arguments) {
        try {
            string runnerDirectory = Path.GetDirectoryName(RunnerSource);
            string runnerObject = Path.Combine(runnerDirectory, "Runner.o");
            string runnerBinary = Path.Combine(runnerDirectory, "Runner");
            bool compilesRunner = false, linksRunnerObject = false, writesRunner = false, hasFramework = false;
            for (int i = 0; i < arguments.Length; i++) {
                compilesRunner |= SamePath(arguments[i], RunnerSource);
                linksRunnerObject |= SamePath(arguments[i], runnerObject);
                if (i + 1 < arguments.Length && arguments[i] == "-o") writesRunner |= SamePath(arguments[i + 1], runnerBinary);
                if (i + 1 < arguments.Length && arguments[i] == "-framework" && arguments[i + 1] == "UserNotifications") hasFramework = true;
            }
            if (compilesRunner) PrepareRunner();
            StringBuilder forwarded = new StringBuilder();
            foreach (string argument in arguments) forwarded.Append(Quote(argument)).Append(' ');
            if (linksRunnerObject && writesRunner && !hasFramework) forwarded.Append("-framework UserNotifications");
            ProcessStartInfo start = new ProcessStartInfo(RealClang, forwarded.ToString());
            start.UseShellExecute = false;
            using (Process child = Process.Start(start)) { child.WaitForExit(); return child.ExitCode; }
        } catch (Exception error) {
            Console.Error.WriteLine("ChatLoom runner preparation failed: " + error.Message);
            return 1;
        }
    }
}
'@
$source = $source.Replace('__CLANG__', [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($realClang)))
$source = $source.Replace('__RUNNER__', [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($runnerSource)))
[IO.Directory]::CreateDirectory($helperRoot) | Out-Null
$sourcePath = Join-Path $helperRoot 'ChatLoomClang.cs'
foreach ($path in @($sourcePath, $helperPath)) {
    if ((Test-Path -LiteralPath $path) -and
        ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Refusing linked generated compiler helper files'
    }
}
if (-not (Test-Path -LiteralPath $sourcePath) -or
    [IO.File]::ReadAllText($sourcePath) -ne $source -or
    -not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
    [IO.File]::WriteAllText($sourcePath, $source, [Text.UTF8Encoding]::new($false))
    & $csc /nologo /target:exe /optimize+ "/out:$helperPath" $sourcePath
    if ($LASTEXITCODE -ne 0) { throw 'Failed to compile the scoped clang helper' }
}
$env:CHATLOOM_XCROSS_REAL_CLANG = $realClang
$env:XCROSS_APPLE_TOOL_CLANG = $helperPath
Write-Output 'Prepared xcross notification runner hook for this PowerShell session.'

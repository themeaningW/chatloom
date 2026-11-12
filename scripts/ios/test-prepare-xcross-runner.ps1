#requires -Version 7.0
# Synthetic compiler transport checks only: no Flutter, Apple SDK or native app build.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$fixtureRoot = Join-Path $repoRoot ('build\xcross-runner-tests\fixture with spaces ' + [Guid]::NewGuid().ToString('N'))
$runnerRoot = Join-Path $fixtureRoot 'build\xcross-flutter-runner-bin'
[IO.Directory]::CreateDirectory($runnerRoot) | Out-Null
[IO.File]::WriteAllText((Join-Path $fixtureRoot 'pubspec.yaml'), 'name: runner_fixture')
$runnerSource = Join-Path $runnerRoot 'Runner.m'
$originalSource = @'
#import <UIKit/UIKit.h>
#import <Flutter/Flutter.h>
@interface AppDelegate : FlutterAppDelegate <FlutterImplicitEngineDelegate>
@end
@implementation AppDelegate
- (void)didInitializeImplicitFlutterEngine:(NSObject<FlutterImplicitEngineBridge>*)engineBridge {
  XcrossRegisterGeneratedPlugins(engineBridge.pluginRegistry);
}
@end
'@
[IO.File]::WriteAllText($runnerSource, $originalSource)
$fakeSource = Join-Path $fixtureRoot 'FakeClang.cs'
$fakeCompiler = Join-Path $fixtureRoot 'FakeClang.exe'
[IO.File]::WriteAllText($fakeSource, @'
using System;
using System.IO;
using System.Text;
internal static class FakeClang {
    private static int Main(string[] arguments) {
        string[] encoded = new string[arguments.Length];
        for (int i = 0; i < arguments.Length; i++) encoded[i] = Convert.ToBase64String(Encoding.UTF8.GetBytes(arguments[i]));
        File.WriteAllLines(Environment.GetEnvironmentVariable("CHATLOOM_TEST_CLANG_ARGS"), encoded);
        string exit = Environment.GetEnvironmentVariable("CHATLOOM_TEST_CLANG_EXIT");
        return String.IsNullOrEmpty(exit) ? 0 : Int32.Parse(exit);
    }
}
'@)
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $csc /nologo /target:exe "/out:$fakeCompiler" $fakeSource
if ($LASTEXITCODE -ne 0) { throw 'Fake compiler did not compile' }
$previousClang = $env:XCROSS_APPLE_TOOL_CLANG
$previousCc = $env:CC
$previousRealClang = $env:CHATLOOM_XCROSS_REAL_CLANG
$previousCapture = $env:CHATLOOM_TEST_CLANG_ARGS
$previousExit = $env:CHATLOOM_TEST_CLANG_EXIT
function Assert-Arguments([string[]]$Expected) {
    $actual = @([IO.File]::ReadAllLines($env:CHATLOOM_TEST_CLANG_ARGS) | ForEach-Object {
        [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_))
    })
    if ($actual.Count -ne $Expected.Count) { throw "Argument count changed: $($actual.Count) vs $($Expected.Count)" }
    for ($index = 0; $index -lt $actual.Count; $index++) {
        if ($actual[$index] -cne $Expected[$index]) { throw "Argument changed at index $index" }
    }
}
try {
    $env:CHATLOOM_TEST_CLANG_ARGS = Join-Path $fixtureRoot 'arguments.txt'
    $env:CHATLOOM_TEST_CLANG_EXIT = '0'
    & (Join-Path $PSScriptRoot 'prepare-xcross-runner.ps1') -ProjectPath $fixtureRoot -ClangPath $fakeCompiler
    $shim = $env:CC
    if ($shim -cne (Join-Path $fixtureRoot 'build\xcross-notification-runner\clang.exe')) { throw 'CC did not select the generated runner compiler' }
    # A second setup in the same session must retain the real compiler instead
    # of embedding the shim itself and recursing forever.
    & (Join-Path $PSScriptRoot 'prepare-xcross-runner.ps1') -ProjectPath $fixtureRoot
    if ($env:CC -cne $shim -or $env:CHATLOOM_XCROSS_REAL_CLANG -cne $fakeCompiler) { throw 'Repeated setup changed the real compiler' }
    $arguments = @('-c', $runnerSource, '-o', (Join-Path $runnerRoot 'Runner.o'), '', 'with spaces', 'embedded"quote', 'C:\trailing path\', 'before\\"quote', 'zażółć', 'a&b', '$(literal)')
    & $shim @arguments
    if ($LASTEXITCODE -ne 0) { throw 'Runner compile transport failed' }
    Assert-Arguments $arguments
    $patched = [IO.File]::ReadAllText($runnerSource)
    if ($patched -notmatch 'XcrossRegisterGeneratedPlugins\(engineBridge.pluginRegistry\);\r?\n\s*// ChatLoom[^\r\n]*\r?\n\s*\[\(UNUserNotificationCenter \*\)\[NSClassFromString\(@"UNUserNotificationCenter"\) currentNotificationCenter\] setDelegate:self\];') {
        throw 'The notification delegate was not restored after registration'
    }
    & $shim @arguments
    if ($LASTEXITCODE -ne 0 -or [IO.File]::ReadAllText($runnerSource) -cne $patched) { throw 'Runner patch is not idempotent' }
    # xcross may regenerate this source for every build. The compile interception
    # must restore the hook again, rather than relying on stale patched output.
    [IO.File]::WriteAllText($runnerSource, $originalSource)
    & $shim @arguments
    if ($LASTEXITCODE -ne 0 -or [IO.File]::ReadAllText($runnerSource) -cne $patched) { throw 'Regenerated runner was not prepared' }
    $link = @((Join-Path $runnerRoot 'Runner.o'), '-o', (Join-Path $runnerRoot 'Runner'))
    & $shim @link
    Assert-Arguments $link
    $linkWithFramework = $link + @('-framework', 'UserNotifications')
    & $shim @linkWithFramework
    Assert-Arguments $linkWithFramework
    $otherRoot = Join-Path $fixtureRoot 'other'
    [IO.Directory]::CreateDirectory($otherRoot) | Out-Null
    $otherSource = Join-Path $otherRoot 'Runner.m'
    [IO.File]::WriteAllText($otherSource, 'unrelated runner remains untouched')
    $otherArguments = @('-c', $otherSource, '-o', (Join-Path $otherRoot 'Runner.o'))
    & $shim @otherArguments
    Assert-Arguments $otherArguments
    if ([IO.File]::ReadAllText($otherSource) -cne 'unrelated runner remains untouched') { throw 'Unrelated source was modified' }
    $otherLink = @((Join-Path $runnerRoot 'Runner.o'), '-o', (Join-Path $otherRoot 'Runner'))
    & $shim @otherLink
    Assert-Arguments $otherLink
    # The compatibility case reads a pinned cached plugin source but invokes
    # only FakeClang. It never compiles or modifies the real package/cache.
    $cacheRoot = Join-Path $env:LOCALAPPDATA 'xcross\swiftpm'
    $pluginSuffix = 'plugins\Packages\flutter_local_notifications\ios\flutter_local_notifications\Sources\flutter_local_notifications\FlutterLocalNotificationsPlugin.m'
    $pinnedPlugin = @(Get-ChildItem -LiteralPath $cacheRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^[a-fA-F0-9]{16}$' } | ForEach-Object {
        $candidate = Join-Path $_.FullName $pluginSuffix
        if ((Test-Path -LiteralPath $candidate -PathType Leaf) -and
            (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash -eq '42D8A987645116E599BF887B0211851636033418D63A45A414FF162ACB5B7BD7') { $candidate }
    }) | Select-Object -First 1
    if ($pinnedPlugin) {
        $pluginArguments = @('-c', $pinnedPlugin, '-o', (Join-Path $fixtureRoot 'plugin.o'))
        & $shim @pluginArguments
        if ($LASTEXITCODE -ne 0) { throw 'Pinned plugin compatibility transport failed' }
        Assert-Arguments ($pluginArguments + @('-Wno-error=incompatible-pointer-types'))
    } else {
        Write-Output 'SKIP: pinned cached plugin source is absent; no positive compatibility fixture available.'
    }
    $env:CHATLOOM_TEST_CLANG_EXIT = '23'
    & $shim --version
    if ($LASTEXITCODE -ne 23) { throw 'Compiler exit code was not forwarded' }
    $env:CHATLOOM_TEST_CLANG_EXIT = '0'
    [IO.File]::WriteAllText($runnerSource, 'unsupported generated source')
    [IO.File]::WriteAllText($env:CHATLOOM_TEST_CLANG_ARGS, 'not invoked')
    & $shim @arguments
    if ($LASTEXITCODE -eq 0 -or [IO.File]::ReadAllText($env:CHATLOOM_TEST_CLANG_ARGS) -cne 'not invoked') { throw 'Unsupported source did not fail before compiler invocation' }
    Write-Output 'PASS: CC hook, exact argv/exit forwarding, scoped patch, regeneration, idempotence, unchanged linker arguments and unsupported-source rejection.'
} finally {
    $env:CC = $previousCc
    $env:XCROSS_APPLE_TOOL_CLANG = $previousClang
    $env:CHATLOOM_XCROSS_REAL_CLANG = $previousRealClang
    $env:CHATLOOM_TEST_CLANG_ARGS = $previousCapture
    $env:CHATLOOM_TEST_CLANG_EXIT = $previousExit
}
if ($env:CC -cne $previousCc -or $env:XCROSS_APPLE_TOOL_CLANG -cne $previousClang -or
    $env:CHATLOOM_XCROSS_REAL_CLANG -cne $previousRealClang) {
    throw 'Synthetic tests did not restore the calling process compiler environment'
}

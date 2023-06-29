# dopt

A CLI parser for D

### Example

An example of using this library exists in the [example folder](./example/) and can 
be run with `dub run --root=example`.

```
example
dopt example app

usage: example [command]

Flags:
          -v,--verbose  Set verbose logging
             -h,--help  Print help
          -V,--version  Print version

Options:
  -c,--config [config]  Path to the configuration file

Commands:
                 build  Compile the program
                  test  Run tests
               install  Install dependencies
```

```d
import std.conv : ConvException;
import std.exception;
import std.format : format;
import std.functional : toDelegate;
import std.stdio;
import std.sumtype;
import std.typecons;

import dopt;

enum Profile
{
    Debug,
    Release,
}

static Profile parseProfile(string s)
{
    switch (s)
    {
    case "debug":
        return Profile.Debug;
    case "release":
        return Profile.Release;
    default:
        throw new ConvException(
                format!"%s is not a valid profile. Valid values are: debug, release"(s));
    }
}

@Command() @Help("Compile the program")
struct Build
{
    @Option() @Long() @Help("Build for the provided profile") @Parse!Profile(&parseProfile)
    Profile profile = Profile.Debug;
    @Option() @Long() @Short() @Help("Number of parallel jobs")
    int jobs;
}

@Command() @Help("Run tests")
struct Test
{
    @Option() @Long() @Help("Build for the provided profile") @Parse!Profile(&parseProfile)
    Profile profile = Profile.Debug;
    @Option() @Long("no-run") @Help("Compile but don't run tests")
    bool noRun;
}

@Command() @Help("Install dependencies")
struct Install
{
    @Positional() @Required() @Help("Space separated list of dependencies")
    string[] dependencies;
}

// WARNING: Subcommands cannot be named "Subcommand" as that
// collides w/ the @Subcommand UDA.
alias ExampleSubcommand = SumType!(Build, Test, Install);

@Command("example") @Help("dopt example app") @Version("0.1.0")
struct Example
{
    @Global() @Short() @Long() @Help("Set verbose logging")
    bool verbose = false;
    @Global() @Long() @Short() @Help("Path to the configuration file")
    string config;
    @Subcommand()
    ExampleSubcommand subcommand;
}

int main(string[] args)
{
    Example cli;
    try
    {
        cli = parse!Example(args);
    }
    catch (HelpException e)
    {
        return 0;
    }
    catch (VersionException e)
    {
        return 0;
    }
    catch (Exception e)
    {
        return 1;
    }

    writeln(cli);

    return 0;
}
```


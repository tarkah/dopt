module dopt;

public import dopt.uda;
public import dopt.parse : parse, HelpException, UsageException;

unittest
{
    import std.conv : ConvException;
    import std.exception;
    import std.format : format;
    import std.functional : toDelegate;
    import std.stdio;
    import std.sumtype;
    import std.typecons;

    import dopt.uda;
    import meta = dopt.meta;

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

    @Command() @Help("Build the app")
    struct Build
    {
        @Option() @Long() @Short()
        int jobs;
        @Positional("path") @Required()
        string[] paths;
    }

    @Command("tst") @Help("Run tests")
    struct Test
    {
        @Option() @Long() @Short() @Required()
        @Parse!Profile(&parseProfile) Profile profile = Profile.Debug;
        @Positional() @Required()
        string path;
    }

    alias ExampleSubcommand = SumType!(Build, Test);

    @Command() @Help("Example app help...") @Version("0.1.0")
    struct Example
    {
        @Global() @Long("debug") @Short("d") @Help("Sets output logging to debug level")
        bool _debug = false;
        @Global() @Long() @Help("Set verbose logging")
        bool verbose = false;
        @Global() @Long() @Short() @Help("Path to the configuration file")
        string config;
        @Subcommand()
        ExampleSubcommand subcommand;
    }

    auto _meta = meta.build!Example(Nullable!(meta.Command).init);
    writeln(_meta);

    auto args = ["example", "-d", "--verbose",];
    auto example = parse!Example(args);
    writeln(example);

    args = [
        "example", "tst", "--profile", "release", "/usr/", "-d", "--verbose"
    ];
    example = parse!Example(args);
    writeln(example);

    args = [
        "example", "build", "-j", "8", "/usr,/home,/etc", "-c", "/etc/test.conf",
    ];
    example = parse!Example(args);
    writeln(example);

    args = ["example", "-d", "build", "-x", "9", "/usr",];
    assertThrown!UsageException(parse!Example(args));

    args = ["example", "tst", "/asdf"];
    assertThrown!UsageException(parse!Example(args));

    args = ["example", "-h",];
    assertThrown!HelpException(parse!Example(args));

    args = ["example", "build", "-h",];
    assertThrown!HelpException(parse!Example(args));
}

module dopt;

public import dopt.exception : DoptException, HelpException, UsageException, VersionException;
public import dopt.parse : parse;
public import dopt.uda;

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

    @Command("test") @Alias("tst") @Alias("t") @Help("Run tests")
    struct Test
    {
        @Option() @Long() @Short() @Required()
        @Parse!Profile(&parseProfile) Profile profile = Profile.Debug;
        @Positional() @Required()
        string path;
    }

    alias Subcommands = SumType!(Build, Test);

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
        Subcommands subcmd;
    }

    auto _meta = meta.build!Example(Nullable!(meta.Command).init);
    writeln(_meta);

    auto args = ["example", "-d", "--verbose", "build", "/usr"];
    auto example = parse!Example(args);
    writeln(example);
    assert(example == Example(true, true, "", Subcommands(Build(0, ["/usr"]))));

    args = [
        "example", "tst", "--profile", "release", "/usr/", "-d", "--verbose"
    ];
    example = parse!Example(args);
    assert(example == Example(true, true, "", Subcommands(Test(Profile.Release, "/usr/"))));
    writeln(example);

    args = [
        "example", "build", "-j", "8", "/usr,/home,/etc", "-c", "/etc/test.conf",
    ];
    example = parse!Example(args);
    assert(example == Example(false, false, "/etc/test.conf", Subcommands(Build(8, ["/usr,/home,/etc"]))));
    writeln(example);

    args = ["example", "-d", "build", "-x", "9", "/usr",];
    assertThrown!UsageException(parse!Example(args));

    args = ["example", "tst", "/asdf"];
    assertThrown!UsageException(parse!Example(args));

    args = ["example", "-h",];
    assertThrown!HelpException(parse!Example(args));

    args = ["example", "build", "-h",];
    assertThrown!HelpException(parse!Example(args));

    args = ["example", "--version",];
    assertThrown!VersionException(parse!Example(args));

    args = ["example", "build", "-V",];
    assertThrown!VersionException(parse!Example(args));
}

unittest
{

    import std.conv : ConvException;
    import std.exception;
    import std.format : format;
    import std.stdio;
    import std.sumtype;
    import std.typecons;

    import dopt.uda;
    import meta = dopt.meta;

    @Command() @Alias("nt") @Help("This")
    struct This
    {
    }

    @Command() @Alias("nh") @Help("That")
    struct That
    {
    }

    alias NestedSub = SumType!(This, That);

    @Command() @Help("A subcommand with nested commands")
    struct Nested
    {
        @Subcommand NestedSub sub;
    }

    @Command() @Help("A flat subcommand")
    struct Flat
    {
    }

    alias Subcommands = SumType!(Nested, Flat);

    @Command() @Help("Testing nested & aliases")
    struct Example
    {
        @Global() @Short()
        bool verbose = false;
        @Subcommand()
        Subcommands subcmd;
    }

    auto _meta = meta.build!Example(Nullable!(meta.Command).init);
    writeln(_meta);

    auto args = ["example", "nested", "-h"];
    assertThrown!HelpException(parse!Example(args));

    args = ["example", "nested", "this"];
    auto expanded = parse!Example(args);
    args = ["example", "nt"];
    auto nested = parse!Example(args);
    writeln(nested);
    assert(expanded == nested);

    args = ["example", "nested", "that", "-v"];
    expanded = parse!Example(args);
    args = ["example", "nh", "-v"];
    nested = parse!Example(args);
    writeln(nested);
    assert(expanded == nested);
}

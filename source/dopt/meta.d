module dopt.meta;

import std.stdio : writeln;
import std.sumtype : isSumType;
import std.traits : getSymbolsByUDA;
import std.typecons : Nullable, nullable;

import uda = dopt.uda;

struct Command
{
    string name;
    string help;

    string[] path;

    Global[] globals;
    Option[] options;
    Positional[] positionals;

    Command[] subcommands;
}

struct Positional
{
    string name;
    bool required;
    string help;
}

struct Option
{
    string _long;
    string _short;
    bool required;
    string help;
}

struct Global
{
    string _long;
    string _short;
    bool required;
    string help;
}

// TODO: Static assert global & option have long and/or short UDA set
static Command build(T)(Nullable!Command parent)
{
    Command cmd = Command.init;
    cmd.name = uda.commandValue!T;
    cmd.help = uda.helpValue!T;

    cmd.globals = parent.isNull ? [] : parent.get.globals;
    cmd.path = parent.isNull ? [cmd.name] : parent.get.path ~ cmd.name;

    static foreach (arg; getSymbolsByUDA!(T, uda.Global))
    {
        cmd.globals ~= global!arg;
    }
    static foreach (arg; getSymbolsByUDA!(T, uda.Option))
    {
        cmd.options ~= option!arg;
    }
    static foreach (arg; getSymbolsByUDA!(T, uda.Positional))
    {
        cmd.positionals ~= positional!arg;
    }

    cmd.subcommands = subcommands!T(cmd);

    return cmd;
}

Nullable!Command find(Command cmd, string[] path)
{
    if (cmd.path == path)
    {
        return cmd.nullable;
    }
    else
    {
        foreach (sub; cmd.subcommands)
        {
            auto result = find(sub, path);

            if (!result.isNull)
            {
                return result;
            }
        }
    }

    return Nullable!Command.init;
}

void printHelp(T)(string[] path)
{
    auto root = build!(T)(Nullable!Command.init);

    // null should be unreachable
    auto cmd = find(root, path);

    writeln(cmd);
}

void printUsage(T)(string[] path, string error)
{
    auto root = build!(T)(Nullable!Command.init);

    // null should be unreachable
    auto cmd = find(root, path);

    writeln(error);
}

static Global global(alias arg)()
{
    static _long = uda.longValue!(arg);
    static _short = uda.shortValue!(arg);
    static required = uda.requiredValue!(arg);
    static help = uda.helpValue!(arg);

    return Global(_long, _short, required, help);
}

static Option option(alias arg)()
{
    static _long = uda.longValue!(arg);
    static _short = uda.shortValue!(arg);
    static required = uda.requiredValue!(arg);
    static help = uda.helpValue!(arg);

    return Option(_long, _short, required, help);
}

static Positional positional(alias arg)()
{
    static name = uda.positionalValue!(arg);
    static required = uda.requiredValue!(arg);
    static help = uda.helpValue!(arg);

    return Positional(name, required, help);
}

static Command[] subcommands(T)(Command cmd)
{
    Command[] cmds = [];

    alias udaSubcommand = getSymbolsByUDA!(T, uda.Subcommand);

    static if (udaSubcommand.length == 1)
    {
        alias subcommand = udaSubcommand[0];

        static if (isSumType!(typeof(subcommand)))
        {
            static foreach (member; subcommand.Types)
            {
                cmds ~= build!(member)(cmd.nullable);
            }
        }
    }

    return cmds;
}

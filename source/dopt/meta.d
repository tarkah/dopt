module dopt.meta;

import std.sumtype : isSumType;
import std.traits : getSymbolsByUDA, isBoolean, isArray, isSomeString;
import std.typecons : Nullable, nullable;

import uda = dopt.uda;

struct Command
{
    string name;
    string[] aliases;
    string help;
    string _version;

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
    bool isArray;
}

enum Value
{
    Bool,
    Array,
    Other,
}

struct Option
{
    string _long;
    string _short;
    bool required;
    string help;
    Value value;
}

struct Global
{
    string _long;
    string _short;
    bool required;
    string help;
    Value value;
}

// TODO: Static assert global & option have long and/or short UDA set
static Command build(T)(Nullable!Command parent)
{
    Command cmd = Command.init;
    cmd.name = uda.commandValue!T;
    cmd.aliases = uda.aliasValues!T;
    cmd.help = uda.helpValue!T;
    cmd._version = uda.versionValue!T;

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

static string[][string] aliasMap(T)()
{
    string[][string] map;

    auto command = build!T(Nullable!Command.init);

    void update(Command cmd)
    {
        foreach (_alias; cmd.aliases)
        {
            map[_alias] = cmd.path[1 .. $];
        }

        foreach (subcmd; cmd.subcommands)
        {
            update(subcmd);
        }
    }

    update(command);

    return map;
}

static bool isNonStrArray(T)()
{
    return isArray!T && !isSomeString!T;
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

private:

static Global global(alias arg)()
{
    static _long = uda.longValue!(arg);
    static _short = uda.shortValue!(arg);
    static required = uda.requiredValue!(arg);
    static help = uda.helpValue!(arg);
    static value = value!(arg);

    return Global(_long, _short, required, help, value);
}

static Option option(alias arg)()
{
    static _long = uda.longValue!(arg);
    static _short = uda.shortValue!(arg);
    static required = uda.requiredValue!(arg);
    static help = uda.helpValue!(arg);
    static value = value!(arg);

    return Option(_long, _short, required, help, value);
}

static Value value(alias arg)()
{
    static if (isBoolean!(typeof(arg)))
    {
        return Value.Bool;
    }
    else static if (isNonStrArray!(typeof(arg)))
    {
        return Value.Array;
    }
    else
    {
        return Value.Other;
    }
}

static Positional positional(alias arg)()
{
    static name = uda.positionalValue!(arg);
    static required = uda.requiredValue!(arg);
    static help = uda.helpValue!(arg);
    static isArray = isNonStrArray!(typeof(arg));

    return Positional(name, required, help, isArray);
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

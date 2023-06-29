module dopt.uda;

import std.conv : text;
import std.range : empty;
import std.string : toLower, toUpper;
import std.traits : getUDAs;

struct Command
{
    string value;
}

/**
 Mark a field as as subcommand. The field must be a sumtype value.

 ```d
 // WARNING: Subcommands cannot be named "Subcommand" as that
 // collides w/ the @Subcommand UDA.
 alias Subcmd = SumType!(CmdA, CmdB);

 @Command()
 struct App {
     @Subcommand()
     Subcmd subcmd;
 }
 ```
*/
struct Subcommand
{
}

struct Version
{
    string value;
}

struct Help
{
    string value;
}

struct Positional
{
    string value;
}

struct Option
{
}

struct Global
{
}

struct Required
{
}

struct Long
{
    string value;
}

struct Short
{
    string value;
}

struct Parse(T)
{
    T function(string s) value;
}

struct Alias
{
    string value;
}

static string commandValue(alias T)()
{
    alias uda = getUDAs!(T, Command);

    static if (uda.length > 0)
    {
        return uda[0].value.empty ? T.stringof.toLower : uda[0].value;
    }
    else
    {
        return "";
    }

}

static string helpValue(alias T)()
{
    alias uda = getUDAs!(T, Help);

    static if (uda.length > 0)
    {
        return uda[0].value.empty ? "" : uda[0].value;
    }
    else
    {
        return "";
    }
}

static string versionValue(alias T)()
{
    alias uda = getUDAs!(T, Version);

    static if (uda.length > 0)
    {
        return uda[0].value.empty ? "" : uda[0].value;
    }
    else
    {
        return "";
    }
}

static string positionalValue(alias T)()
{
    alias uda = getUDAs!(T, Positional);

    static if (uda.length > 0)
    {
        return uda[0].value.empty ? T.stringof.toLower : uda[0].value;
    }
    else
    {
        return "";
    }

}

static string longValue(alias T)()
{
    alias uda = getUDAs!(T, Long);

    static if (uda.length > 0)
    {
        return uda[0].value.empty ? T.stringof : uda[0].value;
    }
    else
    {
        return "";
    }
}

static string shortValue(alias T)()
{
    alias uda = getUDAs!(T, Short);

    static if (uda.length > 0)
    {
        return uda[0].value.empty ? text(T.stringof[0]) : uda[0].value;
    }
    else
    {
        return "";
    }
}

static string[] aliasValues(alias T)()
{
    alias udas = getUDAs!(T, Alias);

    static if (udas.length > 0)
    {
        string[] parsed;

        static foreach (uda; udas)
        {
            static if (!uda.value.empty)
            {
                parsed = parsed ~ uda.value;
            }
        }
        return parsed;
    }
    else
    {
        return [];
    }
}

static bool requiredValue(alias T)()
{
    alias uda = getUDAs!(T, Required);

    return uda.length > 0;
}

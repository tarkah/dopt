module dopt.format;

import std.algorithm : map, fold, max, filter;
import std.array : join, array;
import std.format : format;
import std.range : empty;
import std.stdio : writeln;
import std.traits : isArray;
import std.typecons : Nullable;

import dopt.meta;

const SPACE = "  ";

void printHelp(T)(string[] path)
{
    Command root = build!(T)(Nullable!Command.init);

    // null should be unreachable
    Command cmd = find(root, path).get;

    auto usage = usage(cmd);

    writeln(format!"%-(%s %)"(path));
    if (cmd.help.length > 0)
    {
        writeln(cmd.help);
    }

    writeln();
    writeln(usage);

    auto maxSubcmd = maxLeftLength(cmd.subcommands);
    auto maxOption = maxLeftLength(cmd.globals);
    auto maxGlobal = maxLeftLength(cmd.options);

    auto maxLeft = max(maxSubcmd, maxOption, maxGlobal);

    printFlags(cmd.options, cmd.globals, maxLeft);
    printOptions(cmd.options, cmd.globals, maxLeft);
    printSubcommands(cmd.subcommands, maxLeft);
    printPositionals(cmd.positionals, maxLeft);
}

void printVersion(T)()
{
    Command root = build!(T)(Nullable!Command.init);

    writeln(format!"%s %s"(root.name, root._version));
}

void printUsage(T)(string[] path, string error)
{
    auto root = build!(T)(Nullable!Command.init);

    // null should be unreachable
    auto cmd = find(root, path).get;

    auto usage = usage(cmd);

    writeln(error);
    writeln();
    writeln(usage);
}

private string usage(Command cmd)
{
    auto path = cmd.path.join(" ");

    if (cmd.subcommands.length > 0)
    {
        return `usage: %s <command>`.format(path);
    }
    else
    {
        auto positionals = cmd.positionals.map!(p => fmtArg(p, p.required)).join(" ");

        return `usage: %s %s`.format(path, positionals);
    }

}

private void printSubcommands(Command[] subcommands, ulong maxLeft)
{
    if (subcommands.length > 0)
    {
        writeln();
        writeln("Commands:");

        foreach (cmd; subcommands)
        {
            writeln(SPACE, format!`%*s`(maxLeft, fmtCommandName(cmd)), SPACE, cmd.help);
        }
    }
}

private void printFlags(Option[] _opts, Global[] _globals, ulong maxLeft)
{
    auto helpFlag = Global("help", "h", false, "Print help", Value.Bool);
    auto versionFlag = Global("version", "V", false, "Print version", Value.Bool);

    auto opts = flags(_opts).array;
    auto globals = flags(_globals).array ~ [helpFlag, versionFlag];

    writeln();
    writeln("Flags:");

    foreach (opt; opts)
    {
        writeln(SPACE, format!"%*s"(maxLeft, fmtLeft(opt)), SPACE, opt.help);
    }
    foreach (global; globals)
    {
        writeln(SPACE, format!"%*s"(maxLeft, fmtLeft(global)), SPACE, global.help);
    }
}

private void printOptions(Option[] _opts, Global[] _globals, ulong maxLeft)
{
    auto opts = options(_opts).array;
    auto globals = options(_globals).array;

    if (opts.length > 0 || globals.length > 0)
    {
        writeln();
        writeln("Options:");

        foreach (opt; opts)
        {
            writeln(SPACE, format!"%*s"(maxLeft, fmtLeft(opt)), SPACE, opt.help);
        }
        foreach (global; globals)
        {
            writeln(SPACE, format!"%*s"(maxLeft, fmtLeft(global)), SPACE, global.help);
        }
    }
}

private void printPositionals(Positional[] positionals, ulong maxLeft)
{

    if (positionals.length > 0)
    {
        writeln();
        writeln("Args:");

        foreach (positional; positionals)
        {
            writeln(SPACE, format!"%*s"(maxLeft, fmtLeft(positional)), SPACE, positional.help);
        }
    }
}

auto flags(Range)(Range range)
{
    return range.filter!(i => i.value == Value.Bool);
}

auto options(Range)(Range range)
{
    return range.filter!(i => i.value != Value.Bool);
}

ulong maxLeftLength(T)(T[] items)
{
    const ulong seed = 0;
    return items.map!(i => fmtLeft!T(i).length)
        .fold!(max)(seed);
}

string fmtCommandName(Command cmd)
{
    if (cmd.aliases.empty)
    {
        return cmd.name;
    }
    else
    {
        return format!"%s (%-(%s, %))"(cmd.name, cmd.aliases);
    }
}

string fmtArg(T)(T item, bool required)
{
    if (required)
    {
        return format!"<%s>"(fmtArray(item));
    }
    else
    {
        return format!"[%s]"(fmtArray(item));
    }
}

string fmtArray(T)(T item)
{
    static if (is(T : Positional))
    {
        if (item.isArray)
        {
            return format!"%s..."(fmtName(item));
        }
    }

    return fmtName(item);
}

string fmtName(T)(T item)
{
    static if (is(T : Positional))
    {
        return item.name;
    }
    else
    {
        return item._long;
    }
}

string fmtLeft(T)(T item)
{
    static if (is(T : Command))
    {
        return fmtCommandName(item);
    }
    else static if (is(T : Positional))
    {
        return fmtArg(item, item.required);
    }
    else
    {
        if (item.value == Value.Bool)
        {
            if (item._short.length > 0)
            {
                return format!"-%s,--%s"(item._short, item._long);
            }
            else
            {
                return format!"--%s"(item._long);
            }
        }
        else
        {
            if (item._short.length > 0)
            {
                return format!"-%s,--%s %s"(item._short, item._long, fmtArg(item, true));
            }
            else
            {
                return format!"--%s %s"(item._long, fmtArg(item, true));
            }
        }
    }
}

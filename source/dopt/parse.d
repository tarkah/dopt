module dopt.parse;

import std.algorithm : findSplit, findSplitBefore, filter, each, countUntil, count;
import std.array : array;
import std.conv : text, ConvException;
import std.format : format;
import std.getopt : getopt, config, arraySep, GetOptException;
import std.range : empty, enumerate;
import std.sumtype : isSumType, SumType, match;
import std.traits : getSymbolsByUDA, getUDAs;
import std.typecons : tuple, Nullable, nullable;
import std.uni : toLower;

import dopt.exception : HelpException, UsageException, VersionException;
import dopt.format : printHelp, printUsage, printVersion;
import dopt.meta : isNonStrArray, aliasMap;
import dopt.uda;

struct Help
{
    string[] path;
}

struct Version
{
}

struct Error
{
    string[] path;
    string msg;
}

enum BuiltinFlag
{
    None,
    Help,
    Version,
}

alias Result(T) = SumType!(T, Help, Version, Error);

static T parse(T)(ref string[] args)
{
    // Replace all aliases w/ their full
    // command path
    replaceAliases!T(args);

    auto result = parseArgs!(T)(args, []);

    T function(Help) onHelp = (help) {
        printHelp!T(help.path);
        throw new HelpException("help printed");
    };
    T function(Version) onVersion = (_version) {
        printVersion!T;
        throw new VersionException("version printed");
    };
    T function(Error) onError = (error) {
        printUsage!T(error.path, error.msg);
        throw new UsageException("usage printed");
    };

    return result.match!((T t) => t, onHelp, onVersion, onError);
}

static replaceAliases(T)(ref string[] args)
{
    auto aliases = aliasMap!T;

    foreach (find, replacement; aliases)
    {
        auto split = args.findSplit([find]);

        if (!split[1].empty)
        {
            args = split[0] ~ replacement ~ split[2];
        }
    }
}

static Result!T parseArgs(T)(ref string[] args, string[] inPath)
{
    T t = T.init;

    string[] path = inPath ~ commandValue!T;

    try
    {
        // Globals
        globals!(T)(t, args);

        // Options 
        auto builtin = options!(T)(t, args);

        // Return if help or version passed
        if (builtin == BuiltinFlag.Help)
        {
            return Result!T(Help(path));
        }
        else if (builtin == BuiltinFlag.Version)
        {
            return Result!T(Version());
        }

        // Subcommand
        auto withSub = subcommand!(T)(t, args, path);
        if (!withSub.isNull)
        {
            return withSub.get;
        }

        // Positionals
        positionals!(T)(t, args);
    }
    catch (GetOptException err)
    {
        return Result!T(Error(path, err.msg));
    }
    catch (ConvException err)
    {
        return Result!T(Error(path, err.msg));
    }
    catch (Exception err)
    {
        throw err;
    }

    return Result!T(t);
}

template setupOptCallbacks(T)
{
    static foreach (member; getSymbolsByUDA!(T, Parse))
    {
        mixin("static cb" ~ member.stringof ~ " = getUDAs!(member, Parse)[0].value;");
        mixin("void dg" ~ member.stringof ~ "(string option, string value) { t."
                ~ member.stringof ~ " = cb" ~ member.stringof ~ "(value); }");
    }
}

string genOpts(T, bool global)()
{
    template fmtLabel(alias field)
    {
        alias longFmt = longValue!(field);
        alias shortFmt = shortValue!(field);

        static if (shortFmt.empty)
        {
            enum fmtLabel = escaped!(longFmt);
        }
        else
        {
            enum fmtLabel = escaped!(shortFmt ~ "|" ~ longFmt);
        }
    }

    template fmtDg(alias field)
    {
        alias parse = getUDAs!(field, Parse);

        static if (parse.length == 1)
        {
            enum fmtDg = "&dg" ~ field.stringof;
        }
        else
        {
            enum fmtDg = "&t." ~ field.stringof;
        }
    }

    template fmt(T, Fields...)
    {
        static if (Fields.length == 0)
        {
            enum fmt = "tuple()";
        }
        else
        {
            alias field = Fields[0];
            alias rest = Fields[1 .. $];

            alias required = requiredValue!(field);
            alias label = fmtLabel!(field);
            alias dg = fmtDg!(field);

            static if (required)
            {
                enum fmt = "tuple(config.required, " ~ label ~ "," ~ dg ~ ") ~ " ~ fmt!(T, rest);
            }
            else
            {
                enum fmt = "tuple(" ~ label ~ "," ~ dg ~ ") ~ " ~ fmt!(T, rest);
            }

        }
    }

    static if (global)
    {
        return fmt!(T, getSymbolsByUDA!(T, Global));
    }
    else
    {
        return fmt!(T, getSymbolsByUDA!(T, Option));
    }

}

template escaped(alias s)
{
    enum escaped = `"` ~ s ~ `"`;
}

static globals(T)(ref T t, ref string[] args)
{
    if (args.length > 1)
    {
        mixin setupOptCallbacks!T;
        mixin("auto opts = " ~ genOpts!(T, true) ~ ";");

        // Prevent help from getting captured at this level
        args.filter!(a => a == "-h" || a == "--help")
            .each!((ref a) => a = a ~ "~");

        arraySep = ",";
        getopt(args, config.keepEndOfOptions, config.caseSensitive,
                config.passThrough, opts.expand);

        // Restore help flags
        args.filter!(a => a == "-h~" || a == "--help~")
            .each!((ref a) => a = a[0 .. $ - 1]);
    }
}

static BuiltinFlag options(T)(ref T t, ref string[] args)
{
    bool _version = false;

    mixin setupOptCallbacks!T;
    mixin("auto opts = " ~ genOpts!(T, false) ~ `~ tuple("version|V", &_version);`);

    ulong cmdPos = subcommandPosition!(T)(args);
    ulong end = cmdPos > 0 ? cmdPos : args.length;
    auto target = args[0 .. end];

    arraySep = ",";
    auto result = getopt(target, config.keepEndOfOptions, config.caseSensitive,
            config.noPassThrough, opts.expand);

    args = target ~ args[end .. $];

    if (result.helpWanted)
    {
        return BuiltinFlag.Help;
    }
    else if (_version)
    {
        return BuiltinFlag.Version;
    }

    return BuiltinFlag.None;
}

static positionals(T)(ref T t, ref string[] args)
{

    // Statically count how many required fields
    template countRequired(Fields...)
    {
        static if (Fields.length > 0)
        {
            static if (requiredValue!(Fields[0]))
            {
                enum countRequired = 1 + countRequired!(Fields[1 .. $]);
            }
            else
            {
                enum countRequired = countRequired!(Fields[1 .. $]);
            }
        }
        else
        {
            enum countRequired = 0;
        }
    }

    // Statically check if required array exists
    template requiredArrayExists(Fields...)
    {
        static if (Fields.length > 0)
        {
            static if (requiredValue!(Fields[0]) && isNonStrArray!(typeof(Fields[0])))
            {
                enum requiredArrayExists = true;
            }
            else
            {
                enum requiredArrayExists = requiredArrayExists!(Fields[1 .. $]);
            }
        }
        else
        {
            enum requiredArrayExists = false;
        }
    }

    // Compute stats around required fields
    alias positionals = getSymbolsByUDA!(T, Positional);
    alias numRequired = countRequired!positionals;
    alias hasRequiredArray = requiredArrayExists!positionals;

    // Assert no optional fields exist if there is a required array
    static if (hasRequiredArray && positionals.length - numRequired > 0)
    {
        static assert(0,
                "Optional positional field is not allows if a required array positional field exists.");
    }

    // Determine how many optional fields we are allowed to parse
    // If required array we can't support options
    // else # args - # required
    int optRemaining = hasRequiredArray ? 0 : cast(int) args[1 .. $].filter!(s => s != "--")
        .count - numRequired;

    static foreach (positional; getSymbolsByUDA!(T, Positional))
    {
        // If array, we exhaust the remaining args into it
        static if (isNonStrArray!(typeof(positional)))
        {
            {
                alias required = requiredValue!positional;

                args = args.filter!(s => s != "--").array;

                if (args[1 .. $].length > 0)
                {
                    mixin(`t.` ~ positional.stringof ~ `.length = args[1 .. $].length;`);

                    args[1 .. $].enumerate().each!((i, arg) {
                        auto _args = [args[0], "--positional", arg];

                        mixin(
                            `auto opts = tuple("positional",` ~ `&t.` ~ positional.stringof
                            ~ "[i]);");

                        getopt(_args, config.caseSensitive, config.required, opts.expand);
                    });
                }
                else if (required)
                {
                    throw new GetOptException(format!"Missing values for argument <%s...>"(
                            positionalValue!positional));
                }
            }
        }
        // Otherwise parse them one at a time
        else
        {
            try
            {
                alias required = requiredValue!positional;

                auto nonEndPos = args[1 .. $].countUntil!(s => s != "--") + 1;

                // No arg exists, error if required else continue
                if (nonEndPos == 0)
                {
                    if (required)
                    {
                        throw new GetOptException("");
                    }
                }
                else if (required || optRemaining > 0)
                {
                    if (!required)
                    {
                        optRemaining -= 1;
                    }

                    // Hacky solution to support positionals w/ getopt =P
                    auto posArg = [args[0]] ~ "--positional" ~ args[nonEndPos .. nonEndPos + 1];

                    mixin(`auto opts = tuple("positional",` ~ `&t.` ~ positional.stringof ~ ");");

                    arraySep = ",";

                    getopt(posArg, config.caseSensitive, config.required, opts.expand);

                    args = args[0 .. nonEndPos] ~ args[nonEndPos + 1 .. $];
                }
            }
            catch (GetOptException err)
            {
                throw new GetOptException(format!"Missing value for argument <%s>"(
                        positionalValue!positional));
            }
        }
    }
}

static Nullable!(Result!T) subcommand(T)(ref T t, ref string[] args, string[] path)
{
    alias subs = getSymbolsByUDA!(T, Subcommand);

    static if (subs.length == 1)
    {
        alias sub = subs[0];

        static if (isSumType!(typeof(sub)))
        {
            static foreach (member; sub.Types)
            {
                {
                    static cmd = commandValue!member;

                    if (args.length > 1)
                    {
                        if (cmd == args[1])
                        {
                            args = args[0] ~ args[2 .. $];

                            auto result = parseArgs!member(args, path);

                            auto mapSub = (member subcmd) {
                                mixin("t." ~ sub.stringof ~ " = subcmd;");
                                return Result!T(t).nullable;
                            };
                            auto mapHelp = (Help help) => Result!T(help).nullable;
                            auto mapVersion = (Version _version) => Result!T(_version).nullable;
                            auto mapError = (Error error) => Result!T(error).nullable;

                            return result.match!(mapSub, mapHelp, mapVersion, mapError);
                        }
                    }
                }
            }
        }

        throw new GetOptException("Missing [command]");
    }
    else
    {
        return Nullable!(Result!T).init;
    }
}

static ulong subcommandPosition(T)(ref string[] args)
{
    alias subs = getSymbolsByUDA!(T, Subcommand);

    static if (subs.length == 1)
    {
        alias sub = subs[0];

        static if (isSumType!(typeof(sub)))
        {
            static foreach (member; sub.Types)
            {

                {
                    static cmd = commandValue!member;

                    auto split = args.findSplitBefore([cmd]);

                    if (split)
                    {
                        return split[0].length;
                    }
                }
            }
        }
    }

    return 0;
}

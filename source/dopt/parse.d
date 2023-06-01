module dopt.parse;

import std.algorithm : findSplitBefore, filter, each;
import std.conv : text, ConvException;
import std.exception : basicExceptionCtors;
import std.format : format;
import std.getopt : getopt, config, arraySep, GetOptException;
import std.range : empty, enumerate;
import std.sumtype : isSumType, SumType, match;
import std.traits : getSymbolsByUDA, getUDAs;
import std.typecons : tuple, Nullable, nullable;
import std.uni : toLower;

import dopt.uda;
import dopt.format : printHelp, printUsage, printVersion;
import dopt.meta : isNonStrArray;

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

class HelpException : Exception
{
    ///
    mixin basicExceptionCtors;
}

class VersionException : Exception
{
    ///
    mixin basicExceptionCtors;
}

class UsageException : Exception
{
    ///
    mixin basicExceptionCtors;
}

alias Result(T) = SumType!(T, Help, Version, Error);

static T parse(T)(ref string[] args)
{
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
        getopt(args, config.caseSensitive, config.passThrough, opts.expand);

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
    auto result = getopt(target, config.caseSensitive, config.noPassThrough, opts.expand);

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
    static foreach (positional; getSymbolsByUDA!(T, Positional))
    {
        // TODO: Handle optional positional args, currently they are always required
        static if (isNonStrArray!(typeof(positional)))
        {
            if (args[1 .. $].length > 1)
            {
                // Safe to assume positional array is always last? (at least for now while
                // we assume space separated values)
                mixin(`t.` ~ positional.stringof ~ `.length = args[1 .. $].length;`);

                args[1 .. $].enumerate().each!((i, arg) {
                    auto _args = [args[0], "--positional", arg];

                    mixin(`auto opts = tuple("positional",` ~ `&t.` ~ positional.stringof ~ "[i]);");

                    getopt(_args, config.caseSensitive, config.required, opts.expand);
                });
            }
            else
            {
                throw new GetOptException(format!"Missing values for argument [%s]..."(
                        positionalValue!positional));
            }
        }
        else
        {
            try
            {
                // Hacky solution to support positionals w/ getopt =P
                args = [args[0]] ~ "--positional" ~ args[1 .. $];

                mixin(`auto opts = tuple("positional",` ~ `&t.` ~ positional.stringof ~ ");");

                arraySep = ",";

                getopt(args, config.caseSensitive, config.required, opts.expand);
            }
            catch (GetOptException err)
            {
                throw new GetOptException(format!"Missing value for argument [%s]"(
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
                                t.subcommand = subcmd;
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

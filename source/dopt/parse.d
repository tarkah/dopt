module dopt.parse;

import std.algorithm : findSplitBefore;
import std.conv : text, ConvException;
import std.exception : basicExceptionCtors;
import std.getopt : getopt, config, arraySep, GetOptException;
import std.range : empty;
import std.stdio : writeln;
import std.sumtype : isSumType, SumType, match;
import std.traits : getSymbolsByUDA, getUDAs;
import std.typecons : tuple, Nullable, nullable;
import std.uni : toLower;

import dopt.uda;
import meta = dopt.meta;

struct Help
{
    string[] path;
}

struct Error
{
    string[] path;
    string msg;
}

class HelpException : Exception
{
    ///
    mixin basicExceptionCtors;
}

class UsageException : Exception
{
    ///
    mixin basicExceptionCtors;
}

alias Result(T) = SumType!(T, Help, Error);

static T parse(T)(ref string[] args)
{
    auto result = parseArgs!(T)(args, []);

    T function(Help) onHelp = (help) {
        meta.printHelp!T(help.path);
        throw new HelpException("help printed");
    };
    T function(Error) onError = (error) {
        meta.printUsage!T(error.path, error.msg);
        throw new UsageException("usage printed");
    };

    return result.match!((T t) => t, onHelp, onError);
}

static Result!T parseArgs(T)(ref string[] args, string[] inPath)
{
    T t = T.init;

    string[] path = inPath ~ commandValue!T;

    try
    {
        // Globals
        bool help = globals!(T)(t, args);
        if (help)
        {
            return Result!T(Help(path));
        }

        // Options 
        options!(T)(t, args);

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

static bool globals(T)(ref T t, ref string[] args)
{
    if (args.length > 1)
    {
        mixin setupOptCallbacks!T;
        mixin("auto opts = " ~ genOpts!(T, true) ~ ";");

        arraySep = ",";
        auto result = getopt(args, config.caseSensitive, config.passThrough, opts.expand);

        return result.helpWanted;
    }

    return false;
}

static options(T)(ref T t, ref string[] args)
{
    if (args.length > 1)
    {
        mixin setupOptCallbacks!T;
        mixin("auto opts = " ~ genOpts!(T, false) ~ ";");

        ulong cmdPos = subcommandPosition!(T)(args);
        ulong end = cmdPos > 0 ? cmdPos : args.length;
        auto target = args[0 .. end];

        arraySep = ",";
        getopt(target, config.caseSensitive, config.noPassThrough, opts.expand);

        args = target ~ args[end .. $];
    }
}

static positionals(T)(ref T t, ref string[] args)
{
    if (args.length > 1)
    {
        static foreach (positional; getSymbolsByUDA!(T, Positional))
        {
            // TODO: Handle optional positional args, currently they are always required
            {
                // Hacky solution to support positionals w/ getopt =P
                args = [args[0]] ~ "--positional" ~ args[1 .. $];

                mixin(`auto opts = tuple("positional",` ~ `&t.` ~ positional.stringof ~ ");");

                arraySep = ",";
                getopt(args, config.caseSensitive, config.required, opts.expand);
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
                            auto mapError = (Error error) => Result!T(error).nullable;

                            return result.match!(mapSub, mapHelp, mapError);
                        }
                    }
                }
            }
        }
    }

    return Nullable!(Result!T).init;
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

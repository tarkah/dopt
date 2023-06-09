module dopt.exception;

/// Base exception for all dopt errors
class DoptException : Exception
{
    this(bool isUsage, string msg, string file = __FILE__, size_t line = __LINE__)
    {
        this.isUsage = isUsage;
        super(msg, file, line);
    }

    bool isUsage;
}

class HelpException : DoptException
{
    this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(false, msg, file, line);
    }
}

class VersionException : DoptException
{
    this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(false, msg, file, line);
    }
}

class UsageException : DoptException
{
    this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(true, msg, file, line);
    }
}

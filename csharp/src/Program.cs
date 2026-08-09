using System.Text.Json;

namespace Ytapis;

static class Program
{
    private const string Version = "1.0.0";

    static int Main(string[] args)
    {
        if (args.Length == 0)
        {
            ShowHelp();
            return 1;
        }

        var cmd = args[0];

        if (cmd == "--version" || cmd == "-v")
        {
            Console.WriteLine($"ytapis v{Version}");
            return 0;
        }

        if (cmd == "--help" || cmd == "-h")
        {
            ShowHelp();
            return 0;
        }

        try
        {
            return cmd switch
            {
                "search" => HandleSearch(args),
                "trending" => HandleTrending(args),
                "channel" => HandleChannel(args),
                "playlist" => HandlePlaylist(args),
                "video" => HandleVideo(args),
                _ =>
                {
                    Console.Error.WriteLine($"Unknown command: {cmd}");
                    ShowHelp();
                    return 1;
                }
            };
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Error: {ex.Message}");
            return 1;
        }
    }

    static int HandleSearch(string[] args)
    {
        var (queryArgs, limit) = ParseArgsWithLimit(args, 1);
        if (queryArgs.Count == 0)
        {
            Console.Error.WriteLine("Error: search query required");
            return 1;
        }

        var query = string.Join(" ", queryArgs);
        var results = Ytapis.Search(query, limit);
        Console.WriteLine(JsonSerializer.Serialize(results, new JsonSerializerOptions { WriteIndented = true }));
        return 0;
    }

    static int HandleTrending(string[] args)
    {
        var (_, limit) = ParseArgsWithLimit(args, 1);
        var results = Ytapis.SearchTrending(limit);
        Console.WriteLine(JsonSerializer.Serialize(results, new JsonSerializerOptions { WriteIndented = true }));
        return 0;
    }

    static int HandleChannel(string[] args)
    {
        var (queryArgs, limit) = ParseArgsWithLimit(args, 1);
        if (queryArgs.Count == 0)
        {
            Console.Error.WriteLine("Error: channel ID required");
            return 1;
        }

        var results = Ytapis.SearchChannel(queryArgs[0], limit);
        Console.WriteLine(JsonSerializer.Serialize(results, new JsonSerializerOptions { WriteIndented = true }));
        return 0;
    }

    static int HandlePlaylist(string[] args)
    {
        var (queryArgs, limit) = ParseArgsWithLimit(args, 1);
        if (queryArgs.Count == 0)
        {
            Console.Error.WriteLine("Error: playlist ID required");
            return 1;
        }

        var results = Ytapis.SearchPlaylist(queryArgs[0], limit);
        Console.WriteLine(JsonSerializer.Serialize(results, new JsonSerializerOptions { WriteIndented = true }));
        return 0;
    }

    static int HandleVideo(string[] args)
    {
        var (queryArgs, _) = ParseArgsWithLimit(args, 1);
        if (queryArgs.Count == 0)
        {
            Console.Error.WriteLine("Error: video ID required");
            return 1;
        }

        var result = Ytapis.GetVideo(queryArgs[0]);
        if (result is null)
        {
            Console.Error.WriteLine("Error: video not found");
            return 1;
        }

        Console.WriteLine(JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = true }));
        return 0;
    }

    static (List<string> queryParts, int limit) ParseArgsWithLimit(string[] args, int startIndex)
    {
        var queryParts = new List<string>();
        var limit = 15;

        for (var i = startIndex; i < args.Length; i++)
        {
            if ((args[i] == "--limit" || args[i] == "-l") && i + 1 < args.Length)
            {
                if (int.TryParse(args[i + 1], out var n))
                    limit = Math.Max(1, n);
                i++;
            }
            else if (args[i] == "--version" || args[i] == "-v")
            {
                Console.WriteLine($"ytapis v{Version}");
                Environment.Exit(0);
            }
            else if (args[i] == "--help" || args[i] == "-h")
            {
                ShowHelp();
                Environment.Exit(0);
            }
            else if (!args[i].StartsWith("-"))
            {
                queryParts.Add(args[i]);
            }
        }

        return (queryParts, limit);
    }

    static void ShowHelp()
    {
        Console.Error.WriteLine($@"ytapis v{Version}
  YouTube search engine — no API key required.

Usage:
  ytapis search <query> [--limit N]
  ytapis trending [--limit N]
  ytapis channel <id> [--limit N]
  ytapis playlist <id> [--limit N]
  ytapis video <id>
  ytapis --version | -v
  ytapis --help | -h

Options:
  --limit, -l  <N>   Max results (default 15)");
    }
}

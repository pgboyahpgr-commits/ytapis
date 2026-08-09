import Foundation
import Ytapis

let VERSION = "1.0.0"

func showHelp() {
    fputs("""
ytapis v\(VERSION)
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
  --limit, -l  <N>   Max results (default 15)

""", stderr)
}

func parseArgsWithLimit(_ args: [String], startIndex: Int) -> (queryParts: [String], limit: Int) {
    var queryParts = [String]()
    var limit = 15
    var i = startIndex

    while i < args.count {
        let arg = args[i]
        if (arg == "--limit" || arg == "-l") && i + 1 < args.count {
            if let n = Int(args[i + 1]) {
                limit = max(1, n)
            }
            i += 1
        } else if arg == "--version" || arg == "-v" {
            print("ytapis v\(VERSION)")
            exit(0)
        } else if arg == "--help" || arg == "-h" {
            showHelp()
            exit(0)
        } else if !arg.hasPrefix("-") {
            queryParts.append(arg)
        }
        i += 1
    }

    return (queryParts, limit)
}

func jsonEncode<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(value), let str = String(data: data, encoding: .utf8) {
        return str
    }
    return ""
}

struct Runner {
    static func run() {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            showHelp()
            exit(1)
        }

        let cmd = args[1]

        if cmd == "--version" || cmd == "-v" {
            print("ytapis v\(VERSION)")
            exit(0)
        }

        if cmd == "--help" || cmd == "-h" {
            showHelp()
            exit(0)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var exitCode: Int32 = 0

        Task {
            do {
                try await dispatchCommand(cmd, args: args)
            } catch {
                fputs("Error: \(error.localizedDescription)\n", stderr)
                exitCode = 1
            }
            semaphore.signal()
        }

        semaphore.wait()
        exit(exitCode)
    }

    static func dispatchCommand(_ cmd: String, args: [String]) async throws {
        switch cmd {
        case "search":
            let (queryParts, limit) = parseArgsWithLimit(args, startIndex: 2)
            guard !queryParts.isEmpty else {
                fputs("Error: search query required\n", stderr)
                exit(1)
            }
            let results = try await Ytapis.search(query: queryParts.joined(separator: " "), limit: limit)
            print(jsonEncode(results))

        case "trending":
            let (_, limit) = parseArgsWithLimit(args, startIndex: 2)
            let results = try await Ytapis.searchTrending(limit: limit)
            print(jsonEncode(results))

        case "channel":
            let (queryParts, limit) = parseArgsWithLimit(args, startIndex: 2)
            guard !queryParts.isEmpty else {
                fputs("Error: channel ID required\n", stderr)
                exit(1)
            }
            let results = try await Ytapis.searchChannel(queryParts[0], limit: limit)
            print(jsonEncode(results))

        case "playlist":
            let (queryParts, limit) = parseArgsWithLimit(args, startIndex: 2)
            guard !queryParts.isEmpty else {
                fputs("Error: playlist ID required\n", stderr)
                exit(1)
            }
            let results = try await Ytapis.searchPlaylist(queryParts[0], limit: limit)
            print(jsonEncode(results))

        case "video":
            let (queryParts, _) = parseArgsWithLimit(args, startIndex: 2)
            guard !queryParts.isEmpty else {
                fputs("Error: video ID required\n", stderr)
                exit(1)
            }
            let result = try await Ytapis.getVideo(id: queryParts[0])
            print(jsonEncode(result))

        default:
            fputs("Unknown command: \(cmd)\n", stderr)
            showHelp()
            exit(1)
        }
    }
}

Runner.run()

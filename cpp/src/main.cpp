#include <ytapis/ytapis.hpp>

#include <iostream>
#include <string>
#include <vector>
#include <cstdlib>
#include <nlohmann/json.hpp>

namespace {

constexpr const char* VERSION = "1.0.0";

void show_help() {
    std::cerr
        << "ytapis v" << VERSION << R"(
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
)";
}

struct ParsedArgs {
    std::vector<std::string> query_parts;
    int limit = 15;
};

ParsedArgs parse_args_with_limit(int argc, char* argv[], int start) {
    ParsedArgs result;
    for (int i = start; i < argc; ++i) {
        std::string arg = argv[i];
        if ((arg == "--limit" || arg == "-l") && i + 1 < argc) {
            int n = std::atoi(argv[i + 1]);
            result.limit = std::max(1, n);
            ++i;
        } else if (arg == "--version" || arg == "-v") {
            std::cout << "ytapis v" << VERSION << "\n";
            std::exit(0);
        } else if (arg == "--help" || arg == "-h") {
            show_help();
            std::exit(0);
        } else if (!arg.empty() && arg[0] != '-') {
            result.query_parts.push_back(arg);
        }
    }
    return result;
}

nlohmann::json results_to_json(const std::vector<ytapis::VideoResult>& results) {
    return nlohmann::json(results);
}

} // namespace

int main(int argc, char* argv[]) {
    if (argc < 2) {
        show_help();
        return 1;
    }

    std::string cmd = argv[1];

    if (cmd == "--version" || cmd == "-v") {
        std::cout << "ytapis v" << VERSION << "\n";
        return 0;
    }

    if (cmd == "--help" || cmd == "-h") {
        show_help();
        return 0;
    }

    try {
        if (cmd == "search") {
            auto parsed = parse_args_with_limit(argc, argv, 2);
            if (parsed.query_parts.empty()) {
                std::cerr << "Error: search query required\n";
                return 1;
            }
            std::string query;
            for (size_t i = 0; i < parsed.query_parts.size(); ++i) {
                if (i > 0) query += " ";
                query += parsed.query_parts[i];
            }
            auto resp = ytapis::search(query, parsed.limit);
            std::cout << results_to_json(resp.results).dump(2) << "\n";
        }
        else if (cmd == "trending") {
            auto parsed = parse_args_with_limit(argc, argv, 2);
            auto resp = ytapis::search_trending(parsed.limit);
            std::cout << results_to_json(resp.results).dump(2) << "\n";
        }
        else if (cmd == "channel") {
            auto parsed = parse_args_with_limit(argc, argv, 2);
            if (parsed.query_parts.empty()) {
                std::cerr << "Error: channel ID required\n";
                return 1;
            }
            auto resp = ytapis::search_channel(parsed.query_parts[0], parsed.limit);
            std::cout << results_to_json(resp.results).dump(2) << "\n";
        }
        else if (cmd == "playlist") {
            auto parsed = parse_args_with_limit(argc, argv, 2);
            if (parsed.query_parts.empty()) {
                std::cerr << "Error: playlist ID required\n";
                return 1;
            }
            auto resp = ytapis::search_playlist(parsed.query_parts[0], parsed.limit);
            std::cout << results_to_json(resp.results).dump(2) << "\n";
        }
        else if (cmd == "video") {
            auto parsed = parse_args_with_limit(argc, argv, 2);
            if (parsed.query_parts.empty()) {
                std::cerr << "Error: video ID required\n";
                return 1;
            }
            auto result = ytapis::get_video(parsed.query_parts[0]);
            std::cout << nlohmann::json(result).dump(2) << "\n";
        }
        else {
            std::cerr << "Unknown command: " << cmd << "\n";
            show_help();
            return 1;
        }
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 1;
    }

    return 0;
}

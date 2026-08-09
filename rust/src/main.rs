use std::env;
use std::process;

const VERSION: &str = "1.0.0";

fn show_help() {
    eprintln!(
        "ytapis v{VERSION}
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
  --limit, -l  <N>   Max results (default 15)"
    );
}

struct ParsedArgs {
    query_parts: Vec<String>,
    limit: usize,
}

fn parse_args_with_limit(args: &[String], start: usize) -> ParsedArgs {
    let mut query_parts = Vec::new();
    let mut limit: usize = 15;
    let mut i = start;

    while i < args.len() {
        match args[i].as_str() {
            "--limit" | "-l" => {
                if i + 1 < args.len() {
                    if let Ok(n) = args[i + 1].parse::<usize>() {
                        limit = n.max(1);
                    }
                    i += 1;
                }
            }
            "--version" | "-v" => {
                println!("ytapis v{VERSION}");
                process::exit(0);
            }
            "--help" | "-h" => {
                show_help();
                process::exit(0);
            }
            other => {
                if !other.starts_with('-') {
                    query_parts.push(other.to_string());
                }
            }
        }
        i += 1;
    }

    ParsedArgs {
        query_parts,
        limit,
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        show_help();
        process::exit(1);
    }

    let cmd = args[1].as_str();

    match cmd {
        "--version" | "-v" => {
            println!("ytapis v{VERSION}");
            process::exit(0);
        }
        "--help" | "-h" => {
            show_help();
            process::exit(0);
        }
        "search" => handle_search(&args),
        "trending" => handle_trending(&args),
        "channel" => handle_channel(&args),
        "playlist" => handle_playlist(&args),
        "video" => handle_video(&args),
        other => {
            eprintln!("Unknown command: {other}");
            show_help();
            process::exit(1);
        }
    }
}

fn handle_search(args: &[String]) {
    let parsed = parse_args_with_limit(args, 2);
    if parsed.query_parts.is_empty() {
        eprintln!("Error: search query required");
        process::exit(1);
    }
    let query = parsed.query_parts.join(" ");
    match ytapis::search(&query, parsed.limit) {
        Ok(resp) => println!("{}", serde_json::to_string_pretty(&resp.results).unwrap()),
        Err(e) => {
            eprintln!("Error: {e}");
            process::exit(1);
        }
    }
}

fn handle_trending(args: &[String]) {
    let parsed = parse_args_with_limit(args, 2);
    match ytapis::search_trending(parsed.limit) {
        Ok(resp) => println!("{}", serde_json::to_string_pretty(&resp.results).unwrap()),
        Err(e) => {
            eprintln!("Error: {e}");
            process::exit(1);
        }
    }
}

fn handle_channel(args: &[String]) {
    let parsed = parse_args_with_limit(args, 2);
    if parsed.query_parts.is_empty() {
        eprintln!("Error: channel ID required");
        process::exit(1);
    }
    match ytapis::search_channel(&parsed.query_parts[0], parsed.limit) {
        Ok(resp) => println!("{}", serde_json::to_string_pretty(&resp.results).unwrap()),
        Err(e) => {
            eprintln!("Error: {e}");
            process::exit(1);
        }
    }
}

fn handle_playlist(args: &[String]) {
    let parsed = parse_args_with_limit(args, 2);
    if parsed.query_parts.is_empty() {
        eprintln!("Error: playlist ID required");
        process::exit(1);
    }
    match ytapis::search_playlist(&parsed.query_parts[0], parsed.limit) {
        Ok(resp) => println!("{}", serde_json::to_string_pretty(&resp.results).unwrap()),
        Err(e) => {
            eprintln!("Error: {e}");
            process::exit(1);
        }
    }
}

fn handle_video(args: &[String]) {
    let parsed = parse_args_with_limit(args, 2);
    if parsed.query_parts.is_empty() {
        eprintln!("Error: video ID required");
        process::exit(1);
    }
    match ytapis::get_video(&parsed.query_parts[0]) {
        Ok(result) => println!("{}", serde_json::to_string_pretty(&result).unwrap()),
        Err(e) => {
            eprintln!("Error: {e}");
            process::exit(1);
        }
    }
}

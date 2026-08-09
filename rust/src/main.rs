// ytapis CLI v2.0 — geethudinoyt & geethudino (Ruthvik)
use std::env;
use std::process;

fn to_json(results: &Vec<ytapis::VideoResult>) -> String {
    serde_json::to_string_pretty(results).unwrap_or_else(|_| "[]".into())
}

fn to_json_one(v: &ytapis::VideoResult) -> String {
    serde_json::to_string_pretty(v).unwrap_or_else(|_| "{}".into())
}

fn show_help() {
    eprintln!("ytapis v2.0.0 — YouTube search engine, no API key required\n");
    eprintln!("Usage:");
    eprintln!("  ytapis search <query> [--limit N]");
    eprintln!("  ytapis trending [--limit N]");
    eprintln!("  ytapis channel <id> [--limit N]");
    eprintln!("  ytapis playlist <id> [--limit N]");
    eprintln!("  ytapis video <id>");
    eprintln!("  ytapis --version | -v");
    eprintln!("  ytapis --help | -h");
}

fn parse_limit(args: &[String]) -> usize {
    if let Some(pos) = args.iter().position(|a| a == "--limit" || a == "-l") {
        if let Some(val) = args.get(pos + 1) {
            return val.parse().unwrap_or(15);
        }
    }
    15
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 { show_help(); process::exit(1); }

    match args[1].as_str() {
        "--version" | "-v" => { println!("ytapis v2.0.0"); return; }
        "--help" | "-h" => { show_help(); return; }
        "search" => {
            let query: String = args[2..].iter()
                .filter(|a| !a.starts_with('-') && !a.parse::<u32>().is_ok())
                .cloned().collect::<Vec<_>>().join(" ");
            if query.is_empty() { eprintln!("Error: query required"); process::exit(1); }
            match ytapis::search(&query, Some(parse_limit(&args)), None, None) {
                Ok(r) => println!("{}", to_json(&r)),
                Err(e) => { eprintln!("Error: {}", e); process::exit(1); }
            }
        }
        "trending" => {
            match ytapis::search_trending(Some(parse_limit(&args))) {
                Ok(r) => println!("{}", to_json(&r)),
                Err(e) => { eprintln!("Error: {}", e); process::exit(1); }
            }
        }
        "channel" => {
            let id = args.get(2).cloned().unwrap_or_default();
            if id.is_empty() { eprintln!("Error: channel ID required"); process::exit(1); }
            match ytapis::search_channel(&id, Some(parse_limit(&args))) {
                Ok(r) => println!("{}", to_json(&r)),
                Err(e) => { eprintln!("Error: {}", e); process::exit(1); }
            }
        }
        "playlist" => {
            let id = args.get(2).cloned().unwrap_or_default();
            if id.is_empty() { eprintln!("Error: playlist ID required"); process::exit(1); }
            match ytapis::search_playlist(&id, Some(parse_limit(&args))) {
                Ok(r) => println!("{}", to_json(&r)),
                Err(e) => { eprintln!("Error: {}", e); process::exit(1); }
            }
        }
        "video" => {
            let id = args.get(2).cloned().unwrap_or_default();
            if id.is_empty() { eprintln!("Error: video ID required"); process::exit(1); }
            match ytapis::get_video(&id) {
                Ok(r) => println!("{}", to_json_one(&r)),
                Err(e) => { eprintln!("Error: {}", e); process::exit(1); }
            }
        }
        _ => { eprintln!("Unknown command: {}", args[1]); show_help(); process::exit(1); }
    }
}

//! macwand-engine: the scanning backend for the MacWand app.
//!
//! Usage:
//!   macwand-engine scan [--home PATH] [--min-large BYTES]
//!   macwand-engine sizes PATH...
//!
//! `scan` also emits `size` events for the direct children of the Library folders
//! where apps keep data, so the app can size uninstall leftovers without a second walk.
//!
//! Output is JSON lines on stdout (see `events.rs`). The engine never deletes anything.

mod categories;
mod events;
mod scanner;

use categories::{resolve_roots, CATEGORIES, DEV_ARTIFACTS};
use events::{Emitter, Event, Sink};
use rayon::prelude::*;
use scanner::{ScanOptions, Scanner, Stats};
use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

const DEFAULT_MIN_LARGE: u64 = 100 * 1024 * 1024;
const PROGRESS_INTERVAL: Duration = Duration::from_millis(120);
/// Library folders where apps keep per-app data, indexed for uninstall leftovers.
const APP_DATA_FOLDERS: &[&str] = &[
    "Library/Application Support",
    "Library/Caches",
    "Library/Containers",
    "Library/Group Containers",
    "Library/HTTPStorages",
    "Library/Logs",
    "Library/Saved Application State",
    "Library/WebKit",
];

fn main() {
    // Deep trees recurse through rayon; give workers room.
    let _ = rayon::ThreadPoolBuilder::new().stack_size(16 * 1024 * 1024).build_global();

    let args: Vec<String> = std::env::args().skip(1).collect();
    let result = match args.first().map(String::as_str) {
        Some("scan") => parse_scan(&args[1..]).map(|(home, min)| run_scan(&home, min)),
        Some("sizes") if args.len() > 1 => Ok(run_sizes(&args[1..])),
        _ => Err("usage: macwand-engine scan [--home PATH] [--min-large BYTES] | sizes PATH...".to_string()),
    };
    if let Err(message) = result {
        eprintln!("{message}");
        std::process::exit(2);
    }
}

fn parse_scan(args: &[String]) -> Result<(PathBuf, u64), String> {
    let mut home = std::env::var_os("HOME").map(PathBuf::from).ok_or("HOME is not set")?;
    let mut min_large = DEFAULT_MIN_LARGE;
    let mut it = args.iter();
    while let Some(flag) = it.next() {
        let value = it.next().ok_or(format!("{flag} needs a value"))?;
        match flag.as_str() {
            "--home" => home = PathBuf::from(value),
            "--min-large" => min_large = value.parse().map_err(|_| format!("bad --min-large: {value}"))?,
            _ => return Err(format!("unknown flag {flag}")),
        }
    }
    Ok((home, min_large))
}

/// Full scan: the home folder (large files, categories, artifacts) and installed apps.
fn run_scan(home: &Path, min_large: u64) {
    let sink = Emitter::stdout();
    for category in CATEGORIES.iter().chain([&DEV_ARTIFACTS]) {
        sink.emit(Event::Category {
            id: category.id.into(),
            name: category.name.into(),
            description: category.description.into(),
            safety: category.safety.as_str().into(),
        });
    }

    let stats = Stats::default();
    let started = Instant::now();
    let user_apps = home.join("Applications");
    let options = ScanOptions {
        min_large: Some(min_large),
        category_roots: resolve_roots(home).into_iter().collect(),
        detect_artifacts: true,
        skip: HashSet::from([user_apps.clone()]),
        indexed: APP_DATA_FOLDERS.iter().map(|f| home.join(f)).collect(),
        skip_extensions: vec!["photoslibrary"],
    };

    with_progress(&sink, &stats, || {
        rayon::join(
            || Scanner::new(options, &sink, &stats).size_of(home),
            || scan_apps(&[PathBuf::from("/Applications"), user_apps.clone()], &sink, &stats),
        );
    });

    sink.emit(Event::Done {
        files: stats.files.load(Ordering::Relaxed),
        bytes: stats.bytes.load(Ordering::Relaxed),
        errors: stats.errors.load(Ordering::Relaxed),
        elapsed_ms: started.elapsed().as_millis() as u64,
    });
    sink.flush();
}

/// Sizes each `.app` bundle found at the top of the given folders (or one level down).
fn scan_apps(folders: &[PathBuf], sink: &Emitter, stats: &Stats) {
    let bundles: Vec<PathBuf> = folders.iter().flat_map(|f| find_bundles(f, 1)).collect();
    let scanner = Scanner::new(ScanOptions::default(), sink, stats);
    bundles.par_iter().for_each(|bundle| {
        let size = scanner.size_of(bundle);
        sink.emit(Event::App { path: bundle.to_string_lossy().into_owned(), size });
    });
}

fn find_bundles(folder: &Path, depth: u8) -> Vec<PathBuf> {
    let Ok(entries) = std::fs::read_dir(folder) else { return Vec::new() };
    let mut found = Vec::new();
    for entry in entries.flatten() {
        if !entry.file_type().map(|t| t.is_dir()).unwrap_or(false) {
            continue;
        }
        let path = entry.path();
        if path.extension().is_some_and(|e| e == "app") {
            found.push(path);
        } else if depth > 0 {
            found.extend(find_bundles(&path, depth - 1));
        }
    }
    found
}

/// Sizes arbitrary paths, e.g. an app's support files.
fn run_sizes(paths: &[String]) {
    let sink = Emitter::stdout();
    let stats = Stats::default();
    let scanner = Scanner::new(ScanOptions::default(), &sink, &stats);
    paths.par_iter().for_each(|path| {
        let size = scanner.size_of(Path::new(path));
        sink.emit(Event::Size { path: path.clone(), size });
    });
    sink.flush();
}

/// Runs `work` while a side thread reports progress at a fixed interval.
fn with_progress(sink: &Emitter, stats: &Stats, work: impl FnOnce() + Send) {
    let finished = AtomicBool::new(false);
    std::thread::scope(|scope| {
        scope.spawn(|| {
            while !finished.load(Ordering::Relaxed) {
                std::thread::sleep(PROGRESS_INTERVAL);
                sink.emit(Event::Progress {
                    files: stats.files.load(Ordering::Relaxed),
                    bytes: stats.bytes.load(Ordering::Relaxed),
                    current: stats.current(),
                });
                sink.flush();
            }
        });
        work();
        finished.store(true, Ordering::Relaxed);
    });
}

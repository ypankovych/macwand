//! Parallel directory walker that sizes trees and reports cleanup findings.

use crate::categories::{artifact_kind, Category, DEV_ARTIFACTS};
use crate::events::{Event, Sink};
use rayon::prelude::*;
use std::collections::{HashMap, HashSet};
use std::fs::{self, Metadata};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;

/// What the scanner should report while it walks.
#[derive(Default)]
pub struct ScanOptions {
    /// Files at or above this many bytes produce `large_file` events.
    pub min_large: Option<u64>,
    /// Category root directories mapped to the category they belong to.
    pub category_roots: HashMap<PathBuf, &'static Category>,
    /// Whether to detect build-artifact folders such as `node_modules`.
    pub detect_artifacts: bool,
    /// Directories never entered (and never counted).
    pub skip: HashSet<PathBuf>,
    /// Folder extensions never entered, e.g. `photoslibrary`, whose contents
    /// macOS guards with a privacy prompt and which their own app manages.
    pub skip_extensions: Vec<&'static str>,
    /// Directories whose direct children get `size` events, so the app can size
    /// an uninstalled app's support files without walking them again.
    pub indexed: HashSet<PathBuf>,
}

/// Running totals, readable while a scan is in progress.
#[derive(Default)]
pub struct Stats {
    pub files: AtomicU64,
    pub bytes: AtomicU64,
    pub errors: AtomicU64,
    current: Mutex<String>,
}

impl Stats {
    /// The directory most recently entered by any worker.
    pub fn current(&self) -> String {
        self.current.lock().map(|c| c.clone()).unwrap_or_default()
    }
}

/// Walks directory trees in parallel, computing allocated sizes.
pub struct Scanner<'a> {
    options: ScanOptions,
    sink: &'a dyn Sink,
    stats: &'a Stats,
    /// (device, inode) pairs of multiply-linked files already counted.
    seen_links: Mutex<HashSet<(u64, u64)>>,
}

/// Where a directory sits relative to reported findings.
#[derive(Clone, Copy)]
struct Context {
    /// Set when the directory being walked is a category root: its children become items.
    category: Option<&'static Category>,
    /// True once inside a category root or artifact folder, so nothing is reported twice.
    claimed: bool,
    /// Set when the directory being walked is an indexed root.
    indexed: bool,
}

impl<'a> Scanner<'a> {
    /// Creates a scanner that reports to `sink` and counts into `stats`.
    pub fn new(options: ScanOptions, sink: &'a dyn Sink, stats: &'a Stats) -> Self {
        Self { options, sink, stats, seen_links: Mutex::new(HashSet::new()) }
    }

    /// Returns the allocated size of `path` (a file or a whole tree), emitting findings on the way.
    pub fn size_of(&self, path: &Path) -> u64 {
        match fs::symlink_metadata(path) {
            Ok(meta) if meta.is_dir() => self.walk(path, self.context_for(path, false)),
            Ok(meta) => self.count_file(path, &meta),
            Err(_) => {
                self.stats.errors.fetch_add(1, Ordering::Relaxed);
                0
            }
        }
    }

    fn should_skip(&self, dir: &Path) -> bool {
        self.options.skip.contains(dir)
            || dir
                .extension()
                .and_then(|e| e.to_str())
                .is_some_and(|e| self.options.skip_extensions.contains(&e))
    }

    fn context_for(&self, dir: &Path, claimed: bool) -> Context {
        let category = self.options.category_roots.get(dir).copied();
        let indexed = self.options.indexed.contains(dir);
        Context { category, claimed: claimed || category.is_some(), indexed }
    }

    fn walk(&self, dir: &Path, ctx: Context) -> u64 {
        if let Ok(mut current) = self.stats.current.try_lock() {
            current.clear();
            current.push_str(&dir.to_string_lossy());
        }
        let entries = match fs::read_dir(dir) {
            Ok(entries) => entries,
            Err(_) => {
                self.stats.errors.fetch_add(1, Ordering::Relaxed);
                return 0;
            }
        };

        let mut total = 0;
        let mut subdirs = Vec::new();
        for entry in entries.flatten() {
            let path = entry.path();
            // DirEntry::file_type comes from readdir and needs no extra syscall.
            let is_dir = entry.file_type().map(|t| t.is_dir()).unwrap_or(false);
            if is_dir {
                if !self.should_skip(&path) {
                    subdirs.push(path);
                }
                continue;
            }
            let Ok(meta) = entry.metadata() else {
                self.stats.errors.fetch_add(1, Ordering::Relaxed);
                continue;
            };
            let size = self.count_file(&path, &meta);
            if let Some(category) = ctx.category {
                self.emit_item(category, &path, size, &meta, None);
            }
            if ctx.indexed {
                self.emit_size(&path, size);
            }
            total += size;
        }

        total
            + subdirs
                .par_iter()
                .map(|sub| self.walk_child(sub, ctx))
                .sum::<u64>()
    }

    fn walk_child(&self, dir: &Path, parent: Context) -> u64 {
        let artifact = match parent.claimed || !self.options.detect_artifacts {
            true => None,
            false => artifact_kind(dir),
        };
        let mut ctx = self.context_for(dir, parent.claimed);
        ctx.claimed |= artifact.is_some();

        let size = self.walk(dir, ctx);
        let meta = fs::symlink_metadata(dir).ok();
        if let Some(category) = parent.category {
            if let Some(meta) = &meta {
                self.emit_item(category, dir, size, meta, None);
            }
        }
        if let (Some(kind), Some(meta)) = (artifact, &meta) {
            self.emit_item(&DEV_ARTIFACTS, dir, size, meta, Some(kind));
        }
        if parent.indexed {
            self.emit_size(dir, size);
        }
        size
    }

    fn emit_size(&self, path: &Path, size: u64) {
        self.sink.emit(Event::Size { path: path.to_string_lossy().into_owned(), size });
    }

    /// Counts one non-directory entry and returns its allocated size.
    fn count_file(&self, path: &Path, meta: &Metadata) -> u64 {
        if meta.nlink() > 1 && !self.first_sighting(meta) {
            return 0;
        }
        // st_blocks reflects real disk usage: sparse files and evicted iCloud files count as small.
        let size = meta.blocks() * 512;
        self.stats.files.fetch_add(1, Ordering::Relaxed);
        self.stats.bytes.fetch_add(size, Ordering::Relaxed);
        if self.options.min_large.is_some_and(|min| size >= min) {
            self.sink.emit(Event::LargeFile {
                path: path.to_string_lossy().into_owned(),
                size,
                modified: Some(meta.mtime()),
            });
        }
        size
    }

    fn first_sighting(&self, meta: &Metadata) -> bool {
        let mut seen = self.seen_links.lock().unwrap_or_else(|e| e.into_inner());
        seen.insert((meta.dev(), meta.ino()))
    }

    fn emit_item(&self, category: &Category, path: &Path, size: u64, meta: &Metadata, label: Option<&str>) {
        if size == 0 {
            return;
        }
        self.sink.emit(Event::CategoryItem {
            category: category.id.to_string(),
            path: path.to_string_lossy().into_owned(),
            size,
            modified: Some(meta.mtime()),
            label: label.map(str::to_string),
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::categories::CATEGORIES;

    #[derive(Default)]
    struct Collect(Mutex<Vec<Event>>);

    impl Sink for Collect {
        fn emit(&self, event: Event) {
            self.0.lock().unwrap().push(event);
        }
    }

    fn write(path: &Path, bytes: usize) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, vec![7u8; bytes]).unwrap();
    }

    #[test]
    fn sizes_trees_and_reports_findings() {
        let tmp = tempfile::tempdir().unwrap();
        let home = tmp.path();
        write(&home.join("big.bin"), 2 * 1024 * 1024);
        write(&home.join("Library/Caches/com.example/blob"), 64 * 1024);
        write(&home.join("code/app/node_modules/pkg/index.js"), 10_000);
        write(&home.join("code/app/node_modules/dep/node_modules/x.js"), 10_000);

        let caches = CATEGORIES.iter().find(|c| c.id == "user_caches").unwrap();
        let options = ScanOptions {
            min_large: Some(1024 * 1024),
            category_roots: HashMap::from([(home.join("Library/Caches"), caches)]),
            detect_artifacts: true,
            skip: HashSet::new(),
            skip_extensions: Vec::new(),
            indexed: HashSet::from([home.join("code")]),
        };
        let sink = Collect::default();
        let stats = Stats::default();
        let total = Scanner::new(options, &sink, &stats).size_of(home);

        assert!(total >= 2 * 1024 * 1024 + 64 * 1024 + 20_000);
        assert_eq!(stats.files.load(Ordering::Relaxed), 4);

        let events = sink.0.into_inner().unwrap();
        let large: Vec<_> = events.iter().filter(|e| matches!(e, Event::LargeFile { .. })).collect();
        assert_eq!(large.len(), 1);

        let items: Vec<_> = events
            .iter()
            .filter_map(|e| match e {
                Event::CategoryItem { category, path, .. } => Some((category.as_str(), path.as_str())),
                _ => None,
            })
            .collect();
        let cache_item = home.join("Library/Caches/com.example");
        let modules = home.join("code/app/node_modules");
        assert!(items.contains(&("user_caches", cache_item.to_str().unwrap())));
        assert!(items.contains(&("dev_artifacts", modules.to_str().unwrap())));
        // Nested node_modules are part of the outer one, not reported separately.
        assert_eq!(items.iter().filter(|(c, _)| *c == "dev_artifacts").count(), 1);

        let indexed: Vec<_> = events.iter().filter(|e| matches!(e, Event::Size { .. })).collect();
        assert_eq!(indexed.len(), 1, "only the direct child of the indexed root");
    }

    #[test]
    fn skips_protected_packages() {
        let tmp = tempfile::tempdir().unwrap();
        write(&tmp.path().join("Pictures/Photos Library.photoslibrary/originals/a.heic"), 100_000);
        write(&tmp.path().join("Pictures/keep.jpg"), 1_000);

        let options = ScanOptions { skip_extensions: vec!["photoslibrary"], ..ScanOptions::default() };
        let sink = Collect::default();
        let stats = Stats::default();
        Scanner::new(options, &sink, &stats).size_of(tmp.path());
        assert_eq!(stats.files.load(Ordering::Relaxed), 1);
    }

    #[test]
    fn counts_hard_links_once() {
        let tmp = tempfile::tempdir().unwrap();
        write(&tmp.path().join("a"), 100_000);
        fs::hard_link(tmp.path().join("a"), tmp.path().join("b")).unwrap();

        let sink = Collect::default();
        let stats = Stats::default();
        let one = fs::metadata(tmp.path().join("a")).unwrap().blocks() * 512;
        let total = Scanner::new(ScanOptions::default(), &sink, &stats).size_of(tmp.path());
        assert_eq!(total, one);
    }
}

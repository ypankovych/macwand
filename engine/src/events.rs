//! Events the engine writes to stdout, one JSON object per line.
//!
//! The SwiftUI app decodes these, so field names here are the wire protocol.

use serde::Serialize;
use std::io::{BufWriter, Stdout, Write};
use std::sync::Mutex;

/// A single message on the engine's output stream.
#[derive(Debug, Serialize, PartialEq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Event {
    /// Periodic scan progress.
    Progress { files: u64, bytes: u64, current: String },
    /// A file at or above the large-file threshold.
    LargeFile { path: String, size: u64, modified: Option<i64> },
    /// A cleanup category that has at least one item.
    Category { id: String, name: String, description: String, safety: String },
    /// One removable entry inside a cleanup category.
    CategoryItem { category: String, path: String, size: u64, modified: Option<i64>, label: Option<String> },
    /// An application bundle and its on-disk size.
    App { path: String, size: u64 },
    /// The total size of a path requested via the `sizes` command.
    Size { path: String, size: u64 },
    /// The scan finished.
    Done { files: u64, bytes: u64, errors: u64, elapsed_ms: u64 },
}

/// Destination for scan events. Implementations must be shareable across worker threads.
pub trait Sink: Sync {
    /// Records one event.
    fn emit(&self, event: Event);
}

/// Thread-safe JSON-lines writer shared by all scan workers.
pub struct Emitter {
    out: Mutex<BufWriter<Stdout>>,
}

impl Emitter {
    /// Creates an emitter that writes to the process's stdout.
    pub fn stdout() -> Self {
        Self { out: Mutex::new(BufWriter::new(std::io::stdout())) }
    }

    /// Pushes buffered events to the reader.
    pub fn flush(&self) {
        let mut out = self.out.lock().unwrap_or_else(|e| e.into_inner());
        let _ = out.flush();
    }
}

impl Sink for Emitter {
    /// Serializes and buffers one event. Write errors (closed pipe) are ignored:
    /// the app cancelling a scan simply closes the pipe.
    fn emit(&self, event: Event) {
        let mut out = self.out.lock().unwrap_or_else(|e| e.into_inner());
        if serde_json::to_writer(&mut *out, &event).is_ok() {
            let _ = out.write_all(b"\n");
        }
    }
}

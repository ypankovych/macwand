//! Known cleanup locations and developer build-artifact detection.

use std::path::{Path, PathBuf};

/// How careful the user should be before removing items in a category.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Safety {
    /// Regenerated automatically by apps or tools.
    Safe,
    /// May hold something the user wants to keep.
    Review,
}

impl Safety {
    /// Wire name used in `category` events.
    pub fn as_str(self) -> &'static str {
        match self {
            Safety::Safe => "safe",
            Safety::Review => "review",
        }
    }
}

/// A cleanup category whose removable items are the direct children of its roots.
#[derive(Debug, Clone)]
pub struct Category {
    pub id: &'static str,
    pub name: &'static str,
    pub description: &'static str,
    pub safety: Safety,
    /// Root directories, relative to the home folder.
    pub roots: &'static [&'static str],
}

/// Id of the synthetic category that collects detected build artifacts.
pub const DEV_ARTIFACTS: Category = Category {
    id: "dev_artifacts",
    name: "Build Artifacts",
    description: "node_modules, Rust targets, Python virtualenvs and similar folders that rebuild from source.",
    safety: Safety::Safe,
    roots: &[],
};

/// All root-based categories. Roots must not nest inside each other.
pub const CATEGORIES: &[Category] = &[
    Category {
        id: "user_caches",
        name: "App Caches",
        description: "Per-app caches in ~/Library/Caches. Apps rebuild them as needed.",
        safety: Safety::Safe,
        roots: &["Library/Caches"],
    },
    Category {
        id: "logs",
        name: "Logs",
        description: "Application and diagnostic logs.",
        safety: Safety::Safe,
        roots: &["Library/Logs"],
    },
    Category {
        id: "xcode",
        name: "Xcode Data",
        description: "DerivedData, old device support files and simulator caches.",
        safety: Safety::Safe,
        roots: &[
            "Library/Developer/Xcode/DerivedData",
            "Library/Developer/Xcode/iOS DeviceSupport",
            "Library/Developer/Xcode/watchOS DeviceSupport",
            "Library/Developer/CoreSimulator/Caches",
        ],
    },
    Category {
        id: "xcode_archives",
        name: "Xcode Archives",
        description: "Archived builds. Keep the ones you need for crash symbolication.",
        safety: Safety::Review,
        roots: &["Library/Developer/Xcode/Archives"],
    },
    Category {
        id: "simulators",
        name: "Simulator Devices",
        description: "iOS/watchOS simulator devices and their data.",
        safety: Safety::Review,
        roots: &["Library/Developer/CoreSimulator/Devices"],
    },
    Category {
        id: "package_caches",
        name: "Package Caches",
        description: "npm, pnpm, Cargo, Gradle, Maven, Go and pip/uv download caches.",
        safety: Safety::Safe,
        roots: &[
            ".npm/_cacache",
            ".pnpm-store",
            "Library/pnpm/store",
            ".cargo/registry",
            ".gradle/caches",
            ".m2/repository",
            "go/pkg/mod",
            ".cache",
        ],
    },
    Category {
        id: "ios_backups",
        name: "iPhone & iPad Backups",
        description: "Local device backups made by Finder.",
        safety: Safety::Review,
        roots: &["Library/Application Support/MobileSync/Backup"],
    },
    Category {
        id: "mail_downloads",
        name: "Mail Attachments",
        description: "Attachments Mail saved when you opened them.",
        safety: Safety::Safe,
        roots: &["Library/Containers/com.apple.mail/Data/Library/Mail Downloads"],
    },
    Category {
        id: "downloads",
        name: "Downloads",
        description: "Everything in your Downloads folder.",
        safety: Safety::Review,
        roots: &["Downloads"],
    },
    Category {
        id: "trash",
        name: "Trash",
        description: "Items already in the Trash. Removing them deletes them permanently.",
        safety: Safety::Safe,
        roots: &[".Trash"],
    },
];

/// Resolves category roots against a home folder.
pub fn resolve_roots(home: &Path) -> Vec<(PathBuf, &'static Category)> {
    CATEGORIES
        .iter()
        .flat_map(|c| c.roots.iter().map(move |r| (home.join(r), c)))
        .collect()
}

/// Returns a human label if `dir` is a build-artifact folder that can be regenerated.
pub fn artifact_kind(dir: &Path) -> Option<&'static str> {
    let name = dir.file_name()?.to_str()?;
    let parent = dir.parent()?;
    match name {
        "node_modules" => Some("node_modules"),
        "target" if parent.join("Cargo.toml").exists() => Some("Rust target"),
        ".venv" | "venv" if dir.join("pyvenv.cfg").exists() => Some("Python virtualenv"),
        "Pods" if parent.join("Podfile").exists() => Some("CocoaPods"),
        ".next" if parent.join("package.json").exists() => Some("Next.js build"),
        ".gradle" if parent.join("settings.gradle").exists() || parent.join("settings.gradle.kts").exists() => {
            Some("Gradle project cache")
        }
        ".terraform" => Some("Terraform providers"),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn detects_artifacts_only_with_markers() {
        let tmp = tempfile::tempdir().unwrap();
        let proj = tmp.path().join("proj");
        fs::create_dir_all(proj.join("target")).unwrap();
        fs::create_dir_all(proj.join("node_modules")).unwrap();
        assert_eq!(artifact_kind(&proj.join("target")), None);
        assert_eq!(artifact_kind(&proj.join("node_modules")), Some("node_modules"));

        fs::write(proj.join("Cargo.toml"), "").unwrap();
        assert_eq!(artifact_kind(&proj.join("target")), Some("Rust target"));
    }

    #[test]
    fn category_roots_do_not_nest() {
        let roots = resolve_roots(Path::new("/h"));
        for (a, _) in &roots {
            for (b, _) in &roots {
                assert!(a == b || !b.starts_with(a), "{a:?} contains {b:?}");
            }
        }
    }
}

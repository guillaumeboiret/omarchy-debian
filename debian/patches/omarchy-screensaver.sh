# Lock-after-screensaver without a flash of the desktop (Debian port, idle.lockAfterScreensaver).
# With OMARCHY_SCREENSAVER_HOLD=1, input no longer closes the screensaver at once: it stays up so
# the shell can raise the session lock over it first, then the shell kills it. Failsafe: it closes
# by itself 5 s after the first input, so a shell that never locks can't leave you stuck.
f=$(echo omarchy-screensaver-*/src/wayland.rs)
expect "$f" '^    exit: bool,$'
expect "$f" '^        exit: false,$'
expect "$f" '    fn request_dismiss(&mut self) {'
expect "$f" 'if self.terminated.load(Ordering::Relaxed) {'
sed -i 's/^    exit: bool,$/    exit: bool,\n    dismiss_at: Option<Instant>,/' "$f"
sed -i 's/^        exit: false,$/        exit: false,\n        dismiss_at: None,/' "$f"
perl -0pi -e 's/    fn request_dismiss\(&mut self\) \{\n        self\.exit = true;\n    \}/    fn request_dismiss(&mut self) {\n        if std::env::var_os("OMARCHY_SCREENSAVER_HOLD").is_some() {\n            if self.dismiss_at.is_none() {\n                self.dismiss_at = Some(Instant::now() + Duration::from_secs(5));\n            }\n            return;\n        }\n        self.exit = true;\n    }/' "$f"
perl -0pi -e 's/(    fn tick\(&mut self, qh: &QueueHandle<Self>\) \{\n        let now = Instant::now\(\);\n)        if self\.terminated\.load\(Ordering::Relaxed\) \{\n            self\.request_dismiss\(\);/$1        if self.dismiss_at.is_some_and(|deadline| now >= deadline) {\n            self.exit = true;\n            return;\n        }\n        if self.terminated.load(Ordering::Relaxed) {\n            self.exit = true;/' "$f"
expect "$f" 'OMARCHY_SCREENSAVER_HOLD'
expect "$f" 'dismiss_at.is_some_and'

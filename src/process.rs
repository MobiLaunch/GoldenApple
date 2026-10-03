//! Spawning child processes (builds, apps) and streaming their output back
//! onto the GTK main loop.

use std::cell::RefCell;
use std::io::{Read, Write};
use std::os::unix::process::CommandExt;
use std::process::{ChildStdin, Command, Stdio};
use std::rc::Rc;

use gtk::glib;

#[derive(Debug, Clone)]
pub enum ProcEvent {
    Stdout(String),
    Stderr(String),
    /// Exit code, or `None` when the process was killed by a signal.
    Exit(Option<i32>),
}

/// Handle to a running child process. The child runs in its own process
/// group so that terminating it also stops anything it spawned (e.g. the
/// compiler jobs started by `swift build`).
pub struct RunningProcess {
    pid: i32,
    stdin: RefCell<Option<ChildStdin>>,
    finished: Rc<RefCell<bool>>,
}

impl RunningProcess {
    pub fn spawn(
        mut cmd: Command,
        on_event: impl Fn(ProcEvent) + 'static,
    ) -> std::io::Result<Rc<Self>> {
        cmd.stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .process_group(0);
        let mut child = cmd.spawn()?;
        let pid = child.id() as i32;
        let stdout = child.stdout.take().expect("piped stdout");
        let stderr = child.stderr.take().expect("piped stderr");
        let stdin = child.stdin.take();

        let (tx, rx) = async_channel::unbounded::<ProcEvent>();

        let out_reader = spawn_reader(stdout, tx.clone(), ProcEvent::Stdout);
        let err_reader = spawn_reader(stderr, tx.clone(), ProcEvent::Stderr);
        std::thread::spawn(move || {
            let _ = out_reader.join();
            let _ = err_reader.join();
            let code = child.wait().ok().and_then(|s| s.code());
            let _ = tx.send_blocking(ProcEvent::Exit(code));
        });

        let finished = Rc::new(RefCell::new(false));
        let proc = Rc::new(Self { pid, stdin: RefCell::new(stdin), finished: finished.clone() });
        glib::spawn_future_local(async move {
            while let Ok(ev) = rx.recv().await {
                if matches!(ev, ProcEvent::Exit(_)) {
                    *finished.borrow_mut() = true;
                }
                on_event(ev);
            }
        });
        Ok(proc)
    }

    pub fn is_running(&self) -> bool {
        !*self.finished.borrow()
    }

    /// Politely ask the process group to stop, then force it after a grace period.
    pub fn terminate(&self) {
        if !self.is_running() {
            return;
        }
        unsafe {
            libc::kill(-self.pid, libc::SIGTERM);
        }
        let pid = self.pid;
        let finished = self.finished.clone();
        glib::timeout_add_local_once(std::time::Duration::from_millis(1500), move || {
            if !*finished.borrow() {
                unsafe {
                    libc::kill(-pid, libc::SIGKILL);
                }
            }
        });
    }

    pub fn write_stdin(&self, text: &str) {
        if let Some(stdin) = self.stdin.borrow_mut().as_mut() {
            let _ = stdin.write_all(text.as_bytes());
            let _ = stdin.flush();
        }
    }
}

fn spawn_reader(
    mut source: impl Read + Send + 'static,
    tx: async_channel::Sender<ProcEvent>,
    wrap: fn(String) -> ProcEvent,
) -> std::thread::JoinHandle<()> {
    std::thread::spawn(move || {
        let mut buf = [0u8; 8192];
        // Bytes of an incomplete UTF-8 sequence carried over to the next read.
        let mut carry: Vec<u8> = Vec::new();
        loop {
            match source.read(&mut buf) {
                Ok(0) | Err(_) => break,
                Ok(n) => {
                    carry.extend_from_slice(&buf[..n]);
                    let valid = match std::str::from_utf8(&carry) {
                        Ok(_) => carry.len(),
                        Err(e) if e.error_len().is_none() => e.valid_up_to(),
                        Err(_) => carry.len(),
                    };
                    let text = String::from_utf8_lossy(&carry[..valid]).into_owned();
                    carry.drain(..valid);
                    if !text.is_empty() && tx.send_blocking(wrap(text)).is_err() {
                        break;
                    }
                }
            }
        }
        if !carry.is_empty() {
            let _ = tx.send_blocking(wrap(String::from_utf8_lossy(&carry).into_owned()));
        }
    })
}

/// Splits a stream of text chunks into complete lines.
#[derive(Default)]
pub struct LineBuffer {
    pending: String,
}

impl LineBuffer {
    pub fn push(&mut self, chunk: &str) -> Vec<String> {
        self.pending.push_str(chunk);
        let mut lines = Vec::new();
        while let Some(idx) = self.pending.find('\n') {
            let line: String = self.pending.drain(..=idx).collect();
            lines.push(line.trim_end_matches(['\n', '\r']).to_string());
        }
        lines
    }

    pub fn flush(&mut self) -> Option<String> {
        if self.pending.is_empty() {
            None
        } else {
            Some(std::mem::take(&mut self.pending))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::LineBuffer;

    #[test]
    fn splits_lines_across_chunks() {
        let mut b = LineBuffer::default();
        assert_eq!(b.push("hel"), Vec::<String>::new());
        assert_eq!(b.push("lo\nwor"), vec!["hello"]);
        assert_eq!(b.push("ld\r\n\n"), vec!["world", ""]);
        assert_eq!(b.flush(), None);
        b.push("tail");
        assert_eq!(b.flush().as_deref(), Some("tail"));
    }
}

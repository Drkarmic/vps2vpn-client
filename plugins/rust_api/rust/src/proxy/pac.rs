use std::io::{ErrorKind, Read, Write};
use std::net::{Ipv4Addr, SocketAddr, TcpListener, TcpStream};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use super::PAC_PATH;

const MAX_REQUEST_BYTES: usize = 16 * 1024;
const MAX_CONCURRENT_HANDLERS: usize = 16;
const ACCEPT_ERROR_BACKOFF: Duration = Duration::from_millis(50);
const REQUEST_TIMEOUT: Duration = Duration::from_secs(5);

#[derive(Default)]
struct Script {
    text: String,
    revision: u64,
}

impl Script {
    fn update(&mut self, text: String) -> u64 {
        if self.text != text {
            self.text = text;
            self.revision = self.revision.wrapping_add(1);
        }
        self.revision
    }
}

static SCRIPT: Mutex<Script> = Mutex::new(Script {
    text: String::new(),
    revision: 0,
});

static ACTIVE_HANDLERS: AtomicUsize = AtomicUsize::new(0);

struct HandlerGuard;

impl HandlerGuard {
    fn try_acquire() -> Option<Self> {
        let mut current = ACTIVE_HANDLERS.load(Ordering::Acquire);
        loop {
            if current >= MAX_CONCURRENT_HANDLERS {
                return None;
            }
            match ACTIVE_HANDLERS.compare_exchange_weak(
                current,
                current + 1,
                Ordering::AcqRel,
                Ordering::Acquire,
            ) {
                Ok(_) => return Some(Self),
                Err(actual) => current = actual,
            }
        }
    }
}

impl Drop for HandlerGuard {
    fn drop(&mut self) {
        ACTIVE_HANDLERS.fetch_sub(1, Ordering::Release);
    }
}

/// Serves `script` and returns its URL. The listener stays up for the life of
/// the process; a changed script gets a fresh query to invalidate URL caches.
pub fn serve(script: String) -> Option<String> {
    let revision = SCRIPT
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .update(script);
    let address = listener_address()?;
    Some(format!("http://{address}{PAC_PATH}?v={revision}"))
}

fn listener_address() -> Option<SocketAddr> {
    static ADDRESS: Mutex<Option<SocketAddr>> = Mutex::new(None);
    let mut guard = ADDRESS
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if let Some(address) = *guard {
        return Some(address);
    }
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).ok()?;
    let address = listener.local_addr().ok()?;
    std::thread::Builder::new()
        .name("system-proxy-pac".into())
        .spawn(move || accept(listener))
        .ok()?;
    *guard = Some(address);
    Some(address)
}

fn accept(listener: TcpListener) {
    for incoming in listener.incoming() {
        match incoming {
            Ok(stream) => {
                let Some(guard) = HandlerGuard::try_acquire() else {
                    drop(stream);
                    continue;
                };
                let _ = std::thread::Builder::new()
                    .name("system-proxy-pac-request".into())
                    .spawn(move || {
                        let _guard = guard;
                        respond(stream);
                    });
            }
            Err(_) => {
                std::thread::sleep(ACCEPT_ERROR_BACKOFF);
            }
        }
    }
}

fn respond(mut stream: TcpStream) {
    let _ = stream.set_write_timeout(Some(REQUEST_TIMEOUT));
    let Some(head) = read_head(&mut stream) else {
        return;
    };
    let script = SCRIPT
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .text
        .clone();
    let _ = stream.write_all(&response(&head, &script));
}

fn read_head(stream: &mut TcpStream) -> Option<String> {
    let deadline = Instant::now() + REQUEST_TIMEOUT;
    let mut head = Vec::new();
    let mut buffer = [0u8; 1024];
    let mut scan_from = 0usize;
    loop {
        let remaining = deadline.checked_duration_since(Instant::now())?;
        if remaining.is_zero() {
            return None;
        }
        stream.set_read_timeout(Some(remaining)).ok()?;
        let read = match stream.read(&mut buffer) {
            Ok(0) => return None,
            Ok(n) => n,
            Err(error) if error.kind() == ErrorKind::Interrupted => continue,
            Err(_) => return None,
        };
        if head.len() + read > MAX_REQUEST_BYTES {
            return None;
        }
        head.extend_from_slice(&buffer[..read]);
        if let Some(pos) = head[scan_from..]
            .windows(4)
            .position(|window| window == b"\r\n\r\n")
        {
            head.truncate(scan_from + pos + 4);
            return Some(String::from_utf8_lossy(&head).into_owned());
        }
        scan_from = head.len().saturating_sub(3);
    }
}

fn is_loopback_host(value: &str) -> bool {
    let value = value.trim();
    if value == "127.0.0.1" {
        return true;
    }
    match value.strip_prefix("127.0.0.1:") {
        Some(port) => {
            !port.is_empty()
                && port.bytes().all(|b| b.is_ascii_digit())
                && port.parse::<u16>().is_ok()
        }
        None => false,
    }
}

fn normalize_target_path(target: &str) -> Option<&str> {
    // `get` instead of `[..7]`: byte 7 of a non-ASCII target can fall inside a
    // character, and slicing there panics, which aborts a release build.
    let path = if target.get(..7).is_some_and(|s| s.eq_ignore_ascii_case("http://")) {
        let rest = &target[7..];
        let (authority, path_and_query) = match rest.find(['/', '?']) {
            Some(index) => (&rest[..index], &rest[index..]),
            None => (rest, "/"),
        };
        if !is_loopback_host(authority) {
            return None;
        }
        path_and_query
    } else {
        target
    };
    Some(path.split_once('?').map_or(path, |(path, _)| path))
}

fn is_forbidden_request(head: &str) -> bool {
    let mut host_seen = false;
    for line in head.lines().skip(1) {
        if line.is_empty() {
            break;
        }
        let Some((name, value)) = line.split_once(':') else {
            continue;
        };
        let name = name.trim();
        let value = value.trim();
        if name.eq_ignore_ascii_case("host") {
            if host_seen || !is_loopback_host(value) {
                return true;
            }
            host_seen = true;
        } else if name.eq_ignore_ascii_case("origin") {
            return true;
        } else if name.eq_ignore_ascii_case("sec-fetch-site")
            && value.eq_ignore_ascii_case("cross-site")
        {
            return true;
        } else if name.eq_ignore_ascii_case("sec-fetch-dest")
            && value.eq_ignore_ascii_case("script")
        {
            return true;
        }
    }
    false
}

fn response(head: &str, script: &str) -> Vec<u8> {
    let mut parts = head.lines().next().unwrap_or_default().split(' ');
    let method = parts.next().unwrap_or_default();
    let target = parts.next().unwrap_or_default();
    let (status, extra_headers, body) = if is_forbidden_request(head) {
        ("403 Forbidden", "", "")
    } else {
        match normalize_target_path(target) {
            None => ("403 Forbidden", "", ""),
            Some(path) => match method {
                "GET" | "HEAD" if path == PAC_PATH && !script.is_empty() => ("200 OK", "", script),
                "GET" | "HEAD" => ("404 Not Found", "", ""),
                _ => ("405 Method Not Allowed", "Allow: GET, HEAD\r\n", ""),
            },
        }
    };
    let mut response = format!(
        "HTTP/1.1 {status}\r\n\
         Content-Type: application/x-ns-proxy-autoconfig\r\n\
         X-Content-Type-Options: nosniff\r\n\
         {extra_headers}\
         Content-Length: {}\r\n\
         Cache-Control: no-store\r\n\
         Connection: close\r\n\r\n",
        body.len()
    )
    .into_bytes();
    if method != "HEAD" {
        response.extend_from_slice(body.as_bytes());
    }
    response
}

#[cfg(test)]
mod tests {
    use super::*;

    fn text(bytes: Vec<u8>) -> String {
        String::from_utf8(bytes).unwrap()
    }

    #[test]
    fn unchanged_script_keeps_its_cache_key() {
        let mut script = Script::default();
        let first = script.update("one".into());
        assert_eq!(script.update("one".into()), first);
        assert_ne!(script.update("two".into()), first);
        assert_eq!(script.text, "two");
    }

    #[test]
    fn serves_the_script_at_its_path_whatever_the_query() {
        let reply = text(response(
            "GET /flclash.pac?v=3 HTTP/1.1\r\n",
            "function x() {}",
        ));
        assert!(reply.starts_with("HTTP/1.1 200 OK\r\n"));
        assert!(reply.contains("X-Content-Type-Options: nosniff\r\n"));
        assert!(reply.contains("Content-Length: 15\r\n"));
        assert!(reply.ends_with("\r\n\r\nfunction x() {}"));
    }

    #[test]
    fn non_ascii_target_is_refused_without_a_panic() {
        // byte 7 falls inside the second "é": slicing there used to panic
        assert_eq!(normalize_target_path("/aaaaaéé"), Some("/aaaaaéé"));
        assert_eq!(normalize_target_path("ééééé"), Some("ééééé"));
        let reply = text(response("GET /aaaaaéé HTTP/1.1\r\n\r\n", "function x() {}"));
        assert!(!reply.starts_with("HTTP/1.1 200 OK\r\n"));
    }

    #[test]
    fn normalizes_absolute_form_request_target() {
        let reply = text(response(
            "GET http://127.0.0.1:12345/flclash.pac?v=1 HTTP/1.1\r\nHost: 127.0.0.1:12345\r\n\r\n",
            "function x() {}",
        ));
        assert!(reply.starts_with("HTTP/1.1 200 OK\r\n"));
        assert!(reply.ends_with("\r\n\r\nfunction x() {}"));

        let evil = text(response(
            "GET http://evil.test/flclash.pac HTTP/1.1\r\n\r\n",
            "function x() {}",
        ));
        assert!(evil.starts_with("HTTP/1.1 403 Forbidden\r\n"));
    }

    #[test]
    fn answers_head_without_a_body() {
        let reply = text(response("HEAD /flclash.pac HTTP/1.1\r\n", "abc"));
        assert!(reply.contains("Content-Length: 3\r\n"));
        assert!(reply.ends_with("\r\n\r\n"));
    }

    #[test]
    fn refuses_other_paths_methods_and_an_unset_script() {
        assert!(text(response("GET / HTTP/1.1\r\n", "abc")).starts_with("HTTP/1.1 404"));
        assert!(text(response("GET /flclash.pac HTTP/1.1\r\n", "")).starts_with("HTTP/1.1 404"));
        let post = text(response("POST /flclash.pac HTTP/1.1\r\n", "abc"));
        assert!(post.starts_with("HTTP/1.1 405"));
        assert!(post.contains("Allow: GET, HEAD\r\n"));
    }

    #[test]
    fn refuses_rebound_hosts_and_browser_xssi_requests() {
        for request in [
            "GET /flclash.pac HTTP/1.1\r\nHost: evil.test:8080\r\n\r\n",
            "GET /flclash.pac HTTP/1.1\r\nHost: 127.0.0.1.evil.test\r\n\r\n",
            "GET /flclash.pac HTTP/1.1\r\nHost: 127.0.0.1:99999\r\n\r\n",
            "GET /flclash.pac HTTP/1.1\r\nHost: 127.0.0.1\r\nHost: 127.0.0.1\r\n\r\n",
            "GET /flclash.pac HTTP/1.1\r\nHost: 127.0.0.1:8080\r\nOrigin: https://evil.test\r\n\r\n",
            "GET /flclash.pac HTTP/1.1\r\nHost: 127.0.0.1:8080\r\nOrigin: null\r\n\r\n",
            "GET /flclash.pac HTTP/1.1\r\nHost: 127.0.0.1:8080\r\nSec-Fetch-Site: cross-site\r\n\r\n",
            "GET /flclash.pac HTTP/1.1\r\nHost: 127.0.0.1:8080\r\nSec-Fetch-Dest: script\r\n\r\n",
        ] {
            let reply = text(response(request, "function x() {}"));
            assert!(
                reply.starts_with("HTTP/1.1 403 Forbidden\r\n"),
                "expected 403 for {request:?}, got {reply:?}"
            );
            assert!(reply.ends_with("\r\n\r\n"));
        }
    }

    #[test]
    fn serves_the_latest_script_over_loopback() {
        let first = serve("first".into()).unwrap();
        let second = serve("second".into()).unwrap();
        assert_ne!(first, second);
        let address = second
            .strip_prefix("http://")
            .and_then(|rest| rest.split_once('/'))
            .map(|(address, _)| address.to_owned())
            .unwrap();
        let mut stream = TcpStream::connect(&address).unwrap();
        stream
            .write_all(format!("GET /flclash.pac HTTP/1.1\r\nHost: {address}\r\n\r\n").as_bytes())
            .unwrap();
        let mut reply = String::new();
        stream.read_to_string(&mut reply).unwrap();
        assert!(reply.ends_with("\r\n\r\nsecond"));
    }
}

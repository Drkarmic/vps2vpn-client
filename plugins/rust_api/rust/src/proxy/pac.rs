use std::io::{Read, Write};
use std::net::{Ipv4Addr, SocketAddr, TcpListener, TcpStream};
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

use super::PAC_PATH;

const MAX_REQUEST_BYTES: usize = 16 * 1024;

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

/// Serves `script` and returns its URL. The listener stays up for the life of
/// the process; a changed script gets a fresh query to invalidate URL caches.
pub fn serve(script: String) -> Option<String> {
    let revision = SCRIPT
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .update(script);
    let address = (*listener_address())?;
    Some(format!("http://{address}{PAC_PATH}?v={revision}"))
}

fn listener_address() -> &'static Option<SocketAddr> {
    static ADDRESS: OnceLock<Option<SocketAddr>> = OnceLock::new();
    ADDRESS.get_or_init(|| {
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).ok()?;
        let address = listener.local_addr().ok()?;
        std::thread::Builder::new()
            .name("system-proxy-pac".into())
            .spawn(move || accept(listener))
            .ok()?;
        Some(address)
    })
}

fn accept(listener: TcpListener) {
    for stream in listener.incoming().flatten() {
        let _ = std::thread::Builder::new()
            .name("system-proxy-pac-request".into())
            .spawn(move || respond(stream));
    }
}

fn respond(mut stream: TcpStream) {
    let _ = stream.set_read_timeout(Some(Duration::from_secs(5)));
    let _ = stream.set_write_timeout(Some(Duration::from_secs(5)));
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
    let mut head = Vec::new();
    let mut buffer = [0; 1024];
    while !head.windows(4).any(|window| window == b"\r\n\r\n") {
        let read = stream.read(&mut buffer).ok()?;
        if read == 0 || head.len() + read > MAX_REQUEST_BYTES {
            return None;
        }
        head.extend_from_slice(&buffer[..read]);
    }
    Some(String::from_utf8_lossy(&head).into_owned())
}

fn response(head: &str, script: &str) -> Vec<u8> {
    let mut parts = head.lines().next().unwrap_or_default().split(' ');
    let method = parts.next().unwrap_or_default();
    let path = parts.next().unwrap_or_default();
    let path = path.split_once('?').map_or(path, |(path, _)| path);
    let (status, body) = match method {
        "GET" | "HEAD" if path == PAC_PATH && !script.is_empty() => ("200 OK", script),
        "GET" | "HEAD" => ("404 Not Found", ""),
        _ => ("405 Method Not Allowed", ""),
    };
    let mut response = format!(
        "HTTP/1.1 {status}\r\n\
         Content-Type: application/x-ns-proxy-autoconfig\r\n\
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
        assert!(reply.contains("Content-Length: 15\r\n"));
        assert!(reply.ends_with("\r\n\r\nfunction x() {}"));
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
        assert!(text(response("POST /flclash.pac HTTP/1.1\r\n", "abc")).starts_with("HTTP/1.1 405"));
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
        let mut stream = TcpStream::connect(address).unwrap();
        stream
            .write_all(b"GET /flclash.pac HTTP/1.1\r\nHost: x\r\n\r\n")
            .unwrap();
        let mut reply = String::new();
        stream.read_to_string(&mut reply).unwrap();
        assert!(reply.ends_with("\r\n\r\nsecond"));
    }
}

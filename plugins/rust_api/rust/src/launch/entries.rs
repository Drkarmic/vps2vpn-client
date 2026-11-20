pub const RUN_KEY: &str = r"Software\Microsoft\Windows\CurrentVersion\Run";
pub const STARTUP_APPROVED_KEY: &str =
    r"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";

pub const STARTUP_APPROVED_ENABLED: [u8; 12] = [2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

fn is_valid_executable(executable: &str) -> bool {
    !executable.is_empty() && !executable.contains(['"', '\0'])
}

fn is_valid_scheme(scheme: &str) -> bool {
    let mut bytes = scheme.bytes();
    let Some(first) = bytes.next() else {
        return false;
    };
    first.is_ascii_alphabetic()
        && bytes.all(|b| b.is_ascii_alphanumeric() || matches!(b, b'+' | b'-' | b'.'))
}

pub fn run_value(executable: &str) -> Option<String> {
    is_valid_executable(executable).then(|| format!("\"{executable}\""))
}

pub fn matches_run_value(stored: &str, executable: &str) -> bool {
    let Some(quoted) = run_value(executable) else {
        return false;
    };
    stored == quoted || stored == executable
}

/// Task Manager disables a Run entry with an odd first byte.
pub fn startup_approved(value: Option<&[u8]>) -> bool {
    value
        .and_then(|bytes| bytes.first())
        .is_none_or(|first| first % 2 == 0)
}

pub fn url_protocol_key(scheme: &str) -> Option<String> {
    is_valid_scheme(scheme).then(|| format!(r"Software\Classes\{scheme}"))
}

pub const URL_COMMAND_KEY: &str = r"shell\open\command";
pub const URL_PROTOCOL_VALUE: &str = "URL Protocol";

pub fn url_command(executable: &str) -> Option<String> {
    is_valid_executable(executable).then(|| format!(r#""{executable}" "%1""#))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_untouched_or_even_entry_is_approved() {
        assert!(startup_approved(None));
        assert!(startup_approved(Some(&[])));
        assert!(startup_approved(Some(&STARTUP_APPROVED_ENABLED)));
        assert!(startup_approved(Some(&[6, 1])));
    }

    #[test]
    fn an_odd_first_byte_is_disabled_in_task_manager() {
        assert!(!startup_approved(Some(&[3, 0, 0, 0])));
    }

    #[test]
    fn writes_the_url_protocol_keys_and_validates_scheme_and_executable() {
        assert_eq!(
            url_protocol_key("flclash").as_deref(),
            Some(r"Software\Classes\flclash")
        );
        assert_eq!(
            url_protocol_key("my-app+1.0").as_deref(),
            Some(r"Software\Classes\my-app+1.0")
        );
        for bad_scheme in ["", "1app", r"..\evil", "a/b", "a b", "a\0b"] {
            assert!(url_protocol_key(bad_scheme).is_none(), "{bad_scheme:?}");
        }
        assert_eq!(
            url_command(r"C:\Program Files\FlClash\FlClash.exe").as_deref(),
            Some(r#""C:\Program Files\FlClash\FlClash.exe" "%1""#),
        );
        for bad_exec in ["", "C:\\bad\"path.exe", "C:\\bad\0path.exe"] {
            assert!(url_command(bad_exec).is_none(), "{bad_exec:?}");
            assert!(run_value(bad_exec).is_none(), "{bad_exec:?}");
            assert!(!matches_run_value(bad_exec, bad_exec));
        }
    }

    #[test]
    fn the_run_value_is_quoted_and_matches_legacy_unquoted_entries() {
        let exe = r"C:\Program Files\FlClash\FlClash.exe";
        let quoted = run_value(exe).unwrap();
        assert_eq!(quoted, r#""C:\Program Files\FlClash\FlClash.exe""#);
        assert!(matches_run_value(&quoted, exe));
        assert!(matches_run_value(exe, exe));
        assert!(!matches_run_value(r"C:\Other\App.exe", exe));
    }
}

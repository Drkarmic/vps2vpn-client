fn main() {
    // The Helper runs as SYSTEM: let the loader resolve its imported DLLs from
    // System32 only, never from the install directory (DLL planting).
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows")
        && std::env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("msvc")
    {
        println!("cargo:rustc-link-arg-bins=/DEPENDENTLOADFLAG:0x800");
    }
    let core_sha256 = std::env::var("CORE_SHA256").unwrap_or_default();
    let core_name = std::env::var("CORE_NAME").unwrap_or_else(|_| "vps2vpnCore.exe".to_string());
    println!("cargo:rustc-env=CORE_SHA256={}", core_sha256);
    println!("cargo:rustc-env=CORE_NAME={}", core_name);
    println!("cargo:rerun-if-env-changed=CORE_SHA256");
    println!("cargo:rerun-if-env-changed=CORE_NAME");
}

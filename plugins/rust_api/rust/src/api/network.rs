use crate::frb_generated::StreamSink;
use flutter_rust_bridge::for_generated::SseCodec;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NetworkState {
    pub wifi: bool,
    pub vpn: bool,
    /// What the default route runs through, in a form only compared with
    /// itself; empty with no default route, or where it is not read (macOS).
    pub default_interface: String,
    /// The report follows a wake from sleep.
    pub resumed: bool,
}

pub fn network_changes(sink: StreamSink<NetworkState, SseCodec>) {
    crate::network::listen(sink)
}

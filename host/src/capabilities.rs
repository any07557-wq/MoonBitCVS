use anyhow::{Result, ensure};

pub const AVAILABLE: [&str; 4] = [
    "staged_content.list",
    "staged_content.read",
    "commit_metadata.read",
    "diagnostic.emit",
];

/// Manifest declarations are requests, never authority. All requested MVP
/// capabilities are mandatory; an incomplete intersection fails closed.
pub struct CapabilityManager;

impl CapabilityManager {
    pub fn resolve(requested: &[String], granted: &[String]) -> Result<Vec<String>> {
        let mut effective = Vec::new();
        for capability in requested {
            ensure!(
                AVAILABLE.contains(&capability.as_str()),
                "CapabilityDenied: requested capability is not provided by this host"
            );
            ensure!(
                granted.contains(capability),
                "CapabilityDenied: requested capability was not granted by the repository"
            );
            if !effective.contains(capability) {
                effective.push(capability.clone());
            }
        }
        Ok(effective)
    }
}

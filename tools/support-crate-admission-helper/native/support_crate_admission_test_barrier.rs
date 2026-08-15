use crate::support_crate_admission_fs::{AdmissionFsError, AdmissionFsErrorFactory};
use std::fs::OpenOptions;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::{Duration, Instant};

#[derive(Debug)]
pub struct AdmissionTestBarrier;

static USED: AtomicBool = AtomicBool::new(false);

impl AdmissionTestBarrier {
    pub fn after_first_pass() -> Result<(), AdmissionFsError> {
        Self::wait("after-first-pass", "")
    }

    pub fn before_child_open(component: String) -> Result<(), AdmissionFsError> {
        Self::wait("before-child-open", &component)
    }

    fn wait(phase: &str, component: &str) -> Result<(), AdmissionFsError> {
        let selected_phase = std::env::var("HXRS_ADMISSION_TEST_PHASE")
            .map_err(|_| AdmissionFsErrorFactory::invalid_input())?;
        let selected_component = std::env::var("HXRS_ADMISSION_TEST_COMPONENT")
            .unwrap_or_default();
        if selected_phase != phase || selected_component != component {
            return Ok(());
        }
        if USED.swap(true, Ordering::SeqCst) {
            return Ok(());
        }
        let ready = std::env::var_os("HXRS_ADMISSION_TEST_READY")
            .ok_or_else(AdmissionFsErrorFactory::invalid_input)?;
        let release = std::env::var_os("HXRS_ADMISSION_TEST_RELEASE")
            .ok_or_else(AdmissionFsErrorFactory::invalid_input)?;
        OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(ready)
            .map_err(|_| AdmissionFsErrorFactory::invalid_input())?;
        let started = Instant::now();
        while !Path::new(&release).is_file() {
            if started.elapsed() > Duration::from_secs(5) {
                return Err(AdmissionFsErrorFactory::invalid_input());
            }
            thread::sleep(Duration::from_millis(1));
        }
        Ok(())
    }
}

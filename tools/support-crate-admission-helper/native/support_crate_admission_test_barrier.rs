use crate::support_crate_admission_fs::{AdmissionFsError, AdmissionFsErrorFactory};
use std::fs::OpenOptions;
use std::path::Path;
use std::thread;
use std::time::{Duration, Instant};

#[derive(Debug)]
pub struct AdmissionTestBarrier;

impl AdmissionTestBarrier {
    pub fn after_first_pass() -> Result<(), AdmissionFsError> {
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

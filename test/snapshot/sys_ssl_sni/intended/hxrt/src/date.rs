use crate::{dynamic, exception};
use chrono::{Datelike, Local, TimeZone, Timelike, Utc, Weekday};

fn throw_msg(msg: &str) -> ! {
    exception::throw(dynamic::from(String::from(msg)))
}

/// Convert a timestamp (ms since Unix epoch UTC) to a local datetime.
fn to_local(ms: i64) -> chrono::DateTime<Local> {
    let utc = Utc.timestamp_millis_opt(ms).single().unwrap_or_else(|| {
        // Outside supported range for this runtime; match Haxe's "unspecified" by throwing.
        throw_msg("Date out of range")
    });
    utc.with_timezone(&Local)
}

/// Convert a timestamp (ms since Unix epoch UTC) to a UTC datetime.
fn to_utc(ms: i64) -> chrono::DateTime<Utc> {
    Utc.timestamp_millis_opt(ms)
        .single()
        .unwrap_or_else(|| throw_msg("Date out of range"))
}

#[inline]
pub fn now_ms() -> i64 {
    Utc::now().timestamp_millis()
}

/// Construct a timestamp (ms since epoch UTC) from local date/time components.
///
/// Month is 0-based (0..11), matching Haxe.
pub fn local_to_ms(year: i32, month0: i32, day: i32, hour: i32, min: i32, sec: i32) -> i64 {
    let month = (month0 + 1) as u32;
    let res = Local.with_ymd_and_hms(year, month, day as u32, hour as u32, min as u32, sec as u32);
    match res {
        chrono::LocalResult::Single(dt) => dt.with_timezone(&Utc).timestamp_millis(),
        chrono::LocalResult::Ambiguous(dt, _) => dt.with_timezone(&Utc).timestamp_millis(),
        chrono::LocalResult::None => throw_msg("Invalid local date"),
    }
}

/// Parse a Haxe Date string into a timestamp in ms since epoch UTC.
pub fn parse_to_ms(s: &str) -> i64 {
    // "YYYY-MM-DD hh:mm:ss" (local)
    if let Ok(naive) = chrono::NaiveDateTime::parse_from_str(s, "%Y-%m-%d %H:%M:%S") {
        let res = Local.from_local_datetime(&naive);
        return match res {
            chrono::LocalResult::Single(dt) => dt.with_timezone(&Utc).timestamp_millis(),
            chrono::LocalResult::Ambiguous(dt, _) => dt.with_timezone(&Utc).timestamp_millis(),
            chrono::LocalResult::None => throw_msg("Invalid local datetime"),
        };
    }

    // "YYYY-MM-DD" (local, midnight)
    if let Ok(date) = chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d") {
        let naive = date.and_hms_opt(0, 0, 0).unwrap();
        let res = Local.from_local_datetime(&naive);
        return match res {
            chrono::LocalResult::Single(dt) => dt.with_timezone(&Utc).timestamp_millis(),
            chrono::LocalResult::Ambiguous(dt, _) => dt.with_timezone(&Utc).timestamp_millis(),
            chrono::LocalResult::None => throw_msg("Invalid local date"),
        };
    }

    // "hh:mm:ss" (time relative to the UTC epoch)
    if let Ok(time) = chrono::NaiveTime::parse_from_str(s, "%H:%M:%S") {
        let seconds = time.num_seconds_from_midnight() as i64;
        return seconds * 1000;
    }

    throw_msg("Invalid date string")
}

/// Format a timestamp (ms since epoch) as "YYYY-MM-DD HH:MM:SS" in local time.
pub fn format_local(ms: i64) -> String {
    let dt = to_local(ms);
    dt.format("%Y-%m-%d %H:%M:%S").to_string()
}

fn weekday_sun0(w: Weekday) -> i32 {
    w.num_days_from_sunday() as i32
}

/// Local time accessors (Haxe semantics).
pub fn local_hours(ms: i64) -> i32 {
    to_local(ms).hour() as i32
}
pub fn local_minutes(ms: i64) -> i32 {
    to_local(ms).minute() as i32
}
pub fn local_seconds(ms: i64) -> i32 {
    to_local(ms).second() as i32
}
pub fn local_full_year(ms: i64) -> i32 {
    to_local(ms).year()
}
pub fn local_month0(ms: i64) -> i32 {
    (to_local(ms).month0()) as i32
}
pub fn local_date(ms: i64) -> i32 {
    to_local(ms).day() as i32
}
pub fn local_day(ms: i64) -> i32 {
    weekday_sun0(to_local(ms).weekday())
}

/// UTC time accessors.
pub fn utc_hours(ms: i64) -> i32 {
    to_utc(ms).hour() as i32
}
pub fn utc_minutes(ms: i64) -> i32 {
    to_utc(ms).minute() as i32
}
pub fn utc_seconds(ms: i64) -> i32 {
    to_utc(ms).second() as i32
}
pub fn utc_full_year(ms: i64) -> i32 {
    to_utc(ms).year()
}
pub fn utc_month0(ms: i64) -> i32 {
    (to_utc(ms).month0()) as i32
}
pub fn utc_date(ms: i64) -> i32 {
    to_utc(ms).day() as i32
}
pub fn utc_day(ms: i64) -> i32 {
    weekday_sun0(to_utc(ms).weekday())
}

/// Time zone difference to UTC, in minutes, matching Haxe/JS semantics.
///
/// For example, in UTC+2 this returns -120.
pub fn timezone_offset_minutes(ms: i64) -> i32 {
    let dt = to_local(ms);
    let local_minus_utc = dt.offset().local_minus_utc() / 60;
    -(local_minus_utc as i32)
}

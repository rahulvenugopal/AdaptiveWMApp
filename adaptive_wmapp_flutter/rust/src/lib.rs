use std::ffi::{CStr, CString};
use std::fs::File;
use std::io::{Seek, SeekFrom, Write};
use std::os::raw::c_char;
use std::ptr;

pub struct EdfWriter {
    file: File,
    channel_count: usize,
    sample_rate: usize,
    record_samples: Vec<Vec<i16>>,
    records: u64,
}

// ─── Original function (EEG-only, backward compatible) ──────────────────────

#[no_mangle]
pub unsafe extern "C" fn tn_edf_open(
    path: *const c_char,
    subject: *const c_char,
    channel_count: usize,
    sample_rate: usize,
) -> *mut EdfWriter {
    if path.is_null() || channel_count == 0 || sample_rate == 0 {
        return ptr::null_mut();
    }
    let path_str = match CStr::from_ptr(path).to_str() {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let subject_str = if subject.is_null() {
        "unknown"
    } else {
        CStr::from_ptr(subject).to_str().unwrap_or("unknown")
    };

    // Build default EEG labels: ["EEG 1", "EEG 2", ..., "Marker"]
    let labels: Vec<String> = (0..channel_count)
        .map(|i| {
            if i == channel_count - 1 {
                "Marker".to_string()
            } else {
                format!("EEG {}", i + 1)
            }
        })
        .collect();
    let dims: Vec<String> = (0..channel_count)
        .map(|i| {
            if i == channel_count - 1 {
                "code".to_string()
            } else {
                "uV".to_string()
            }
        })
        .collect();
    let prefilters: Vec<String> = (0..channel_count)
        .map(|i| {
            if i == channel_count - 1 {
                "HP:0 LP:0".to_string()
            } else {
                "HP:0.1 LP:100".to_string()
            }
        })
        .collect();
    let transducers: Vec<String> = (0..channel_count)
        .map(|i| {
            if i == channel_count - 1 {
                "Event markers".to_string()
            } else {
                "frontal electrode".to_string()
            }
        })
        .collect();

    _open_edf_internal(
        path_str, subject_str, channel_count, sample_rate,
        &labels, &dims, &prefilters, &transducers,
    )
}

// ─── Extended function with custom channel labels (for fNIRS, LSL EEG, etc.) ─

#[no_mangle]
pub unsafe extern "C" fn tn_edf_open_with_labels(
    path: *const c_char,
    subject: *const c_char,
    channel_names: *const *const c_char,   // array of label strings
    physical_dims: *const *const c_char,   // array of dimension strings (e.g. "uV", "umol/L")
    prefilter_strs: *const *const c_char,  // array of prefilter strings (can be null)
    transducer_strs: *const *const c_char, // array of transducer type strings (can be null)
    channel_count: usize,
    sample_rate: usize,
) -> *mut EdfWriter {
    if path.is_null() || channel_names.is_null() || channel_count == 0 || sample_rate == 0 {
        return ptr::null_mut();
    }

    let path_str = match CStr::from_ptr(path).to_str() {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let subject_str = if subject.is_null() {
        "unknown"
    } else {
        CStr::from_ptr(subject).to_str().unwrap_or("unknown")
    };

    // Safely read the arrays of strings
    let labels: Vec<String> = (0..channel_count)
        .map(|i| {
            let ptr = *channel_names.add(i);
            if ptr.is_null() { format!("CH{}", i + 1) }
            else { CStr::from_ptr(ptr).to_str().unwrap_or("CH").to_string() }
        })
        .collect();

    let dims: Vec<String> = (0..channel_count)
        .map(|i| {
            if physical_dims.is_null() { return "uV".to_string(); }
            let ptr = *physical_dims.add(i);
            if ptr.is_null() { "uV".to_string() }
            else { CStr::from_ptr(ptr).to_str().unwrap_or("uV").to_string() }
        })
        .collect();

    let prefilters: Vec<String> = (0..channel_count)
        .map(|i| {
            if prefilter_strs.is_null() { return "".to_string(); }
            let ptr = *prefilter_strs.add(i);
            if ptr.is_null() { "".to_string() }
            else { CStr::from_ptr(ptr).to_str().unwrap_or("").to_string() }
        })
        .collect();

    let transducers: Vec<String> = (0..channel_count)
        .map(|i| {
            if transducer_strs.is_null() { return "".to_string(); }
            let ptr = *transducer_strs.add(i);
            if ptr.is_null() { "".to_string() }
            else { CStr::from_ptr(ptr).to_str().unwrap_or("").to_string() }
        })
        .collect();

    _open_edf_internal(
        path_str, subject_str, channel_count, sample_rate,
        &labels, &dims, &prefilters, &transducers,
    )
}

// ─── Shared push/close functions ────────────────────────────────────────────

#[no_mangle]
pub unsafe extern "C" fn tn_edf_push_sample(
    writer: *mut EdfWriter,
    samples: *const f64,
    count: usize,
) -> bool {
    if writer.is_null() || samples.is_null() {
        return false;
    }
    let writer = &mut *writer;
    let values = std::slice::from_raw_parts(samples, count);
    for channel in 0..writer.channel_count {
        let value = values.get(channel).copied().unwrap_or(0.0);
        writer.record_samples[channel].push(value.round().clamp(-32768.0, 32767.0) as i16);
    }
    if writer.record_samples[0].len() >= writer.sample_rate {
        write_edf_record(writer).is_ok()
    } else {
        true
    }
}

#[no_mangle]
pub unsafe extern "C" fn tn_edf_close(writer: *mut EdfWriter) -> bool {
    if writer.is_null() {
        return false;
    }
    let mut writer = Box::from_raw(writer);

    // Pad any remaining samples in the current record with the last value
    if !writer.record_samples[0].is_empty() {
        for channel in 0..writer.channel_count {
            let last = writer.record_samples[channel].last().copied().unwrap_or(0);
            while writer.record_samples[channel].len() < writer.sample_rate {
                writer.record_samples[channel].push(last);
            }
        }
        if write_edf_record(&mut writer).is_err() {
            return false;
        }
    }

    // Update the record count in the header
    let count_bytes = ascii_pad(&writer.records.to_string(), 8);
    writer.file.seek(SeekFrom::Start(236)).is_ok()
        && writer.file.write_all(&count_bytes).is_ok()
        && writer.file.flush().is_ok()
}

// ─── Internal helpers ────────────────────────────────────────────────────────

fn _open_edf_internal(
    path_str: &str,
    subject_str: &str,
    channel_count: usize,
    sample_rate: usize,
    labels: &[String],
    dims: &[String],
    prefilters: &[String],
    transducers: &[String],
) -> *mut EdfWriter {
    let mut file = match File::create(path_str) {
        Ok(f) => f,
        Err(_) => return ptr::null_mut(),
    };

    let header = edf_header(subject_str, channel_count, sample_rate, -1, labels, dims, prefilters, transducers);
    if file.write_all(&header).is_err() {
        return ptr::null_mut();
    }

    Box::into_raw(Box::new(EdfWriter {
        file,
        channel_count,
        sample_rate,
        record_samples: vec![Vec::with_capacity(sample_rate); channel_count],
        records: 0,
    }))
}

fn write_edf_record(writer: &mut EdfWriter) -> std::io::Result<()> {
    for channel in 0..writer.channel_count {
        for &sample in &writer.record_samples[channel] {
            writer.file.write_all(&sample.to_le_bytes())?;
        }
        writer.record_samples[channel].clear();
    }
    writer.records += 1;
    Ok(())
}

fn edf_header(
    subject: &str,
    channel_count: usize,
    sample_rate: usize,
    records: i64,
    labels: &[String],
    dims: &[String],
    prefilters: &[String],
    transducers: &[String],
) -> Vec<u8> {
    let header_bytes = 256 + channel_count * 256;
    let mut header = Vec::with_capacity(header_bytes);

    header.extend(ascii_pad("0", 8));
    header.extend(ascii_pad(subject, 80));
    header.extend(ascii_pad("Startdate ANGEL EEG/fNIRS", 80));
    header.extend(ascii_pad("01.01.26", 8));
    header.extend(ascii_pad("00.00.00", 8));
    header.extend(ascii_pad(&header_bytes.to_string(), 8));
    header.extend(ascii_pad("", 44));
    header.extend(ascii_pad(&records.to_string(), 8));
    header.extend(ascii_pad("1", 8)); // duration of a data record in seconds (always 1s)
    header.extend(ascii_pad(&channel_count.to_string(), 4));

    // Channel labels (16 bytes each)
    for i in 0..channel_count {
        let label = labels.get(i).map(|s| s.as_str()).unwrap_or("CH");
        header.extend(ascii_pad(label, 16));
    }
    // Transducer types (80 bytes each)
    for i in 0..channel_count {
        let t = transducers.get(i).map(|s| s.as_str()).unwrap_or("");
        header.extend(ascii_pad(t, 80));
    }
    // Physical dimensions (8 bytes each)
    for i in 0..channel_count {
        let d = dims.get(i).map(|s| s.as_str()).unwrap_or("uV");
        header.extend(ascii_pad(d, 8));
    }
    // Physical min/max
    for _ in 0..channel_count {
        header.extend(ascii_pad("-32768", 8));
    }
    for _ in 0..channel_count {
        header.extend(ascii_pad("32767", 8));
    }
    // Digital min/max
    for _ in 0..channel_count {
        header.extend(ascii_pad("-32768", 8));
    }
    for _ in 0..channel_count {
        header.extend(ascii_pad("32767", 8));
    }
    // Prefiltering (80 bytes each)
    for i in 0..channel_count {
        let pf = prefilters.get(i).map(|s| s.as_str()).unwrap_or("");
        header.extend(ascii_pad(pf, 80));
    }
    // Samples per data record
    for _ in 0..channel_count {
        header.extend(ascii_pad(&sample_rate.to_string(), 8));
    }
    // Reserved per channel
    for _ in 0..channel_count {
        header.extend(ascii_pad("", 32));
    }
    header.resize(header_bytes, b' ');
    header
}

fn ascii_pad(value: &str, len: usize) -> Vec<u8> {
    let mut out = vec![b' '; len];
    for (idx, byte) in value.as_bytes().iter().copied().take(len).enumerate() {
        out[idx] = byte;
    }
    out
}

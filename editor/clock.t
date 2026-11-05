package editor

// Darwin CLOCK_MONOTONIC. Mapping deadlines must not use wall-clock time.
@[header="time.h", default_cc="c"]
extern {
    fn clock_gettime_nsec_np(clock u32) u64
}

fn monotonic_ms() u64 {
    return clock_gettime_nsec_np(6) / 1000000
}

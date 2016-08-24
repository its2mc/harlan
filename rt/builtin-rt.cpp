// Builtins for the runtime system.

#include <inttypes.h>

#define NO_GLOBALS
#include "harlan.hpp"

extern uint64_t g_memtime;

// () -> float
//
// Returns the amount of time spend in memory copying.
float rt$dmem$dcopy$dtime() {
    return double(g_memtime) / 1e9;
}

// () -> bool
//
// Returns whether the current device is a CPU device
bool_t rt$dis$dcpu() {
    if(CL_DEVICE_TYPE_CPU & get_device_type()) {
        return true;
    }
    else {
        return false;
    }
}

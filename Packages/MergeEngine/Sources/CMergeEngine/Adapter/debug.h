// Replacement for Perforce's support/debug.h.
//
// The vendored code guards its trace output with p4debug.GetLevel(DT_DIFF).
// Tracing is always off here; printf() still writes to stderr so that the
// guarded code keeps compiling and behaving as written.

#ifndef MERGEENGINE_ADAPTER_DEBUG_H
#define MERGEENGINE_ADAPTER_DEBUG_H

enum P4DebugType { DT_DIFF };

class P4Debug {
  public:
    int GetLevel(P4DebugType) const { return 0; }

    // No format attribute: the vendored trace code passes pointers for %x.
    void printf(const char *format, ...) const;
};

extern const P4Debug p4debug;

#endif

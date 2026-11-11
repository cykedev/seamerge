// Replacement for Perforce's support/tunable.h.
//
// Only the tunables read by the vendored diff code are defined. Their values
// are fixed at the Perforce 2025.1 defaults from support/debug.cc.

#ifndef MERGEENGINE_ADAPTER_TUNABLE_H
#define MERGEENGINE_ADAPTER_TUNABLE_H

enum P4TunableName {
    P4TUNE_DIFF_SLIMIT1,    // diff.slimit1
    P4TUNE_DIFF_SLIMIT2,    // diff.slimit2
    P4TUNE_DIFF_STHRESH,    // diff.sthresh
    P4TUNE_MERGE_DL_ENDEOL, // merge.dl.endeol
};

class P4Tunable {
  public:
    constexpr int Get(P4TunableName name) const {
        switch (name) {
        case P4TUNE_DIFF_SLIMIT1:
            return 10000000;
        case P4TUNE_DIFF_SLIMIT2:
            return 100000000;
        case P4TUNE_DIFF_STHRESH:
            return 50000;
        case P4TUNE_MERGE_DL_ENDEOL:
            return 0;
        }
        return 0;
    }
};

inline constexpr P4Tunable p4tunable{};

#endif

// Implementation of CMergeEngine.h on top of the vendored Perforce engine.
//
// Two-way diff: Sequence + DiffAnalyze; the snake list is turned into
// alternating equal/changed blocks the way diff/diff.cc's walkers read it.
// Three-way merge: DiffMerge::NextChunk(), which reports the line ranges of
// each chunk in base, leg 1 and leg 2 (see VENDORING.md).

#include <limits.h>
#include <stdlib.h>
#include <string.h>

#include <memory>
#include <new>
#include <vector>

#define NEED_TYPES
#include <stdhdrs.h>

#include <debug.h>
#include <error.h>
#include <filesys.h>
#include <readfile.h>
#include <strbuf.h>

#include <diff.h>
#include <diffan.h>
#include <diffmerge.h>
#include <diffsp.h>
#include <diffsr.h>

#include "CMergeEngine.h"

struct me_diff {
    std::vector<int64_t> offsets[2];
    std::vector<me_diff_block> blocks;
};

struct me_merge {
    std::vector<int64_t> offsets[3];
    std::vector<me_merge_block> blocks;
};

namespace {

// DiffDiff() depends on the line positions, which an empty chunk leaves
// unchanged, and on the mode of the previous chunk. After an empty chunk that
// mode is again determined by the positions, so a second empty chunk in a row
// would repeat forever; DiffMerge::Read() would never return.
constexpr int maximumEmptyChunksInARow = 1;

// Read() makes at most four reads of length zero per chunk: the announcement
// of a chunk that is not DD_ALL and the end of each leg. With at most one
// empty chunk in a row, a run of empty reads spans at most three chunks.
constexpr int maximumEmptyReadsInARow = 3 * 4;

// Flag string for DiffFlags::Init(), or nullptr for an unknown value.
const char *FlagString(me_sequence sequence, me_grid grid) {
    static const char *const table[6][5] = {
        {"", "g", "x", "gx", "t"},      {"l", "lg", "lx", "lgx", "lt"},
        {"b", "bg", "bx", "bgx", "bt"}, {"w", "wg", "wx", "wgx", "wt"},
        {"v", "vg", "vx", "vgx", "vt"}, {"h", "hg", "hx", "hgx", "ht"},
    };
    if (sequence < ME_SEQUENCE_LINES || sequence > ME_SEQUENCE_WORDS || grid < ME_GRID_OPTIMAL ||
        grid > ME_GRID_TWO_WAY) {
        return nullptr;
    }
    return table[sequence][grid];
}

bool IsLineSequence(me_sequence sequence) {
    return sequence >= ME_SEQUENCE_LINES && sequence <= ME_SEQUENCE_LINES_IGNORE_ALL_SPACE;
}

me_status CheckInput(const void *data, size_t length) {
    if (!data && length > 0) {
        return ME_ERROR_INVALID_ARGUMENT;
    }
    // The engine indexes with int (LineNo, ReadFile window lengths).
    if (length > static_cast<size_t>(INT32_MAX)) {
        return ME_ERROR_INPUT_TOO_LARGE;
    }
    return ME_OK;
}

me_status StatusFor(const Error &error) {
    if (!error.Test()) {
        return ME_OK;
    }
    return strcmp(error.Operation(), "new") == 0 ? ME_ERROR_OUT_OF_MEMORY : ME_ERROR_INTERNAL;
}

// Runs body, translating C++ exceptions into status codes so that none
// crosses the C boundary.
template <typename Body> me_status Guarded(Body &&body) {
    try {
        return body();
    } catch (const std::bad_alloc &) {
        return ME_ERROR_OUT_OF_MEMORY;
    } catch (...) {
        return ME_ERROR_INTERNAL;
    }
}

std::vector<int64_t> ElementOffsets(const Sequence &sequence) {
    std::vector<int64_t> offsets(static_cast<size_t>(sequence.Lines()) + 1);
    for (LineNo line = 0; line <= sequence.Lines(); ++line) {
        offsets[static_cast<size_t>(line)] = sequence.Length(0, line);
    }
    return offsets;
}

// Element offsets of input as split by flags. Used for merges, whose own
// sequences are private to DiffMerge; the same sequencer splits identically.
me_status ElementOffsets(FileSys &input, const DiffFlags &flags, std::vector<int64_t> &offsets) {
    Error error;
    Sequence sequence(&input, flags, &error);
    if (error.Test()) {
        return StatusFor(error);
    }
    offsets = ElementOffsets(sequence);
    return ME_OK;
}

me_merge_kind MergeKind(DiffDiffs chunk) {
    switch (chunk) {
    case DD_LEG1:
        return ME_MERGE_CHANGED_A;
    case DD_LEG2:
        return ME_MERGE_CHANGED_B;
    case DD_BOTH:
        return ME_MERGE_CHANGED_BOTH;
    case DD_CONF:
        return ME_MERGE_CONFLICT;
    default:
        return ME_MERGE_UNCHANGED;
    }
}

// The blocks of a merge, from DiffMerge::NextChunk(). The engine is released
// on return, before the caller allocates the offset tables.
me_status MergeBlocks(FileSys &base, FileSys &a, FileSys &b, const DiffFlags &flags,
                      std::vector<me_merge_block> &blocks) {
    Error error;
    DiffMerge engine(&base, &a, &b, flags, LineTypeRaw, &error);
    if (error.Test()) {
        return StatusFor(error);
    }

    LineNo ranges[6];
    int emptyChunks = 0;
    for (DiffDiffs chunk; (chunk = engine.NextChunk(ranges)) != DD_EOF;) {
        bool empty = ranges[0] == ranges[1] && ranges[2] == ranges[3] && ranges[4] == ranges[5];
        if (empty) {
            if (++emptyChunks > maximumEmptyChunksInARow) {
                return ME_ERROR_INTERNAL;
            }
            continue;
        }
        emptyChunks = 0;
        blocks.push_back(
            {MergeKind(chunk), ranges[0], ranges[1], ranges[2], ranges[3], ranges[4], ranges[5]});
    }
    return ME_OK;
}

template <typename Handle>
const int64_t *Offsets(const Handle *handle, int side, int sides, size_t *count) {
    if (!handle || side < 0 || side >= sides) {
        if (count) {
            *count = 0;
        }
        return nullptr;
    }
    const auto &offsets = handle->offsets[side];
    if (count) {
        *count = offsets.size();
    }
    return offsets.data();
}

template <typename Block> const Block *Blocks(const std::vector<Block> *blocks, size_t *count) {
    if (count) {
        *count = blocks ? blocks->size() : 0;
    }
    return blocks && !blocks->empty() ? blocks->data() : nullptr;
}

} // namespace

extern "C" {

me_status me_diff_create(const void *a, size_t a_length, const void *b, size_t b_length,
                         me_sequence sequence, me_diff **result) {
    if (!result) {
        return ME_ERROR_INVALID_ARGUMENT;
    }
    *result = nullptr;
    const char *flagString = FlagString(sequence, ME_GRID_OPTIMAL);
    if (!flagString) {
        return ME_ERROR_INVALID_ARGUMENT;
    }
    for (me_status status : {CheckInput(a, a_length), CheckInput(b, b_length)}) {
        if (status != ME_OK) {
            return status;
        }
    }

    return Guarded([&] {
        DiffFlags flags(flagString);
        FileSys inputA(a, a_length, "a");
        FileSys inputB(b, b_length, "b");

        Error error;
        Sequence sequenceA(&inputA, flags, &error);
        Sequence sequenceB(&inputB, flags, &error);
        if (error.Test()) {
            return StatusFor(error);
        }

        DiffAnalyze analysis(&sequenceA, &sequenceB);
        auto diff = std::make_unique<me_diff>();

        // Snakes are the matching runs; BracketSnake() guarantees one starting
        // at (0, 0) and one ending at the end of both inputs, so the gaps
        // between consecutive snakes are exactly the changes.
        for (const Snake *snake = analysis.GetSnake(); snake; snake = snake->next) {
            if (snake->u > snake->x) {
                diff->blocks.push_back({ME_DIFF_EQUAL, snake->x, snake->u, snake->y, snake->v});
            }
            const Snake *next = snake->next;
            if (next && (next->x > snake->u || next->y > snake->v)) {
                diff->blocks.push_back({ME_DIFF_CHANGED, snake->u, next->x, snake->v, next->y});
            }
        }
        diff->offsets[ME_DIFF_SIDE_A] = ElementOffsets(sequenceA);
        diff->offsets[ME_DIFF_SIDE_B] = ElementOffsets(sequenceB);

        *result = diff.release();
        return ME_OK;
    });
}

void me_diff_destroy(me_diff *diff) {
    delete diff;
}

const me_diff_block *me_diff_blocks(const me_diff *diff, size_t *count) {
    return Blocks(diff ? &diff->blocks : nullptr, count);
}

const int64_t *me_diff_offsets(const me_diff *diff, me_diff_side side, size_t *count) {
    return Offsets(diff, side, 2, count);
}

me_status me_merge_create(const void *base, size_t base_length, const void *a, size_t a_length,
                          const void *b, size_t b_length, me_sequence sequence, me_grid grid,
                          me_merge **result) {
    if (!result) {
        return ME_ERROR_INVALID_ARGUMENT;
    }
    *result = nullptr;
    const char *flagString = FlagString(sequence, grid);
    if (!flagString || !IsLineSequence(sequence)) {
        return ME_ERROR_INVALID_ARGUMENT;
    }
    for (me_status status :
         {CheckInput(base, base_length), CheckInput(a, a_length), CheckInput(b, b_length)}) {
        if (status != ME_OK) {
            return status;
        }
    }

    return Guarded([&] {
        DiffFlags flags(flagString);
        FileSys inputBase(base, base_length, "base");
        FileSys inputA(a, a_length, "a");
        FileSys inputB(b, b_length, "b");

        auto merge = std::make_unique<me_merge>();
        me_status status = MergeBlocks(inputBase, inputA, inputB, flags, merge->blocks);
        if (status != ME_OK) {
            return status;
        }

        // With the two-way grid, DiffMerge merged against an empty base.
        FileSys emptyBase(nullptr, 0, "base");
        FileSys &effectiveBase = grid == ME_GRID_TWO_WAY ? emptyBase : inputBase;

        for (auto [input, side] :
             {std::pair{&effectiveBase, ME_MERGE_SIDE_BASE}, std::pair{&inputA, ME_MERGE_SIDE_A},
              std::pair{&inputB, ME_MERGE_SIDE_B}}) {
            status = ElementOffsets(*input, flags, merge->offsets[side]);
            if (status != ME_OK) {
                return status;
            }
        }

        *result = merge.release();
        return ME_OK;
    });
}

void me_merge_destroy(me_merge *merge) {
    delete merge;
}

const me_merge_block *me_merge_blocks(const me_merge *merge, size_t *count) {
    return Blocks(merge ? &merge->blocks : nullptr, count);
}

const int64_t *me_merge_offsets(const me_merge *merge, me_merge_side side, size_t *count) {
    return Offsets(merge, side, 3, count);
}

me_status me_merge_reference_text(const void *base, size_t base_length, const void *a,
                                  size_t a_length, const void *b, size_t b_length,
                                  me_sequence sequence, me_grid grid, void **text,
                                  size_t *text_length, size_t *conflict_count) {
    if (!text || !text_length || !conflict_count) {
        return ME_ERROR_INVALID_ARGUMENT;
    }
    *text = nullptr;
    *text_length = 0;
    *conflict_count = 0;
    const char *flagString = FlagString(sequence, grid);
    if (!flagString || !IsLineSequence(sequence)) {
        return ME_ERROR_INVALID_ARGUMENT;
    }
    for (me_status status :
         {CheckInput(base, base_length), CheckInput(a, a_length), CheckInput(b, b_length)}) {
        if (status != ME_OK) {
            return status;
        }
    }

    return Guarded([&] {
        DiffFlags flags(flagString);
        FileSys inputBase(base, base_length, "base");
        FileSys inputA(a, a_length, "a");
        FileSys inputB(b, b_length, "b");

        Error error;
        DiffMerge engine(&inputBase, &inputA, &inputB, flags, LineTypeRaw, &error);
        if (error.Test()) {
            return StatusFor(error);
        }

        std::vector<char> output;
        char buffer[4096];
        int length = 0;
        int previousBits = 0;
        int emptyReads = 0;
        size_t conflicts = 0;

        // Read() returns each chunk as one or more reads with the same
        // selection bits; a conflict starts where leg 1's conflict text does.
        while (int bits = engine.Read(buffer, sizeof buffer, &length)) {
            const int conflictLeg1 = SEL_CONF | SEL_LEG1;
            if ((bits & conflictLeg1) == conflictLeg1 &&
                (previousBits & conflictLeg1) != conflictLeg1) {
                ++conflicts;
            }
            if (bits & SEL_RSLT) {
                output.insert(output.end(), buffer, buffer + length);
            }
            emptyReads = length > 0 ? 0 : emptyReads + 1;
            if (emptyReads > maximumEmptyReadsInARow) {
                return ME_ERROR_INTERNAL;
            }
            previousBits = bits;
        }

        if (!output.empty()) {
            void *copy = malloc(output.size());
            if (!copy) {
                return ME_ERROR_OUT_OF_MEMORY;
            }
            memcpy(copy, output.data(), output.size());
            *text = copy;
            *text_length = output.size();
        }
        *conflict_count = conflicts;
        return ME_OK;
    });
}

} // extern "C"

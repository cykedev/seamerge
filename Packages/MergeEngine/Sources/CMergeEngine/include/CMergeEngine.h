// C interface to the vendored Perforce diff and merge engine.
//
// Inputs are byte buffers; nothing is read from or written to files. The
// buffers only need to stay valid for the duration of a call: results own
// copies of everything they report.
//
// Inputs are split into elements (lines, or tokens for the token
// sequencers). Ranges are half-open [start, end) element indices. Each
// result also carries, per input, the byte offset where each element
// starts: count + 1 values, the last being the input length.
//
// All functions are reentrant and may be called concurrently.

#ifndef CMERGEENGINE_H
#define CMERGEENGINE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    ME_OK = 0,
    ME_ERROR_INVALID_ARGUMENT,
    // An input is larger than INT32_MAX bytes.
    ME_ERROR_INPUT_TOO_LARGE,
    // Memory could not be allocated. See "Memory" in VENDORING.md.
    ME_ERROR_OUT_OF_MEMORY,
    // The engine failed or stopped making progress.
    ME_ERROR_INTERNAL,
} me_status;

// How inputs are split into elements and how elements are compared.
typedef enum {
    ME_SEQUENCE_LINES = 0,              // byte-exact lines
    ME_SEQUENCE_LINES_IGNORE_EOL,       // Perforce -dl
    ME_SEQUENCE_LINES_IGNORE_SPACE,     // Perforce -db
    ME_SEQUENCE_LINES_IGNORE_ALL_SPACE, // Perforce -dw
    ME_SEQUENCE_CHARACTER_CLASSES,      // Perforce -dv (WClassReader); diff only
    ME_SEQUENCE_WORDS,                  // Perforce -dh (WordReader); diff only
} me_sequence;

// Merge grid, see Perforce's DiffFlags.
typedef enum {
    ME_GRID_OPTIMAL = 0,
    ME_GRID_GUARDED,       // -dg
    ME_GRID_DIFF3,         // -dx
    ME_GRID_GUARDED_DIFF3, // -dgx
    ME_GRID_TWO_WAY,       // -dt: the base is replaced by an empty input
} me_grid;

// ---------------------------------------------------------------------------
// Two-way diff

typedef enum {
    ME_DIFF_EQUAL = 0,
    ME_DIFF_CHANGED,
} me_diff_kind;

typedef struct {
    me_diff_kind kind;
    int32_t a_start, a_end;
    int32_t b_start, b_end;
} me_diff_block;

typedef enum {
    ME_DIFF_SIDE_A = 0,
    ME_DIFF_SIDE_B,
} me_diff_side;

typedef struct me_diff me_diff;

me_status me_diff_create(const void *a, size_t a_length, const void *b, size_t b_length,
                         me_sequence sequence, me_diff **result);
void me_diff_destroy(me_diff *diff);

// Blocks tile both inputs in order, alternating equal and changed.
const me_diff_block *me_diff_blocks(const me_diff *diff, size_t *count);
const int64_t *me_diff_offsets(const me_diff *diff, me_diff_side side, size_t *count);

// ---------------------------------------------------------------------------
// Three-way merge. Leg 1 is "A" (incoming, Perforce "theirs"), leg 2 is "B"
// (own, Perforce "yours").

typedef enum {
    ME_MERGE_UNCHANGED = 0, // DD_ALL
    ME_MERGE_CHANGED_A,     // DD_LEG1
    ME_MERGE_CHANGED_B,     // DD_LEG2
    ME_MERGE_CHANGED_BOTH,  // DD_BOTH: identical change in A and B
    ME_MERGE_CONFLICT,      // DD_CONF
} me_merge_kind;

typedef struct {
    me_merge_kind kind;
    int32_t base_start, base_end;
    int32_t a_start, a_end;
    int32_t b_start, b_end;
} me_merge_block;

typedef enum {
    ME_MERGE_SIDE_BASE = 0,
    ME_MERGE_SIDE_A,
    ME_MERGE_SIDE_B,
} me_merge_side;

typedef struct me_merge me_merge;

// sequence must be one of the line sequences.
me_status me_merge_create(const void *base, size_t base_length, const void *a, size_t a_length,
                          const void *b, size_t b_length, me_sequence sequence, me_grid grid,
                          me_merge **result);
void me_merge_destroy(me_merge *merge);

// Blocks tile all three inputs in order.
const me_merge_block *me_merge_blocks(const me_merge *merge, size_t *count);
const int64_t *me_merge_offsets(const me_merge *merge, me_merge_side side, size_t *count);

// Reference output of Perforce's own DiffMerge::Read(): the concatenation of
// all chunks marked SEL_RSLT (a conflict contributes A, then B, without
// markers). Intended for verifying me_merge_create(). On success *text is
// allocated with malloc() (NULL if empty) and must be released with free().
me_status me_merge_reference_text(const void *base, size_t base_length, const void *a,
                                  size_t a_length, const void *b, size_t b_length,
                                  me_sequence sequence, me_grid grid, void **text,
                                  size_t *text_length, size_t *conflict_count);

#ifdef __cplusplus
}
#endif

#endif

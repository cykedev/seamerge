// ReadFile over an in-memory buffer.
//
// Implements the class declared in the vendored sys/readfile.h; Perforce's own
// sys/readfile.cc (mmap(2) and read(2) on files) is not used. The whole buffer
// is the memory window, which is the state the original reaches after a
// successful mmap(2): maddr..mend spans the input, offset == size, and Read()
// never has more data. The inline accessors in readfile.h rely on exactly
// these invariants.

#include <string.h>

#define NEED_TYPES
#include <stdhdrs.h>

#include <error.h>
#include <filesys.h>
#include <readfile.h>

namespace {

// Open() needs a valid address for empty input: (unsigned char *)-1 is the
// header's "closed" marker.
unsigned char emptyInput[1];

} // namespace

ReadFile::ReadFile()
    : mptr(nullptr), maddr(reinterpret_cast<unsigned char *>(-1)), mend(nullptr), size(0),
      offset(0), mapped(0), mlen(0), fp(nullptr) {}

ReadFile::~ReadFile() {
    Close();
}

void ReadFile::Open(FileSys *file, Error *) {
    fp = file;
    size = static_cast<offL_t>(file->Size());
    maddr = file->Size() > 0 ? const_cast<unsigned char *>(file->Data()) : emptyInput;
    mapped = 1;
    mlen = file->Size();
    offset = size;
    mptr = maddr;
    mend = maddr + size;
}

void ReadFile::Close() {
    maddr = reinterpret_cast<unsigned char *>(-1);
    mptr = mend = nullptr;
    mapped = 0;
    fp = nullptr;
}

int ReadFile::Read() {
    return 0;
}

void ReadFile::Seek(offL_t position) {
    if (position < 0) {
        position = 0;
    }
    if (position > size) {
        position = size;
    }
    mptr = maddr + position;
}

offL_t ReadFile::Memcmp(ReadFile *other, offL_t length) {
    offL_t count = length;
    count = count < mend - mptr ? count : mend - mptr;
    count = count < other->mend - other->mptr ? count : other->mend - other->mptr;

    if (int result = memcmp(mptr, other->mptr, static_cast<size_t>(count))) {
        return result;
    }
    mptr += count;
    other->mptr += count;
    return 0;
}

offL_t ReadFile::Memcpy(char *buffer, offL_t length) {
    offL_t count = length < mend - mptr ? length : mend - mptr;
    memcpy(buffer, mptr, static_cast<size_t>(count));
    mptr += count;
    return count;
}

offL_t ReadFile::Memccpy(char *buffer, int marker, offL_t length) {
    offL_t count = length < mend - mptr ? length : mend - mptr;
    if (auto *end =
            static_cast<char *>(memccpy(buffer, mptr, marker, static_cast<size_t>(count)))) {
        count = end - buffer;
    }
    mptr += count;
    return count;
}

offL_t ReadFile::Memchr(int marker, offL_t length) {
    offL_t available = mend - mptr;
    offL_t count = length == -1 || length > available ? available : length;
    if (auto *found =
            static_cast<unsigned char *>(memchr(mptr, marker, static_cast<size_t>(count)))) {
        count = found - mptr;
    }
    mptr += count;
    return count;
}

offL_t ReadFile::Textcpy(char *destination, offL_t destinationLength, offL_t sourceLength,
                         LineType type) {
    switch (type) {
    case LineTypeCr: {
        // Copy, translating CR to LF.
        offL_t count = Memcpy(destination,
                              destinationLength < sourceLength ? destinationLength : sourceLength);
        for (offL_t i = 0; i < count; ++i) {
            if (destination[i] == '\r') {
                destination[i] = '\n';
            }
        }
        return count;
    }
    case LineTypeCrLf:
    case LineTypeLfcrlf: {
        // Copy, translating CRLF to LF. A CR at the end of the source range
        // that is followed by LF consumes that LF too, so the source can be
        // overrun by one byte, as in the original implementation.
        char *start = destination;
        while (destinationLength > 0 && sourceLength > 0 && mptr < mend) {
            char c = static_cast<char>(*mptr++);
            --sourceLength;
            if (c == '\r' && mptr < mend && *mptr == '\n') {
                ++mptr;
                --sourceLength;
                c = '\n';
            }
            *destination++ = c;
            --destinationLength;
        }
        return destination - start;
    }
    case LineTypeRaw:
        break;
    }
    return Memcpy(destination, destinationLength < sourceLength ? destinationLength : sourceLength);
}

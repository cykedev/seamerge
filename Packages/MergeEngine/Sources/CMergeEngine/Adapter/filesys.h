// Replacement for Perforce's sys/filesys.h.
//
// In Perforce, FileSys abstracts local files. Here it is a non-owning view of
// a byte buffer: the vendored code passes it to ReadFile::Open() (implemented
// in MemoryReadFile.cc) and creates an empty one for the two-way merge grid.
// The buffer must outlive every ReadFile that reads it.

#ifndef MERGEENGINE_ADAPTER_FILESYS_H
#define MERGEENGINE_ADAPTER_FILESYS_H

#include <stddef.h>

enum FileSysType { FST_EMPTY };

class FileSys {
  public:
    FileSys(const void *data, size_t size, const char *name)
        : data_(static_cast<const unsigned char *>(data)), size_(data ? size : 0), name_(name) {}

    FileSys(const FileSys &) = delete;
    FileSys &operator=(const FileSys &) = delete;

    static FileSys *Create(FileSysType) { return new FileSys(nullptr, 0, "empty"); }

    const char *Name() const { return name_; }
    const unsigned char *Data() const { return data_; }
    size_t Size() const { return size_; }

  private:
    const unsigned char *data_;
    size_t size_;
    const char *name_;
};

#endif

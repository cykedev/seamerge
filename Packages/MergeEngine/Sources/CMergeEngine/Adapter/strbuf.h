// Replacement for Perforce's support/strbuf.h.
//
// The only use in the vendored code is DiffFlags::Init(const StrPtr *), which
// reads the flag string through StrPtr::Text().

#ifndef MERGEENGINE_ADAPTER_STRBUF_H
#define MERGEENGINE_ADAPTER_STRBUF_H

class StrPtr {
  public:
    explicit StrPtr(const char *text) : text_(text) {}

    char *Text() const { return const_cast<char *>(text_); }

  private:
    const char *text_;
};

#endif

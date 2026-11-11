// Replacement for Perforce's support/error.h.
//
// The vendored diff code only asks whether an operation failed and records
// allocation failures through Error::Sys("new", ...). Perforce's full Error
// class (message catalogs, StrDict parameters, formatting) is not needed.

#ifndef MERGEENGINE_ADAPTER_ERROR_H
#define MERGEENGINE_ADAPTER_ERROR_H

class Error {
  public:
    int Test() const { return failed_ ? 1 : 0; }

    void Sys(const char *operation, const char *) {
        failed_ = true;
        operation_ = operation;
    }

    const char *Operation() const { return operation_; }

  private:
    bool failed_ = false;
    const char *operation_ = "";
};

#endif

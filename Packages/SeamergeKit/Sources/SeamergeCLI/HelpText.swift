/// The text `seamerge --help` prints.
enum HelpText {
  static let text = """
    Usage:
      seamerge merge [--base <file>] --local <file> --remote <file> --output <file>
                     [--label-base <name>] [--label-local <name>]
                     [--label-remote <name>] [--from-git]
      seamerge diff [--path <path>] [--label-left <name>] [--label-right <name>]
                    [--] <old> <new>
      seamerge [--] <old> <new>
      seamerge --version | --help

    Opens a merge or a comparison in Seamerge and waits until its window is closed.

    Merge options:
      --base <file>          Common ancestor, if there is one
      --local <file>         Version Git calls LOCAL, shown on the right
      --remote <file>        Version Git calls REMOTE, shown on the left
      --output <file>        File the result is saved to
      --label-base <name>    Name shown above the base
      --label-local <name>   Name shown above LOCAL
      --label-remote <name>  Name shown above REMOTE
      --from-git             Git runs the command and waits for it

    Diff options:
      --path <path>          Path shown for both files
      --label-left <name>    Name shown above the old file
      --label-right <name>   Name shown above the new file

    Exit status:
      0  The merge was saved, or the comparison was closed.
      1  The merge was not saved, or the connection to Seamerge was lost.
      2  The arguments are invalid, or a file cannot be read.
      3  Seamerge cannot be opened or does not answer.

    """
}

/// The text `seamerge --help` prints.
enum HelpText {
  static let text = """
    Usage:
      seamerge merge [--base <file>] --local <file> --remote <file> --output <file>
                     [--label-base <name>] [--label-local <name>]
                     [--label-remote <name>] [--from-git]
      seamerge diff [--path <path>] [--label-left <name>] [--label-right <name>]
                    [--collect] [--] <old> <new>
      seamerge [--] <old> <new>
      seamerge patch [--wait] [<file> | -]
      <command> | seamerge
      seamerge --version | --help

    Opens a merge or a comparison in Seamerge and waits until its window is closed.
    A collected comparison of several files only waits until Seamerge has them.
    A patch, a unified diff such as git diff writes, opens in a window that shows
    its changes; without a file or with -, it is read from standard input.

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
      --collect              Show the files of one Git run in one window, and end
                             as soon as Seamerge has them

    <old> and <new> may be the two folders of git difftool --dir-diff.

    Patch options:
      --wait                 Wait until the window is closed, rather than ending
                             as soon as it shows

    Exit status:
      0  The merge was saved, the comparison or the patch was closed, Seamerge
         took over the files of a collected comparison, or it shows the patch.
      1  The merge was not saved, or the connection to Seamerge was lost.
      2  The arguments are invalid, a file cannot be read, or the patch is not
         a unified diff.
      3  Seamerge cannot be opened or does not answer, or cannot open the window
         of a patch.

    """
}

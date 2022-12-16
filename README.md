# CppChecker

This is helper for [cppcheck](https://github.com/danmar/cppcheck).

Remarkable point of this helper is to support repo, git and summarizing function.

# Precondition

You need to install cppcheck in advance.

For Mac

```
% brew install cppcheck
```

For Ubuntu

```
$ sudo apt-get install cppcheck
```

# Help

```
Usage: usage ANDROID_HOME
    -m, --mode=                      Specify report mode all or summary or detail default:all
    -p, --reportOutPath=             Specify report output folder if you want to report out as file
    -r, --reportFormat=              Specify report format markdown|csv|xml (default:)
    -g, --gitOpt=                    Specify option for git (default:
    -e, --optEnable=                 Specify option --enable for cppcheck (default:)
        --summarySection=
                                     Specify summary sections with | separator (default:moduleName|path|error|warning|performance|style|information)("" means everything)
        --detailSection=
                                     Specify detail sections with | separator (default:)("" means everything)
    -f, --pathFilter=                Specify file path filter (default:)("" means everything)
    -a, --filterAuthorMatch=         Specify if match-only-filter for git blame result (default:)
    -s, --surpressNonIssue           Specify if surpress non issues e.g. syntaxError (default:false)
    -t, --execTimeout=               Specify time out (sec) of cppcheck execution (default:300)
    -j, --numOfThreads=              Specify number of threads to analyze (default:10)
    -l, --enableLinkInSummary        Enable link in summary.md to each detail report.md. Note that this is only available in markdown.
        --verbose
                                     Enable verbose status output
```

# Basic usage

```
$ ruby CppChecker.rb ~/work/android/s -f frameworks --gitOpt="--author=google.com" -a "google.com" -s
```

This means to apply cppcheck for 
 * Android's source code
 * the targetting under system/ such as system/core, system/bt, etc.
 * limiting to apply *files* which are modified by google.com's author
 * limiting the report if the error is caused by google.com's author.
 * the following are following to the default
   * surpressing non-errors such as toomanyconfig, etc.
   * creating report of summary.md and per-git result including the analysis whose commit causes the error, warning, etc. which are identified by cppcheck.


```
| moduleName | path | error | warning | performance | style | information |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| bt | /system/bt | 45 | 3 |  |  |  |
| core | /system/core | 23 |  |  |  |  |
| extras | /system/extras | 16 | 6 |  |  |  |
| hidl | /system/tools/hidl | 5 |  |  |  |  |
| security | /system/security | 4 |  |  |  |  |
| netd | /system/netd | 4 |  |  |  |  |
| incremental_delivery | /system/incremental_delivery | 4 |  |  |  |  |
| apex | /system/apex | 3 |  |  |  |  |
| iorap | /system/iorap | 3 |  |  |  |  |
| keymaster | /system/keymaster | 3 |  |  |  |  |
| logging | /system/logging | 3 |  |  |  |  |
| nfc | /system/nfc |  | 1 |  |  |  |
| sysprop | /system/tools/sysprop | 3 |  |  |  |  |
| unwinding | /system/unwinding | 3 |  |  |  |  |
| vold | /system/vold | 3 |  |  |  |  |
| libvintf | /system/libvintf | 2 |  |  |  |  |
| chre | /system/chre | 2 |  |  |  |  |
| libbase | /system/libbase | 1 |  |  |  |  |
| teeui | /system/teeui | 1 |  |  |  |  |
```

```
| filename | line | severity | id | message | commitId | author | authorMail | theLine |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| debuggerd/crasher/crasher.cpp | 119 | error | nullPointer | Null pointer dereference: null_func | b9de87f7edefd7a2473134b267716c5fd750e89f | xxxx | <xxxx@google.com> | ```return null_func();``` |
..snip..
```


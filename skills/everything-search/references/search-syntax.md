# Everything query syntax

## Operators

| Syntax | Meaning |
|---|---|
| `foo bar` | both terms (AND) |
| `foo\|bar` | either term (OR) |
| `!foo` | exclude term |
| `<foo\|bar> baz` | grouped expression |
| `"exact phrase"` | literal phrase |
| `*` / `?` | any characters / one character |

## High-value functions

| Query | Meaning |
|---|---|
| `file:` / `folder:` | files only / folders only |
| `path:` | match the full path |
| `ext:ps1;py;js` | extension list |
| `size:>1gb` | files larger than 1 GiB |
| `size:100mb..1gb` | inclusive size range |
| `dm:today` | modified today |
| `dc:thisweek` | created this week |
| `parent:"C:\path"` | direct children only |
| `content:"needle"` | search indexed/readable content; potentially slow |
| `regex:^report-\d+\.pdf$` | regex for one term |

## Intent translations

```text
Find large videos on D:          D:\ ext:mp4;mkv;mov size:>2gb
PowerShell edited today          ext:ps1 dm:today
Exact project folder             folder:wholefilename:"project-name"
PDFs under Downloads             path:"C:\Users\name\Downloads" ext:pdf
Recent installers                path:Downloads ext:exe;msi dm:thismonth
Logs containing an error         ext:log content:"specific error"
Exclude build dependencies       ext:js !path:node_modules !path:dist
```

Spaces are AND operators, so quote paths and phrases containing spaces. Prefer Everything functions over broad regex. Global regex mode disables normal functions and operators; use the `regex:` modifier on a single term when combining regex with other filters.

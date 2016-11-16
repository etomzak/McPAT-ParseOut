# McPAT::ParseOut

McPAT::ParseOut is a Perl 5 module for parsing the output from the
[McPAT power model](https://code.google.com/archive/p/mcpat/). It turns the
output from McPAT into a tree made of perl hashes.

# Installation

```
$> git clone https://github.com/etomzak/McPAT-ParseOut.git parseout_trunk
```

Then add the following to the top of your perl script:
```
use lib "/path/to/parseout_trunk";
use McPAT::ParseOut;
```

# Usage

```
my ($tree, $errors, $warnings) = parseOut("/path/to/mcpat/output");
```

`$tree` points to the parsed output. `$errors` and `$warnings` point to arrays
of errors and warnings encountered when parsing the McPAT output. Complete
Documentation is available with
```
$> perldoc McPAT/ParseOut.pm
```


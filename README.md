# McPAT Utilities

This repo contains two Perl modules for working with the
[McPAT power model](https://code.google.com/archive/p/mcpat/): `McPAT::M5XML`
and `McPAT::ParseOut`. The first one helps generate input for McPAT, and the
second one helps parse output from McPAT. `gather.pl`, a script for building
tables from [gem5](http://gem5.org/) and McPAT simulation results, is also
included.

## Quick Set-Up

```
$> git clone https://github.com/etomzak/McPAT-Utils.git utils_trunk
```

Then add the following to the top of your perl script:
```
use lib "/path/to/utils_trunk";
use McPAT::M5XML;
use McPAT::ParseOut;
```

Note that `M5XML` and `ParseOut` currently have no interdependencies and can
be used separately.

## McPAT::M5XML

`McPAT::M5XML` is a Perl 5 module that parses gem5 config.ini and stats.txt
files for parameter values and hardware counters, and plugs them into a
template XML file. The resulting file is used as input for the McPAT power
model. 

### Usage

```
($errors, $warnings) = m5xml($stats, $config, $template, $xml);
```

`$stats` is the path to a stats.txt file, `$config` is the path to a
config.ini file, `$template` is the path to a template XML file, and `$xml` is
the path to the output XML file (which will be created). Complete documentation
is available with
```
$> perldoc McPAT/M5XML.pm
```

### Template File

A template XML file is just a McPAT configuration XML file like the ones
distributed with McPAT, but some values have been replaced with placeholders.
The parameter and counter names in the placeholders are replaced with parameter
and counter values and then executed as Perl expressions. Some examples:

```
<!-- config.ini replacement: -->
<param name="ROB_size" value="{config.system.cpu.numROBEntries}"/>
<!-- might turn into: -->
<param name="ROB_size" value="16"/>

<!-- stats.txt replacement: -->
<stat name="total_cycles" value="{stats.system.cpu.numCycles}"/>
<!-- might turn into: -->
<stat name="total_cycles" value="123456"/>

<!-- arithmetic in placeholder: -->
<stat name="runtime_sec" value="{stats.system.cpu.numCycles * config.system.cpu.clock / stats.sim_freq}"/>
<!-- might turn into: -->
<stat name="runtime_sec" value="0.321"/>

<!-- logic in placeholder: -->
<param name="number_of_L2s" value="{('config.system.children' =~ /l2/) ? 1 : 0}"/>
<!-- if an L2 cache is simulated: -->
<param name="number_of_L2s" value="1"/>
<!-- else: -->
<param name="number_of_L2s" value="0"/>

```

## McPAT::ParseOut

McPAT::ParseOut is a Perl 5 module for parsing the output from the
[McPAT power model](https://code.google.com/archive/p/mcpat/). It turns the
output from McPAT into a tree made of perl hashes.

### Usage

```
my ($tree, $errors, $warnings) = parseOut("/path/to/mcpat/output");
```

`$tree` points to the parsed output. `$errors` and `$warnings` point to arrays
of errors and warnings encountered when parsing the McPAT output. Complete
documentation is available with
```
$> perldoc McPAT/ParseOut.pm
```




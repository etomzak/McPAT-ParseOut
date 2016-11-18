#!/usr/bin/perl -w

# gather.pl -- Parses gem5 and McPAT output
# Copyright (C) 2016  Erik Tomusk
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;

=head1 NAME

gather.pl

=head1 SYNOPSIS

 gather.pl --config conf.cfg
           --root /path/to/ecdf_run
           --mcpat report_name

=head1 OPTIONS

--bar          Display progress bar (only valid with --outfile)

--config       Configuration describing data to extract; see below for
               format (required)

--mcpat        Name of McPAT reports (recommended)

--outfile      File to dump the data table (default: STDOUT)

--progressive  Append new data from I<root>s to C<outfile>. Creates a
               file named C<gather_log> in each I<root>. Requires
               --outfile.

--root         Simulation directory (directory containing directories
               000000-nnnnnn). Can be given more than once (one
               required).

--stats        In case stats.txt files contain more than one set of
               statistics, which set to use. Range: [1,n]
               (default: 1)

--verbose      Print some debugging info

=head1 CONFIGURATION FILE FORMAT

 +---------------------------------------------------------+
 |my $hash = {                                             |
 |            config => ['5!system.cpu.LQEntries'],        |
 |            stats  => ['2!sim_seconds'],                 |
 |            log    => ['1!JOB_BIN','3!robEntries'],      |
 |            mcpat  => ['4!core.Subthreshold Leakage+' .  |
 |                       'core.Gate Leakage+' .            |
 |                       'core.Runtime Dynamic']           |
 |           }                                             |
 +---------------------------------------------------------+
Where:

=over

=item

I<1!> indicates the column

=item

I<+> shows that items should be added

=item

I<<spaceE<gt>> is NOT a delimitter

=item

For mcpat, the special form I<6!_SOLVED_> can be used to get a
true/false column for whether mcpat was able to find a good solution

=item

For log, the special form I<7!_CONF_> will attempt to pick out the
ordinal number of the hardware configuration. Technically it looks
for what which configuration was extracted from configuration file(s).
Therefore, it only makes sense when all hardware parameters, and no
workload parameters, are specified within the configuration file(s).
If the entire session was completely described in configuration files,
then I<_CONF> will be the number of the particular run.

=back

=head1 KNOWN BUGS

In progressive mode with McPAT, running gather.pl while McPAT is
running can result in NAs in the output. This happens if gather.pl
checks for directories after McPAT has created a report file, and
parses the report before McPAT finishes writing to it. The workaround
is to not run gather.pl while McPAT is running.

=cut

=head1 COPYRIGHT

gather.pl  Copyright (C) 2016  Erik Tomusk

This software is licensed under GPL-3.0 and comes with ABSOLUTELY NO
WARRANTY.
This is free software, and you are welcome to redistribute it under
certain conditions; see L<http://www.gnu.org/licenses/>.

=cut

# Put your McPAT parsing library location here if in different directory
use File::Basename;
use lib dirname(__FILE__);
use McPAT::ParseOut;
use Getopt::Long;
use Data::Dumper;

# --------------------------------------------------------------------------- #
# ------------------------------ G L O B A L S ------------------------------ #
# --------------------------------------------------------------------------- #

my $OPT_bar = 0;              # Whether to display progress bar
my $OPT_config = '';          # The configuration file
my $OPT_help = 0;             # Display man page
my $OPT_mcpat = '';           # McPAT file
my $OPT_ofile = '';           # Output file
my $OPT_prog = 0;							# Progressive run flag
my $OPT_root = [];            # Pointer to array of data directories
my $OPT_verbose = 0;          # Verbose flag
my $OPT_stats = 1;            # Which set of stats to use

my $config;                   # The configuration data structure
my @data;                     # Array of arrays to store the collected data

# --------------------------------------------------------------------------- #
# -------------------- E N V I R O N M E N T   S E T U P -------------------- #
# --------------------------------------------------------------------------- #

GetOptions('bar'         => \$OPT_bar,
           'config=s'    => \$OPT_config,
           'mcpat=s'     => \$OPT_mcpat,
           'root=s@'     => \$OPT_root,
           'verbose'     => \$OPT_verbose,
           'outfile=s'   => \$OPT_ofile,
           'help'        => \$OPT_help,
           'progressive' => \$OPT_prog,
           'stats=i'     => \$OPT_stats
          );

if($OPT_help)
{
  system("perldoc -T $0");
  exit 0;
}

print STDERR "Verbose mode\n" if $OPT_verbose;

die "ERROR: No --root option supplied\n" unless (@$OPT_root);
die "ERROR: no --config option supplied\n" unless ($OPT_config);
print STDERR "WARNING: No --mcpat option\n" unless ($OPT_mcpat);
if ($OPT_prog && !$OPT_ofile)
  {die "ERROR: Progressive mode without --outfile\n";}
if ($OPT_bar and !$OPT_ofile)
  {die "ERROR: Progress bar without --outfile\n";}
$| = 1 if ($OPT_bar);

unless ($config = do $OPT_config)
{
  die("couldn't parse config file: $@\n") if $@;
  die("couldn't do config file: $!\n")    unless defined $config;
  die("couldn't run config file\n")       unless $config;
}

# --------------------------------------------------------------------------- #
# ------------------- G A T H E R   D I R E C T O R I E S ------------------- #
# --------------------------------------------------------------------------- #

# Get all individual simulation directories from all roots and put them into
#   @dirs
# Weed out non-run directories and non-directories
# Remove already read directories if --progressive
my $root_handle;
my @dirs;
my $fin_max = -1;
my $l_max = -1;
foreach my $root (@$OPT_root)
{
  opendir $root_handle, $root or die "ERROR: Could not open $root\n";
  my @temp = readdir $root_handle;
  
  print "Reading $root\n" if ($OPT_bar);
  
  # See if anything's already been processed
  if ($OPT_prog and -e "$root/gather_log" and -f "$root/gather_log")
  {
    print STDERR "Found $root/gather_log\n" if ($OPT_verbose);
    my $handle;
    open($handle, '<', "$root/gather_log") or 
      die "ERROR: Could not open $root/gather_log\n";
    if ((<$handle>) =~ /(-?\d+)/){
      $fin_max = $1;}
    else {
      $fin_max = -1;}
    close $handle;
    print STDERR "Data gathered up to $fin_max\n" if ($OPT_verbose);
  }
  
  # Build list of directories
  my $one_perc = @temp ? 100/scalar(@temp) : 0;
  my $perc_complete = 0.0;
  drawBar(0) if ($OPT_bar);
  foreach my $dir (@temp)
  {
    if ($OPT_bar)
    {
      $perc_complete += $one_perc;
      drawBar($perc_complete);
    }
    next unless ($dir =~ /(\d{6})$/);
    if ($OPT_prog)
    {
      next if ($OPT_mcpat and !(-e "$root/$dir/$OPT_mcpat"));
      $l_max = $l_max < $1 ? $1 : $l_max;
      next if ($1 <= $fin_max);
    }
    push @dirs, "$root/$dir";
  }
  if ($OPT_bar)
  {
    drawBar(100);
    print "\n";
  }
  closedir $root_handle;
  
  # If progressive, note what will have been processed
  if ($OPT_prog)
  {
    print STDERR "Writing $l_max to log for next time\n" if ($OPT_verbose);
    my $handle;
    open($handle, '>', "$root/gather_log") or
      die "ERROR: Could not open $root/gather_log\n";
    print $handle $l_max;
    close $handle;
    $l_max = -1
  }
}


# --------------------------------------------------------------------------- #
# ------------------------ T H E   M A I N   L O O P ------------------------ #
# --------------------------------------------------------------------------- #

# Column width
my $width = 0;
my $one_perc = @dirs ? 100/scalar(@dirs) : 0;
my $perc_complete = 0.0;
if ($OPT_bar)
{
  print "Parsing\n";
  drawBar(0);
}

# Get the data
foreach my $dir (sort @dirs)
{
  next if $dir !~ /\/\d{6}$/;
  my $line = [];
  getConfig($dir, $config->{config}, $line);
  getStats($dir, $config->{stats}, $line);
  getLog($dir, $config->{log}, $line);
  getMcpat($dir, $config->{mcpat}, $line);
  push @data, $line;
  
  $width = $width > @$line ? $width : @$line;
  
  if ($OPT_bar)
  {
    $perc_complete += $one_perc;
    drawBar($perc_complete);
  }
}

if ($OPT_bar)
{
  drawBar(100);
  print "\n" ;
}

# --------------------------------------------------------------------------- #
# ------------------------ P R I N T   R E S U L T S ------------------------ #
# --------------------------------------------------------------------------- #

my $out_handle;
if ($OPT_ofile)
{
  if ($OPT_prog)
  {
    open($out_handle, '>>', $OPT_ofile) or 
      die "ERROR: Could not open $OPT_ofile for write\n";
  }
  else
  {
    open($out_handle, '>', $OPT_ofile) or 
      die "ERROR: Could not open $OPT_ofile for write\n";
  }
}
else
{
  $out_handle = \*STDOUT;
}

# Print the data
foreach my $line (@data)
{
  # Expand line to full width
  if (@$line < $width){
    $line->[$width-1] = undef;}
  
  for (my $i = 0; $i < @$line; $i++)
  {
    if (defined $line->[$i]){
      print $out_handle $line->[$i];}
    else{
      print $out_handle 'NA';}
    
    if ($i == @$line -1){
      print $out_handle "\n";}
    else{
      print $out_handle "\t";}
  }
}

exit 0; ### THE END ###

# --------------------------------------------------------------------------- #
# -------------------------- S U B R O U T I N E S -------------------------- #
# --------------------------------------------------------------------------- #

# get methods
# Extract the items in question and place them in the correct location in the
#   line
# Only recognizes the addition operation
sub getConfig
{
  my $dir = shift;
  my $items = shift;
  my $line = shift;
  
  return unless (@$items);
  return unless (-e "$dir/config.ini");
  my $handle;
  open($handle, '<', "$dir/config.ini") or return;
 
  my $numbered = expand($items);
#  my $tree = tree($numbered);
  my $uniques = uHash($numbered);
  
  my $current_base = '';
  
  while (my $line = <$handle>)
  {
    next if ($line =~ /^\s+$/);
    
    if ($line =~ /\[(.*)\]/)
    {
      $current_base = $1;
      next;
    }
    
    if (($line =~ /(.+)=(.+)/) and 
        (exists $uniques->{"$current_base.$1"})){
      $uniques->{"$current_base.$1"} = $2;}
  }
  
  close $handle;
  
  addToLine($numbered, $uniques, $line);
}

sub getStats
{
  my $dir = shift;
  my $items = shift;
  my $line = shift;
  
  return unless (@$items);
  return unless (-e "$dir/stats.txt");
  my $handle;
  open($handle, '<', "$dir/stats.txt") or return;
  
  # TODO: these could be static I think
  my $numbered = expand($items);
  my $uniques = uHash($numbered);
  
  my $statset = 0;
  
  while (my $line = <$handle>)
  {
    next if ($line =~ /^\s*$/);
    if ($line =~ /Begin Simulation Statistics/)
    {
      $statset++;
      next;
    }
    if ($line =~ /End Simulation Statistics/)
    {
      last if ($statset == $OPT_stats);
      next;
    }
    next if ($statset != $OPT_stats);
    if (($line =~ /^(\S+)\s+([\d\.\-]+|no_value|inf|nan)\s/) and
        (exists $uniques->{$1})){
      $uniques->{$1} = $2;}
  }
  
  close $handle;
  
  addToLine($numbered, $uniques, $line);
}

sub getLog
{
  my $dir = shift;
  my $items = shift;
  my $line = shift;
  
  my $dir_handle;
  my @files;
  my $handle;
  my $file = '';
  
  return unless (@$items);
  
  opendir($dir_handle, "$dir") or return;
  @files = readdir $dir_handle;
  close $dir_handle;
  
  foreach my $temp (@files){
    $file = $temp if $temp =~ /^ecdf-run_log/;}
  
  return unless ($file);
  open($handle, '<', "$dir/$file") or return;
  
  my $numbered = expand($items);
  my $uniques = uHash($numbered);
  
  while (my $line = <$handle>)
  {
    # Magic conf number parsing
    if (($line =~ /Generating configuration (\d+) from conf files/) and
        (exists $uniques->{_CONF_})){
      $uniques->{_CONF_}=$1;}
    
    # Regular parameter parsing
    next unless ($line =~ /^\+[^-]/);
    if (($line =~ /\+([\w_]+):"?([\w.\d_-]+)/) and
        (exists $uniques->{$1})){
      $uniques->{$1} = $2;}
  }
  
  close $handle;
  
  addToLine($numbered, $uniques, $line);
}

# Get McPAT report data
# Inputs: String with directory where to find report
#         Configuration array from conf file
#         Pointer to array for the current line of the table (results go here)
sub getMcpat
{
  my $dir = shift;
  my $items = shift;
  my $line = shift;
  
  return unless($OPT_mcpat);
  return unless(@$items);
  
  # Grab the McPAT tree
  print STDERR "Trying to parse $dir/$OPT_mcpat\n" if $OPT_verbose;
  my ($tree, $errors, $warnings) = parseOut("$dir/$OPT_mcpat");
  if (@$errors)
  {
    print STDERR "Found errors when parsing $dir/$OPT_mcpat\n"
      if ($OPT_verbose);
    return;
  }
  if (!defined $tree)
  {
    print STDERR "Could not get tree from $dir/$OPT_mcpat\n" if $OPT_verbose;
    return;
  }
  
  my $numbered = expand($items);
  my $uniques = uHash($numbered);
  
  foreach my $unique (keys %$uniques)
  {
    my $string = $unique;
    my $hash = $tree;
    my $key;
    
    # If magic value _SOLVED_ is used, check for constraint problems
    if ($string eq '_SOLVED_')
    {
      $uniques->{$unique} = 'TRUE';
      foreach my $warn (@$warnings)
      {
        if ($warn =~ /constraint/i)
        {
          $uniques->{$unique} = 'FALSE';
          last;
        }
      }
      next;
    }
    
    # While the key matches something with a period in it
    #   If the thing before the period is in $tree
    #     And the thing before the period is a reference
    #       Go down a level in $tree
    #     But if it's not a reference
    #       And there was something after the period
    #         Then there is a problem
    #       But if there was nothing after the period
    #         Then we're at the bottom of $tree
    #   But if the thing before the period is not in tree
    #     Then we have a problem
    while (defined($string) and 
      $string =~ /([\w \(\)\/]+)(?:\.([\w .\(\)\/]+))?/)
    {
      $key = $1;
      $string = $2;
      if (defined $hash->{$key})
      {
        print STDERR "$key\n" if $OPT_verbose;
        if (ref $hash->{$key})
        {
          $hash = $hash->{$key};
          print STDERR "Matched $key; remaining: $string\n" if $OPT_verbose;
        }
        else
        {
          if (defined $string)
          {
            print STDERR "Found dangling string $string\n" if $OPT_verbose;
            last;
          }
          $uniques->{$unique} = $hash->{$key};
        }
      }
      else
      {
        print STDERR "$key not defined in \$tree\n" if $OPT_verbose;
        last;
      }
    }
  }
  
  addToLine($numbered, $uniques, $line);
}

# Expand an array of items into a hash
# For the time being, only recognize the addition operation between individual
#   items
# Hash is of the form:
# %h = {1 => [item],
#       4 => [add_item, add_item],
#       ...
#      }
# Input:  Pointer to array of items where each item is of form '#!item'
# Return: Pointer to hash
sub expand
{
  my $items = shift;
  
  my $hash = {};
  
  foreach my $item (@$items)
  {
    $item =~ /(\d+)!(.+)/;
    $hash->{$1} = $2;
  }
  
  foreach my $key (keys %$hash)
  {
    $hash->{$key} = [split(q/\+/, $hash->{$key})];
  }
  
  return $hash;
}

# Generate a hierarchical tree of items from the values in a numbered hash
# Hash is of the form:
# $h = {head1 => [subh1 = {subsubh => {}},
#                 subh2 = {}
#                ],
#       head2 => {},
#       ...
#       }
# Input:  Pointer to hash from expand()
# Return: Pointer to this tree hash
sub tree
{
  my $numbered = shift;
  my $tree = {};
  
  foreach my $key (keys %$numbered)
  {
    foreach my $item (@{$numbered->{$key}})
    {
      my $temp = $item;
      my $temp_hash = $tree;
      while ($item =~ /(.+?)\.(.+)/)
      {
        $temp = $2;
        $temp_hash->{$1} = {} unless exists $temp_hash->{$1};
        $temp_hash = $temp_hash->{$1};
      }
    }
  }
  
  return $tree;
}

# Take a numbered hash from expand() and create a hash of all the items in
#   the value arrays as keys (u == unique). Values should be filled in later.
# Format:
#   $hash-> {unique_key_1 => undef, unique_key_2 => undef, ...}
# Input:  Pointer to numbered hash from expand()
# Return: Pointer to hash
sub uHash
{
  my $numbered = shift;
  my $hash = {};
  
  foreach my $key (keys %$numbered)
  {
    foreach my $item (@{$numbered->{$key}})
    {
      my $temp = $item;
      $hash->{$temp} = undef;
    }
  }
  
  return $hash;
}

# For every array item in the numbered hash, replace the item with its value
# Then add up the values if more than one per key
# And finally place the values in the row array
# Input:  pointer to numbered hash
#         pointer to uniques hash
#         pointer to line array
sub addToLine
{
  my $numbered = shift;
  my $uniques = shift;
  my $line = shift;
  
  foreach my $key (keys %$numbered)
  {
    foreach my $item (@{$numbered->{$key}}){
      $item = $uniques->{$item};}
    
    if (@{$numbered->{$key}} > 1)
    {
      my $temp = 0;
      foreach my $val (@{$numbered->{$key}})
      {
        if (!defined($val) or $val =~ /nan/)
        {
          undef($temp);
          last;
        }
        $temp+=$val;
      }
      $numbered->{$key} = [$temp];
    }
    
    $line->[$key-1] = $numbered->{$key}->[0];
  }
}

# Draw progress bar
# Input: Completed percentage
sub drawBar
{
  my $perc_complete = shift;
  
  print '[';
  print '=' x int($perc_complete);
  print '|' unless ($perc_complete >= 100);
  print ' ' x (99-int($perc_complete));
  print '] ';
  print sprintf("%.2f%%", $perc_complete);
  print "\b" x 120;
}









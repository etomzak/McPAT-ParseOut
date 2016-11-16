# McPAT::ParseOut.pm -- Parses output from McPAT
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

package McPAT::ParseOut;
require Exporter;
@ISA = (Exporter);
@EXPORT = qw(parseOut treeSanity treeCmp $TOL);
use strict;
use Carp;
use Scalar::Util qw(looks_like_number);

=head1 McPAT::ParseOut

B<McPAT::ParseOut> is a set of utilities for working with reports from
McPAT. It is known to work with McPAT 0.8.

=cut

# This value was determined empirically; works, but *might* need to be adjusted
our $TOL = 0.000006;

=head2 Methods

=head2 parseOut()

C<($tree, $errors, $warnings) = parseOut('McPAT_output')>

parseOut() parses a McPAT output file into a tree-like hash of hashes
and returns a pointer to the root of the tree, or undef in case of
errors. 'McPAT_output' is the name of a file containing output piped
from McPAT. Errors and warnings encountered while parsing are stored
in arrays pointed to by $errors and $warnings, respectively.
@$warnings contains failed constraint messages.

parseOut() attempts to return normally and to avoid dying, exiting,
croaking, carping, crapping out, etc. if at all possible. parseOut()
is intended for use in scripts that parse potentially 1000s of McPAT
output files, and one corrupt output file should not stop the script.
Sanity checking the return values is mandatory.

=cut

sub parseOut
{
  my $errors   = [];
  my $warnings = [];
  
  unless(@_)
  {
    push @$errors, "Input file required for parsing";
    return (undef, $errors, $warnings);
  }

  my $file = shift;
  
  unless(-e $file)
  {
    push @$errors, "Input file '$file' doesn't exist";
    return (undef, $errors, $warnings);
  }
  
  my $handle;
  unless(open($handle, '<', $file))
  {
    push @$errors, "Could not open $file";
    return (undef, $errors, $warnings);
  }
  
  my $tree = {};
  my @stack = ($tree);
  
  my $proc  = 0;
  my $core  = 0;
  my $l2    = 0;
  my $mem_c = 0;
  my $noc   = 0;
  my $l3    = 0;
  my $fld   = 0;
  my $niu   = 0;
  my $pcie  = 0;
  my $buses = 0;
  
  my $level = 0;
  my $temp_l;
  
  $tree -> {_DEPTH_} = 0;
  
  my $val_re = qr/([a-zA-Z ]+)|(?:([-0-9\.e]+)\s*(?:W|mm\^2))/;
  
  # Work through McPAT output and build a tree of the data
  # This would be much simpler if McPAT's output indentation were always
  #   two spaces
  while (my $line = <$handle>)
  {
    chomp $line;
    next if ($line =~ /^\*+$/);
    next if ($line =~ /^\s*$/);
    
    if (!$proc and $line =~ /^Processor:/)
    {
      $proc = 1;
      $level = 0;
      $core = $l2 = $mem_c = $noc = $l3 = $niu = $pcie = $fld = $buses = 0;
      @stack = ($tree);
      next;
    }
    # Technically, these look like level 0 in the file, but subheadings don't
    #   start until level 3, and logically these are under the processor
    # Technically, each of these could be instantiated a number of times, but
    #   since the data is for one instance, _COUNT_ is set to 1
    if (!$core and $line =~ /^Core/)
    {
      $core = 1;
      $level = 1;
      $proc = $l2 = $mem_c = $noc = $l3 = $niu = $pcie = $fld = $buses = 0;
      $tree->{Core} = {_DEPTH_=>1, _COUNT_=>1};
      @stack = ($tree, $tree->{Core});
      next;
    }
    if (!$l2 and $line =~ /^L2/)
    {
      $l2 = 1;
      $level = 1;
      $proc = $core = $mem_c = $noc = $l3 = $niu = $pcie = $fld = $buses = 0;
      $tree->{L2} = {_DEPTH_=>1, _COUNT_=>1};
      @stack = ($tree, $tree->{L2});
      next;
    }
    if (!$mem_c and $line =~ /^Memory Controller/)
    {
      $mem_c = 1;
      $level = 1;
      $proc = $core = $l2 = $noc = $l3 = $niu = $pcie = $fld = $buses = 0;
      $tree->{'Memory Controller'} = {_DEPTH_=>1, _COUNT_=>1};
      @stack = ($tree, $tree->{'Memory Controller'});
      next;
    }
    if (!$noc and $line =~ /^NOC/)
    {
      $noc = 1;
      $level = 1;
      $proc = $core = $l2 = $mem_c = $l3 = $niu = $pcie = $fld = $buses = 0;
      $tree->{NOC} = {_DEPTH_=>1, _COUNT_=>1};
      @stack = ($tree, $tree->{NOC});
      next;
    }
    if (!$l3 and $line =~ /^( {6}|)L3/)# b/c L3 has some nasty indentation
    {
      $l3 = 1;
      $level = 1;
      $proc = $core = $l2 = $mem_c = $noc = $niu = $pcie = $fld = $buses = 0;
      $tree->{L3} = {_DEPTH_=>1, _COUNT_=>1};
      @stack = ($tree, $tree->{L3});
      next;
    }
    if (!$fld and $line =~ /^First Level Directory/)
    {
      $fld = 1;
      $level = 1;
      $proc = $core = $l2 = $mem_c = $noc = $l3 = $niu = $pcie = $buses = 0;
      $tree->{'First Level Directory'} = {_DEPTH_=>1, _COUNT_=>1};
      @stack = ($tree, $tree->{'First Level Directory'});
      next;
    }
    if (!$niu and $line =~ /^NIU/)
    {
      $niu = 1;
      $level = 1;
      $proc = $core = $l2 = $mem_c = $noc = $l3 = $fld = $pcie = $buses = 0;
      $tree->{NIU} = {_DEPTH_=>1, _COUNT_=>1};
      @stack = ($tree, $tree->{NIU});
      next;
    }
    if (!$pcie and $line =~ /^PCIe/)
    {
      $pcie = 1;
      $level = 1;
      $proc = $core = $l2 = $mem_c = $noc = $l3 = $fld = $niu = $buses = 0;
      $tree->{PCIe} = {_DEPTH_=>1, _COUNT_=>1};
      @stack = ($tree, $tree->{PCIe});
      next;
    }
    if (!$buses and $line =~ /^BUSES/)
    {
      $buses = 1;
      $level = 1;
      $proc = $core = $l2 = $mem_c = $noc = $l3 = $fld = $niu = $pcie = 0;
      $tree->{BUSES} = {_DEPTH_=>1, _COUNT_=>1};
      @stack = ($tree, $tree->{BUSES});
      next;
    }
    
    # If we aren't inside any of the interesting bits, check for constraint
    #   and other problems
    unless ($proc or $core or $l2 or $mem_c or $noc or $l3 or $fld or $niu 
            or $pcie or $buses)
    {
      if ($line =~ /error/i)
        {push @$errors, $line;}
      if ($line =~ /constraint/)
      {
        $line =~ s/Warning:\s+//;
        push @$warnings, $line;
      }
      next;
    }

    $temp_l = _getLevel($line);
    
    # Simplify parsing by indenting "Device Type=..." lines
    $temp_l+=1 if ($line =~ /^\s*Device Type/);
    
    # If the line is a heading
    if (($proc and $line =~ /\s*([\w \(\)\/]+)\s*:\s*(\d+)?/) or 
        (!$proc and 
           $line =~ /^\s*([\w \(\)\/]+)(?:\s+\(Count: (\d+)\s*\))?:\s*$/))
    {
      my $head = $1;
      my $count = $2;
      
      # If the new heading is not nested within the current heading, back out
      if ($temp_l <= $level)
      {
        while ($stack[-1] -> {_DEPTH_} >= $temp_l){
          pop @stack;}
      }
      
      # Create a hash for the new level
      $stack[-1] -> {$head} = {};
      push @stack, $stack[-1] -> {$head};
      $stack[-1] -> {_DEPTH_} = $temp_l;
      $stack[-1] -> {_COUNT_} = defined($count) ? $count : 1;
    }
    # Else if it's a key-value pair
    elsif ($line=~/\s*([\w ]+?)\s*=\s*(?:$val_re)$/)
    {
      my $key = $1;
      my $val = defined($2) ? $2 : $3;
      if ($key eq 'Area Overhead')
      {
        push @$warnings, "Found an 'Area Overhead' key";
        $key = 'Area';
      }
      if ($temp_l < $level)
      {
        push @$errors, "ERROR: key-value pair '$line' under no particular " .
                       "heading";
      }
      else{
        $stack[-1] -> {$key} = $val;}
    }
    else
    {
      push @$warnings, "Unmatched line:'$line'";
    }
    
    $level = $temp_l;
  }
  
  close $handle;
  return ($tree, $errors, $warnings);
}

=head2 treeSanity()

C<($errors, $warnings) = treeSanity($tree)>

treeSanity() takes a pointer to hash of hashes (such as the one
produced by parseOut()) and performs sanity checks. Any errors it
finds will be stored in @$errors; warnings are in @$warnings.

treeSanity() is still experimental. It gets confused by some McPAT
features and cannot handle some McPAT magic.

=cut

sub treeSanity
{
  my $tree = shift;
  my $errors = [];
  my $warnings = [];
  
  unless(defined $tree)
  {
    push @$errors, '$tree is undefined';
    return ($errors, $warnings);
  }
  
  # First, check that the to level components' values match between their two
  #   appearances
  _topSanity($tree, $errors, $warnings);
  
  # Next, check the whole processor values against the top-level components
  _procSanity($tree, $errors, $warnings);
  
  # Finally, recursively check that all the components' values add up
  foreach my $comp ('Core', 'L2', 'Memory Controller', 'NOC')
  {
    my ($l_err) = _recSanity($tree->{$comp});
    foreach my $err (@$l_err){
      $err = "[$comp]$err";}
    push @$errors, @$l_err;
  }
  
  return($errors, $warnings);
}

=head2 treeCmp()

C<($eq, $errors) = treeCmp($tree1, $tree2)>

treeCmp() compares two tree-like hashes from parseOut(). It returns a
1 in $eq if the trees are identical and 0 otherwise. @$errors contains
errors.

=cut

sub treeCmp
{
  my $tree1 = shift;
  my $tree2 = shift;
  
  my $errors = [];
  # Turning $verbose on will pipe lots of debug info to STDERR
  my $verbose = 0;
  
  if ($verbose){
    open(ERRH, ">&STDERR") or die "VERBOSITY ERROR\n";}
  else{
    open(ERRH, '>', "/dev/null") or die "UNEXPECTED ERROR\n";}
  
  _hashCmp($tree1, $tree2, $errors);
  
  close ERRH;
  
  return (@$errors ? 0 : 1, $errors);
}

# Returns the nested-ness of a line
# "nested-ness" is defined as leading white space / 2
# Input:  a string
# Return: an int
sub _getLevel
{
  my $string = shift;
  $string =~ /^(\s*)/;
  return (length($1) >> 1);
}

# Checks that the two sets of overall component reports are identical
# Any problems are reported in either errors or warnings
# Input: $tree, $errors, $warnings
sub _topSanity
{
  my $tree = shift;
  my $errors = shift;
  my $warnings = shift;
  
  _topSanityCmp($tree, 'Total Cores', 'Core', $errors);
  _topSanityCmp($tree, 'Total L2s', 'L2', $errors);
  _topSanityCmp($tree, 'Total NoCs (Network/Bus)', 'NOC', $errors);
  _topSanityCmp($tree, 'Total MCs', 'Memory Controller', $errors);
}

# Checks two top-level component reports (e.g. 'Total Cores' vs. 'Core')
# Input: $tree, 'Name1', 'Name2', $errors
sub _topSanityCmp
{
  my $tree = shift;
  my $a = shift;
  my $b = shift;
  my $errors = shift;
  
  my $error = 0;
  
  unless (defined $tree->{$a})
  {
    push @$errors, "Could not find data for [$a]";
    $error = 1;
  }
  
  unless (defined $tree->{$b})
  {
    push @$errors, "Could not find data for [$b]";
    $error = 1;
  }
  
  return if $error;
  
  foreach my $comp ('Area', 'Peak Dynamic', 'Subthreshold Leakage',
                    'Gate Leakage', 'Runtime Dynamic')
  {
    $error = 0;
    unless (exists $tree->{$a}->{$comp} and defined $tree->{$a}->{$comp})
    {
      push @$errors, "Could not find [$a]>[$comp]";
      $error = 1;
    }
    
    unless (exists $tree->{$b}->{$comp} and defined $tree->{$b}->{$comp})
    {
      push @$errors, "Could not find [$b]>[$comp]";
      $error = 1;
    }
    
    next if $error;
    
    # _COUNT_ multipliers are swapped because _COUNT_==2 says "this counts
    #   twice"
    unless (_fcmp($tree->{$a}->{$comp} * $tree->{$b}->{_COUNT_},
                  $tree->{$b}->{$comp} * $tree->{$a}->{_COUNT_}))
    {
      push @$errors, "[$a]>[$comp] and [$b]>[$comp] do not match: " .
                     "$tree->{$b}->{_COUNT_}x $tree->{$a}->{$comp} vs. " .
                     "$tree->{$a}->{_COUNT_}x $tree->{$b}->{$comp}";
    }
  }  
}

# Check the whole processor values against the top-level components
# Does not complain about missing values since this gets handled in
#   _topSanity()
# Input: $tree, $errors, $warnings
sub _procSanity
{
  my $tree = shift;
  my $errors = shift;
  my $warnings = shift;
  
  my $area          = 0;
  my $peak_power    = 0;
  my $total_leakage = 0;
  my $peak_dynamic  = 0;
  my $sub_leakage   = 0;
  my $gate_leakage  = 0;
  my $run_dyn       = 0;
  
  foreach my $comp ('Total Cores', 'Total L2s', 'Total NoCs (Network/Bus)',
                    'Total MCs')
  {
    if (defined $tree->{$comp}->{'Area'}){
      $area += $tree->{$comp}->{'Area'};}
    if (defined $tree->{$comp}->{'Peak Dynamic'}){
      $peak_dynamic += $tree->{$comp}->{'Peak Dynamic'};}
    if (defined $tree->{$comp}->{'Subthreshold Leakage'}){
      $sub_leakage += $tree->{$comp}->{'Subthreshold Leakage'};}
    if (defined $tree->{$comp}->{'Gate Leakage'}){
      $gate_leakage += $tree->{$comp}->{'Gate Leakage'};}
    if (defined $tree->{$comp}->{'Runtime Dynamic'}){
      $run_dyn += $tree->{$comp}->{'Runtime Dynamic'};}
  }
  
  $total_leakage = $sub_leakage + $gate_leakage;
  $peak_power = $peak_dynamic + $total_leakage;
  
  my @temp = ($area, $peak_power, $total_leakage, $peak_dynamic, $sub_leakage,
              $gate_leakage, $run_dyn);
  
  foreach my $item ('Area', 'Peak Power', 'Total Leakage', 'Peak Dynamic',
                    'Subthreshold Leakage', 'Gate Leakage', 'Runtime Dynamic')
  {
    my $val = shift(@temp);
    unless (_fcmp($tree->{$item}, $val)){
      push @$errors, "Top-level [$item] does not add up to its components: " .
        "is $tree->{$item} but expected $val";}
  }
}

# Recursively check that a component's sub-components' values add up
# Input:  $comp (where %$comp is the component)
# Return: ($err, $area, $peak_dyn, $sub_leak, $gate_leak, $run_dyn)
#   where @$err is an array of errors
sub _recSanity
{
  my $comp = shift;
  my $l_err = [];
  
  my $area;
  my $peak_dyn;
  my $sub_leak;
  my $gate_leak;
  my $run_dyn;
  
  my $c_area      = 0;
  my $c_peak_dyn  = 0;
  my $c_sub_leak  = 0;
  my $c_gate_leak = 0;
  my $c_run_dyn   = 0;
  
  my $children = 0;
  
  foreach my $c ('Area', 'Peak Dynamic', 'Subthreshold Leakage',
                 'Gate Leakage', 'Runtime Dynamic')
  {
    unless (defined $comp->{$c}){
      push @$l_err, ">[$c] does not exist";}
  }
  
  foreach my $key (keys %$comp)
  {
    next if ($comp->{$key} eq '_DEPTH_' or $comp->{$key} eq '_COUNT_' );
    # 'Local Predictor' (not to be confuses with 'L1_Local Predictor' or
    #   'L2_Local Predictor) is a weird, special case
    next if ($key eq 'Local Predictor');
    
    if ($key eq 'Area'){
      $area = $comp->{$key} * $comp->{_COUNT_};}
    elsif ($key eq 'Peak Dynamic'){
      $peak_dyn  = $comp->{$key} * $comp->{_COUNT_};}
    elsif($key eq 'Subthreshold Leakage'){
      $sub_leak  = $comp->{$key} * $comp->{_COUNT_};}
    elsif($key eq 'Gate Leakage'){
      $gate_leak = $comp->{$key} * $comp->{_COUNT_};}
    elsif($key eq 'Runtime Dynamic'){
      $run_dyn   = $comp->{$key} * $comp->{_COUNT_};}
    
    if (ref ($comp->{$key}))
    {
      $children++;
      
      my ($err, $v, $w, $x, $y, $z) = _recSanity($comp->{$key});
      $c_area      += $v;
      $c_peak_dyn  += $w;
      $c_sub_leak  += $x;
      $c_gate_leak += $y;
      $c_run_dyn   += $z;
      
      foreach my $e (@$err){
        $e = ">[$key]$e";}
      push @$l_err, @$err;
    }
  }
  
  if ($children)
  {
    if (defined($area) and !_fcmp($area, $c_area)){
      push @$l_err, ">[Area] does not add up: " .
                      "expected $area, but calculated $c_area";}
    if (defined($peak_dyn) and !_fcmp($peak_dyn, $c_peak_dyn)){
      push @$l_err, ">[Peak Dynamic] does not add up: " .
                       "expected $peak_dyn, but calculated $c_peak_dyn";}
    if (defined($sub_leak) and !_fcmp($sub_leak, $c_sub_leak)){
      push @$l_err, ">[Subthreshold Leakage] does not add up: " .
                       "expected $sub_leak, but calculated $c_sub_leak";}
    if (defined($gate_leak) and !_fcmp($gate_leak, $c_gate_leak)){
      push @$l_err, ">[Gate Leakage] does not add up: " .
                       "expected $gate_leak, but calculated $c_gate_leak";}
    if (defined($run_dyn) and !_fcmp($run_dyn, $c_run_dyn)){
      push @$l_err, ">[Runtime Dynamic] does not add up: " .
                       "expected $run_dyn, but calculated $c_run_dyn";}
  }
  
  $area      = 0 unless defined($area);
  $peak_dyn  = 0 unless defined($peak_dyn);
  $sub_leak  = 0 unless defined($sub_leak);
  $gate_leak = 0 unless defined($gate_leak);
  $run_dyn   = 0 unless defined($run_dyn);
  
  return ($l_err, $area, $peak_dyn, $sub_leak, $gate_leak, $run_dyn);
  
}

# Recursively compare two hashes
# Input: \%hash1, \%hash2, \@errors
sub _hashCmp
{
  my $tree1 = shift;
  my $tree2 = shift;
  my $errors = shift;
  
  # First do a reverse key check
  print ERRH "Reverse check\n";
  foreach my $key (keys %$tree2)
  {
    print ERRH "Checking that LHS has $key...";
    unless (exists $tree1->{$key})
    {
      push @$errors, "[$key] is missing on LHS";
      print ERRH "no\n";
    }
    print ERRH "yes\n";
  }
  
  # Then do a forward key and value check
  print ERRH "Forward check\n";
  foreach my $key (keys %$tree1)
  {
    print ERRH "Checking $key\n";
    unless (exists $tree2->{$key})
    {
      push @$errors, "[$key] is missing on RHS";
      print ERRH "  RHS doesn't have $key\n";
      next;
    }
    unless (defined $tree1->{$key})
    {
      push @$errors, "[$key] does not have value or child on LHS";
      print ERRH "  $key is not defined\n";
      next;
    }
    unless (defined $tree2->{$key})
    {
      push @$errors, "[$key] does not have value or child on RHS";
      print ERRH "  $key not defined on RHS\n";
      next;
    }
    
    if (ref $tree1->{$key})
    {
      print ERRH "  $key is a reference\n";
      if (ref $tree2->{$key})
      {
        print ERRH "  $key is also a reference on RHS\n";
        my $c_err = [];
        print ERRH "  Descending into $key\n";
        _hashCmp($tree1->{$key}, $tree2->{$key}, $c_err);
        foreach my $err (@$c_err){
          $err = "[$key]>$err";}
        push @$errors, @$c_err;
      }
      else
      {
        print ERRH "  $key has child on LHS but not RHS\n";
        push @$errors, "[$key] has child on LHS but not RHS";
      }
      next;
    }
    
    if (ref $tree2->{$key})
    {
      print ERRH "  $key has child on RHS but not LHS\n";
      push @$errors, "[$key] has child on RHS but not LHS";
      next;
    }
    # Check the two values are identical
    else
    {
      print ERRH "  Checking that $tree1->{$key} and $tree2->{$key} are " .
        "identical\n";
      # Check data type
      if (looks_like_number($tree1->{$key}) xor
          looks_like_number($tree2->{$key}))
      {
        print ERRH "  One is numeric, the other isn't\n";
        push @$errors, "[$key] has both a string and a numeric value";
        next;
      }
      if (looks_like_number($tree1->{$key}))
      {
        unless (_fcmp($tree1->{$key}, $tree2->{$key}))
        {
          print ERRH "  -NUMERIC MISMATCH-\n";
          push @$errors, "[$key] mismatch";
        }
      }
      else
      {
        unless ($tree1->{$key} eq $tree2->{$key})
        {
          print ERRH "  -STRING MISMATCH-\n";
          push @$errors, "[$key] mismatch";
        }
      }
      print ERRH "  -END TEST- ($key)\n\n";
    }
  }
  print ERRH "  -RETURN-\n\n";
}

# floating point equality test with tolerance
# This version inspired by: http://stackoverflow.com/questions/21265/
#   comparing-ieee-floats-and-doubles-for-equality
# Input:  Two floating point numbers
# Return: 1 for equal, 0 for unequal
sub _fcmp
{
  my $a = shift;
  my $b = shift;
  
  if (abs($b) > abs($a))
  {
    return 1 if $b==0.0; # probably not needed
    return (abs(($a - $b) / $b) < $TOL);
  }
  else
  {
    return 1 if $a==0.0;
    return (abs(($a - $b) / $a) < $TOL);
  }
}

1;
__END__


=head2 Global variables

=head2 I<$TOL>

I<$TOL> controls the tolerance of floating-point comparisons. It
defaults to 0.000006, but can be set to anything else if you want to
shoot yourself in the foot. For example, $TOL=0.501 means that
2.0 == 1.0.

=cut

=head2 Known bugs

Adding a colon to the top-level "L2" causes a crash.

The script is oblivious to the top-level "Second Level Directory".

=cut

=head1 COPYRIGHT

McPAT::ParseOut.pm  Copyright (C) 2016  Erik Tomusk

This software is licensed under GPL-3.0 and comes with ABSOLUTELY NO
WARRANTY.
This is free software, and you are welcome to redistribute it under
certain conditions; see L<http://www.gnu.org/licenses/>.

=cut

# McPAT::M5XML.pm -- Fill in template McPAT XML file with gem5 info
# Copyright (C) 2016  Erik Tomusk
# Derived from the m5-mcpat.pl script by Andrew Rice
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

package McPAT::M5XML;
require Exporter;
@ISA = (Exporter);
@EXPORT = qw(m5xml stats_number);
use strict;
use Carp;

=head1 McPAT::M5XML

B<McPAT::M5XML> is used to convert gem5 data to a McPAT XML file.

=cut

=head2 Methods

=head2 m5xml

C<($errors, $warnings) = m5xml($stats, $config, $template, $xml)>

m5xml() replaces the m5-mcpat.pl script as the method of converting
from gem5 to McPAT. Inputs are paths to the three files (stats.txt,
config.ini, XML template) and the path to where the output should go.

m5xml() attempts to return normally regardless of conditions
encountered. Pointers to an array of errors and an array of warnings
are returned and should certainly be checked.

=head2 $stats_number

In case gem5's stats.ini file contains more than one set of stats,
$McPAT::M5XML::stats_number can be set to select which set should be
used. Defaults to 1 (the first set).

=cut

our $stats_number = 1;

my $errors;
my $warnings;
my $stats;
my $config;
my $mcpatxml;

sub m5xml
{
  my $stats_file  = shift;
  my $config_file = shift;
  my $template    = shift;
  my $out_file    = shift;
  my $handle;
  
  $errors = [];
  $warnings = [];

  $stats    = _loadStats($stats_file);
  $config   = _loadConfig($config_file);
  $mcpatxml = _loadxml($template);
  
  if (!(keys %$stats) or !(keys %$config) or $mcpatxml eq '') {
    return($errors, $warnings);}
  
  $mcpatxml =~ s/value="{(.*?)}"/'value="'.&_subst($1).'"'/ge;
  
  unless (open($handle, '>', $out_file))
  {
    push @$errors, "Failed open for write $out_file";
    return ($errors, $warnings);
  }
  
  print $handle $mcpatxml;
  
  close $handle;
  
  return ($errors, $warnings);
}


# Load stats.txt file into a hash
#  Input:  String with file name
#  Return: Pointer to hash of data or hash with no members in case of errors
sub _loadStats
{
  my $file = shift;
  my $result = {};
  my $handle;
  my $beCtr = 0;
  
  unless (open($handle, '<', "$file"))
  {
    push @$errors, "Failed to open stats file $file";
    return {};
  }
  
  my $statset = 0;
  
  while (my $line = <$handle>)
  {
    next if ($line =~ /^\s*$/);
    if ($line =~ /Begin Simulation Statistics/)
    {
      $statset++;
      $beCtr++;
      next;
    }
    if ($line =~ /End Simulation Statistics/)
    {
      $beCtr++;
      last if ($statset == $stats_number);
      next;
    }
    next if ($statset != $stats_number);
    if ($statset == $stats_number and 
        $line =~ /^(\S+)\s+([\d\.\-]+|no_value|inf|nan)\s/){
      $result->{$1} = $2;}
  }

  close($handle);
  if ($beCtr % 2 or $statset != $stats_number)
  {
    push @$errors, 'Incomplete stats file';
    return {};
  }
  return $result;
}


# Load config.ini file into a hash
#  Input:  String with file name
#  Return: Pointer to hash of data or hash with no members in case of errors
sub _loadConfig
{
  my $file = shift;
  my $result = {};
  my $current = '';
  my $handle;
  
  unless (open($handle, '<', "$file"))
  {
    push @$errors, "Failed to open config file $file";
    return {};
  }
  
  while(my $line = <$handle>)
  {
    chomp($line);
    if ($line =~ /\[(.*)\]/) {
      $current = $1;
    }
    elsif ($line =~ /(.*)=(.*)/) {
      $result->{$current.".".$1} = $2;
    }
    elsif ($line =~ /^\s*$/) {}
    else
    {
      push @$errors, "Failed to parse config $line";
      return {};
    }
  }
  
  close($handle);
  return $result;
}


# Load XML template file to a string
#  Input:  String with file name
#  Return: File in string or empty string in case of errors
sub _loadxml
{
  my $file = shift;
  my $result = "";
  my $handle;

  unless (open($handle, '<', "$file"))
  {
    push @$errors, "Failed to open xml file $file";
    return $result;
  }

  while(my $line = <$handle>) {
    $result .= $line;}

  close($handle);
  return $result;
}


# Substitute {} entries in template with the appropriate values
#  Input:  String to substitute
#  Return: The string with the substitution done
sub _subst
{
  my ($e) = @_;
  my $f = $e;
  $e =~ s/stats.([\w\d\.:]+)(?:\|([\w\d\.]))?/&_default(q(s), $1, $2)/ge;
  $e =~ s/config.([\w\d\.:]+)(?:\|([\w\d\.]))?/&_default(q(c), $1, $2)/ge;
  my $r = eval $e;
  unless (defined $r)
  {
    push @$warnings, "Evaluated to undefined: $f";
    return '';
  }
  if ($r eq "")
  {
    push @$errors, "Evaluated to empty $f";
  }
  return $r;
}


# Handle default value substitution for _subst()
#  Input:  String with 's' or 'c' for stats or config
#          String to substitute
#          Optional default value
#  Return: Final string
sub _default
{
  my ($t, $p, $d) = @_;
  if ($t eq 's')
  {
    return $stats->{$p} if defined $stats->{$p};
    return $d if defined $d;
    push @$warnings, "No known value for stats.$p";
    return 0;
  }
  elsif ($t eq 'c')
  {
    return $config->{$p} if defined $config->{$p};
    return $d if defined $d;
    push @$warnings, "No known value for config.$p";
    return 0;
  }
  else {
    push @$warnings, "Bad type in default()";}
    
  return 0;
}


1;

=head2 Known bugs

None

=cut

=head1 COPYRIGHT

McPAT::M5XML.pm  Copyright (C) 2016  Erik Tomusk

Incorporates code from the m5-mcpat.pl script by Andrew Rice. See
https://www.cl.cam.ac.uk/~acr31/sicsa/

This software is licensed under GPL-3.0 and comes with ABSOLUTELY NO
WARRANTY.
This is free software, and you are welcome to redistribute it under
certain conditions; see L<http://www.gnu.org/licenses/>.

=cut

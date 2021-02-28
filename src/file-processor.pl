use strict;
use warnings;
use Term::ANSIColor;
use File::Spec;

# TODO: track file as they are included <- done?

my $main_file=shift;
my $output_file=shift;
my @search_dirs=@ARGV;

my $find_search=join(' ', map("'$_'", @search_dirs));

my $output;
if ("$output_file" eq "-") {
  $output = *STDOUT;
}
else {
  open($output, '>:encoding(UTF-8)', $output_file)
    or die "Could not open file '$output_file'";
}

my $sourced_files = {};

sub printErr {
  my $msg = shift;

  print STDERR color('red');
  print STDERR "$msg\n";
  print STDERR color('reset');
}

sub process_file {
  my $input_file = shift;
  my $input_abs = $input_file =~ m|^/| && $input_file || File::Spec->rel2abs($input_file);
  my $source_base=($input_file =~ m|^(.*)/| ? $1 : ""); # that's 'dirname'
  if ($sourced_files->{$input_abs}) {
    # TODO: if 'verbose'
    # print "Dropping additional inclusion of '$input_file'.\n";
    return;
  }
  $sourced_files->{$input_abs} = 1;

  open(my $input, '<:encoding(UTF-8)', $input_file)
    or die "Could not open file '$input_file'";

  while (<$input>) {
    # Tried to do the 'comment' check as a negative lookahead, but was tricky.
    if ($_ !~ /#.*import\s+/ && /(^|;|do +|then +)\s*import\s+([^;\s]+)/) {
      my $pattern=$2;
      # In an earlier version, had tried to use '-not -name', but the need to
      # use parens to group the tests seemed to cause problems with running the
      # embedded script.
      # TODO: but why do we want '*$pattern*'? The first match should be enough...
      my $source_name=`find $find_search -name "$pattern*" -o -path "*$pattern*" | grep -v "\.test\." | grep -v "\.seqtest\."`;
      my $source_count = split(/\n/, $source_name);
      if ($source_count > 1) {
        printErr "Ambiguous results trying to import '$1' in file $input_file".'@'."$.";
        die 10;
      }
      elsif ($source_count == 0) {
        printErr "No source found trying to import '$1' in file $input_file".'@'."$.";
        die 10;
      }
      else {
        chomp($source_name);
        process_file($source_name);
      }
    }
    elsif ($_ !~ /#.*source\s+/ && m:(^|;|do +|then +)\s*source\s+((\./)?([^;\s]+)):) {
      my $next_file="$source_base/$4";
      my $source_spec="$2";
      if ($next_file =~ /\$/) {
        print "Leaving dynamic source: '$source_spec' in $input_file".'@'."$.\n";
        print $output $_;
      }
      elsif (-f "$next_file") {
        process_file($next_file);
      }
      else {
        printErr "No source found trying to source '$source_spec' in file $input_file".'@'."$.";
        print $output $_;
      }
    }
    else {
      print $output $_;
    }
  }
}

process_file($main_file);

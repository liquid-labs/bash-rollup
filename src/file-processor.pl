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
  my $no_recur = shift || 0;
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
    if ($no_recur) {
      print $output $_;
    }
    # Tried to do the 'comment' check as a negative lookahead, but was tricky.
    elsif ($_ !~ /#.*import\s+/ && /(^|;|do +|then +)\s*import\s+([^;\s]+)/) {
      my $pattern=$2;
      # sharpen the match to a standard '<name>.*=<content type>.sh' if not specified.
      $pattern !~ /\.$/ and $pattern .= '.';
      # Note, we *do* follow links and limit depth to 4.
      # TODO: in future, these can be turned into options if use case presents
      my $source_name=`find -L $find_search -maxdepth 4 -path "*/$pattern*.sh" -not -name '*.test.sh' -not -name '*.seqtest.sh' -not -name *.pkg.sh`;
      my $source_count = split(/\n/, $source_name);
      if ($source_count > 1) {
        printErr "Ambiguous results trying to import '$pattern' in file $input_file".' line '."$.\nLooking in: $find_search\nGot:\n$source_name\n";
        die 10;
      }
      elsif ($source_count == 0) {
        printErr "No source found trying to import '$pattern' in file $input_file".' line '."$.\nLooking in: $find_search";
        die 10;
      }
      else {
        chomp($source_name);
        process_file($source_name);
      }
    }
    elsif ($_ !~ /#.*source\s+/ && m:(^|;|do +|then +)\s*source\s+((\./)?([^;\s]+));?\s*(#\s*bash-rollup-no-recur)?:) {
      my $next_file="$source_base/$4";
      my $source_spec="$2";
      if ($next_file =~ /\$/) {
        print "Leaving dynamic source: '$source_spec' in $input_file".'@'."$.\n";
        print $output $_;
      }
      elsif ($5) {
        process_file($next_file, 1);
      }
      elsif (-f "$next_file") {
        process_file($next_file);
      }
      else {
        # TODO: support an 'ignore' directive like we do in the 'source-only' mode (see bash script)
        printErr "No source found trying to source '$source_spec' in file $input_file".'@'."$.";
        die 10
      }
    }
    else {
      print $output $_;
    }
  }
}

process_file($main_file);
